import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import '../ast/style.dart';
import '../html/html_unescape.dart';
import '../html/html_view.dart';
import '../widgets/math.dart';
import 'theme.dart';

/// Default body text style used by [MathRender] / [EquationSolver] when the
/// caller does not pass an explicit `style:`. Tweaked for a more polished
/// look — Bengali typography, gentle line-height, richer near-black/-white.
/// Sizes/weights here intentionally only affect the *fallback* path; every
/// premium card already passes its own [TextStyle].
TextStyle _defaultMathTextStyle(BuildContext context, {required bool isDark}) {
  return TextStyle(
    fontFamily: MathRenderTheme.of(context).fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.65,
    letterSpacing: 0.1,
    color: isDark ? const Color(0xFFE8EAED) : const Color(0xFF1A1F2C),
  );
}

// The style to hand flutter_math, derived from the prose style around the
// equation so a formula sits in a sentence without changing weight or size.
//
// flutter_math draws with the KaTeX fonts, which ship a Regular and a Bold face
// and nothing between: `MathOptions` reaches for the Bold file on
// `FontWeight.bold` exactly, so every other weight silently falls back to
// Regular. The question and option text run at w600 / w500, so as written every
// equation rendered a full face lighter than the Bengali beside it — which is
// the "different colour" it reads as on screen, a lighter stroke rather than a
// different colour value.
//
// Measuring ink coverage over the digits gives the face each weight belongs to:
//
//     KaTeX_Main-Regular  0.380     NotoSansBengali w400  0.381
//     KaTeX_Main-Bold     0.492     NotoSansBengali w500  0.446
//                                   NotoSansBengali w600  0.512
//
// so w600 belongs on Bold and w400 on Regular, and w500 — sitting between the
// two faces — is marginally nearer Bold than Regular.
const FontWeight _kKatexBoldFrom = FontWeight.w500;

// KaTeX sets digits shorter than NotoSansBengali does at the same point size
// (a digit stands 0.688 em on the Regular face and 0.665 em on Bold, against
// 0.734 em in NotoSansBengali),
// so an equation given the prose font size still looks small next to the prose.
// These line the digits up; math here is digit-dominant, so digit height is the
// thing worth matching.
const double _kKatexRegularScale = 1.07;
const double _kKatexBoldScale = 1.10;

TextStyle _katexTextStyle(TextStyle style) {
  final weight = style.fontWeight ?? FontWeight.normal;
  final bold = weight.value >= _kKatexBoldFrom.value;
  return style.copyWith(
    fontSize:
        (style.fontSize ?? 16) *
        (bold ? _kKatexBoldScale : _kKatexRegularScale),
    fontWeight: bold ? FontWeight.bold : FontWeight.normal,
  );
}

bool hasEquation(String html) {
  final equationRegex = RegExp(
    r'(\$.*?\$|<math[\s\S]*?</math>|application/x-tex)',
    caseSensitive: false,
    dotAll: true,
  );
  return equationRegex.hasMatch(html);
}

bool hasTable(String html) {
  return RegExp(r'<table[\s\S]*?</table>', caseSensitive: false).hasMatch(html);
}

// ═══════════════════════════════════════════════════════════════════════════
// PLAIN-TEXT LINE BREAKS
// ═══════════════════════════════════════════════════════════════════════════
// Bodies reach us from two different editors. Some fields are real HTML
// (`<p>…</p>`), but others — MCQ explanations in particular — are plain text
// typed into a textarea, where the author's line breaks *are* the formatting:
//
//     প্রশ্ন: a = 1 + √3 হলে a3 - 6√3 = কত?
//
//     সমাধান:
//     দেওয়া আছে,
//     a = 1 + √3
//
// HtmlWidget treats `\n` as ordinary whitespace, so every one of those
// step-by-step solutions collapsed into a single running paragraph. The
// [EquationSolver] path already splits on `\n`, so only the plain-HTML path
// needed this — which is why the bug only showed on bodies with no `$…$`.

/// Tags that already carry line structure of their own. If the source has any
/// of these it is genuinely HTML, and its `\n`s are source formatting that
/// HTML is right to collapse.
final RegExp _htmlBlockTag = RegExp(
  r'<\s*/?\s*(p|div|br|li|ul|ol|table|tr|td|th|pre|blockquote|h[1-6])\b',
  caseSensitive: false,
);

final RegExp _anyHtmlTag = RegExp(r'<\s*/?\s*[a-zA-Z][^>]*>');

/// Turns an author's newlines into `<br>` when — and only when — the body is
/// not already block-structured HTML.
String applySourceLineBreaks(String source) {
  if (!source.contains('\n') && !source.contains('\r')) return source;
  if (_htmlBlockTag.hasMatch(source)) return source;

  var text = source;
  // With no tags at all this is plain text, so `<`, `>` and `&` are content
  // (`a < b` is a comparison, not the start of an element) and must be escaped
  // before HtmlWidget sees them.
  if (!_anyHtmlTag.hasMatch(text)) {
    text = const HtmlEscape().convert(text);
  }
  return text.replaceAll(RegExp(r'\r\n?'), '\n').replaceAll('\n', '<br>');
}

// ═══════════════════════════════════════════════════════════════════════════
// SCROLL-COST CACHES
// ═══════════════════════════════════════════════════════════════════════════
// A question sheet is rebuilt every time it scrolls back into view, and again
// whenever anything above it changes. None of the work below depends on
// anything but the raw HTML string, so it is done once per distinct body and
// remembered — otherwise a long paper re-runs the whole regex pipeline, and
// re-decodes every embedded image, on frames that are trying to scroll.
//
// The maps are bounded rather than an LRU: a paper is a few dozen bodies, and
// dropping the oldest entries is only ever a re-parse, never a wrong result.

//
// Sized for a long practice session (~6 bodies per question, and the endless
// chapter list scrolls through hundreds of questions): at 64 the maps churned
// after ~10 questions and every scroll-back re-ran the whole pipeline. Hits go
// through [_recall], which moves the entry to the back so eviction is
// least-recently-used rather than first-in.
//
// Decoded images are far larger than strings, so they get a smaller budget.

const int _kCacheLimit = 512;
const int _kImageCacheLimit = 48;

void _remember<K, V>(
  Map<K, V> cache,
  K key,
  V value, [
  int limit = _kCacheLimit,
]) {
  if (cache.length >= limit) cache.remove(cache.keys.first);
  cache[key] = value;
}

/// LRU lookup: a hit is re-inserted at the back (Dart maps keep insertion
/// order), so [_remember] evicts the entry used longest ago.
V? _recall<K, V>(Map<K, V> cache, K key) {
  final value = cache.remove(key);
  if (value != null) cache[key] = value;
  return value;
}

// Compiled once: these run per text run / per LaTeX token on every build.
final RegExp _inlineTokenRegex = RegExp(
  r'(__ALIGN_[A-Z]+__|<img[^>]+>|__BMATH__[\s\S]*?__/BMATH__|__FRAC__[\s\S]*?__/FRAC__|__DDOT__[\s\S]__/DDOT__|__DOT__[\s\S]__/DOT__|__BOLD__|__/BOLD__|__ITAL__|__/ITAL__|__ULINE__|__/ULINE__|__SUP__|__/SUP__|__SUB__|__/SUB__|\$[\s\S]*?\$)',
);
final RegExp _wideEnvRegex = RegExp(
  r'\\begin\{(array|[bBpvV]?matrix|cases|aligned|gathered|split)\}',
);
final RegExp _latexCommandRegex = RegExp(r'\\[a-zA-Z]+');
final RegExp _latexNoiseRegex = RegExp(r'[{}\\\s,]');
final RegExp _leadingAlignRegex = RegExp(r'^\s*((?:__ALIGN_[A-Z]+__\s*)+)');

/// Upper bound on the pixel width question images are decoded at — the
/// screen's long side, so nothing wider than the display can ever show is
/// kept in the image cache. Scanned diagrams arrive at several thousand
/// pixels; decoding those at full size is what filled memory on 4 GB phones.
/// Smaller images are never upscaled ([ResizeImage] default). Zoomable images
/// pass twice this so pinch-zoom stays sharp.
int get _imageDecodeWidth {
  final views = PlatformDispatcher.instance.views;
  if (views.isEmpty) return 2048;
  return views.first.physicalSize.longestSide.round().clamp(720, 2048);
}

final Map<String, bool> _needsSolverCache = <String, bool>{};

/// Whether a body carries maths or a table, and so must go through
/// [EquationSolver] rather than plain [HtmlWidget].
bool _needsSolver(String html) {
  final cached = _recall(_needsSolverCache, html);
  if (cached != null) return cached;
  final result = hasEquation(html) || hasTable(html);
  _remember(_needsSolverCache, html, result);
  return result;
}

final Map<String, String> _preparedHtmlCache = <String, String>{};

/// Decoded `data:image/...` bytes, shared by both render paths. A base64
/// answer image runs to hundreds of kilobytes; decoding it again per rebuild
/// is the most expensive thing a scrolling list can do.
final Map<String, Uint8List> _base64ImageCache = <String, Uint8List>{};

Uint8List _decodeBase64Image(String src) {
  final cached = _recall(_base64ImageCache, src);
  if (cached != null) return cached;
  final bytes = base64Decode(src.split(',').last);
  _remember(_base64ImageCache, src, bytes, _kImageCacheLimit);
  return bytes;
}

class MathRender extends StatelessWidget {
  final String htmlContent;
  final TextStyle? style;

  /// When true, a line wider than the screen makes the WHOLE content scroll
  /// horizontally as one surface (used for answers / MCQ options). When false
  /// (default, used for questions) each wide equation scrolls on its own.
  final bool fullContainerScroll;

  const MathRender({
    super.key,
    required this.htmlContent,
    this.style,
    this.fullContainerScroll = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    // 🔥 If equation or table exists → use EquationSolver
    if (_needsSolver(htmlContent)) {
      return EquationSolver(
        htmlContent: htmlContent,
        baseStyle: style,
        fullContainerScroll: fullContainerScroll,
      );
    }

    // 🔥 Strip inline colors in dark mode so HtmlWidget respects textStyle
    String html = applySourceLineBreaks(htmlContent);
    if (isDark) {
      // Remove color from style attributes: style="color: #000; ..." → style="..."
      html = html.replaceAll(
        RegExp(r'color\s*:\s*[^;"]+;?', caseSensitive: false),
        '',
      );
      // Remove <font color="..."> but keep inner content
      html = html.replaceAll(
        RegExp(
          r'<font[^>]*color=["\u0027][^"\u0027]*["\u0027][^>]*>',
          caseSensitive: false,
        ),
        '',
      );
      html = html.replaceAll(RegExp(r'</font>', caseSensitive: false), '');
    }

    // 🔥 If no equation → use HtmlWidget
    return HtmlView(
      html,
      textStyle: style ?? _defaultMathTextStyle(context, isDark: isDark),
      onTapUrl: MathRenderTheme.of(context).onTapUrl,
      // customStylesBuilder: isDark
      //     ? (element) {
      //         return {'color': 'white'};
      //       }
      //     : null,
      customWidgetBuilder: (element) {
        if (element.name == 'img') {
          final src = element.attributes['src'];
          if (src == null) return null;

          return _ImageBox(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            child: _buildImageFromSrc(src),
          );
        }
        return null;
      },
    );
  }
}

class EquationSolver extends StatelessWidget {
  final String htmlContent;
  final TextStyle? baseStyle;

  /// See [MathRender.fullContainerScroll].
  final bool fullContainerScroll;

  const EquationSolver({
    super.key,
    required this.htmlContent,
    this.baseStyle,
    this.fullContainerScroll = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    final style = baseStyle ?? _defaultMathTextStyle(context, isDark: isDark);

    final processedHtml = _prepareHtml(htmlContent);

    // Answers / options: the whole block scrolls together when any line is too
    // wide. Questions (default): each wide equation scrolls on its own.
    return fullContainerScroll
        ? _buildScrollableContent(processedHtml, style, isDark)
        : _buildRichText(processedHtml, style, isDark);
  }

  // ---------------------------------------------------------------------------
  // PREPROCESS HTML & LATEX
  // ---------------------------------------------------------------------------
  String _prepareHtml(String source) {
    final cached = _recall(_preparedHtmlCache, source);
    if (cached != null) return cached;
    final prepared = _prepareHtmlUncached(source);
    _remember(_preparedHtmlCache, source, prepared);
    return prepared;
  }

  String _prepareHtmlUncached(String html) {
    html = decodeHtmlEntities(html);
    html = supportHtmlLists(html);
    html = fixInlineExamMath(html);
    html = fixUndefinedLatexCommands(html);
    html = extractMathML(html);
    html = extractKatexAnnotation(html);
    html = _removeMsOfficeConditionalBlocks(html);

    html = _removeBrokenMsOfficeTags(html);
    html = convertMsOfficeMathToLatex(html);
    html = _removeEmptyTags(html);
    html = _protectSupSub(html);

    final mathMap = <String, String>{};
    html = _protectLatex(html, mathMap);
    html = _convertMathMLToLatex(html);
    html = _restoreLatex(html, mathMap);

    // Bangla embedded inside $...$ can't be shaped by flutter_math; lift it out
    // as ordinary text (and normalize trapped digits) so it renders correctly.
    html = _pullBengaliOutOfMath(html);

    return html;
  }

  // ---------------------------------------------------------------------------
  // BUILD RICH TEXT (TEXT + TABLES)
  // ---------------------------------------------------------------------------
  // Renders the whole block inside ONE horizontal scroll surface so two things
  // hold at once:
  //  • a wide equation (matrix / determinant / long pure LaTeX) always gets a
  //    line to itself — if prose shared its source line, that prose is split off
  //    above/below it. The equation keeps its intrinsic width and extends past
  //    the screen, so dragging anywhere scrolls the WHOLE question/answer
  //    container to reveal it (full-container scroll, not a per-line scrollbar),
  //  • every other line — prose, and lines mixing Bengali with math short enough
  //    to fit — is bound to the screen width and stays a wrapping RichText, so
  //    text line-breaks at the screen edge and short math stays inline.
  Widget _buildRichText(String content, TextStyle style, bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Measured ABOVE the scroll view, so it is the real screen width →
        // text blocks bound to it wrap; only wide equations exceed it.
        final double maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 0;
        final blocks = <Widget>[];
        final aligns = _AlignTracker();

        void addTextSegment(String segment) {
          if (segment.trim().isEmpty) return;
          final lines = segment.split('\n');
          var buffer = <String>[];
          var bufferAlign = TextAlign.start;

          void flushBuffer() {
            if (buffer.isEmpty) return;
            final text = buffer.join('\n');
            buffer = <String>[];
            if (text.trim().isEmpty) return;
            blocks.add(
              SizedBox(
                width: maxWidth > 0 ? maxWidth : null,
                child: RichText(
                  textAlign: bufferAlign,
                  text: TextSpan(
                    children: _processInlineTokens(text, style, isDark),
                  ),
                ),
              ),
            );
          }

          for (final rawLine in lines) {
            final lineAlign = aligns.next(rawLine);
            final line = _stripAlignMarkers(rawLine);
            // Lines sharing one RichText share its alignment, so a paragraph
            // aligned differently from the one before starts a new block. A
            // blank line is only spacing and rides along with either.
            if (line.trim().isNotEmpty) {
              if (lineAlign != bufferAlign &&
                  buffer.any((l) => l.trim().isNotEmpty)) {
                flushBuffer();
              }
              bufferAlign = lineAlign;
            }
            final segments = _splitAtWideMath(line);
            if (segments.length == 1 && segments.first.mathToken == null) {
              buffer.add(line);
              continue;
            }
            // The line mixes prose with a wide equation: flush the prose that
            // precedes the equation as its own wrapping line, give the equation
            // a line, then carry on with whatever follows it.
            for (final seg in segments) {
              if (seg.mathToken != null) {
                flushBuffer();
                blocks.add(_wideMathBlock(seg.mathToken!, style));
              } else if (seg.text!.trim().isNotEmpty) {
                buffer.add(seg.text!);
              }
            }
            flushBuffer();
          }
          flushBuffer();
        }

        final tableRegex = RegExp(
          r'<table[\s\S]*?</table>',
          caseSensitive: false,
        );
        int lastIndex = 0;

        for (final match in tableRegex.allMatches(content)) {
          // 1️⃣ Text before table
          addTextSegment(content.substring(lastIndex, match.start));

          // 2️⃣ Table itself (bound to screen width; it keeps its own internal
          //    horizontal scroll for too-wide tables).
          for (final span in _renderTableExactly(
            match.group(0)!,
            style,
            isDark,
          )) {
            blocks.add(
              maxWidth > 0
                  ? SizedBox(width: maxWidth, child: span.child)
                  : span.child,
            );
          }

          lastIndex = match.end;
        }

        // 3️⃣ Text after last table
        addTextSegment(content.substring(lastIndex));

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: blocks,
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // BANGLA-INSIDE-MATH REPAIR
  // ---------------------------------------------------------------------------
  // flutter_math cannot shape Bangla letters in math mode, so any Bangla that
  // authors embedded INSIDE a `$...$` (e.g. `\text{ এর ক্রয়মূল্য}`, raw
  // `$১৬√২$`) renders garbled. This lifts top-level Bangla — `\text{...}` groups
  // and raw Bangla runs — OUT of the equation as ordinary text (which RichText
  // shapes correctly) and leaves only real math for the engine. Bangla digits
  // trapped inside a structure (e.g. `\frac{\text{১০০}}{\text{১২০}}`) can't be
  // lifted out, so those are converted to English digits so the structure still
  // renders. `$...$` segments with no Bangla are returned byte-for-byte.
  String _pullBengaliOutOfMath(String html) {
    final bengali = RegExp(r'[ঀ-৿]');
    return html.replaceAllMapped(RegExp(r'\$([\s\S]*?)\$'), (m) {
      final raw = m.group(1)!;
      if (!bengali.hasMatch(raw)) return m.group(0)!;
      // Recurring-decimal overdots (`\dot{১}` / `\ddot{১}`) are dropped up front —
      // the digit is kept plain (no dot drawn, per request) — so an expression
      // that mixes a recurring decimal with a fraction (e.g.
      // `০.\dot{১} = \frac{১}{৯}`) still reaches the plain/fraction paths below
      // instead of falling through to the English-converting math path.
      final stripped = _stripDots(raw);
      // Normalise LaTeX operator/relation commands (`\times`, `\therefore`, …) to
      // their Unicode glyphs so the plain-number and fraction checks below treat
      // them as ordinary symbols rather than markup that forces the English math
      // path. The original (un-normalised) form is kept for the flutter_math
      // fallback, which needs the LaTeX commands.
      final inner = _normalizeSimpleOps(stripped);
      // A text-renderable expression — plain numbers, arithmetic, or algebra with
      // Bengali variables (`$১৬$`, `$০.৫$`, `$১২ + ৩$`, `$∴ ০.৪৭$`, `$∴ ক = ৯০$`) —
      // has no real math structure (no `\frac`, roots, sub/superscripts), yet
      // flutter_math would convert its Bengali digits to English. Keep it as plain
      // text so the Bengali digits survive.
      if (_isSimpleFracCell(inner)) return inner;
      // A simple numeric/algebraic fraction expression — `\frac{২×২×২}{১×৪×১০০০}`,
      // `∴ ০.৪৭ = \frac{৪৭ - ৪}{৯০} = \frac{৪৩}{৯০}` — is drawn with a custom
      // fraction widget so its Bengali digits survive (flutter_math would convert
      // them to English).
      final frac = _tryRenderSimpleFrac(inner);
      if (frac != null) return frac;
      // Same idea one step further: an expression whose only "structure" is a
      // sub/superscript or an italic variable (`$(৪+৫+৩)^২ = ?$`, `$x^২ = ২৫$`)
      // is drawn as plain text with markers — Bengali digits survive, the exponent
      // is raised, and (unlike a widget) the line still wraps at the screen edge.
      final asText = _tryRenderTextExpression(inner);
      if (asText != null) return asText;
      // Real structure that must still keep its Bengali digits — roots, nested
      // fractions (`$\sqrt{৬২৫} = ২৫$`, `$\frac{\sqrt{২৮৯}}{\sqrt{৩৬১}}$`) — is
      // drawn by the Bengali-safe math widget instead of flutter_math.
      final asWidget = _tryRenderMathWidget(inner);
      if (asWidget != null) return asWidget;
      return _rewriteBengaliMath(stripped);
    });
  }

  // Removes recurring-decimal overdot markers `\dot{X}` / `\ddot{X}`, keeping
  // their content `X` plain (no dot drawn over the digit — per request). Every
  // other character is passed through unchanged, so this composes with the
  // plain-number and fraction paths (e.g. `০.\dot{১} = \frac{১}{৯}` becomes
  // `০.১ = \frac{১}{৯}`). Bengali digits are preserved.
  String _stripDots(String inner) {
    if (!inner.contains(r'\dot') && !inner.contains(r'\ddot')) return inner;
    final out = StringBuffer();
    int i = 0;
    while (i < inner.length) {
      final isDouble = inner.startsWith(r'\ddot{', i);
      if (isDouble || inner.startsWith(r'\dot{', i)) {
        i += isDouble ? 6 : 5; // skip `\ddot{` / `\dot{`
        int depth = 1;
        while (i < inner.length && depth > 0) {
          final ch = inner[i];
          if (ch == '{') {
            depth++;
            out.write(ch);
          } else if (ch == '}') {
            depth--;
            if (depth > 0) out.write(ch);
          } else {
            out.write(ch);
          }
          i++;
        }
        continue;
      }
      out.write(inner[i]);
      i++;
    }
    return out.toString();
  }

  // Rewrites a `$...$` made only of simple numeric fractions, numbers and the
  // operators/`=` joining them into a stream of `__FRAC__num__FRACSEP__den__/FRAC__`
  // tokens (drawn as real stacked fractions) with the plain parts left as text —
  // all keeping their Bengali digits. Returns null when it hits anything that
  // isn't a simple fraction/number (variables, roots, nested non-numeric groups)
  // so those fall back to the flutter_math path.
  String? _tryRenderSimpleFrac(String inner) {
    if (!inner.contains(r'\frac')) return null;
    // Normalise LaTeX operator commands (`\times`, `\div`, …) to their Unicode
    // glyphs so a numeric fraction written with `\times` is recognised the same
    // as one written with `×`.
    inner = _normalizeSimpleOps(inner);
    final out = StringBuffer();
    int i = 0;
    while (i < inner.length) {
      if (inner.startsWith(r'\frac{', i)) {
        i += 6; // skip `\frac{`
        final num = _readBalancedGroup(inner, i);
        if (num == null) return null;
        i = num.end;
        if (i >= inner.length || inner[i] != '{') return null; // need `{den}`
        i += 1;
        final den = _readBalancedGroup(inner, i);
        if (den == null) return null;
        i = den.end;
        final numText = num.text.trim();
        final denText = den.text.trim();
        if (!_isSimpleFracCell(numText) || !_isSimpleFracCell(denText)) {
          return null;
        }
        out
          ..write('__FRAC__')
          ..write(numText)
          ..write('__FRACSEP__')
          ..write(denText)
          ..write('__/FRAC__');
        continue;
      }
      final ch = inner[i];
      // Simple operators/digits and raw Bengali (letters like the variable `ক`,
      // digits) pass through as text; anything else (LaTeX commands, `^`, `_`)
      // means real math → bail so the flutter_math path handles it.
      if (!_isSimpleMathChar(ch) && !_isBengali(ch.codeUnitAt(0))) return null;
      out.write(ch);
      i++;
    }
    return out.toString();
  }

  // An expression whose only "structure" is a sub/superscript, an italic variable
  // or a numeric fraction — `(৪+৫+৩)^২ = ?`, `x^২ + ২৫x - ৭৫০০ = ০`, `a=১, b=২` —
  // needs no math engine, yet flutter_math would convert its Bengali digits to
  // English, and the Bengali fallback in [_rewriteBengaliMath] would split it into
  // broken `$…$` fragments (leaving a dangling `^` and dropping the exponent onto
  // the baseline). Rewrite it as plain text with the `__SUP__` / `__SUB__` /
  // `__ITAL__` / `__FRAC__` markers the inline tokenizer already draws: the
  // Bengali digits survive, scripts are raised, variables stay italic — and,
  // unlike a widget, the line still wraps at the screen edge. Returns null on
  // anything needing real structure (roots, LaTeX commands, script/fraction cells
  // that aren't plain text) so those fall through to the math paths.
  String? _tryRenderTextExpression(String inner) {
    final out = StringBuffer();
    int i = 0;
    while (i < inner.length) {
      // A numeric fraction inside the expression (`\frac{১}{২} + ৩^২`) is drawn
      // with the same stacked-fraction token as the fraction-only path.
      if (inner.startsWith(r'\frac{', i)) {
        i += 6; // skip `\frac{`
        final num = _readBalancedGroup(inner, i);
        if (num == null) return null;
        i = num.end;
        if (i >= inner.length || inner[i] != '{') return null; // need `{den}`
        i += 1;
        final den = _readBalancedGroup(inner, i);
        if (den == null) return null;
        i = den.end;
        final numText = num.text.trim();
        final denText = den.text.trim();
        if (!_isSimpleFracCell(numText) || !_isSimpleFracCell(denText)) {
          return null;
        }
        out
          ..write('__FRAC__')
          ..write(numText)
          ..write('__FRACSEP__')
          ..write(denText)
          ..write('__/FRAC__');
        continue;
      }
      final ch = inner[i];
      if (ch == '^' || ch == '_') {
        final isSup = ch == '^';
        i++;
        while (i < inner.length && inner[i] == ' ') {
          i++;
        }
        if (i >= inner.length) return null; // dangling `^` / `_`
        // The script body is either a `{...}` group or a single character.
        String script;
        if (inner[i] == '{') {
          final group = _readBalancedGroup(inner, i + 1);
          if (group == null) return null;
          script = group.text.trim();
          i = group.end;
        } else {
          script = inner[i];
          i++;
        }
        if (!_isSimpleFracCell(script)) return null; // real math inside → bail
        out
          ..write(isSup ? '__SUP__' : '__SUB__')
          ..write(script)
          ..write(isSup ? '__/SUP__' : '__/SUB__');
        continue;
      }
      // A run of latin letters is a variable (`x`, `abcd`) → italic text.
      if (_isAsciiLetter(ch)) {
        final start = i;
        while (i < inner.length && _isAsciiLetter(inner[i])) {
          i++;
        }
        out
          ..write('__ITAL__')
          ..write(inner.substring(start, i))
          ..write('__/ITAL__');
        continue;
      }
      // Anything that isn't a simple operator/digit or raw Bengali (a LaTeX
      // command, a stray brace) means real structure → let the math paths have it.
      if (!_isSimpleMathChar(ch) && !_isBengali(ch.codeUnitAt(0))) return null;
      out.write(ch);
      i++;
    }
    return out.toString();
  }

  bool _isAsciiLetter(String ch) {
    final c = ch.codeUnitAt(0);
    return (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
  }

  // ---------------------------------------------------------------------------
  // BENGALI-SAFE MATH WIDGET (roots / nested fractions / scripts)
  // ---------------------------------------------------------------------------
  // Expressions that keep real structure but must also keep their Bengali digits —
  // `\sqrt{৬২৫} = ২৫`, `\sqrt[3]{১২৫}`, `\frac{\sqrt{২৮৯}}{\sqrt{৩৬১}}`,
  // `\sqrt{৪১ - \sqrt{২১ + \sqrt{৯}}}`, `(\frac{১}{১০০})^২` — can go to neither
  // path above: flutter_math draws their Bengali digits as English, and they can't
  // be flattened into the text markers (those can't nest). They are drawn instead
  // by a small renderer of our own — radicals, fractions and scripts built from
  // the app's font, so every Bengali digit survives. The `$...$` becomes a
  // `__BMATH__…__/BMATH__` token carrying the LaTeX, which [_buildMathWidget]
  // parses again at paint time. Returns null when the expression uses something
  // the renderer doesn't know, so it keeps the existing flutter_math fallback.
  String? _tryRenderMathWidget(String inner) {
    final atoms = _parseMathAtoms(inner);
    if (atoms == null || atoms.isEmpty) return null;
    return '__BMATH__${inner}__/BMATH__';
  }

  Widget _buildMathWidget(String latex, TextStyle style) {
    final atoms = _parseMathAtoms(latex);
    if (atoms == null) {
      // Only reachable if a token outlives a parser change — keep the old engine.
      return Math.tex(
        _sanitizeLatex(latex),
        textStyle: _katexTextStyle(style),
        mathStyle: MathStyle.display,
      );
    }
    return _atomsWidget(atoms, style, TextAlign.start);
  }

  // Parses [src] into the atoms the renderer can draw, or null for anything it
  // doesn't know (an unknown `\command`, unbalanced braces, a stray symbol) — the
  // caller then keeps the flutter_math path rather than mis-drawing the equation.
  List<_MathAtom>? _parseMathAtoms(String src) {
    return _parseAtomSeq(_normalizeSimpleOps(src));
  }

  List<_MathAtom>? _parseAtomSeq(String s) {
    final out = <_MathAtom>[];
    int i = 0;
    while (i < s.length) {
      if (s.startsWith(r'\frac', i)) {
        i = _skipSpaces(s, i + 5);
        if (i >= s.length || s[i] != '{') return null;
        final numGroup = _readBalancedGroup(s, i + 1);
        if (numGroup == null) return null;
        int j = _skipSpaces(s, numGroup.end);
        if (j >= s.length || s[j] != '{') return null;
        final denGroup = _readBalancedGroup(s, j + 1);
        if (denGroup == null) return null;
        final num = _parseAtomSeq(numGroup.text);
        final den = _parseAtomSeq(denGroup.text);
        if (num == null || den == null) return null;
        out.add(_MathFrac(num, den));
        i = denGroup.end;
        continue;
      }
      if (s.startsWith(r'\sqrt', i)) {
        i = _skipSpaces(s, i + 5);
        // Optional index: `\sqrt[3]{...}` is a cube root.
        List<_MathAtom>? index;
        if (i < s.length && s[i] == '[') {
          final close = s.indexOf(']', i);
          if (close < 0) return null;
          index = _parseAtomSeq(s.substring(i + 1, close));
          if (index == null) return null;
          i = _skipSpaces(s, close + 1);
        }
        if (i >= s.length || s[i] != '{') return null;
        final bodyGroup = _readBalancedGroup(s, i + 1);
        if (bodyGroup == null) return null;
        final body = _parseAtomSeq(bodyGroup.text);
        if (body == null) return null;
        out.add(_MathRoot(body, index));
        i = bodyGroup.end;
        continue;
      }
      // `\begin{array}{ccc} … & … \\ … \end{array}` and its siblings. The engine
      // parses these itself, but the Bangla sitting in their `\text{}` cells is
      // exactly what this renderer exists for — and the old Bangla fallback tore
      // the environment apart at every `\text{}`, handing the engine fragments it
      // rejected with "Expected & or \\ or \cr or \end".
      if (s.startsWith(r'\begin{', i)) {
        final env = _parseEnvironment(s, i);
        if (env == null) return null;
        out.add(env.atom);
        i = env.end;
        continue;
      }
      // A labelled reaction arrow — `\xrightarrow[25^\circ]{\text{ZnCl}_2}` —
      // drawn as the arrow with its labels stacked above and below it.
      if (s.startsWith(r'\xrightarrow', i) || s.startsWith(r'\xleftarrow', i)) {
        final pointsRight = s.startsWith(r'\xrightarrow', i);
        int j = _skipSpaces(s, i + (pointsRight ? 12 : 11));
        var below = const <_MathAtom>[];
        if (j < s.length && s[j] == '[') {
          final close = s.indexOf(']', j);
          if (close < 0) return null;
          final parsed = _parseAtomSeq(s.substring(j + 1, close));
          if (parsed == null) return null;
          below = parsed;
          j = _skipSpaces(s, close + 1);
        }
        var above = const <_MathAtom>[];
        if (j < s.length && s[j] == '{') {
          final group = _readBalancedGroup(s, j + 1);
          if (group == null) return null;
          final parsed = _parseAtomSeq(group.text);
          if (parsed == null) return null;
          above = parsed;
          j = group.end;
        }
        out.add(_MathArrow(above, below, pointsRight));
        i = j;
        continue;
      }
      // Upright-font wrappers. `\mathrm{ZnCl}` is the same glyphs as a `\text{}`
      // run — what matters is only that its letters do NOT come out italic.
      if (s.startsWith(r'\mathrm{', i) ||
          s.startsWith(r'\mathbf{', i) ||
          s.startsWith(r'\mathit{', i) ||
          s.startsWith(r'\operatorname{', i)) {
        final open = s.indexOf('{', i);
        final group = _readBalancedGroup(s, open + 1);
        if (group == null) return null;
        final inner = _parseAtomSeq(group.text);
        if (inner == null) return null;
        out.addAll(s.startsWith(r'\mathit{', i) ? inner : _uprightAtoms(inner));
        i = group.end;
        continue;
      }
      // Authors write the brace apart from the command — `\text { পরিসর }` —
      // and `\frac` above already skips that space. Doing the same here keeps
      // `\frac{\text {…}}{\text {…}}` on this path; matching only `\text{` bailed
      // to flutter_math, which cannot shape the Bangla this branch exists to
      // keep. `-1` when the brace never arrives, so `\textbf{…}` and friends
      // still fall through to the handling they had.
      final textOpen = s.startsWith(r'\text', i) ? _skipSpaces(s, i + 5) : -1;
      if (textOpen >= 0 && textOpen < s.length && s[textOpen] == '{') {
        final group = _readBalancedGroup(s, textOpen + 1);
        if (group == null) return null;
        out.add(_MathRun(group.text, false));
        i = group.end;
        continue;
      }
      // `\{` / `\}` are literal brace GLYPHS, not grouping — the backslash only
      // stops LaTeX reading them as a group. Drawing them keeps expressions like
      // `\{(১২ \div ৩) \times ২\}^৩` on this Bengali-safe path; without it the
      // `\` fell through to the bail below and the equation dropped to the
      // flutter_math fallback, which cannot keep Bengali digits.
      if (s.startsWith(r'\{', i) || s.startsWith(r'\}', i)) {
        out.add(_MathRun(s[i + 1], false));
        i += 2;
        continue;
      }
      final ch = s[i];
      if (ch == '^' || ch == '_') {
        final isSup = ch == '^';
        int j = _skipSpaces(s, i + 1);
        if (j >= s.length) return null; // dangling `^` / `_`
        List<_MathAtom>? body;
        if (s[j] == '{') {
          final group = _readBalancedGroup(s, j + 1);
          if (group == null) return null;
          body = _parseAtomSeq(group.text);
          i = group.end;
        } else if (s[j] == r'\') {
          // A command is a single token, so `25^\circ` raises the whole `\circ` —
          // taking one character here would leave a lone backslash and bail.
          int k = j + 1;
          if (k < s.length && _isAsciiLetter(s[k])) {
            while (k < s.length && _isAsciiLetter(s[k])) {
              k++;
            }
          } else {
            k++;
          }
          body = _parseAtomSeq(s.substring(j, k));
          i = k;
        } else {
          body = _parseAtomSeq(s[j]);
          i = j + 1;
        }
        if (body == null) return null;
        out.add(_MathScript(body, isSup));
        continue;
      }
      if (ch == '{') {
        final group = _readBalancedGroup(s, i + 1);
        if (group == null) return null;
        final inner = _parseAtomSeq(group.text);
        if (inner == null) return null;
        out.addAll(inner);
        i = group.end;
        continue;
      }
      // A `\command` the renderer knows as one glyph (`\circ`, `\to`, `\Delta`)
      // or as pure spacing (`\,`, `\quad`) is drawn here; every other command
      // still bails so the equation keeps the flutter_math path.
      if (ch == r'\') {
        final symbol = _readSymbolCommand(s, i);
        if (symbol == null) return null;
        if (symbol.$1.isNotEmpty) out.add(_MathRun(symbol.$1, false));
        i = symbol.$2;
        continue;
      }
      // A stray closing brace / bracket — bail so the equation keeps the
      // flutter_math path.
      if (ch == '}' || ch == '[' || ch == ']') return null;
      if (_isAsciiLetter(ch)) {
        final start = i;
        while (i < s.length && _isAsciiLetter(s[i])) {
          i++;
        }
        out.add(_MathRun(s.substring(start, i), true));
        continue;
      }
      if (!_isMathRunChar(ch)) return null;
      final start = i;
      while (i < s.length && _isMathRunChar(s[i])) {
        i++;
      }
      out.add(_MathRun(s.substring(start, i), false));
    }
    return out;
  }

  // A character the renderer draws as-is inside a run: digits (Bengali or ASCII),
  // operators and relations. Deliberately excludes the structural characters
  // (`{ } ^ _ \ [ ]`) and latin letters, which the parser handles itself.
  bool _isMathRunChar(String ch) {
    if (ch == '{' ||
        ch == '}' ||
        ch == '^' ||
        ch == '_' ||
        ch == r'\' ||
        ch == '[' ||
        ch == ']') {
      return false;
    }
    if (_isAsciiLetter(ch)) return false;
    return _isSimpleMathChar(ch) || _isBengali(ch.codeUnitAt(0));
  }

  int _skipSpaces(String s, int i) {
    while (i < s.length && s[i] == ' ') {
      i++;
    }
    return i;
  }

  // This renderer exists to keep Bengali digits, so it draws with the prose
  // font — which also put the Latin letters beside them (`X`, `Y`, `Enzyme`,
  // `H₂O`) in that font, while the same letters in an all-Latin equation come
  // from flutter_math's KaTeX faces. Side by side (`… X → Y` above `i. Y …`)
  // they read as two different typefaces. Latin letters and ASCII digits are
  // therefore drawn in the KaTeX face flutter_math would pick for them —
  // Main for upright text, Math-Italic for variables — at the same size and
  // weight [_katexTextStyle] gives flutter_math. Bengali and operators keep
  // the prose font, exactly as before.
  List<InlineSpan> _latinAwareSpans(String text, TextStyle style, bool italic) {
    final prose = italic ? style.copyWith(fontStyle: FontStyle.italic) : style;
    final katex = _katexTextStyle(style).copyWith(
      fontFamily: italic
          ? 'packages/flutter_math_fork/KaTeX_Math'
          : 'packages/flutter_math_fork/KaTeX_Main',
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      fontFamilyFallback: [if (style.fontFamily != null) style.fontFamily!],
    );
    bool isLatin(int c) =>
        (c >= 0x41 && c <= 0x5A) ||
        (c >= 0x61 && c <= 0x7A) ||
        (c >= 0x30 && c <= 0x39);

    final spans = <InlineSpan>[];
    int start = 0;
    for (int i = 1; i <= text.length; i++) {
      if (i == text.length ||
          isLatin(text.codeUnitAt(i)) != isLatin(text.codeUnitAt(start))) {
        final latin = isLatin(text.codeUnitAt(start));
        spans.add(
          TextSpan(
            text: text.substring(start, i),
            style: latin ? katex : prose,
          ),
        );
        start = i;
      }
    }
    return spans;
  }

  Widget _atomsWidget(List<_MathAtom> atoms, TextStyle style, TextAlign align) {
    return Text.rich(
      TextSpan(children: _atomSpans(atoms, style), style: style),
      softWrap: false,
      textAlign: align,
    );
  }

  List<InlineSpan> _atomSpans(List<_MathAtom> atoms, TextStyle style) {
    final double fontSize = style.fontSize ?? 16;
    final spans = <InlineSpan>[];
    for (final atom in atoms) {
      if (atom is _MathRun) {
        spans.addAll(_latinAwareSpans(atom.text, style, atom.italic));
      } else if (atom is _MathFrac) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _stackedFraction(
              _atomsWidget(atom.numerator, style, TextAlign.center),
              _atomsWidget(atom.denominator, style, TextAlign.center),
              style,
            ),
          ),
        );
      } else if (atom is _MathRoot) {
        final indexStyle = style.copyWith(fontSize: fontSize * 0.6);
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _radical(
              _atomsWidget(atom.body, style, TextAlign.start),
              atom.index == null
                  ? null
                  : _atomsWidget(atom.index!, indexStyle, TextAlign.start),
              style,
            ),
          ),
        );
      } else if (atom is _MathScript) {
        final scriptStyle = style.copyWith(fontSize: fontSize * 0.72);
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Transform.translate(
              offset: Offset(
                0,
                atom.isSup ? -fontSize * 0.34 : fontSize * 0.18,
              ),
              child: _atomsWidget(atom.body, scriptStyle, TextAlign.start),
            ),
          ),
        );
      } else if (atom is _MathEnv) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _environmentWidget(atom, style),
          ),
        );
      } else if (atom is _MathArrow) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _arrowWidget(
              atom,
              style,
              style.copyWith(fontSize: fontSize * 0.68),
            ),
          ),
        );
      }
    }
    return spans;
  }

  // ---------------------------------------------------------------------------
  // ENVIRONMENTS (\begin{array} … \end{array})
  // ---------------------------------------------------------------------------
  // Environments that are a plain grid of cells. The delimited ones (`pmatrix`,
  // `cases`, …) are deliberately absent: they need stretched brackets this
  // renderer doesn't draw, so they keep the flutter_math path they have today.
  static const Set<String> _gridEnvironments = {
    'array',
    'subarray',
    'matrix',
    'aligned',
    'gathered',
    'split',
  };

  /// Parses `\begin{name}[{colspec}] body \end{name}` starting at [i], returning
  /// the environment atom and the index just past its `\end{…}`. Null for an
  /// environment this renderer doesn't draw, or a malformed one — the caller then
  /// bails the whole expression to flutter_math.
  ({_MathAtom atom, int end})? _parseEnvironment(String s, int i) {
    final nameEnd = s.indexOf('}', i + 7);
    if (nameEnd < 0) return null;
    final name = s.substring(i + 7, nameEnd);
    if (!_gridEnvironments.contains(name)) return null;

    int j = _skipSpaces(s, nameEnd + 1);
    var align = const <String>[];
    if (name == 'array' || name == 'subarray') {
      if (j >= s.length || s[j] != '{') return null;
      final spec = _readBalancedGroup(s, j + 1);
      if (spec == null) return null;
      // `|` rules and `@{…}` inserts carry no column of their own — only the
      // alignment letters do.
      align = spec.text
          .split('')
          .where((c) => c == 'l' || c == 'c' || c == 'r')
          .toList();
      j = spec.end;
    }

    // Same-name environments can nest, so count opens rather than taking the
    // first `\end{…}`.
    final openTag = '\\begin{$name}';
    final endTag = '\\end{$name}';
    int depth = 1, k = j, bodyEnd = -1;
    while (k < s.length) {
      if (s.startsWith(openTag, k)) {
        depth++;
        k += openTag.length;
      } else if (s.startsWith(endTag, k)) {
        depth--;
        if (depth == 0) {
          bodyEnd = k;
          break;
        }
        k += endTag.length;
      } else {
        k++;
      }
    }
    if (bodyEnd < 0) return null;

    final rows = <List<List<_MathAtom>>>[];
    for (final rawRow in _splitEnvironmentBody(
      s.substring(j, bodyEnd),
      onRows: true,
    )) {
      if (rawRow.trim().isEmpty) continue;
      final cells = <List<_MathAtom>>[];
      for (final rawCell in _splitEnvironmentBody(rawRow, onRows: false)) {
        final atoms = _parseAtomSeq(rawCell.trim());
        if (atoms == null) return null;
        cells.add(atoms);
      }
      rows.add(cells);
    }
    if (rows.isEmpty) return null;
    return (atom: _MathEnv(rows, align, name), end: bodyEnd + endTag.length);
  }

  /// Splits an environment body on its `\\` row breaks ([onRows]) or a row on its
  /// `&` cell breaks — counting only separators at brace depth 0 and outside any
  /// nested environment, so an inner `\begin{…}` keeps its own rows and cells.
  List<String> _splitEnvironmentBody(String s, {required bool onRows}) {
    final parts = <String>[];
    final buffer = StringBuffer();
    int depth = 0, env = 0, i = 0;
    while (i < s.length) {
      final ch = s[i];
      if (ch == r'\') {
        if (s.startsWith(r'\begin{', i)) env++;
        if (s.startsWith(r'\end{', i)) env--;
        if (onRows &&
            env == 0 &&
            depth == 0 &&
            i + 1 < s.length &&
            s[i + 1] == r'\') {
          parts.add(buffer.toString());
          buffer.clear();
          i += 2;
          // `\\[6pt]` — an explicit row gap this renderer ignores.
          if (i < s.length && s[i] == '[') {
            final close = s.indexOf(']', i);
            if (close > 0) i = close + 1;
          }
          continue;
        }
        // Copy any other command whole (`\text`, and the escapes `\&`, `\{`) so
        // its characters can never be read as structure.
        buffer.write(ch);
        i++;
        if (i < s.length) {
          buffer.write(s[i]);
          i++;
        }
        while (i < s.length && _isAsciiLetter(s[i])) {
          buffer.write(s[i]);
          i++;
        }
        continue;
      }
      if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        if (depth > 0) depth--;
      } else if (!onRows && ch == '&' && depth == 0 && env == 0) {
        parts.add(buffer.toString());
        buffer.clear();
        i++;
        continue;
      }
      buffer.write(ch);
      i++;
    }
    parts.add(buffer.toString());
    return parts;
  }

  /// The glyph (and the index just past it) for a `\command` the renderer draws
  /// as a single symbol or as spacing. Null for anything else.
  (String, int)? _readSymbolCommand(String s, int i) {
    if (i + 1 >= s.length) return null;
    final next = s[i + 1];
    if (!_isAsciiLetter(next)) {
      const spacing = {',': ' ', ';': ' ', ':': ' ', '!': '', ' ': ' '};
      final space = spacing[next];
      if (space != null) return (space, i + 2);
      // `\&`, `\%`, `\$`, `\#`, `\_` are the literal glyphs, escaped.
      if ('&%\$#_'.contains(next)) return (next, i + 2);
      return null;
    }
    int j = i + 1;
    while (j < s.length && _isAsciiLetter(s[j])) {
      j++;
    }
    final glyph = _mathSymbolCommands[s.substring(i + 1, j)];
    if (glyph == null) return null;
    // The spaces after a command name only terminate it; they aren't spacing.
    return (glyph, _skipSpaces(s, j));
  }

  static const Map<String, String> _mathSymbolCommands = {
    'circ': '∘',
    'degree': '°',
    'to': '→',
    'gets': '←',
    'longrightarrow': '⟶',
    'longleftarrow': '⟵',
    'leftrightarrow': '↔',
    'rightleftharpoons': '⇌',
    'uparrow': '↑',
    'downarrow': '↓',
    'infty': '∞',
    'prime': '′',
    'equiv': '≡',
    'propto': '∝',
    'ast': '∗',
    'bullet': '•',
    'ldots': '…',
    'dots': '…',
    'cdots': '⋯',
    'alpha': 'α',
    'beta': 'β',
    'gamma': 'γ',
    'delta': 'δ',
    'Delta': 'Δ',
    'theta': 'θ',
    'lambda': 'λ',
    'mu': 'μ',
    'pi': 'π',
    'rho': 'ρ',
    'sigma': 'σ',
    'Sigma': 'Σ',
    'phi': 'φ',
    'omega': 'ω',
    'Omega': 'Ω',
    'quad': ' ',
    'qquad': '  ',
  };

  /// Strips the italics a math-mode latin run is drawn with, for the upright
  /// wrappers (`\mathrm`, `\operatorname`).
  List<_MathAtom> _uprightAtoms(List<_MathAtom> atoms) => [
    for (final a in atoms) a is _MathRun ? _MathRun(a.text, false) : a,
  ];

  // The grid itself: an intrinsically-sized [Table], so every column is as wide
  // as its widest cell and rows line up the way the LaTeX says they should.
  Widget _environmentWidget(_MathEnv env, TextStyle style) {
    int columns = 0;
    for (final row in env.rows) {
      if (row.length > columns) columns = row.length;
    }
    return Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        for (final row in env.rows)
          TableRow(
            children: [
              for (int c = 0; c < columns; c++)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: c < row.length
                      ? Align(
                          alignment: _envAlignment(env, c),
                          child: _atomsWidget(
                            row[c],
                            style,
                            _envTextAlign(env, c),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
            ],
          ),
      ],
    );
  }

  // `array` states its own column letters; `aligned` / `split` alternate
  // right-then-left the way LaTeX does; everything else centres.
  String _envColumnKind(_MathEnv env, int column) {
    if (column < env.columnAlign.length) return env.columnAlign[column];
    if (env.name == 'aligned' || env.name == 'split') {
      return column.isEven ? 'r' : 'l';
    }
    return 'c';
  }

  Alignment _envAlignment(_MathEnv env, int column) {
    switch (_envColumnKind(env, column)) {
      case 'l':
        return Alignment.centerLeft;
      case 'r':
        return Alignment.centerRight;
      default:
        return Alignment.center;
    }
  }

  TextAlign _envTextAlign(_MathEnv env, int column) {
    switch (_envColumnKind(env, column)) {
      case 'l':
        return TextAlign.left;
      case 'r':
        return TextAlign.right;
      default:
        return TextAlign.center;
    }
  }

  // A reaction arrow with its conditions stacked over and under it. The
  // [IntrinsicWidth] lets the arrow grow to the widest label, which is what makes
  // `\xrightarrow[\text{তাপ}]{\text{ZnCl}_2}` read as one arrow rather than a
  // stack of three unrelated lines.
  Widget _arrowWidget(_MathArrow arrow, TextStyle style, TextStyle labelStyle) {
    final double fontSize = style.fontSize ?? 16;
    // The span is centred on the line, so a one-sided label (`\xrightarrow{…}`
    // with no `[…]`) would push the shaft off the middle. An invisible copy of
    // the present label on the empty side keeps the shaft centred, level with
    // a neighbouring arrow that carries both labels.
    final above = arrow.above.isNotEmpty ? arrow.above : arrow.below;
    final below = arrow.below.isNotEmpty ? arrow.below : arrow.above;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (above.isNotEmpty)
              Opacity(
                opacity: arrow.above.isNotEmpty ? 1 : 0,
                child: _atomsWidget(above, labelStyle, TextAlign.center),
              ),
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: fontSize * 2.4),
              child: SizedBox(
                height: fontSize * 0.7,
                child: CustomPaint(
                  painter: _ArrowPainter(
                    color: style.color ?? Colors.black,
                    pointsRight: arrow.pointsRight,
                    thickness: (fontSize * 0.08).clamp(1.0, 2.0).toDouble(),
                  ),
                ),
              ),
            ),
            if (below.isNotEmpty)
              Opacity(
                opacity: arrow.below.isNotEmpty ? 1 : 0,
                child: _atomsWidget(below, labelStyle, TextAlign.center),
              ),
          ],
        ),
      ),
    );
  }

  // Numerator over denominator with a rule between — the widget twin of
  // [_fractionWidget], taking already-built children so a fraction can hold a
  // root (`\frac{\sqrt{২৮৯}}{\sqrt{৩৬১}}`) or a script.
  Widget _stackedFraction(
    Widget numerator,
    Widget denominator,
    TextStyle style,
  ) {
    final Color color = style.color ?? Colors.black;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              child: numerator,
            ),
            Container(height: 1.3, color: color),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              child: denominator,
            ),
          ],
        ),
      ),
    );
  }

  // A radical whose sign and overline are painted around [body], so the bar spans
  // exactly the content (however tall or wide it is — a nested root, a fraction).
  // [index] is the small root degree of `\sqrt[3]{...}`, drawn over the left arm.
  Widget _radical(Widget body, Widget? index, TextStyle style) {
    final double fontSize = style.fontSize ?? 16;
    final Color color = style.color ?? Colors.black;
    final double lead = fontSize * 0.58; // width of the radical's arm
    final double stroke = (fontSize * 0.07).clamp(1.0, 2.0);

    final Widget sign = CustomPaint(
      painter: _RadicalPainter(color: color, lead: lead, stroke: stroke),
      child: Padding(
        padding: EdgeInsets.only(
          left: lead + fontSize * 0.12,
          top: fontSize * 0.20,
          right: fontSize * 0.12,
          bottom: fontSize * 0.06,
        ),
        child: body,
      ),
    );

    if (index == null) return sign;
    // The degree sits above the arm: pad the radical over to make room, then lay
    // the (unclipped) index into that gap.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: EdgeInsets.only(left: lead * 0.55),
          child: sign,
        ),
        Positioned(left: 0, top: 0, child: index),
      ],
    );
  }

  // True when [s] can be drawn as plain text: simple numeric/operator/relation
  // characters plus raw Bengali (digits and variable letters such as `ক`). Used
  // both to gate a whole `$...$` as text-renderable and to check a fraction
  // numerator/denominator. Rejects LaTeX commands, sub/superscripts and braces,
  // which need the real math engine.
  bool _isSimpleFracCell(String s) {
    if (s.isEmpty) return false;
    for (int i = 0; i < s.length; i++) {
      final ch = s[i];
      if (_isSimpleMathChar(ch)) continue;
      if (_isBengali(ch.codeUnitAt(0))) continue;
      return false;
    }
    return true;
  }

  // Replaces the simple LaTeX operator commands that appear in plain numeric
  // expressions with their Unicode glyphs (`\times`→`×`, `\div`→`÷`, …) so the
  // "plain number" check treats them as ordinary operators rather than markup.
  String _normalizeSimpleOps(String s) {
    return s
        .replaceAll(r'\times', '×')
        .replaceAll(r'\div', '÷')
        .replaceAll(r'\cdot', '·')
        .replaceAll(r'\therefore', '∴')
        .replaceAll(r'\because', '∵')
        .replaceAll(r'\Rightarrow', '⇒')
        .replaceAll(r'\Leftarrow', '⇐')
        .replaceAll(r'\rightarrow', '→')
        .replaceAll(r'\leftarrow', '←')
        .replaceAll(r'\leq', '≤')
        .replaceAll(r'\geq', '≥')
        .replaceAll(r'\neq', '≠')
        .replaceAll(r'\approx', '≈')
        .replaceAll(r'\pm', '±')
        .replaceAll(r'\mp', '∓');
  }

  // Reads a `{...}` group whose opening brace was already consumed ([start] is
  // the first char inside it). Returns the inner text and the index just past
  // the matching `}`, or null if the braces are unbalanced.
  _BraceGroup? _readBalancedGroup(String s, int start) {
    int depth = 1, i = start;
    final b = StringBuffer();
    while (i < s.length && depth > 0) {
      final ch = s[i];
      if (ch == '{') {
        depth++;
        b.write(ch);
      } else if (ch == '}') {
        depth--;
        if (depth > 0) b.write(ch);
      } else {
        b.write(ch);
      }
      i++;
    }
    if (depth != 0) return null;
    return _BraceGroup(b.toString(), i);
  }

  // Draws a stacked numerator-over-denominator fraction with a rule between —
  // Bengali digits kept intact (unlike flutter_math). [IntrinsicWidth] makes the
  // rule span the wider of the two rows.
  Widget _fractionWidget(
    String numerator,
    String denominator,
    TextStyle style,
  ) {
    final rowStyle = style.copyWith(height: 1.15);
    final Color color = style.color ?? Colors.black;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              child: Text(
                numerator,
                style: rowStyle,
                textAlign: TextAlign.center,
              ),
            ),
            Container(height: 1.3, color: color),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              child: Text(
                denominator,
                style: rowStyle,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Splits a `__FRAC__num__FRACSEP__den__/FRAC__` token into (numerator,
  // denominator).
  List<String> _decodeFracToken(String token) {
    final body = token.substring(8, token.length - 9); // strip wrappers
    final sep = body.indexOf('__FRACSEP__');
    if (sep < 0) return [body, ''];
    return [body.substring(0, sep), body.substring(sep + 11)];
  }

  bool _isSimpleMathChar(String ch) {
    if (ch.trim().isEmpty) return true; // whitespace
    if ('.,+-=()×÷*/·±∓∴∵⇒⇐→←≤≥≠≈<>:;%?!'.contains(ch)) return true;
    final c = ch.codeUnitAt(0);
    if (c >= 0x30 && c <= 0x39) return true; // ASCII digits
    return _isBengaliDigit(c);
  }

  // Draws a single glyph with one (or two, for `\ddot`) small dots centred just
  // above it — a font-independent recurring-decimal overdot. Uses a CustomPaint
  // over a tight (height: 1.0) Text: the paint proxies the Text's alphabetic
  // baseline, so a baseline-aligned WidgetSpan still lines the glyph up with the
  // surrounding text, and the dots are painted just above the glyph box.
  Widget _dottedGlyph(String glyph, TextStyle style, bool isDouble) {
    final double size = style.fontSize ?? 16;
    final Color color = style.color ?? Colors.black;
    return CustomPaint(
      foregroundPainter: _OverdotPainter(
        count: isDouble ? 2 : 1,
        color: color,
        radius: size * 0.07,
      ),
      child: Text(glyph, style: style.copyWith(height: 1.0)),
    );
  }

  bool _isBengali(int c) => c >= 0x0980 && c <= 0x09FF;
  bool _isBengaliDigit(int c) => c >= 0x09E6 && c <= 0x09EF;

  String _rewriteBengaliMath(String s) {
    final out = StringBuffer();
    final math = StringBuffer();
    int depth = 0;
    // An environment is one indivisible unit: lifting a `\text{}` cell or a Bangla
    // run out of the middle of a `\begin{array}…\end{array}` leaves fragments that
    // are no longer valid LaTeX, and the engine rejects every one of them
    // ("Expected & or \\ or \cr or \end"). Inside an environment nothing is lifted
    // — Bangla is wrapped into `\text{}` instead, so the body stays whole and
    // parseable. (The Bangla-safe renderer draws these environments itself; this
    // is the fallback for one it can't parse.)
    final bool inEnvironment = s.contains(r'\begin{');

    void flushMath() {
      final t = math.toString();
      math.clear();
      if (t.trim().isEmpty) {
        out.write(t); // keep spacing, never emit an empty `$$`
        return;
      }
      out
        ..write(r'$')
        ..write(t)
        ..write(r'$');
    }

    int i = 0;
    while (i < s.length) {
      // Top-level \text{...} → lift its content out as plain text (but never out
      // of an environment, where it is a cell the body can't lose).
      // `\text {…}` (brace apart from the command) lifts exactly like `\text{…}`.
      final liftOpen = depth == 0 && !inEnvironment && s.startsWith(r'\text', i)
          ? _skipSpaces(s, i + 5)
          : -1;
      if (liftOpen >= 0 && liftOpen < s.length && s[liftOpen] == '{') {
        int j = liftOpen + 1, d = 1;
        final content = StringBuffer();
        while (j < s.length && d > 0) {
          final ch = s[j];
          if (ch == '{') {
            d++;
          } else if (ch == '}') {
            d--;
          }
          if (d > 0) content.write(ch);
          j++;
        }
        flushMath();
        out.write(content);
        i = j;
        continue;
      }

      final c = s.codeUnitAt(i);

      // `^` / `_` own the token that follows them. An UNBRACED Bangla script
      // (`x^৩`) sits at depth 0, so without this it would be lifted out as plain
      // text by the rule below — leaving a dangling `^` that the engine rejects
      // with "Expected group after '^'" and the digit stranded after it. Consume
      // the script here instead: brace it so the engine always gets a group, and
      // convert a Bangla digit the same way any other trapped digit is. Only ONE
      // character is taken, which is exactly what LaTeX itself scopes to `^`.
      if (s[i] == '^' || s[i] == '_') {
        math.write(s[i]);
        i++;
        while (i < s.length && s[i] == ' ') {
          i++;
        }
        if (i < s.length && s[i] != '{') {
          final script = s.codeUnitAt(i);
          math
            ..write('{')
            ..write(_isBengaliDigit(script) ? _bengaliDigit(s[i]) : s[i])
            ..write('}');
          i++;
        }
        continue;
      }

      // Top-level raw Bangla run (letters or digits) → plain text; inside an
      // environment it becomes a `\text{}` cell instead, so nothing leaves the
      // body.
      if (depth == 0 && _isBengali(c)) {
        final start = i;
        while (i < s.length && _isBengali(s.codeUnitAt(i))) {
          i++;
        }
        final run = s.substring(start, i);
        if (inEnvironment) {
          math
            ..write(r'\text{')
            ..write(run)
            ..write('}');
        } else {
          flushMath();
          out.write(run);
        }
        continue;
      }

      final ch = s[i];
      if (ch == '{') {
        depth++;
        math.write(ch);
      } else if (ch == '}') {
        if (depth > 0) depth--;
        math.write(ch);
      } else if (ch == '√') {
        // Unicode radical the engine can't read → real radical symbol.
        math.write(r'\surd ');
      } else if (_isBengaliDigit(c)) {
        // Bangla digit trapped inside a structure → English so it still renders.
        math.write(_bengaliDigit(ch));
      } else {
        math.write(ch);
      }
      i++;
    }
    flushMath();
    return out.toString();
  }

  String _bengaliDigit(String ch) {
    const map = {
      '০': '0',
      '১': '1',
      '২': '2',
      '৩': '3',
      '৪': '4',
      '৫': '5',
      '৬': '6',
      '৭': '7',
      '৮': '8',
      '৯': '9',
    };
    return map[ch] ?? ch;
  }

  // ---------------------------------------------------------------------------
  // PROCESS INLINE TOKENS (TEXT, MATH, BOLD, SUP/SUB, IMAGES)
  // ---------------------------------------------------------------------------
  List<InlineSpan> _processInlineTokens(
    String text,
    TextStyle style,
    bool isDark,
  ) {
    final spans = <InlineSpan>[];
    bool bold = false, sup = false, sub = false, ital = false, uline = false;

    final regex = _inlineTokenRegex;

    int last = 0;
    for (final m in regex.allMatches(text)) {
      if (m.start > last) {
        spans.add(
          _createTextSpan(
            text.substring(last, m.start),
            style,
            bold,
            sup,
            sub,
            italic: ital,
            underline: uline,
          ),
        );
      }

      final token = m.group(0)!;

      if (token.startsWith('__BMATH__')) {
        final latex = token.substring(9, token.length - 10);
        final mathWidget = _buildMathWidget(
          latex,
          bold ? style.copyWith(fontWeight: FontWeight.bold) : style,
        );
        // Same rule as the flutter_math span above: only a construct too wide for
        // the screen gets its own horizontal scroll, so the prose around it keeps
        // wrapping instead of being dragged off-screen with the equation.
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _isWideLatex(latex)
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: mathWidget,
                  )
                : mathWidget,
          ),
        );
      } else if (token.startsWith('__FRAC__')) {
        final parts = _decodeFracToken(token);
        final fracStyle = bold
            ? style.copyWith(fontWeight: FontWeight.bold)
            : style;
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _fractionWidget(parts[0], parts[1], fracStyle),
          ),
        );
      } else if (token.startsWith('__DDOT__') || token.startsWith('__DOT__')) {
        final isDouble = token.startsWith('__DDOT__');
        final glyph = isDouble
            ? token.substring(8, token.length - 9)
            : token.substring(7, token.length - 8);
        final glyphStyle = bold
            ? style.copyWith(fontWeight: FontWeight.bold)
            : style;
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: _dottedGlyph(glyph, glyphStyle, isDouble),
          ),
        );
      } else if (token.startsWith('<img')) {
        final srcMatch = RegExp(r'src="([^"]+)"').firstMatch(token);
        if (srcMatch != null) {
          final src = srcMatch.group(1)!;
          if (src.startsWith('data:image/')) {
            final bytes = _decodeBase64Image(src);
            spans.add(
              WidgetSpan(
                child: _ImageBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      cacheWidth: _imageDecodeWidth,
                    ),
                  ),
                ),
              ),
            );
          } else if (src.startsWith('http')) {
            spans.add(
              WidgetSpan(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Image.network(
                    src,
                    fit: BoxFit.contain,
                    cacheWidth: _imageDecodeWidth,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      // Image-shaped shimmer instead of a spinner while the
                      // question image downloads.
                      return MathRenderTheme.of(context)
                          .buildImagePlaceholder(context);
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return const SizedBox(
                        height: 100,
                        child: Center(child: Icon(Icons.broken_image)),
                      );
                    },
                  ),
                ),
              ),
            );
          }
        }
      } else if (token == '__BOLD__') {
        bold = true;
      } else if (token == '__/BOLD__') {
        bold = false;
      } else if (token == '__ITAL__') {
        ital = true;
      } else if (token == '__/ITAL__') {
        ital = false;
      } else if (token == '__ULINE__') {
        uline = true;
      } else if (token == '__/ULINE__') {
        uline = false;
      } else if (token == '__SUP__') {
        sup = true;
      } else if (token == '__/SUP__') {
        sup = false;
      } else if (token == '__SUB__') {
        sub = true;
      } else if (token == '__/SUB__') {
        sub = false;
      } else if (token.startsWith(r'$')) {
        var latex = token.substring(1, token.length - 1);
        latex = _sanitizeLatex(latex);
        final mathWidget = Math.tex(
          latex,
          textStyle: _katexTextStyle(style),
          mathStyle: MathStyle.display,
        );
        // A wide construct (matrix / determinant / multi-line aligned block)
        // can be wider than the screen and cannot wrap. Give ONLY that equation
        // its own horizontal scroll, so the surrounding Bengali/English prose
        // still wraps word-by-word and only the wide math scrolls — instead of
        // dragging the whole line (text included) off-screen.
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _isWideLatex(latex)
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: mathWidget,
                  )
                : mathWidget,
          ),
        );
      }

      last = m.end;
    }

    if (last < text.length) {
      spans.add(
        _createTextSpan(
          text.substring(last),
          style,
          bold,
          sup,
          sub,
          italic: ital,
          underline: uline,
        ),
      );
    }

    return spans;
  }

  // True for LaTeX that renders into a wide, non-wrappable block: a structural
  // block (matrix / determinant / multi-line aligned-cases) OR a long single
  // equation (e.g. a vector definition / a big expansion). Such a span is given
  // its own horizontal scroll so prose around it keeps wrapping at the screen
  // edge and only the math scrolls — instead of the whole line overflowing.
  bool _isWideLatex(String latex) {
    if (_wideEnvRegex.hasMatch(latex)) {
      return true;
    }
    // Approximate the on-screen length: collapse every `\command` to a single
    // glyph and drop braces / spaces so the measure tracks the *visible*
    // symbols (a vector line is `\hat`/`\vec`-heavy in source but short on
    // screen). Anything past a phone line's worth of glyphs is treated as wide.
    final visible = latex
        .replaceAll(_latexCommandRegex, 'x')
        .replaceAll(_latexNoiseRegex, '');
    return _renderedLength(visible) > 28;
  }

  // Non-spacing Bangla marks: they stack on the previous letter instead of
  // taking width of their own.
  bool _isBengaliNonSpacing(int c) =>
      c == 0x0981 || // candrabindu
      c == 0x09BC || // nukta
      (c >= 0x09C1 && c <= 0x09C4) || // u / uu / ri / rri vowel signs
      c == 0x09CD || // hasant — fuses the next consonant into one conjunct
      c == 0x09E2 ||
      c == 0x09E3;

  // Glyphs actually drawn, which is what the width threshold above means to
  // measure. `.length` counts UTF-16 code units and so over-measures Bangla:
  // `শ্রে` is four code units but one glyph. That inflation pushed equations
  // that comfortably fit past the threshold, promoting them to their own line
  // and stranding the prose around them on lines of their own. Latin and digits
  // carry no combining marks, so their count is identical either way.
  int _renderedLength(String s) {
    int n = 0, i = 0;
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (_isBengaliNonSpacing(c)) {
        // The consonant following a hasant joins the one before it — the three
        // code units draw as a single conjunct.
        if (c == 0x09CD && i + 1 < s.length) i++;
        i++;
        continue;
      }
      n++;
      i++;
    }
    return n;
  }

  // Matches the two token forms that can hold a full equation. `__FRAC__` /
  // `__DOT__` are deliberately absent: they are always small enough to sit
  // inline, so they never force a line break.
  static final RegExp _mathTokenRegex = RegExp(
    r'(__BMATH__[\s\S]*?__/BMATH__|\$[\s\S]*?\$)',
  );

  // The LaTeX carried by a `$...$` / `__BMATH__` token. `__BMATH__` payloads go
  // to [_buildMathWidget] unsanitized (its own parser normalizes them), so they
  // are measured unsanitized too.
  String _tokenLatex(String token) => token.startsWith('__BMATH__')
      ? token.substring(9, token.length - 10)
      : _sanitizeLatex(token.substring(1, token.length - 1));

  bool _isWideMathToken(String token) => _isWideLatex(_tokenLatex(token));

  // A wide equation promoted to its own line. Intrinsic width, no inner scroll:
  // it extends past the screen and the enclosing horizontal scroll view reveals
  // it — the same treatment a line that is *only* a wide equation already got.
  Widget _wideMathBlock(String token, TextStyle style) {
    final latex = _tokenLatex(token);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: token.startsWith('__BMATH__')
          ? _buildMathWidget(latex, style)
          : Math.tex(
              latex,
              textStyle: _katexTextStyle(style),
              mathStyle: MathStyle.display,
            ),
    );
  }

  // Splits [line] at each equation too wide to share a line with prose, so a
  // mixed line renders as: prose, equation on its own line, prose. Math short
  // enough to fit is left inside the prose segments and keeps wrapping with the
  // text — only width forces the break. A line with no wide equation comes back
  // as a single prose segment.
  List<_LineSegment> _splitAtWideMath(String line) {
    final segments = <_LineSegment>[];
    int last = 0;
    for (final m in _mathTokenRegex.allMatches(line)) {
      final token = m.group(0)!;
      if (!_isWideMathToken(token)) continue;
      if (m.start > last) {
        segments.add(_LineSegment.text(line.substring(last, m.start)));
      }
      segments.add(_LineSegment.math(token));
      last = m.end;
    }
    if (segments.isEmpty) return [_LineSegment.text(line)];
    if (last < line.length) {
      segments.add(_LineSegment.text(line.substring(last)));
    }
    return segments;
  }

  // ===========================================================================
  // FULL-CONTAINER SCROLL PATH (answers / MCQ options)
  // ===========================================================================
  // Whole content lives inside ONE horizontal scroll surface. Pure-text lines
  // are bounded to the screen width so prose still wraps; lines that carry a
  // wide equation/image keep their natural (intrinsic) width. So when ANY line
  // is wider than the screen the entire column becomes wider than the screen and
  // the WHOLE container scrolls horizontally together — not just that one line.
  Widget _buildScrollableContent(String content, TextStyle style, bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 0;
        final blocks = _buildBlocks(content, style, isDark, maxWidth);
        // The LayoutBuilder above still measures the real screen width (this
        // scroll view is its child, not its parent), so `maxWidth` stays finite
        // and prose lines keep wrapping. Only the intrinsic-width rows that hold
        // a wide equation/matrix extend past the screen — and now they scroll
        // horizontally inside this surface instead of overflowing/clipping.
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: blocks,
            ),
          ),
        );
      },
    );
  }

  // Splits content into line/table blocks (tables rendered between text runs).
  List<Widget> _buildBlocks(
    String content,
    TextStyle style,
    bool isDark,
    double maxWidth,
  ) {
    final blocks = <Widget>[];
    final tableRegex = RegExp(r'<table[\s\S]*?</table>', caseSensitive: false);
    int lastIndex = 0;

    for (final match in tableRegex.allMatches(content)) {
      final before = content.substring(lastIndex, match.start);
      if (before.trim().isNotEmpty) {
        blocks.addAll(_buildLineBlocks(before, style, isDark, maxWidth));
      }
      for (final span in _renderTableExactly(match.group(0)!, style, isDark)) {
        // The table renderer's LayoutBuilder expects a finite width (it gets one
        // inside the per-equation RichText). Here the outer horizontal scroll
        // gives unbounded width, so bound the table block to the screen width —
        // it keeps its own internal horizontal scroll. Without this the table's
        // ConstrainedBox(minWidth: maxWidth) is forced to infinity and crashes.
        blocks.add(
          maxWidth > 0
              ? SizedBox(width: maxWidth, child: span.child)
              : span.child,
        );
      }
      lastIndex = match.end;
    }

    final remaining = content.substring(lastIndex);
    if (remaining.trim().isNotEmpty) {
      blocks.addAll(_buildLineBlocks(remaining, style, isDark, maxWidth));
    }
    return blocks;
  }

  // Each `\n`-separated line becomes one block. A text-only line wraps at
  // [maxWidth]; a line containing math / an image is laid out as an intrinsic
  // -width Row so it can extend past the screen and drive the shared scroll.
  List<Widget> _buildLineBlocks(
    String text,
    TextStyle style,
    bool isDark,
    double maxWidth,
  ) {
    final blocks = <Widget>[];
    bool bold = false, sup = false, sub = false, ital = false, uline = false;
    // Paragraph alignment, as [_AlignTracker] reads it: a line takes the
    // marker in force where it starts; markers later in it carry forward.
    String curAlign = _kAlignStart, lineAlign = _kAlignStart;

    var pieces = <_InlinePiece>[];

    // Every line is a width-bounded, wrapping RichText: anything wide enough to
    // break the line was already pulled out into its own block before it could
    // reach [pieces], so what is left is prose plus math small enough to sit
    // inline — and the prose must keep wrapping at the screen edge.
    void flushLine() {
      if (pieces.isEmpty) {
        if (blocks.isNotEmpty && blocks.last is! SizedBox) {
          blocks.add(SizedBox(height: (style.fontSize ?? 16) * 0.5));
        }
        return;
      }
      final spans = <InlineSpan>[
        for (final p in pieces)
          if (p.widget != null)
            WidgetSpan(alignment: PlaceholderAlignment.middle, child: p.widget!)
          else
            _createTextSpan(
              p.text!,
              style,
              p.bold,
              p.sup,
              p.sub,
              italic: p.italic,
              underline: p.underline,
            ),
      ];
      blocks.add(
        SizedBox(
          width: maxWidth,
          child: RichText(
            textAlign: _textAlignFor(lineAlign),
            text: TextSpan(children: spans),
          ),
        ),
      );
      pieces = <_InlinePiece>[];
    }

    void addText(String value) {
      if (value.isEmpty) return;
      final parts = value.split('\n');
      for (int i = 0; i < parts.length; i++) {
        if (i > 0) {
          flushLine();
          lineAlign = curAlign;
        }
        if (parts[i].isNotEmpty) {
          pieces.add(
            _InlinePiece.text(
              parts[i],
              bold: bold,
              sup: sup,
              sub: sub,
              italic: ital,
              underline: uline,
            ),
          );
        }
      }
    }

    final regex = _inlineTokenRegex;

    int last = 0;
    for (final m in regex.allMatches(text)) {
      if (m.start > last) addText(text.substring(last, m.start));
      final token = m.group(0)!;

      if (token.startsWith('__ALIGN_')) {
        curAlign = token;
        if (pieces.isEmpty) lineAlign = token;
      } else if (token.startsWith('__BMATH__')) {
        final mathStyle = bold
            ? style.copyWith(fontWeight: FontWeight.bold)
            : style;
        if (_isWideMathToken(token)) {
          flushLine();
          blocks.add(_wideMathBlock(token, mathStyle));
        } else {
          final latex = token.substring(9, token.length - 10);
          pieces.add(_InlinePiece.widget(_buildMathWidget(latex, mathStyle)));
        }
      } else if (token.startsWith('__FRAC__')) {
        final parts = _decodeFracToken(token);
        final fracStyle = bold
            ? style.copyWith(fontWeight: FontWeight.bold)
            : style;
        pieces.add(
          _InlinePiece.widget(_fractionWidget(parts[0], parts[1], fracStyle)),
        );
      } else if (token.startsWith('__DDOT__') || token.startsWith('__DOT__')) {
        final isDouble = token.startsWith('__DDOT__');
        final glyph = isDouble
            ? token.substring(8, token.length - 9)
            : token.substring(7, token.length - 8);
        final glyphStyle = bold
            ? style.copyWith(fontWeight: FontWeight.bold)
            : style;
        pieces.add(
          _InlinePiece.widget(_dottedGlyph(glyph, glyphStyle, isDouble)),
        );
      } else if (token.startsWith('<img')) {
        final image = _buildImageWidget(token, maxWidth);
        if (image != null) {
          flushLine();
          blocks.add(image);
        }
      } else if (token == '__BOLD__') {
        bold = true;
      } else if (token == '__/BOLD__') {
        bold = false;
      } else if (token == '__ITAL__') {
        ital = true;
      } else if (token == '__/ITAL__') {
        ital = false;
      } else if (token == '__ULINE__') {
        uline = true;
      } else if (token == '__/ULINE__') {
        uline = false;
      } else if (token == '__SUP__') {
        sup = true;
      } else if (token == '__/SUP__') {
        sup = false;
      } else if (token == '__SUB__') {
        sub = true;
      } else if (token == '__/SUB__') {
        sub = false;
      } else if (token.startsWith(r'$')) {
        if (_isWideMathToken(token)) {
          flushLine();
          blocks.add(_wideMathBlock(token, style));
        } else {
          pieces.add(
            _InlinePiece.widget(
              Math.tex(
                _tokenLatex(token),
                textStyle: _katexTextStyle(style),
                mathStyle: MathStyle.display,
              ),
            ),
          );
        }
      }

      last = m.end;
    }

    if (last < text.length) addText(text.substring(last));
    flushLine();

    // Drop a trailing blank-line spacer (childless SizedBox); never drop a
    // width-bounded content block (a SizedBox with a child).
    while (blocks.isNotEmpty &&
        blocks.last is SizedBox &&
        (blocks.last as SizedBox).child == null) {
      blocks.removeLast();
    }

    return blocks;
  }

  // Builds an <img> token as a width-bounded block.
  Widget? _buildImageWidget(String token, double maxWidth) {
    final srcMatch = RegExp(r'src="([^"]+)"').firstMatch(token);
    if (srcMatch == null) return null;
    final src = srcMatch.group(1)!;
    final double? w = maxWidth > 0 ? maxWidth : null;

    if (src.startsWith('data:image/')) {
      final bytes = _decodeBase64Image(src);
      return _ImageBox(
        width: w,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            cacheWidth: _imageDecodeWidth,
          ),
        ),
      );
    } else if (src.startsWith('http')) {
      return SizedBox(
        width: w,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Image.network(
            src,
            fit: BoxFit.contain,
            cacheWidth: _imageDecodeWidth,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              // Image-shaped shimmer instead of a spinner while the
              // question image downloads.
              return MathRenderTheme.of(context).buildImagePlaceholder(context);
            },
            errorBuilder: (context, error, stackTrace) {
              return const SizedBox(
                height: 100,
                child: Center(child: Icon(Icons.broken_image)),
              );
            },
          ),
        ),
      );
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  InlineSpan _createTextSpan(
    String text,
    TextStyle style,
    bool bold,
    bool sup,
    bool sub, {
    bool italic = false,
    bool underline = false,
  }) {
    if (sup || sub) {
      final base = style.fontSize ?? 16;
      TextStyle scriptStyle = style.copyWith(fontSize: base * 0.7);
      if (italic) {
        scriptStyle = scriptStyle.copyWith(fontStyle: FontStyle.italic);
      }
      return WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Transform.translate(
          offset: Offset(0, sup ? -base * 0.32 : base * 0.18),
          child: Text(text, style: scriptStyle),
        ),
      );
    }
    TextStyle out = style;
    if (bold) out = out.copyWith(fontWeight: FontWeight.bold);
    if (italic) out = out.copyWith(fontStyle: FontStyle.italic);
    if (underline) out = out.copyWith(decoration: TextDecoration.underline);
    return TextSpan(text: text, style: out);
  }

  // ---------------------------------------------------------------------------
  String _removeEmptyTags(String html) {
    return html
        .replaceAll(RegExp(r'<sup>\s*</sup>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<sub>\s*</sub>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<span[^>]*>', caseSensitive: false), '')
        .replaceAll(RegExp(r'</span>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<div[^>]*>', caseSensitive: false), '') // ✅ ADD
        .replaceAll(RegExp(r'</div>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<strong[^>]*>', caseSensitive: false), '__BOLD__')
        .replaceAll(RegExp(r'</strong>', caseSensitive: false), '__/BOLD__')
        // `<b>` / `<i>` / `<u>` carry the emphasis in these answer descriptions
        // (`<strong><u>বর্গমূল নির্ণয়</u></strong>`, the `<i>💡 নোট:</i>` footer).
        // Without markers of their own the tags reached the RichText and were
        // drawn as literal `<u>` / `<i>` text. The patterns are anchored on `>`
        // or whitespace so `<img>`, `<br>` and `<ul>` are NOT swallowed here.
        .replaceAll(
          RegExp(r'<b(?:\s[^>]*)?>', caseSensitive: false),
          '__BOLD__',
        )
        .replaceAll(RegExp(r'</b>', caseSensitive: false), '__/BOLD__')
        .replaceAll(
          RegExp(r'<i(?:\s[^>]*)?>', caseSensitive: false),
          '__ITAL__',
        )
        .replaceAll(RegExp(r'</i>', caseSensitive: false), '__/ITAL__')
        .replaceAll(
          RegExp(r'<u(?:\s[^>]*)?>', caseSensitive: false),
          '__ULINE__',
        )
        .replaceAll(RegExp(r'</u>', caseSensitive: false), '__/ULINE__')
        // `<pre>` holds the long-division working (its `<br>`s become newlines
        // just below, and RichText keeps the alignment spaces).
        .replaceAll(RegExp(r'</?pre[^>]*>', caseSensitive: false), '\n')
        // A paragraph's `text-align` (inline style, or Quill's `ql-align-*`
        // class) survives as an [_alignMarker] so the line it opens can be laid
        // out justified / centred / right-aligned like the admin panel shows it.
        // `</p>` resets it for whatever follows the paragraph. A line takes the
        // alignment in force where it starts (see [_AlignTracker]), so the
        // reset at the end of a line doesn't touch the line it ends.
        .replaceAllMapped(
          RegExp(r'<p(\s[^>]*)?>', caseSensitive: false),
          (m) => _alignMarker(m.group(1) ?? ''),
        )
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '$_kAlignStart\n')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        // Blank-line collapse, looking through the markers a `</p><p>` pair now
        // leaves between newlines — so paragraph spacing stays what it was.
        .replaceAll(RegExp(r'\n(?:(?:__ALIGN_[A-Z]+__)*\n){2,}'), '\n\n')
        .trim();
  }

  String _protectSupSub(String html) {
    html = html.replaceAllMapped(
      RegExp(r'<sup.*?>(.*?)</sup>', caseSensitive: false),
      (m) => '__SUP__${m.group(1)}__/SUP__',
    );
    html = html.replaceAllMapped(
      RegExp(r'<sub.*?>(.*?)</sub>', caseSensitive: false),
      (m) => '__SUB__${m.group(1)}__/SUB__',
    );
    html = html.replaceAllMapped(
      RegExp(r'<span[^>]*>(.*?)</span>', dotAll: true),
      (m) => m.group(1) ?? '',
    );
    html = html.replaceAllMapped(
      RegExp(r'<em[^>]*>(.*?)</em>', dotAll: true),
      (m) => m.group(1) ?? '',
    );
    return html;
  }

  String _protectLatex(String html, Map<String, String> mathMap) {
    int index = 0;
    return html.replaceAllMapped(RegExp(r'\$.*?\$'), (m) {
      final key = '__MATH_${index++}__';
      mathMap[key] = m.group(0)!;
      return key;
    });
  }

  String _restoreLatex(String html, Map<String, String> mathMap) {
    mathMap.forEach((k, v) => html = html.replaceAll(k, v));
    return html;
  }

  String _convertMathMLToLatex(String html) {
    return html
        .replaceAllMapped(
          RegExp(
            r'<msup><mrow><mi>(.*?)</mi></mrow><mrow><mn>(.*?)</mn></mrow></msup>',
          ),
          (m) => '${m[1]}^${m[2]}',
        )
        .replaceAllMapped(RegExp(r'<mi>(.*?)</mi>'), (m) => m[1]!)
        .replaceAllMapped(RegExp(r'<mn>(.*?)</mn>'), (m) => m[1]!)
        .replaceAllMapped(RegExp(r'<mo>(.*?)</mo>'), (m) => m[1]!)
        .replaceAll(RegExp(r'<mrow[^>]*>|</mrow>'), '');
  }

  String _sanitizeLatex(String latex) {
    if (latex.contains(r'\\') && !latex.contains(r'\begin')) {
      final lines = latex
          .split(r'\\')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      // A token that is nothing but row separators (`$\\$`, `$\\ \\$`) leaves
      // nothing behind once the empties are dropped, and reading `.first` off
      // that empty list crashed the whole question card.
      latex = lines.isEmpty
          ? ''
          : lines.length > 1
          ? r'\begin{aligned}' + lines.join(r' \\ ') + r'\end{aligned}'
          : lines.first;
    }
    latex = latex.replaceAll(r'\begin{gathered}', r'\begin{aligned}');
    latex = latex.replaceAll(r'\end{gathered}', r'\end{aligned}');
    latex = latex.replaceAll(r'\rightarrow', r'\to');
    latex = latex.replaceAllMapped(RegExp(r'_\s*{'), (_) => '_{');
    latex = latex.replaceAllMapped(RegExp(r'\^\s*{'), (_) => '^{');
    latex = latex.replaceAllMapped(
      RegExp(r'\\operatorname\s*\{([^}]*)\}'),
      (m) => '\\mathrm{${m.group(1)}}',
    );
    latex = latex.replaceAll(r'\left\{', r'\left(');
    latex = latex.replaceAll(r'\right\}', r'\right)');
    latex = latex.replaceAll(r'\re', r'\mathrm{Re}');
    // flutter_math_fork leaves KaTeX's `\AA` macro undefined, so an Ångström
    // unit (`1025.73\,\AA`) failed the whole expression with "Undefined
    // control sequence". Spell it out with the ring accent the engine has.
    latex = latex.replaceAllMapped(
      RegExp(r'\\AA(?![a-zA-Z])'),
      (_) => r'\mathring{\mathrm{A}}',
    );
    return latex;
  }

  // ---------------------------------------------------------------------------
  // EXTRACT KATEX & MATHML
  // ---------------------------------------------------------------------------
}

/// One inline piece of a rendered line (full-container-scroll path): either
/// plain [text] (with its bold / sup / sub flags) or a small [widget] (a
/// fraction, a dotted glyph, a short equation) that sits inline as a
/// [WidgetSpan]. Anything too wide to share a line never becomes a piece — it
/// is emitted as its own block by [EquationSolver._wideMathBlock].
class _LineSegment {
  /// A prose run — may still contain short inline math, which stays inline.
  final String? text;

  /// A `$...$` / `__BMATH__` token wide enough to need a line of its own.
  final String? mathToken;

  const _LineSegment.text(this.text) : mathToken = null;
  const _LineSegment.math(this.mathToken) : text = null;
}

// ═══════════════════════════════════════════════════════════════════════════
// PARAGRAPH ALIGNMENT
// ═══════════════════════════════════════════════════════════════════════════
// The equation path flattens `<p>` into lines, which used to drop the
// paragraph's `text-align` — so a justified explanation with inline LaTeX came
// out ragged-right while the admin panel (a browser) justified it. Each `<p>`
// now leaves one of these markers where it opened; the renderers strip them and
// hand the alignment to the paragraph's RichText.

const String _kAlignStart = '__ALIGN_START__';
const String _kAlignJustify = '__ALIGN_JUSTIFY__';
const String _kAlignCenter = '__ALIGN_CENTER__';
const String _kAlignRight = '__ALIGN_RIGHT__';

final RegExp _alignMarkerRegex = RegExp(
  r'__ALIGN_(START|JUSTIFY|CENTER|RIGHT)__',
);

/// The marker for a `<p>` with these [attrs]: an inline `text-align`, or the
/// `ql-align-*` class the Quill editor writes instead.
String _alignMarker(String attrs) {
  final m =
      RegExp(
        r'text-align\s*:\s*(justify|center|right|left|start|end)',
        caseSensitive: false,
      ).firstMatch(attrs) ??
      RegExp(
        r'ql-align-(justify|center|right)',
        caseSensitive: false,
      ).firstMatch(attrs);
  switch (m?.group(1)?.toLowerCase()) {
    case 'justify':
      return _kAlignJustify;
    case 'center':
      return _kAlignCenter;
    case 'right':
    case 'end':
      return _kAlignRight;
    default:
      return _kAlignStart;
  }
}

TextAlign _textAlignFor(String? marker) {
  switch (marker) {
    case _kAlignJustify:
      return TextAlign.justify;
    case _kAlignCenter:
      return TextAlign.center;
    case _kAlignRight:
      return TextAlign.right;
    default:
      return TextAlign.start;
  }
}

/// Follows the markers line by line. A line takes the alignment in force
/// where it starts — the last of any markers it opens with, else whatever the
/// previous lines left set — and every marker in it (such as the reset a
/// `</p>` leaves at its end) then carries on to the lines after it.
class _AlignTracker {
  String _current = _kAlignStart;

  /// The alignment for [line], advancing the tracker past it.
  TextAlign next(String line) {
    var lineMarker = _current;
    final leading = _leadingAlignRegex.firstMatch(line);
    if (leading != null) {
      lineMarker = _alignMarkerRegex
          .allMatches(leading.group(1)!)
          .last
          .group(0)!;
    }
    final all = _alignMarkerRegex.allMatches(line);
    if (all.isNotEmpty) _current = all.last.group(0)!;
    return _textAlignFor(lineMarker);
  }
}

String _stripAlignMarkers(String s) => s.replaceAll(_alignMarkerRegex, '');

class _InlinePiece {
  final String? text;
  final bool bold;
  final bool sup;
  final bool sub;
  final bool italic;
  final bool underline;
  final Widget? widget;

  const _InlinePiece.text(
    this.text, {
    this.bold = false,
    this.sup = false,
    this.sub = false,
    this.italic = false,
    this.underline = false,
  }) : widget = null;

  const _InlinePiece.widget(this.widget)
    : text = null,
      bold = false,
      sup = false,
      sub = false,
      italic = false,
      underline = false;
}

/// The text of a `{...}` group plus the index just past its closing brace —
/// returned by [EquationSolver._readBalancedGroup].
class _BraceGroup {
  final String text;
  final int end;
  const _BraceGroup(this.text, this.end);
}

/// One piece of a Bengali-safe equation, parsed by
/// [EquationSolver._parseMathAtoms] and drawn by [EquationSolver._atomSpans].
/// The tree nests (a root inside a fraction inside a script), which is exactly
/// what the flat `__FRAC__` / `__SUP__` text markers cannot express.
sealed class _MathAtom {
  const _MathAtom();
}

/// A literal run — digits (Bengali kept as Bengali), operators, relations — or a
/// latin variable run, drawn [italic] like the math engine would.
class _MathRun extends _MathAtom {
  final String text;
  final bool italic;
  const _MathRun(this.text, this.italic);
}

class _MathFrac extends _MathAtom {
  final List<_MathAtom> numerator;
  final List<_MathAtom> denominator;
  const _MathFrac(this.numerator, this.denominator);
}

/// `\sqrt{body}`, or `\sqrt[index]{body}` for a cube (or nth) root.
class _MathRoot extends _MathAtom {
  final List<_MathAtom> body;
  final List<_MathAtom>? index;
  const _MathRoot(this.body, this.index);
}

/// A superscript ([isSup]) or subscript run.
class _MathScript extends _MathAtom {
  final List<_MathAtom> body;
  final bool isSup;
  const _MathScript(this.body, this.isSup);
}

/// A `\begin{array}…\end{array}`-style grid: [rows] of cells, each cell its own
/// atom list. [columnAlign] holds the `l` / `c` / `r` letters of an `array`'s
/// column spec (empty for the environments that don't take one) and [name] is
/// the environment, which decides the alignment when the spec runs out.
class _MathEnv extends _MathAtom {
  final List<List<List<_MathAtom>>> rows;
  final List<String> columnAlign;
  final String name;
  const _MathEnv(this.rows, this.columnAlign, this.name);
}

/// `\xrightarrow[below]{above}` — an arrow carrying reaction conditions.
class _MathArrow extends _MathAtom {
  final List<_MathAtom> above;
  final List<_MathAtom> below;
  final bool pointsRight;
  const _MathArrow(this.above, this.below, this.pointsRight);
}

/// Draws the shaft and head of a [_MathArrow] across the full width it is given,
/// so the arrow always spans its widest label.
class _ArrowPainter extends CustomPainter {
  final Color color;
  final bool pointsRight;
  final double thickness;

  const _ArrowPainter({
    required this.color,
    required this.pointsRight,
    required this.thickness,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final double y = size.height / 2;
    final double head = (size.height * 0.42).clamp(3.0, 7.0).toDouble();
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    final double tip = pointsRight ? size.width : 0;
    final double back = pointsRight ? size.width - head : head;
    canvas
      ..drawLine(Offset(tip, y), Offset(back, y - head * 0.75), paint)
      ..drawLine(Offset(tip, y), Offset(back, y + head * 0.75), paint);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) =>
      old.color != color ||
      old.pointsRight != pointsRight ||
      old.thickness != thickness;
}

/// Paints the radical sign and the overline around a [_MathRoot]'s content. The
/// box it is given is the content plus its padding, so the bar always spans the
/// whole expression under the root and the sign grows with a tall body (a nested
/// root, a fraction). [lead] is the width reserved for the arm.
class _RadicalPainter extends CustomPainter {
  final Color color;
  final double lead;
  final double stroke;

  const _RadicalPainter({
    required this.color,
    required this.lead,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double h = size.height;
    final double w = size.width;
    final path = Path()
      ..moveTo(lead * 0.04, h * 0.60)
      ..lineTo(lead * 0.30, h * 0.52)
      ..lineTo(lead * 0.56, h - stroke * 0.5)
      ..lineTo(lead * 0.86, stroke * 0.5)
      ..lineTo(w - stroke * 0.5, stroke * 0.5);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _RadicalPainter old) =>
      old.color != color || old.lead != lead || old.stroke != stroke;
}

/// Paints [count] small filled dots, horizontally centred, just above the glyph
/// box it decorates — the recurring-decimal overdot for [_dottedGlyph]. Drawn at
/// a negative y so it sits over (not inside) the digit; the host CustomPaint is
/// unclipped, so painting outside the box is fine.
class _OverdotPainter extends CustomPainter {
  final int count;
  final Color color;
  final double radius;

  const _OverdotPainter({
    required this.count,
    required this.color,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final double cy = -radius; // one radius above the glyph-box top edge
    final double cx = size.width / 2;
    if (count <= 1) {
      canvas.drawCircle(Offset(cx, cy), radius, paint);
    } else {
      final double gap = radius * 1.9;
      canvas.drawCircle(Offset(cx - gap, cy), radius, paint);
      canvas.drawCircle(Offset(cx + gap, cy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OverdotPainter old) =>
      old.count != count || old.color != color || old.radius != radius;
}

String extractKatexAnnotation(String html) {
  return html.replaceAllMapped(
    RegExp(
      r'<annotation[^>]*encoding="application/x-tex"[^>]*>(.*?)</annotation>',
      dotAll: true,
    ),
    (m) => '\$${m.group(1)!.trim()}\$',
  );
}

String extractMathML(String html) {
  return html.replaceAllMapped(
    RegExp(r'<math[^>]*>(.*?)</math>', dotAll: true),
    (m) {
      final mathml = m.group(1)!;
      String latex = mathml
          .replaceAllMapped(
            RegExp(r'<msup>\s*<mi>(.*?)</mi>\s*<mn>(.*?)</mn>\s*</msup>'),
            (m) => '${m[1]}^{${m[2]}}',
          )
          .replaceAllMapped(RegExp(r'<mi>(.*?)</mi>'), (m) => m[1]!)
          .replaceAllMapped(RegExp(r'<mn>(.*?)</mn>'), (m) => m[1]!)
          .replaceAllMapped(RegExp(r'<mo>−</mo>'), (m) => '-')
          .replaceAllMapped(RegExp(r'<mo>\+</mo>'), (m) => '+')
          .replaceAllMapped(RegExp(r'<mo>=</mo>'), (m) => '=')
          .replaceAll(RegExp(r'<[^>]+>'), '');
      return '\$${latex.trim()}\$';
    },
  );
}

String fixInlineExamMath(String html) {
  return html
      .replaceAllMapped(
        RegExp(r'<em>f</em>\s*\(x\)\s*=\s*0'),
        (_) => r'$f(x)=0$',
      )
      .replaceAllMapped(RegExp(r'α\s*এবং\s*β'), (_) => r'$\alpha$ এবং $\beta$')
      .replaceAllMapped(
        RegExp(r'q\s*\(\s*x\s*\+\s*1\s*2\s*=\s*4\s*p\s*2\s*x\s*\)'),
        (_) => r'$q(x+12=4p2x)$',
      );
}

String fixUndefinedLatexCommands(String input) {
  const knownFixes = {r'\bg': r'\mathrm{bg}', r'\re': r'\mathrm{Re}'};
  knownFixes.forEach((bad, good) => input = input.replaceAll(bad, good));
  return input;
}

String supportHtmlLists(String html) {
  html = html.replaceAllMapped(
    RegExp(r'<li[^>]*>(.*?)</li>', dotAll: true, caseSensitive: false),
    (m) => '\n• ${m.group(1)!.trim()}\n',
  );
  html = html.replaceAll(RegExp(r'</?ul[^>]*>', caseSensitive: false), '\n');
  return html;
}

List<WidgetSpan> _renderTableExactly(
  String tableHtml,
  TextStyle textStyle,
  bool isDark,
) {
  final spans = <WidgetSpan>[];
  final rowRegex = RegExp(r'<tr[\s\S]*?</tr>', caseSensitive: false);
  final cellRegex = RegExp(
    r'<t[dh][^>]*>(.*?)</t[dh]>',
    caseSensitive: false,
    dotAll: true,
  );
  var rows = <TableRow>[];

  // Turns a plain text run into spans, rendering the emphasis markers
  // (__BOLD__ / __ITAL__ / __ULINE__) as style and stripping them, so <strong>,
  // <i> and <u> inside a cell are never shown literally. Toggling on the markers
  // (rather than matching pairs) means a stray or nested marker still can't leak
  // into the visible text.
  List<InlineSpan> boldAwareSpans(String s) {
    final out = <InlineSpan>[];
    final markerRegex = RegExp(r'__(/?)(BOLD|ITAL|ULINE)__');
    bool bold = false, ital = false, uline = false;

    void addRun(String t) {
      if (t.isEmpty) return;
      var st = const TextStyle();
      if (bold) st = st.copyWith(fontWeight: FontWeight.bold);
      if (ital) st = st.copyWith(fontStyle: FontStyle.italic);
      if (uline) st = st.copyWith(decoration: TextDecoration.underline);
      out.add(TextSpan(text: t, style: st));
    }

    int li = 0;
    for (final m in markerRegex.allMatches(s)) {
      addRun(s.substring(li, m.start));
      final bool open = m.group(1)!.isEmpty;
      switch (m.group(2)) {
        case 'BOLD':
          bold = open;
        case 'ITAL':
          ital = open;
        case 'ULINE':
          uline = open;
      }
      li = m.end;
    }
    addRun(s.substring(li));
    return out;
  }

  for (final rowMatch in rowRegex.allMatches(tableHtml)) {
    final cells = <Widget>[];

    for (final cellMatch in cellRegex.allMatches(rowMatch.group(0)!)) {
      String html = _stripAlignMarkers(decodeHtmlEntities(cellMatch.group(1)!));
      html = html.replaceAll(RegExp(r'<span[^>]*>', caseSensitive: false), '');
      html = html.replaceAll(RegExp(r'</span>', caseSensitive: false), '');
      html = html.replaceAll(RegExp(r'<p[^>]*>', caseSensitive: false), '');
      html = html.replaceAll(RegExp(r'</p>', caseSensitive: false), '');
      final List<InlineSpan> cellSpans = [];
      int lastIndex = 0;

      // Regex for your placeholder __SUP__...__/SUP__
      final supRegex = RegExp(
        r'__SUP__(.*?)__/SUP__',
        caseSensitive: false,
        dotAll: true,
      );

      for (final match in supRegex.allMatches(html)) {
        // Normal text before __SUP__
        if (match.start > lastIndex) {
          String normalText = html.substring(lastIndex, match.start);
          if (normalText.isNotEmpty) {
            cellSpans.addAll(boldAwareSpans(normalText));
          }
        }

        // Superscript text
        String supText = match.group(1)!;
        if (supText.isNotEmpty) {
          cellSpans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.aboveBaseline,
              baseline: TextBaseline.alphabetic,
              child: Transform.translate(
                offset: const Offset(0, -4),
                child: Text(
                  supText,
                  style: textStyle.copyWith(
                    fontSize: (textStyle.fontSize ?? 14) * 0.7,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
            ),
          );
        }

        lastIndex = match.end;
      }

      // Remaining text after last __SUP__
      if (lastIndex < html.length) {
        String remaining = html.substring(lastIndex);
        if (remaining.isNotEmpty) cellSpans.addAll(boldAwareSpans(remaining));
      }

      // Add RichText cell
      cells.add(
        Padding(
          padding: const EdgeInsets.all(6),
          child: RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: textStyle.copyWith(
                fontSize: 14,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              children: cellSpans,
            ),
          ),
        ),
      );
    }

    if (cells.isNotEmpty) rows.add(TableRow(children: cells));
  }
  // 🔥 ADD THIS BLOCK RIGHT HERE
  int maxLength = 0;
  for (var r in rows) {
    if (r.children.length > maxLength) {
      maxLength = r.children.length;
    }
  }

  rows = rows.map((row) {
    List<Widget> padded = List.from(row.children);
    while (padded.length < maxLength) {
      padded.add(const SizedBox());
    }
    return TableRow(children: padded);
  }).toList();
  // 🔥 END OF BLOCK
  if (rows.isNotEmpty) {
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.top,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Table(
                    border: TableBorder.all(
                      color: isDark ? Colors.white38 : Colors.black54,
                    ),
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: rows,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  return spans;
}

String _removeMsOfficeConditionalBlocks(String html) {
  // Remove ALL MS Office conditional comments (if ... endif)
  html = html.replaceAllMapped(
    RegExp(
      r'<!--\s*\[if[^\]]*\]>[\s\S]*?<!\s*\[endif\]\s*-->',
      caseSensitive: false,
    ),
    (match) => '',
  );

  // Remove standalone endif leftovers
  html = html.replaceAll(
    RegExp(r'<!\s*\[endif\]\s*-->', caseSensitive: false),
    '',
  );

  // Remove standalone if !vml leftovers
  html = html.replaceAll(
    RegExp(r'<!--\s*\[if\s*!vml\]\s*-->', caseSensitive: false),
    '',
  );

  // Remove VML tags completely
  html = html.replaceAllMapped(
    RegExp(r'<v:[^>]+>[\s\S]*?</v:[^>]+>', caseSensitive: false),
    (match) => '',
  );

  return html;
}

String convertMsOfficeMathToLatex(String html) {
  return html.replaceAllMapped(
    RegExp(
      r'<!--\s*\[if gte msEquation 12\]>[\s\S]*?<m:oMathPara>[\s\S]*?</m:oMathPara>[\s\S]*?<!\[endif\]-->',
      caseSensitive: false,
    ),
    (match) {
      String block = match.group(0)!;

      final fractions = RegExp(
        r'<m:f[\s\S]*?</m:f>',
        caseSensitive: false,
      ).allMatches(block);

      String output = '';

      for (final frac in fractions) {
        String fracBlock = frac.group(0)!;

        final numMatch = RegExp(
          r'<m:num[\s\S]*?</m:num>',
          caseSensitive: false,
        ).firstMatch(fracBlock);

        final denMatch = RegExp(
          r'<m:den[\s\S]*?</m:den>',
          caseSensitive: false,
        ).firstMatch(fracBlock);

        if (numMatch != null && denMatch != null) {
          String numerator = _extractOfficeText(numMatch.group(0)!);
          String denominator = _extractOfficeText(denMatch.group(0)!);
          output += '\\(\\frac{$numerator}{$denominator}\\)';
        }
      }

      return output;
    },
  );
}

String _extractOfficeText(String input) {
  final matches = RegExp(
    r'<m:r[^>]*>[\s\S]*?<m:t[^>]*>(.*?)</m:t>[\s\S]*?</m:r>',
    caseSensitive: false,
  ).allMatches(input);

  String result = '';

  for (final m in matches) {
    result += m.group(1) ?? '';
  }

  return result.replaceAll('&nbsp;', ' ').replaceAll('\n', ' ').trim();
}

String _removeBrokenMsOfficeTags(String html) {
  // Remove broken MS Office tags like <!— [if ...] —>
  html = html.replaceAllMapped(
    RegExp(r'<![-–—]\s*\[if[^\]]*\][^>]*>', caseSensitive: false),
    (match) => '',
  );

  // Remove broken endif tags like <!—[endif]—>
  html = html.replaceAllMapped(
    RegExp(r'<![-–—]\s*\[endif\][^>]*>', caseSensitive: false),
    (match) => '',
  );

  return html;
}

Widget _buildImageFromSrc(String src) {
  // 🔥 Base64 image
  if (src.startsWith('data:image')) {
    return ZoomableImage(
      child: Image.memory(
        _decodeBase64Image(src),
        fit: BoxFit.contain,
        cacheWidth: _imageDecodeWidth * 2,
        errorBuilder: (context, error, stackTrace) {
          return const Offstage();
        },
      ),
    );
  }

  // 🔥 Normal network image
  return ZoomableImage(
    child: Image.network(
      src,
      fit: BoxFit.contain,
      cacheWidth: _imageDecodeWidth * 2,
      errorBuilder: (context, error, stackTrace) {
        return const Icon(Icons.broken_image);
      },
    ),
  );
}

class ZoomableImage extends StatelessWidget {
  final Widget child;

  const ZoomableImage({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          barrierColor: Colors.black,
          builder: (context) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(10),
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  color: MathRenderTheme.of(context).imageBackgroundColor,
                  padding: const EdgeInsets.all(12),
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 5,
                    child: Center(child: child),
                  ),
                ),
              ),
            );
          },
        );
      },
      child: child,
    );
  }
}

/// The white (by default) backing behind question images, from
/// [MathRenderThemeData.imageBackgroundColor].
class _ImageBox extends StatelessWidget {
  final double? width;
  final EdgeInsetsGeometry? padding;
  final Widget child;

  const _ImageBox({this.width, this.padding, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    color: MathRenderTheme.of(context).imageBackgroundColor,
    width: width,
    padding: padding,
    child: child,
  );
}
