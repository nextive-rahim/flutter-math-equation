import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../render/constants.dart';
import '../../render/layout/custom_layout.dart';
import '../../render/utils/render_box_layout.dart';
import '../../render/utils/render_box_offset.dart';
import '../options.dart';
import '../size.dart';
import '../syntax_tree.dart';

/// Enclosure node
///
/// Examples: `\colorbox`, `\fbox`, `\cancel`.
class EnclosureNode extends SlotableNode<EquationRowNode> {
  /// Base where the enclosure is applied upon
  final EquationRowNode base;

  /// Whether the enclosure has a border.
  final bool hasBorder;

  /// Border color.
  ///
  /// If null, will default to options.color.
  final Color? bordercolor;

  /// Background color.
  final Color? backgroundcolor;

  /// Special styles for this enclosure.
  ///
  /// Including `'updiagonalstrike'`, `'downdiagonalstrike'`,
  /// and `'horizontalstrike'`.
  final List<String> notation;

  /// Horizontal padding.
  final Measurement horizontalPadding;

  /// Vertical padding.
  final Measurement verticalPadding;

  EnclosureNode({
    required this.base,
    required this.hasBorder,
    this.bordercolor,
    this.backgroundcolor,
    this.notation = const [],
    this.horizontalPadding = Measurement.zero,
    this.verticalPadding = Measurement.zero,
  });

  @override
  BuildResult buildWidget(
    MathOptions options,
    List<BuildResult?> childBuildResults,
  ) {
    final horizontalPadding = this.horizontalPadding.toLpUnder(options);
    final verticalPadding = this.verticalPadding.toLpUnder(options);

    if (notation.contains('phase')) {
      final em = 1.0.cssEm.toLpUnder(options);
      return BuildResult(
        options: options,
        widget: CustomLayout<int>(
          delegate: PhaseDelegate(
            lineWeight: 0.6.pt.toLpUnder(options),
            clearance: const Measurement(
              value: 0.35,
              unit: Unit.ex,
            ).toLpUnder(options),
            em: em,
            // Keeps the line weight from following \Huge and friends.
            scale:
                options.sizeMultiplier /
                options.havingBaseSize().sizeMultiplier,
            color: bordercolor ?? options.color,
          ),
          children: [
            CustomLayoutId(id: 0, child: childBuildResults[0]!.widget),
          ],
        ),
      );
    }
    if (notation.contains('angl')) {
      return BuildResult(
        options: options,
        widget: CustomLayout<int>(
          delegate: AnglDelegate(
            rule: options.fontMetrics.defaultRuleThickness.cssEm.toLpUnder(
              options,
            ),
            sidePad: 0.03889.cssEm.toLpUnder(options),
            quarterEm: 0.25.cssEm.toLpUnder(options),
            color: bordercolor ?? options.color,
          ),
          children: [
            CustomLayoutId(id: 0, child: childBuildResults[0]!.widget),
          ],
        ),
      );
    }

    Widget widget = Stack(
      children: <Widget>[
        Container(
          // The background is painted with or without a border: \colorbox
          // has none, and drew no colour at all before.
          decoration: BoxDecoration(
            color: backgroundcolor,
            border: hasBorder
                ? Border.all(
                    // TODO minRuleThickness
                    width: options.fontMetrics.fboxrule.cssEm.toLpUnder(
                      options,
                    ),
                    color: bordercolor ?? options.color,
                  )
                : null,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: verticalPadding,
              horizontal: horizontalPadding,
            ),
            child: childBuildResults[0]!.widget,
          ),
        ),
        if (notation.contains('updiagonalstrike'))
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 0,
            child: LayoutBuilder(
              builder: (context, constraints) => CustomPaint(
                size: constraints.biggest,
                painter: LinePainter(
                  startRelativeX: 0,
                  startRelativeY: 1,
                  endRelativeX: 1,
                  endRelativeY: 0,
                  lineWidth: 0.046.cssEm.toLpUnder(options),
                  color: bordercolor ?? options.color,
                ),
              ),
            ),
          ),
        if (notation.contains('downdiagonalstrike'))
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 0,
            child: LayoutBuilder(
              builder: (context, constraints) => CustomPaint(
                size: constraints.biggest,
                painter: LinePainter(
                  startRelativeX: 0,
                  startRelativeY: 0,
                  endRelativeX: 1,
                  endRelativeY: 1,
                  lineWidth: 0.046.cssEm.toLpUnder(options),
                  color: bordercolor ?? options.color,
                ),
              ),
            ),
          ),
      ],
    );
    if (notation.contains('horizontalstrike')) {
      widget = CustomLayout<int>(
        delegate: HorizontalStrikeDelegate(
          vShift: options.fontMetrics.xHeight.cssEm.toLpUnder(options) / 2,
          ruleThickness: options.fontMetrics.defaultRuleThickness.cssEm
              .toLpUnder(options),
          color: bordercolor ?? options.color,
        ),
        children: <Widget>[CustomLayoutId(id: 0, child: widget)],
      );
    }
    return BuildResult(options: options, widget: widget);
  }

  @override
  List<MathOptions> computeChildOptions(MathOptions options) => [options];

  @override
  List<EquationRowNode> computeChildren() => [base];

  @override
  AtomType get leftType => AtomType.ord;

  @override
  AtomType get rightType => AtomType.ord;

  @override
  bool shouldRebuildWidget(MathOptions oldOptions, MathOptions newOptions) =>
      false;

  @override
  EnclosureNode updateChildren(List<EquationRowNode> newChildren) =>
      EnclosureNode(
        base: newChildren[0],
        hasBorder: hasBorder,
        bordercolor: bordercolor,
        backgroundcolor: backgroundcolor,
        notation: notation,
        horizontalPadding: horizontalPadding,
        verticalPadding: verticalPadding,
      );

  @override
  Map<String, Object?> toJson() => super.toJson()
    ..addAll({
      'base': base.toJson(),
      'hasBorder': hasBorder,
      if (bordercolor != null) 'bordercolor': bordercolor,
      if (backgroundcolor != null) 'backgroundcolor': backgroundcolor,
      if (notation.isNotEmpty) 'notation': notation,
      if (horizontalPadding != Measurement.zero)
        'horizontalPadding': horizontalPadding.toString(),
      if (verticalPadding != Measurement.zero)
        'verticalPadding': verticalPadding.toString(),
    });
}

class LinePainter extends CustomPainter {
  final double startRelativeX;
  final double startRelativeY;
  final double endRelativeX;
  final double endRelativeY;
  final double lineWidth;
  final Color color;

  const LinePainter({
    required this.startRelativeX,
    required this.startRelativeY,
    required this.endRelativeX,
    required this.endRelativeY,
    required this.lineWidth,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(startRelativeX * size.width, startRelativeY * size.height),
      Offset(endRelativeX * size.width, endRelativeY * size.height),
      Paint()
        ..strokeWidth = lineWidth
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => this != oldDelegate;
}

class HorizontalStrikeDelegate extends CustomLayoutDelegate<int> {
  final double ruleThickness;
  final double vShift;
  final Color color;

  HorizontalStrikeDelegate({
    required this.ruleThickness,
    required this.vShift,
    required this.color,
  });

  var height = 0.0;
  var width = 0.0;

  @override
  double computeDistanceToActualBaseline(
    TextBaseline baseline,
    Map<int, RenderBox> childrenTable,
  ) => height;

  @override
  double getIntrinsicSize({
    required Axis sizingDirection,
    required bool max,
    required double extent,
    required double Function(RenderBox child, double extent) childSize,
    required Map<int, RenderBox> childrenTable,
  }) => childSize(childrenTable[0]!, double.infinity);

  @override
  Size computeLayout(
    BoxConstraints constraints,
    Map<int, RenderBox> childrenTable, {
    bool dry = true,
  }) {
    final base = childrenTable[0]!;

    if (dry) {
      return base.getDryLayout(constraints);
    }

    base.layout(constraints, parentUsesSize: true);
    height = base.layoutHeight;
    width = base.size.width;

    return base.size;
  }

  @override
  void additionalPaint(PaintingContext context, Offset offset) {
    context.canvas.drawLine(
      Offset(offset.dx, offset.dy + height - vShift),
      Offset(offset.dx + width, offset.dy + height - vShift),
      Paint()
        ..strokeWidth = ruleThickness
        ..color = color,
    );
  }
}

/// `\phase{…}` (steinmetz package, KaTeX 0.13): an angle whose bottom line
/// runs under the whole argument. Geometry from KaTeX enclose.ts and
/// svgGeometry phasePath.
class PhaseDelegate extends CustomLayoutDelegate<int> {
  /// Line weight (0.6pt) and clearance (0.35ex), in logical pixels.
  final double lineWeight;
  final double clearance;

  /// One em, and KaTeX's `scale` (sizeMultiplier relative to base sizing).
  final double em;
  final double scale;
  final Color color;

  PhaseDelegate({
    required this.lineWeight,
    required this.clearance,
    required this.em,
    required this.scale,
    required this.color,
  });

  var _ascent = 0.0;
  var _angleHeight = 0.0;
  var _width = 0.0;

  @override
  double computeDistanceToActualBaseline(
    TextBaseline baseline,
    Map<int, RenderBox> childrenTable,
  ) => _ascent;

  @override
  double getIntrinsicSize({
    required Axis sizingDirection,
    required bool max,
    required double extent,
    required double Function(RenderBox child, double extent) childSize,
    required Map<int, RenderBox> childrenTable,
  }) {
    final size = childSize(childrenTable[0]!, double.infinity);
    if (sizingDirection == Axis.vertical) return size + lineWeight + clearance;
    return size + (size + lineWeight + clearance) / 2 + lineWeight;
  }

  @override
  Size computeLayout(
    BoxConstraints constraints,
    Map<int, RenderBox> childrenTable, {
    bool dry = true,
  }) {
    final inner = childrenTable[0]!;
    final innerSize = inner.getLayoutSize(infiniteConstraint, dry: dry);
    final height = dry ? innerSize.height : inner.layoutHeight;
    final depth = innerSize.height - height;
    final angleHeight = height + depth + lineWeight + clearance;
    final padLeft = angleHeight / 2 + lineWeight;
    final size = Size(padLeft + innerSize.width, angleHeight);
    if (!dry) {
      _ascent = height;
      _angleHeight = angleHeight;
      _width = size.width;
      (inner.parentData! as CustomLayoutParentData).offset = Offset(padLeft, 0);
    }
    return size;
  }

  @override
  void additionalPaint(PaintingContext context, Offset offset) {
    // phasePath(y) = M400000 y H0 L(y/2) 0 l65 45 L145 (y-80) H400000z,
    // drawn at the angle's height and clipped to the box (hide-tail).
    final viewBoxHeight = (1000 * _angleHeight / em * scale).floorToDouble();
    if (viewBoxHeight <= 0) return;
    final s = _angleHeight / viewBoxHeight;
    final y = viewBoxHeight;
    final path = Path()
      ..moveTo(400000, y)
      ..lineTo(0, y)
      ..lineTo(y / 2, 0)
      ..lineTo(y / 2 + 65, 45)
      ..lineTo(145, y - 80)
      ..lineTo(400000, y - 80)
      ..close();
    context.canvas
      ..save()
      ..clipRect(offset & Size(_width, _angleHeight))
      ..translate(offset.dx, offset.dy)
      ..scale(s, s)
      ..drawPath(path, Paint()..color = color)
      ..restore();
  }
}

/// `\angl{…}` (actuarial angle, KaTeX 0.13): rules above and to the right of
/// the argument, 3 rule widths clear of it on top (KaTeX enclose.ts).
class AnglDelegate extends CustomLayoutDelegate<int> {
  /// Rule thickness, the 1mu side padding, and 0.25em, in logical pixels.
  final double rule;
  final double sidePad;
  final double quarterEm;
  final Color color;

  AnglDelegate({
    required this.rule,
    required this.sidePad,
    required this.quarterEm,
    required this.color,
  });

  var _ascent = 0.0;
  var _box = Size.zero;

  @override
  double computeDistanceToActualBaseline(
    TextBaseline baseline,
    Map<int, RenderBox> childrenTable,
  ) => _ascent;

  @override
  double getIntrinsicSize({
    required Axis sizingDirection,
    required bool max,
    required double extent,
    required double Function(RenderBox child, double extent) childSize,
    required Map<int, RenderBox> childrenTable,
  }) {
    final size = childSize(childrenTable[0]!, double.infinity);
    return sizingDirection == Axis.horizontal
        ? size + 3 * sidePad + rule
        : size + 4 * rule + quarterEm;
  }

  @override
  Size computeLayout(
    BoxConstraints constraints,
    Map<int, RenderBox> childrenTable, {
    bool dry = true,
  }) {
    final inner = childrenTable[0]!;
    final innerSize = inner.getLayoutSize(infiniteConstraint, dry: dry);
    final height = dry ? innerSize.height : inner.layoutHeight;
    final depth = innerSize.height - height;
    final topPad = 4 * rule;
    final bottomPad = math.max(0.0, quarterEm - depth);
    // Box: padding 1mu each side, rule on the right; then a 1mu margin.
    final box = Size(
      sidePad + innerSize.width + sidePad + rule,
      topPad + height + depth + bottomPad,
    );
    if (!dry) {
      _ascent = topPad + height;
      _box = box;
      (inner.parentData! as CustomLayoutParentData).offset = Offset(
        sidePad,
        topPad,
      );
    }
    return Size(box.width + sidePad, box.height);
  }

  @override
  void additionalPaint(PaintingContext context, Offset offset) {
    final paint = Paint()..color = color;
    context.canvas
      ..drawRect(offset & Size(_box.width, rule), paint)
      ..drawRect(
        Offset(offset.dx + _box.width - rule, offset.dy) &
            Size(rule, _box.height),
        paint,
      );
  }
}
