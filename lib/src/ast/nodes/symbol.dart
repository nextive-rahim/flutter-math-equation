import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../render/symbols/make_symbol.dart';
import '../../utils/complex_script.dart';
import '../../utils/unicode_literal.dart';
import '../options.dart';
import '../symbols/symbols.dart';
import '../symbols/symbols_composite.dart';
import '../symbols/symbols_extra.dart';
import '../symbols/symbols_unicode.dart';
import '../symbols/unicode_accents.dart';
import '../syntax_tree.dart';
import '../types.dart';
import 'accent.dart';
import 'glyph_accent.dart';

/// Node for an unbreakable symbol.
class SymbolNode extends LeafNode {
  /// Unicode symbol.
  final String symbol;

  /// Whether it is a varaint form.
  ///
  /// Refer to MathJaX's variantForm
  final bool variantForm;

  /// Effective atom type for this symbol;
  late final AtomType atomType =
      overrideAtomType ??
      getDefaultAtomTypeForSymbol(symbol, variantForm: variantForm, mode: mode);

  /// Overriding atom type;
  final AtomType? overrideAtomType;

  /// Overriding atom font;
  final FontOptions? overrideFont;

  @override
  final Mode mode;

  // bool get noBreak => symbol == '\u00AF';

  SymbolNode({
    required this.symbol,
    this.variantForm = false,
    this.overrideAtomType,
    this.overrideFont,
    this.mode = Mode.math,
  }) : assert(symbol.isNotEmpty);

  @override
  BuildResult buildWidget(
    MathOptions options,
    List<BuildResult?> childBuildResults,
  ) {
    // A complex-script run (a Bengali word, possibly merged from several
    // parsed characters) must be shaped as a whole: splitting it into runes
    // below would treat its vowel signs as accents and drop them.
    if (isComplexScriptText(symbol)) {
      return makeComplexScriptSymbol(
        text: symbol,
        mode: mode,
        overrideFont: overrideFont,
        options: options,
      );
    }
    final expanded = symbol.runes
        .expand((code) {
          final ch = String.fromCharCode(code);
          return unicodeSymbols[ch]?.split('') ?? [ch];
        })
        .toList(growable: false);

    // If symbol is single code
    if (expanded.length == 1) {
      return makeBaseSymbol(
        symbol: expanded[0],
        variantForm: variantForm,
        atomType: atomType,
        overrideFont: overrideFont,
        mode: mode,
        options: options,
      );
    } else if (expanded.length > 1) {
      if (isCombiningMark(expanded[1])) {
        if (expanded[0] == 'i') {
          expanded[0] = '\u0131'; // dotless i, in math and text mode
        } else if (expanded[0] == 'j') {
          expanded[0] = '\u0237'; // dotless j, in math and text mode
        }
      }
      GreenNode res = withSymbol(expanded[0]);
      for (var ch in expanded.skip(1)) {
        // A combining cedilla hangs below the base (\c, KaTeX 0.13.15).
        if (ch == '\u0327') {
          res = GlyphAccentNode(
            base: res.wrapWithEquationRow(),
            glyph: '\u00b8',
            placement: GlyphAccentPlacement.below,
          );
          continue;
        }
        final accent = unicodeAccents[ch];
        if (accent == null) {
          break;
        } else {
          res = AccentNode(
            base: res.wrapWithEquationRow(),
            label: accent,
            isStretchy: false,
            isShifty: true,
          );
        }
      }
      return SyntaxNode(parent: null, value: res, pos: 0).buildWidget(options);
    } else {
      // TODO: log a warning here.
      return BuildResult(
        widget: SizedBox(height: 0, width: 0),
        options: options,
        italic: 0,
      );
    }
  }

  @override
  bool shouldRebuildWidget(MathOptions oldOptions, MathOptions newOptions) =>
      oldOptions.color != newOptions.color ||
      oldOptions.mathFontOptions != newOptions.mathFontOptions ||
      oldOptions.textFontOptions != newOptions.textFontOptions ||
      oldOptions.sizeMultiplier != newOptions.sizeMultiplier ||
      !listEquals(oldOptions.fontFamilyFallback, newOptions.fontFamilyFallback);

  @override
  AtomType get leftType => atomType;

  @override
  AtomType get rightType => atomType;

  @override
  Map<String, Object?> toJson() => super.toJson()
    ..addAll({
      'mode': mode.toString(),
      'symbol': unicodeLiteral(symbol),
      if (variantForm) 'variantForm': variantForm,
      if (overrideAtomType != null) 'atomType': overrideAtomType.toString(),
    });

  SymbolNode withSymbol(String symbol) {
    if (symbol == this.symbol) return this;
    return SymbolNode(
      symbol: symbol,
      variantForm: variantForm,
      overrideAtomType: overrideAtomType,
      overrideFont: overrideFont,
      mode: mode,
    );
  }
}

EquationRowNode stringToNode(String string, [Mode mode = Mode.text]) =>
    EquationRowNode(
      children: string
          .split('')
          .map((ch) => SymbolNode(symbol: ch, mode: mode))
          .toList(growable: false),
    );

AtomType getDefaultAtomTypeForSymbol(
  String symbol, {
  bool variantForm = false,
  required Mode mode,
}) {
  var symbolRenderConfig = symbolRenderConfigs[symbol];
  if (variantForm) {
    symbolRenderConfig = symbolRenderConfig?.variantForm;
  }
  final renderConfig = mode == Mode.math
      ? symbolRenderConfig?.math
      : symbolRenderConfig?.text;
  if (renderConfig != null) {
    return renderConfig.defaultType ?? AtomType.ord;
  }
  if (variantForm == false && mode == Mode.math) {
    if (negatedOperatorSymbols.containsKey(symbol)) {
      return AtomType.rel;
    }
    if (compactedCompositeSymbols.containsKey(symbol)) {
      return compactedCompositeSymbolTypes[symbol]!;
    }
    if (decoratedEqualSymbols.contains(symbol)) {
      return AtomType.rel;
    }
  }
  return AtomType.ord;
}

bool isCombiningMark(String ch) {
  final code = ch.codeUnitAt(0);
  return code >= 0x0300 && code <= 0x036f;
}
