import 'package:flutter/widgets.dart';

import '../../ast/options.dart';
import '../../ast/size.dart';
import '../../ast/symbols/symbols.dart';
import '../../ast/symbols/symbols_composite.dart';
import '../../ast/symbols/symbols_extra.dart';
import '../../ast/syntax_tree.dart';
import '../../ast/types.dart';
import '../../font/metrics/font_metrics.dart';
import '../layout/reset_dimension.dart';
import '../../utils/complex_script.dart';
import 'make_composite.dart';

BuildResult makeBaseSymbol({
  required String symbol,
  bool variantForm = false,
  required AtomType atomType,
  required Mode mode,
  FontOptions? overrideFont,
  required MathOptions options,
}) {
  // First lookup the render config table. We need the information
  var symbolRenderConfig = symbolRenderConfigs[symbol];
  if (symbolRenderConfig != null) {
    if (variantForm) {
      symbolRenderConfig = symbolRenderConfig.variantForm;
    }
    final renderConfig = mode == Mode.math
        ? (symbolRenderConfig?.math ?? symbolRenderConfig?.text)
        : (symbolRenderConfig?.text ?? symbolRenderConfig?.math);
    final char = renderConfig?.replaceChar ?? symbol;

    // Under \boldsymbol, operators and relations come from Main-Bold
    // when it has them (KaTeX buildCommon.mathsym).
    final mathFont = options.mathFontOptions;
    if (atomType != AtomType.ord &&
        mode == Mode.math &&
        mathFont != null &&
        mathFont.fontFamily == 'Math' &&
        mathFont.fontWeight == FontWeight.bold) {
      const mainBold = FontOptions(fontWeight: FontWeight.bold);
      final boldMetrics = lookupChar(char, mainBold, mode);
      if (boldMetrics != null) {
        return BuildResult(
          options: options,
          italic: 0.0,
          skew: boldMetrics.skew.cssEm.toLpUnder(options),
          widget: makeChar(char, mainBold, boldMetrics, options),
        );
      }
    }

    // Only mathord and textord will be affected by user-specified fonts
    // Also, surrogate pairs will ignore any user-specified font.
    if (atomType == AtomType.ord && symbol.codeUnitAt(0) != 0xD835) {
      final useMathFont =
          mode == Mode.math ||
          (mode == Mode.text && options.mathFontOptions != null);
      var font =
          overrideFont ??
          (useMathFont ? options.mathFontOptions : options.textFontOptions);

      if (font != null) {
        var charMetrics = lookupChar(char, font, mode);

        // Some font (such as boldsymbol) has fallback options
        if (charMetrics == null) {
          for (final fallback in font.fallback) {
            charMetrics = lookupChar(char, fallback, mode);
            if (charMetrics != null) {
              font = fallback;
              break;
            }
          }
          font!;
        }

        if (charMetrics != null) {
          final italic = charMetrics.italic.cssEm.toLpUnder(options);
          return BuildResult(
            options: options,
            italic: italic,
            skew: charMetrics.skew.cssEm.toLpUnder(options),
            widget: makeChar(
              symbol,
              font,
              charMetrics,
              options,
              needItalic: mode == Mode.math,
            ),
          );
        } else if (ligatures.containsKey(symbol) &&
            font.fontFamily == 'Typewriter') {
          // Make a special case for ligatures under Typewriter font
          final expandedText = ligatures[symbol]!.split('');
          return BuildResult(
            options: options,
            widget: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: expandedText
                  .map(
                    (e) =>
                        makeChar(e, font!, lookupChar(e, font, mode), options),
                  )
                  .toList(growable: false),
            ),
            italic: 0.0,
            skew: 0.0,
          );
        }
      }
    }

    // If the code reaches here, it means we failed to find any appliable
    // user-specified font. We will use default render configs.
    final defaultFont = renderConfig?.defaultFont ?? const FontOptions();
    final characterMetrics = getCharacterMetrics(
      character: renderConfig?.replaceChar ?? symbol,
      fontName: defaultFont.fontName,
      mode: Mode.math,
    );
    final italic = characterMetrics?.italic.cssEm.toLpUnder(options) ?? 0.0;
    // fontMetricsData[defaultFont.fontName][replaceChar.codeUnitAt(0)];
    return BuildResult(
      options: options,
      widget: makeChar(
        char,
        defaultFont,
        characterMetrics,
        options,
        needItalic: mode == Mode.math,
      ),
      italic: italic,
      skew: characterMetrics?.skew.cssEm.toLpUnder(options) ?? 0.0,
    );

    // Check if it is a special symbol
  } else if (mode == Mode.math && variantForm == false) {
    if (negatedOperatorSymbols.containsKey(symbol)) {
      final chars = negatedOperatorSymbols[symbol]!;
      return makeRlapCompositeSymbol(
        chars[0],
        chars[1],
        atomType,
        mode,
        options,
      );
    } else if (compactedCompositeSymbols.containsKey(symbol)) {
      final chars = compactedCompositeSymbols[symbol]!;
      final spacing = compactedCompositeSymbolSpacings[symbol]!;
      // final type = compactedCompositeSymbolTypes[symbol];
      return makeCompactedCompositeSymbol(
        chars[0],
        chars[1],
        spacing,
        atomType,
        mode,
        options,
      );
    } else if (decoratedEqualSymbols.contains(symbol)) {
      return makeDecoratedEqualSymbol(symbol, atomType, mode, options);
    }
  }
  return BuildResult(
    options: options,
    italic: 0.0,
    skew: 0.0,
    widget: makeChar(
      symbol,
      const FontOptions(),
      null,
      options,
      needItalic: mode == Mode.math,
    ),
  );
}

Widget makeChar(
  String character,
  FontOptions font,
  CharacterMetrics? characterMetrics,
  MathOptions options, {
  bool needItalic = false,
}) {
  final charWidget = ResetDimension(
    height: characterMetrics?.height.cssEm.toLpUnder(options),
    depth: characterMetrics?.depth.cssEm.toLpUnder(options),
    child: RichText(
      text: TextSpan(
        text: character,
        style: TextStyle(
          fontFamily: 'packages/flutter_math_equation/KaTeX_${font.fontFamily}',
          // A character the KaTeX font lacks is drawn from the caller's fonts
          // rather than whatever the platform happens to pick.
          fontFamilyFallback: _fallbackFamilies(options),
          fontWeight: font.fontWeight,
          fontStyle: font.fontShape,
          fontSize: 1.0.cssEm.toLpUnder(options),
          color: options.color,
        ),
      ),
      softWrap: false,
      overflow: TextOverflow.visible,
    ),
  );
  if (needItalic) {
    final italic = characterMetrics?.italic.cssEm.toLpUnder(options) ?? 0.0;
    return Padding(
      padding: EdgeInsets.only(right: italic),
      child: charWidget,
    );
  }
  return charWidget;
}

List<String> _fallbackFamilies(MathOptions options) => [
  ...options.fontFamilyFallback,
  bundledComplexScriptFontFamily,
];

/// Height above and depth below the baseline, in em, given to a complex-script
/// run. KaTeX has no metrics for these scripts and would size the run like an
/// `M` with no depth, letting Bengali vowel signs that hang below the line
/// (`ু`, `ূ`, `ৃ`) and the reph above it collide with fraction bars and
/// neighbouring rows. Measured on Noto Sans Bengali.
const double complexScriptHeightEm = 0.80;
const double complexScriptDepthEm = 0.28;

/// Draws a complex-script run (a Bengali word, digits) as one shaped piece of
/// text in the caller's prose font, so conjuncts and vowel signs join up.
///
/// Weight follows the active font options (`\textbf`, a bold text style); the
/// shape is only slanted for explicit text-mode italics (`\textit`), since
/// math-mode italics are meant for Latin variables and look wrong on Bengali.
BuildResult makeComplexScriptSymbol({
  required String text,
  required Mode mode,
  FontOptions? overrideFont,
  required MathOptions options,
}) {
  final font =
      overrideFont ??
      (mode == Mode.math ? options.mathFontOptions : options.textFontOptions);
  final families = _fallbackFamilies(options);
  final widget = ResetDimension(
    height: complexScriptHeightEm.cssEm.toLpUnder(options),
    depth: complexScriptDepthEm.cssEm.toLpUnder(options),
    child: RichText(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: families.first,
          fontFamilyFallback: families.sublist(1),
          fontWeight: font?.fontWeight ?? FontWeight.normal,
          fontStyle: mode == Mode.text ? font?.fontShape : FontStyle.normal,
          fontSize: 1.0.cssEm.toLpUnder(options),
          color: options.color,
        ),
      ),
      softWrap: false,
      overflow: TextOverflow.visible,
    ),
  );
  return BuildResult(options: options, italic: 0.0, skew: 0.0, widget: widget);
}

CharacterMetrics? lookupChar(String char, FontOptions font, Mode mode) =>
    getCharacterMetrics(character: char, fontName: font.fontName, mode: mode);
