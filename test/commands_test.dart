import 'dart:ui' show Color, FontStyle;

import 'package:flutter_math_equation/src/ast/nodes/box_ops.dart';
import 'package:flutter_math_equation/src/ast/nodes/include_graphics.dart';
import 'package:flutter_math_equation/src/ast/nodes/left_right.dart';
import 'package:flutter_math_equation/src/ast/nodes/space.dart';
import 'package:flutter_math_equation/src/ast/nodes/style.dart';
import 'package:flutter_math_equation/src/ast/nodes/symbol.dart';
import 'package:flutter_math_equation/src/ast/options.dart';
import 'package:flutter_math_equation/src/ast/syntax_tree.dart';
import 'package:flutter_math_equation/src/parser/tex/parse_error.dart';
import 'package:flutter_math_equation/src/parser/tex/parser.dart';
import 'package:flutter_math_equation/src/parser/tex/settings.dart';
import 'package:flutter_test/flutter_test.dart';

EquationRowNode parse(String tex) =>
    TexParser(tex, const TexParserSettings(strict: Strict.ignore)).parse();

Iterable<GreenNode> walk(GreenNode node) sync* {
  yield node;
  for (final child in node.children) {
    if (child != null) yield* walk(child);
  }
}

T first<T>(String tex) => walk(parse(tex)).whereType<T>().first;

String symbols(String tex) =>
    walk(parse(tex)).whereType<SymbolNode>().map((s) => s.symbol).join();

void main() {
  group('lexer', () {
    test('\\ followed by a newline or tab is a control space', () {
      expect(() => parse('a\\\nb'), returnsNormally);
      expect(() => parse('a\\\tb'), returnsNormally);
      expect(() => parse(r'\text{a\   b}'), returnsNormally);
    });
  });

  group('macros', () {
    test('\\providecommand keeps an existing command', () {
      expect(symbols(r'\newcommand\x{a}\providecommand\x{b}\x'), 'a');
      expect(symbols(r'\providecommand\y{c}\y'), 'c');
    });
    test('\\vdots and \\rule work in text mode', () {
      expect(() => parse(r'\text{a \vdots b}'), returnsNormally);
      expect(() => parse(r'\text{Answer: \rule{2cm}{0.4pt}}'), returnsNormally);
    });
    test('\\hspace and \\hspace*', () {
      expect(() => parse(r'a\hspace{1em}b\hspace*{2em}c'), returnsNormally);
    });
    test('colon relations', () {
      for (final cmd in [
        r'\coloneqq',
        r'\Coloneqq',
        r'\eqqcolon',
        r'\dblcolon',
        r'\colonapprox',
        r'\simcolon',
        '⩴',
        r'\coloneq',
      ]) {
        expect(() => parse('a $cmd b'), returnsNormally, reason: cmd);
      }
    });
    test('KaTeX 0.19 macros', () {
      for (final tex in [
        r'\AA',
        r'\text{\aa}',
        r'\injlim_n',
        r'\varlimsup_n',
        r'\mathstrut x',
        r'\underbar{x}',
        r'\dddot{x}',
        r'\ddddot{x}',
        r'\llap{a}',
        r'\rlap{a}',
        r'\clap{a}',
        r'\mapsfrom',
        '↤',
        r'\llbracket a \rrbracket',
        r'\lBrace a \rBrace',
        r'\minuso',
        '≝',
        'a~b',
        r'\pmb{x}',
        r'f\colon A \to B',
      ]) {
        expect(() => parse(tex), returnsNormally, reason: tex);
      }
    });
    test('\\Braket and \\set', () {
      final braket = parse(r'\Braket{ \phi | \psi }');
      expect(walk(braket).whereType<LeftRightNode>(), isNotEmpty);
      expect(() => parse(r'\set{ x | x > 0 }'), returnsNormally);
      expect(() => parse(r'\Set{ x | x \| y }'), returnsNormally);
    });
  });

  group('colors', () {
    test('#RGBA and #RRGGBBAA (alpha last)', () {
      Color colorOf(String tex) =>
          walk(parse(tex)).whereType<StyleNode>().first.optionsDiff.color!;
      expect(colorOf(r'\color{#ff000080} x').toARGB32(), 0x80FF0000);
      expect(colorOf(r'\color{#f008} x').toARGB32(), 0x88FF0000);
      expect(colorOf(r'\color{#f00} x').toARGB32(), 0xFFFF0000);
      expect(() => parse(r'\color{#ff00} x'), returnsNormally);
    });
  });

  group('new functions', () {
    test('\\smash and its [tb] argument', () {
      final both = first<SmashNode>(r'\smash{x}');
      expect((both.smashHeight, both.smashDepth), (true, true));
      final t = first<SmashNode>(r'\smash[t]{x}');
      expect((t.smashHeight, t.smashDepth), (true, false));
      final b = first<SmashNode>(r'\smash[b]{x}');
      expect((b.smashHeight, b.smashDepth), (false, true));
    });
    test('laps', () {
      expect(first<LapNode>(r'\mathllap{x}').alignment, LapAlignment.left);
      expect(first<LapNode>(r'\mathrlap{x}').alignment, LapAlignment.right);
      expect(first<LapNode>(r'\mathclap{x}').alignment, LapAlignment.center);
    });
    test('\\vcenter, \\reflectbox, \\mathchoice, \\hbox, \\html@mathml', () {
      expect(first<VCenterNode>(r'\vcenter{x}'), isNotNull);
      expect(first<ReflectNode>(r'\reflectbox{ab}'), isNotNull);
      expect(first<ReflectNode>(r'\mathreflectbox{x}'), isNotNull);
      expect(first<MathChoiceNode>(r'\mathchoice{a}{b}{c}{d}'), isNotNull);
      expect(() => parse(r'\hbox{text here}'), returnsNormally);
      expect(symbols(r'\html@mathml{a}{b}'), 'a');
    });
    test('\\@binrel takes the class of its first argument', () {
      final row = walk(parse(r'a \@binrel{=}{x} b'))
          .whereType<EquationRowNode>()
          .firstWhere((r) => r.overrideType != null);
      expect(row.overrideType, AtomType.rel);
    });
    test('\\overset is spaced like its base; \\stackrel is a relation', () {
      AtomType? classOf(String tex) =>
          walk(parse('a $tex b'))
              .whereType<EquationRowNode>()
              .firstWhere((r) => r.overrideType != null)
              .overrideType;
      expect(classOf(r'\overset{!}{=}'), AtomType.rel);
      expect(classOf(r'\overset{!}{x}'), AtomType.ord);
      expect(classOf(r'\stackrel{!}{x}'), AtomType.rel);
    });
    test('\\emph toggles italic', () {
      final emph = first<StyleNode>(r'\emph{x}');
      expect(emph.optionsDiff.textFontOptions!.toggleShape, isTrue);
      const upright = FontOptions();
      const italic = FontOptions(fontShape: FontStyleTestHelper.italic);
      expect(
        upright.mergeWith(emph.optionsDiff.textFontOptions).fontShape,
        FontStyleTestHelper.italic,
      );
      expect(
        italic.mergeWith(emph.optionsDiff.textFontOptions).fontShape,
        FontStyleTestHelper.normal,
      );
    });
    test('\\operatornamewithlimits and ignored \\limits', () {
      expect(
        () => parse(r'\operatornamewithlimits{argmax}_x f'),
        returnsNormally,
      );
      expect(() => parse(r'\operatorname{sn}\limits_x'), returnsNormally);
    });
    test('\\rule is spaced as an ordinary atom', () {
      final rule = walk(parse(r'x = \rule{1cm}{1pt}'))
          .whereType<SpaceNode>()
          .first;
      expect(rule.leftType, AtomType.ord);
    });
    test('\\char rejects code points beyond Unicode', () {
      expect(() => parse(r'\char"110000'), throwsA(isA<ParseException>()));
      expect(symbols(r'\char"10FFFF'), String.fromCharCode(0x10FFFF));
    });
  });
  group('HTML commands (KaTeX trust)', () {
    EquationRowNode parseTrusted(String tex, {bool trust = true}) => TexParser(
      tex,
      TexParserSettings(strict: Strict.ignore, trust: trust),
    ).parse();
    String symbolsOf(EquationRowNode row) =>
        walk(row).whereType<SymbolNode>().map((s) => s.symbol).join();

    test('untrusted commands show as unsupported (red) text', () {
      final row = parseTrusted(r'\href{https://x.org}{link}', trust: false);
      expect(symbolsOf(row), r'\href');
      expect(
        walk(row).whereType<StyleNode>().first.optionsDiff.color,
        const Color(0xFFCC0000),
      );
    });
    test('trusted \\href and \\html… show their body', () {
      expect(symbolsOf(parseTrusted(r'\href{https://x.org}{link}')), 'link');
      expect(symbolsOf(parseTrusted(r'\htmlClass{a}{b}')), 'b');
      expect(symbolsOf(parseTrusted(r'\htmlData{k=v, a=b}{c}')), 'c');
    });
    test('\\url keeps % and ~ and unescapes \\#', () {
      expect(
        symbolsOf(parseTrusted(r'\url{https://a.org/%20~me\#x}')),
        'https://a.org/%20~me#x',
      );
    });
    test('\\includegraphics options', () {
      final node = walk(
        parseTrusted(
          r'\includegraphics[height=2em, width=3em, alt=Logo]{https://x.org/logo.png}',
        ),
      ).whereType<IncludeGraphicsNode>().single;
      expect(node.alt, 'Logo');
      expect(node.height.value, 2);
      expect(node.width.value, 3);
      final defaults = walk(parseTrusted(r'\includegraphics{a/b/pic.png}'))
          .whereType<IncludeGraphicsNode>()
          .single;
      expect(defaults.alt, 'pic');
      expect(defaults.height.value, 0.9);
      expect(
        () => parseTrusted(r'\includegraphics[size=1]{a.png}'),
        throwsA(isA<ParseException>()),
      );
    });
    test('% outside a URL is still a comment', () {
      expect(symbols('a % comment\nb'), 'ab');
    });
  });
}

/// FontStyle without importing dart:ui twice in the expectations above.
abstract final class FontStyleTestHelper {
  static const italic = FontStyle.italic;
  static const normal = FontStyle.normal;
}
