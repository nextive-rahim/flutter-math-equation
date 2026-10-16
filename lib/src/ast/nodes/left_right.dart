import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';

import '../../font/metrics/font_metrics.dart';
import '../../render/constants.dart';
import '../../render/layout/layout_builder_baseline.dart';
import '../../render/layout/line.dart';
import '../../render/layout/shift_baseline.dart';
import '../../render/svg/delimiter.dart';
import '../../render/svg/svg_geomertry.dart';
import '../../render/svg/svg_path.dart';
import '../../render/symbols/make_symbol.dart';
import '../options.dart';
import '../size.dart';
import '../spacing.dart';
import '../syntax_tree.dart';
import '../types.dart';

/// Left right node.
class LeftRightNode extends SlotableNode<EquationRowNode> {
  /// Unicode symbol for the left delimiter character.
  final String? leftDelim;

  /// Unicode symbol for the right delimiter character.
  final String? rightDelim;

  /// List of inside bodys.
  ///
  /// Its length should be 1 longer than [middle].
  final List<EquationRowNode> body;

  /// List of middle delimiter characters.
  final List<String?> middle;

  LeftRightNode({
    required this.leftDelim,
    required this.rightDelim,
    required this.body,
    this.middle = const [],
  }) : assert(body.isNotEmpty),
       assert(middle.length == body.length - 1);

  @override
  BuildResult buildWidget(
    MathOptions options,
    List<BuildResult?> childBuildResults,
  ) {
    final numElements = 2 + body.length + middle.length;
    final a = options.fontMetrics.axisHeight.cssEm.toLpUnder(options);

    final childWidgets = List.generate(numElements, (index) {
      if (index % 2 == 0) {
        // Delimiter
        return LineElement(
          customCrossSize: (height, depth) {
            // Under unbounded constraints the row can report an infinite
            // extent; sizing a delimiter to it throws. Upstream PR
            // simpleclub/flutter_math#121.
            if (!height.isFinite || !depth.isFinite) {
              return const BoxConstraints(minHeight: 20.0);
            }
            final delta = math.max(height - a, depth + a);
            final delimeterFullHeight = math.max(
              delta / 500 * delimiterFactor,
              2 * delta - delimiterShorfall.toLpUnder(options),
            );
            return BoxConstraints(minHeight: delimeterFullHeight);
          },
          trailingMargin: index == numElements - 1
              ? 0.0
              : getSpacingSize(
                  index == 0 ? AtomType.open : AtomType.rel,
                  body[(index + 1) ~/ 2].leftType,
                  options.style,
                ).toLpUnder(options),
          child: LayoutBuilderPreserveBaseline(
            builder: (context, constraints) => buildCustomSizedDelimWidget(
              index == 0
                  ? leftDelim
                  : index == numElements - 1
                  ? rightDelim
                  : middle[index ~/ 2 - 1],
              constraints.minHeight,
              options,
            ),
          ),
        );
      } else {
        // Content
        return LineElement(
          trailingMargin: getSpacingSize(
            body[index ~/ 2].rightType,
            index == numElements - 2 ? AtomType.close : AtomType.rel,
            options.style,
          ).toLpUnder(options),
          child: childBuildResults[index ~/ 2]!.widget,
        );
      }
    }, growable: false);
    return BuildResult(
      options: options,
      widget: Line(children: childWidgets),
    );
  }

  @override
  List<MathOptions> computeChildOptions(MathOptions options) =>
      List.filled(body.length, options, growable: false);

  @override
  List<EquationRowNode> computeChildren() => body;

  @override
  AtomType get leftType => AtomType.open;

  @override
  AtomType get rightType => AtomType.close;

  @override
  bool shouldRebuildWidget(MathOptions oldOptions, MathOptions newOptions) =>
      false;

  @override
  LeftRightNode updateChildren(List<EquationRowNode> newChildren) =>
      LeftRightNode(
        leftDelim: leftDelim,
        rightDelim: rightDelim,
        body: newChildren,
        middle: middle,
      );

  @override
  Map<String, Object?> toJson() => super.toJson()
    ..addAll({
      'body': body.map((e) => e.toJson()),
      'leftDelim': leftDelim,
      'rightDelim': rightDelim,
      if (middle.isNotEmpty) 'middle': middle,
    });
}

// TexBook Appendix B
const delimiterFactor = 901;
const delimiterShorfall = Measurement(value: 5.0, unit: Unit.pt);

const stackLargeDelimiters = {
  '(', ')',
  '[', ']',
  '{', '}',
  '\u230a', '\u230b', // '\\lfloor', '\\rfloor',
  '\u2308', '\u2309', // '\\lceil', '\\rceil',
  '\u221a', // '\\surd'
};

// delimiters that always stack
const stackAlwaysDelimiters = {
  '\u2191', // '\\uparrow',
  '\u2193', // '\\downarrow',
  '\u2195', // '\\updownarrow',
  '\u21d1', // '\\Uparrow',
  '\u21d3', // '\\Downarrow',
  '\u21d5', // '\\Updownarrow',
  '|',
  // '\\|',
  // '\\vert',
  '\u2016', // '\\Vert', '\u2225'
  '\u2223', // '\\lvert', '\\rvert', '\\mid'
  '\u2225', // '\\lVert', '\\rVert',
  '\u27ee', // '\\lgroup',
  '\u27ef', // '\\rgroup',
  '\u23b0', // '\\lmoustache',
  '\u23b1', // '\\rmoustache',
};

// and delimiters that never stack
const stackNeverDelimiters = {
  '\u27e8', //'<',
  '\u27e9', //'>',
  '/',
  '\\', // \backslash: without it a tall \left\backslash threw.
};

Widget buildCustomSizedDelimWidget(
  String? delim,
  double minDelimiterHeight,
  MathOptions options,
) {
  if (delim == null) {
    final axisHeight = options.fontMetrics.xHeight.cssEm.toLpUnder(options);
    return ShiftBaseline(
      relativePos: 0.5,
      offset: axisHeight,
      child: SizedBox(
        height: minDelimiterHeight,
        width: nullDelimiterSpace.toLpUnder(options),
      ),
    );
  }

  List<DelimiterConf> sequence;
  if (stackNeverDelimiters.contains(delim)) {
    sequence = stackNeverDelimiterSequence;
  } else if (stackLargeDelimiters.contains(delim)) {
    sequence = stackLargeDelimiterSequence;
  } else {
    sequence = stackAlwaysDelimiterSequence;
  }

  var delimConf = sequence.firstWhereOrNull(
    (element) =>
        getHeightForDelim(
          delim: delim,
          fontName: element.font.fontName,
          style: element.style,
          options: options,
        ) >
        minDelimiterHeight,
  );
  if (stackNeverDelimiters.contains(delim)) {
    delimConf ??= sequence.last;
  }

  if (delimConf != null) {
    final axisHeight = options.fontMetrics.axisHeight.cssEm.toLpUnder(options);
    return ShiftBaseline(
      relativePos: 0.5,
      offset: axisHeight,
      child: makeChar(
        delim,
        delimConf.font,
        lookupChar(delim, delimConf.font, Mode.math),
        options,
      ),
    );
  } else {
    return makeStackedDelim(delim, minDelimiterHeight, Mode.math, options);
  }
}

/// KaTeX draws these tall delimiters as one SVG path (KaTeX 0.16.1): the
/// path label and its viewBox width.
const _tallDelimSvg = {
  '|': ('vert', 333),
  '\u2223': ('vert', 333),
  '\u2016': ('doublevert', 556),
  '\u2225': ('doublevert', 556),
  '[': ('lbrack', 667),
  ']': ('rbrack', 667),
  '\u230a': ('lfloor', 667),
  '\u230b': ('rfloor', 667),
  '\u2308': ('lceil', 667),
  '\u2309': ('rceil', 667),
  '(': ('lparen', 875),
  ')': ('rparen', 875),
};

/// Overlap between the pieces of a stacked delimiter, in em, so no hairline
/// gap shows between them (KaTeX delimiter.ts lapInEms).
const _lapInEms = 0.008;

/// A delimiter at least [minDelimiterHeight] tall, built from pieces and
/// centred on the axis (KaTeX delimiter.ts makeStackedDelim, 0.19.0).
///
/// ( ) [ ] ⌊ ⌋ ⌈ ⌉ | ‖ are drawn as a single SVG path; the others keep
/// their glyph ends with an SVG middle overlapping them. (Stacking repeated
/// glyphs left visible seams.)
Widget makeStackedDelim(
  String delim,
  double minDelimiterHeight,
  Mode mode,
  MathOptions options,
) {
  final conf = stackDelimiterConfs[delim]!;
  final topMetrics = lookupChar(conf.top, conf.font, Mode.math)!;
  final repeatMetrics = lookupChar(conf.repeat, conf.font, Mode.math)!;
  final bottomMetrics = lookupChar(conf.bottom, conf.font, Mode.math)!;

  // Heights in em, as in KaTeX.
  final topHeight = topMetrics.height + topMetrics.depth;
  final repeatHeight = repeatMetrics.height + repeatMetrics.depth;
  final bottomHeight = bottomMetrics.height + bottomMetrics.depth;
  var middleHeight = 0.0;
  var middleFactor = 1;
  CharacterMetrics? middleMetrics;
  if (conf.middle != null) {
    middleMetrics = lookupChar(conf.middle!, conf.font, Mode.math)!;
    middleHeight = middleMetrics.height + middleMetrics.depth;
    middleFactor = 2;
  }

  final emToLp = 1.0.cssEm.toLpUnder(options);
  final minHeight = topHeight + bottomHeight + middleHeight;
  final repeatCount = math
      .max(
        0,
        (minDelimiterHeight / emToLp - minHeight) /
            (middleFactor * repeatHeight),
      )
      .ceil();
  final realHeight = minHeight + repeatCount * middleFactor * repeatHeight;

  final axisHeight = options.fontMetrics.axisHeight.cssEm.toLpUnder(options);
  final color = options.color;

  Widget body;
  final tall = _tallDelimSvg[delim];
  if (tall != null) {
    final midHeight = realHeight - topHeight - bottomHeight;
    final viewBoxHeight = (realHeight * 1000).round();
    body = svgWidgetFromPath(
      tallDelim(tall.$1, (midHeight * 1000).round()),
      Size(tall.$2 / 1000 * emToLp, viewBoxHeight / 1000 * emToLp),
      Rect.fromLTWH(0, 0, tall.$2.toDouble(), viewBoxHeight.toDouble()),
      color,
    );
  } else {
    // The middle section is an SVG 0.016em taller than its slot, so it
    // overlaps the glyphs above and below by 0.008em.
    Widget inner(double heightEm) {
      final width =
          (lookupChar(conf.repeat, size4Font, Mode.math) ??
                  lookupChar(conf.repeat, size1Font, Mode.math)!)
              .width;
      final drawn = heightEm + 2 * _lapInEms;
      return SizedBox(
        width: width * emToLp,
        height: heightEm * emToLp,
        child: OverflowBox(
          minHeight: drawn * emToLp,
          maxHeight: drawn * emToLp,
          child: svgWidgetFromPath(
            innerPath(conf.repeat, (1000 * drawn).round()),
            Size(width * emToLp, drawn * emToLp),
            Rect.fromLTWH(0, 0, 1000 * width, (1000 * drawn).roundToDouble()),
            color,
            fit: BoxFit.contain,
          ),
        ),
      );
    }

    final innerHeight = conf.middle == null
        ? realHeight - topHeight - bottomHeight
        : (realHeight - topHeight - bottomHeight - middleHeight) / 2;
    body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        makeChar(conf.top, conf.font, topMetrics, options),
        inner(innerHeight),
        if (conf.middle != null) ...[
          makeChar(conf.middle!, conf.font, middleMetrics!, options),
          inner(innerHeight),
        ],
        makeChar(conf.bottom, conf.font, bottomMetrics, options),
      ],
    );
  }

  return ShiftBaseline(relativePos: 0.5, offset: axisHeight, child: body);
}

const size4Font = FontOptions(fontFamily: 'Size4');
const size1Font = FontOptions(fontFamily: 'Size1');

class StackDelimiterConf {
  final String top;
  final String? middle;
  final String repeat;
  final String bottom;
  final FontOptions font;
  const StackDelimiterConf({
    required this.top,
    this.middle,
    required this.repeat,
    required this.bottom,
    this.font = size4Font,
  });
}

const stackDelimiterConfs = {
  '\u2191': // '\\uparrow',
  StackDelimiterConf(
    top: '\u2191',
    repeat: '\u23d0',
    bottom: '\u23d0',
    font: size1Font,
  ),
  '\u2193': // '\\downarrow',
  StackDelimiterConf(
    top: '\u23d0',
    repeat: '\u23d0',
    bottom: '\u2193',
    font: size1Font,
  ),
  '\u2195': // '\\updownarrow',
  StackDelimiterConf(
    top: '\u2191',
    repeat: '\u23d0',
    bottom: '\u2193',
    font: size1Font,
  ),
  '\u21d1': // '\\Uparrow',
  StackDelimiterConf(
    top: '\u21d1',
    repeat: '\u2016',
    bottom: '\u2016',
    font: size1Font,
  ),
  '\u21d3': // '\\Downarrow',
  StackDelimiterConf(
    top: '\u2016',
    repeat: '\u2016',
    bottom: '\u21d3',
    font: size1Font,
  ),
  '\u21d5': // '\\Updownarrow',
  StackDelimiterConf(
    top: '\u21d1',
    repeat: '\u2016',
    bottom: '\u21d3',
    font: size1Font,
  ),
  '|': // '\\|' ,'\\vert',
  StackDelimiterConf(
    top: '\u2223',
    repeat: '\u2223',
    bottom: '\u2223',
    font: size1Font,
  ),
  '\u2016': // '\\Vert', '\u2225'
  StackDelimiterConf(
    top: '\u2016',
    repeat: '\u2016',
    bottom: '\u2016',
    font: size1Font,
  ),
  '\u2223': // '\\lvert', '\\rvert', '\\mid'
  StackDelimiterConf(
    top: '\u2223',
    repeat: '\u2223',
    bottom: '\u2223',
    font: size1Font,
  ),
  '\u2225': // '\\lVert', '\\rVert',
  StackDelimiterConf(
    top: '\u2225',
    repeat: '\u2225',
    bottom: '\u2225',
    font: size1Font,
  ),
  '(': StackDelimiterConf(top: '\u239b', repeat: '\u239c', bottom: '\u239d'),
  ')': StackDelimiterConf(top: '\u239e', repeat: '\u239f', bottom: '\u23a0'),
  '[': StackDelimiterConf(top: '\u23a1', repeat: '\u23a2', bottom: '\u23a3'),
  ']': StackDelimiterConf(top: '\u23a4', repeat: '\u23a5', bottom: '\u23a6'),
  '{': StackDelimiterConf(
    top: '\u23a7',
    middle: '\u23a8',
    bottom: '\u23a9',
    repeat: '\u23aa',
  ),
  '}': StackDelimiterConf(
    top: '\u23ab',
    middle: '\u23ac',
    bottom: '\u23ad',
    repeat: '\u23aa',
  ),
  '\u230a': // '\\lfloor',
  StackDelimiterConf(
    top: '\u23a2',
    repeat: '\u23a2',
    bottom: '\u23a3',
  ),
  '\u230b': // '\\rfloor',
  StackDelimiterConf(
    top: '\u23a5',
    repeat: '\u23a5',
    bottom: '\u23a6',
  ),
  '\u2308': // '\\lceil',
  StackDelimiterConf(
    top: '\u23a1',
    repeat: '\u23a2',
    bottom: '\u23a2',
  ),
  '\u2309': // '\\rceil',
  StackDelimiterConf(
    top: '\u23a4',
    repeat: '\u23a5',
    bottom: '\u23a5',
  ),
  '\u27ee': // '\\lgroup',
  StackDelimiterConf(
    top: '\u23a7',
    repeat: '\u23aa',
    bottom: '\u23a9',
  ),
  '\u27ef': // '\\rgroup',
  StackDelimiterConf(
    top: '\u23ab',
    repeat: '\u23aa',
    bottom: '\u23ad',
  ),
  '\u23b0': // '\\lmoustache',
  StackDelimiterConf(
    top: '\u23a7',
    repeat: '\u23aa',
    bottom: '\u23ad',
  ),
  '\u23b1': // '\\rmoustache',
  StackDelimiterConf(
    top: '\u23ab',
    repeat: '\u23aa',
    bottom: '\u23a9',
  ),
};
