import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../render/constants.dart';
import '../../render/symbols/make_symbol.dart';
import '../../render/utils/render_box_layout.dart';
import '../options.dart';
import '../size.dart';
import '../syntax_tree.dart';
import '../types.dart';

/// Where a [GlyphAccentNode] puts its glyph.
enum GlyphAccentPlacement {
  /// Below the base, its baseline at the bottom of the base's depth (`\c`).
  below,

  /// Over the whole base, centred, 0.2em down; the result is at least as
  /// wide as the glyph (`\textcircled`).
  full,
}

/// A text accent drawn from a font glyph that does not sit above the base:
/// the cedilla of `\c` (KaTeX 0.13.15) and the circle of `\textcircled`
/// (KaTeX accent.ts, accentBelow / accentFull).
class GlyphAccentNode extends SlotableNode<EquationRowNode> {
  final EquationRowNode base;
  final String glyph;
  final GlyphAccentPlacement placement;

  GlyphAccentNode({
    required this.base,
    required this.glyph,
    required this.placement,
  });

  @override
  BuildResult buildWidget(
    MathOptions options,
    List<BuildResult?> childBuildResults,
  ) {
    final glyphWidget = makeBaseSymbol(
      symbol: glyph,
      atomType: AtomType.ord,
      mode: Mode.text,
      options: options,
    ).widget;
    return BuildResult(
      options: options,
      widget: _GlyphAccentLayout(
        placement: placement,
        fullShift: 0.2.cssEm.toLpUnder(options),
        children: [childBuildResults[0]!.widget, glyphWidget],
      ),
    );
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
      oldOptions.sizeMultiplier != newOptions.sizeMultiplier ||
      oldOptions.color != newOptions.color;

  @override
  GlyphAccentNode updateChildren(List<EquationRowNode> newChildren) =>
      GlyphAccentNode(base: newChildren[0], glyph: glyph, placement: placement);

  @override
  Map<String, Object?> toJson() => super.toJson()
    ..addAll({
      'base': base.toJson(),
      'glyph': glyph,
      'placement': placement.name,
    });
}

class _GlyphAccentLayout extends MultiChildRenderObjectWidget {
  final GlyphAccentPlacement placement;
  final double fullShift;

  const _GlyphAccentLayout({
    required this.placement,
    required this.fullShift,
    required super.children,
  });

  @override
  _RenderGlyphAccent createRenderObject(BuildContext context) =>
      _RenderGlyphAccent(placement, fullShift);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderGlyphAccent renderObject,
  ) => renderObject
    ..placement = placement
    ..fullShift = fullShift;
}

class _GlyphAccentParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderGlyphAccent extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _GlyphAccentParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _GlyphAccentParentData> {
  _RenderGlyphAccent(this._placement, this._fullShift);

  GlyphAccentPlacement get placement => _placement;
  GlyphAccentPlacement _placement;
  set placement(GlyphAccentPlacement value) {
    if (_placement == value) return;
    _placement = value;
    markNeedsLayout();
  }

  double get fullShift => _fullShift;
  double _fullShift;
  set fullShift(double value) {
    if (_fullShift == value) return;
    _fullShift = value;
    markNeedsLayout();
  }

  double _baseline = 0;

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! _GlyphAccentParentData) {
      child.parentData = _GlyphAccentParentData();
    }
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => _baseline;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _computeLayout(constraints);

  @override
  void performLayout() {
    size = _computeLayout(constraints, dry: false);
  }

  Size _computeLayout(BoxConstraints constraints, {bool dry = true}) {
    final base = firstChild!;
    final glyph = childAfter(base)!;
    final baseSize = base.getLayoutSize(infiniteConstraint, dry: dry);
    final glyphSize = glyph.getLayoutSize(infiniteConstraint, dry: dry);
    final baseAscent = dry
        ? baseSize.height
        : base.getDistanceToBaseline(TextBaseline.alphabetic)!;
    final glyphAscent = dry
        ? glyphSize.height
        : glyph.getDistanceToBaseline(TextBaseline.alphabetic)!;
    final baseDepth = baseSize.height - baseAscent;
    final glyphDepth = glyphSize.height - glyphAscent;

    // Baselines measured downwards from the base's baseline.
    final glyphBaseline = switch (placement) {
      // Glyph baseline at the bottom of the base's depth.
      GlyphAccentPlacement.below => baseDepth,
      // Glyph box bottom on the base's baseline, then 0.2em lower.
      GlyphAccentPlacement.full => fullShift - glyphDepth,
    };
    final ascent = math.max(baseAscent, glyphAscent - glyphBaseline);
    final descent = math.max(baseDepth, glyphBaseline + glyphDepth);
    final width = math.max(baseSize.width, glyphSize.width);

    if (!dry) {
      _baseline = ascent;
      (base.parentData! as _GlyphAccentParentData).offset = Offset(
        (width - baseSize.width) / 2,
        ascent - baseAscent,
      );
      (glyph.parentData! as _GlyphAccentParentData).offset = Offset(
        (width - glyphSize.width) / 2,
        ascent + glyphBaseline - glyphAscent,
      );
    }
    return Size(width, ascent + descent);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}
