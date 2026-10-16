import '../../render/symbols/make_symbol.dart';
import '../options.dart';
import '../size.dart';
import '../style.dart';
import '../syntax_tree.dart';
import '../types.dart';
import 'left_right.dart';

/// Heights of the stacked `\big`…`\Bigg` delimiters, in em (KaTeX
/// delimiter.ts sizeToMaxHeight).
const _sizeToMaxHeight = [0.0, 1.2, 1.8, 2.4, 3.0];

/// A delimiter of fixed size: `\big(`, `\Bigl[`, `\biggm|`, `\Biggr\}` …
/// (KaTeX delimiter.ts makeSizedDelim).
///
/// Ported from a SymbolNode with a Size font, which only took effect for
/// ordinary atoms, so `\bigl(`, `\Bigr)`, `\biggm|` came out at normal size.
class SizedDelimNode extends LeafNode {
  /// The delimiter character, already resolved (`<` is U+27E8 …).
  final String delim;

  /// 1 (`\big`) to 4 (`\Bigg`).
  final int size;

  /// open for `\bigl`, close for `\bigr`, rel for `\bigm`, ord for `\big`.
  final AtomType atomType;

  @override
  final Mode mode;

  SizedDelimNode({
    required this.delim,
    required this.size,
    required this.atomType,
    this.mode = Mode.math,
  }) : assert(size >= 1 && size <= 4);

  @override
  BuildResult buildWidget(
    MathOptions options,
    List<BuildResult?> childBuildResults,
  ) {
    if (stackAlwaysDelimiters.contains(delim)) {
      // Built from pieces to the size's full height, centred on the axis.
      return BuildResult(
        options: options,
        widget: makeStackedDelim(
          delim,
          _sizeToMaxHeight[size].cssEm.toLpUnder(options),
          Mode.math,
          options,
        ),
      );
    }
    // The glyph from the SizeN font, at text style relative to the base
    // size (KaTeX makeLargeDelim: styleWrap(…, Style.TEXT)).
    final textOptions = options.havingStyleUnderBaseSize(MathStyle.text);
    final font = FontOptions(fontFamily: 'Size$size');
    return BuildResult(
      options: options,
      widget: makeChar(
        delim,
        font,
        lookupChar(delim, font, Mode.math),
        textOptions,
      ),
    );
  }

  @override
  AtomType get leftType => atomType;

  @override
  AtomType get rightType => atomType;

  @override
  bool shouldRebuildWidget(MathOptions oldOptions, MathOptions newOptions) =>
      oldOptions.sizeMultiplier != newOptions.sizeMultiplier ||
      oldOptions.color != newOptions.color;

  @override
  Map<String, Object?> toJson() =>
      super.toJson()
        ..addAll({'delim': delim, 'size': size, 'atomType': atomType.name});
}
