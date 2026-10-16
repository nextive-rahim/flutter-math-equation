import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../constants.dart';
import '../utils/render_box_layout.dart';

/// Horizontal placement of a display body and its equation tags.
///
/// KaTeX centres a display body in the full line and pins the tags to its
/// right edge (left with `leqno`), letting a tag take no width. Inside an
/// equation the line width is usually unbounded, so the box is made wide
/// enough to keep the body centred with room for the widest tag on both
/// sides; a finite [maxWidth] is used as the line when it fits.
({double width, double bodyX}) placeTaggedBody({
  required double bodyWidth,
  required double maxTagWidth,
  required double gap,
  required double maxWidth,
}) {
  if (maxTagWidth <= 0) return (width: bodyWidth, bodyX: 0.0);
  final needed = bodyWidth + 2 * (maxTagWidth + gap);
  final width = maxWidth.isFinite ? math.max(maxWidth, needed) : needed;
  return (width: width, bodyX: (width - bodyWidth) / 2);
}

/// A formula with one equation tag (`\tag` outside any environment).
class TaggedLayout extends MultiChildRenderObjectWidget {
  /// Space between the body and the tag, in logical pixels.
  final double gap;

  /// Tag on the left (`leqno`) instead of the right.
  final bool leqno;

  /// [body] then [tag].
  TaggedLayout({
    super.key,
    required Widget body,
    required Widget tag,
    required this.gap,
    this.leqno = false,
  }) : super(children: [body, tag]);

  @override
  RenderTagged createRenderObject(BuildContext context) =>
      RenderTagged(gap: gap, leqno: leqno);

  @override
  void updateRenderObject(BuildContext context, RenderTagged renderObject) =>
      renderObject
        ..gap = gap
        ..leqno = leqno;
}

class TaggedParentData extends ContainerBoxParentData<RenderBox> {}

class RenderTagged extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, TaggedParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, TaggedParentData> {
  RenderTagged({required this._gap, required this._leqno});

  double get gap => _gap;
  double _gap;
  set gap(double value) {
    if (_gap == value) return;
    _gap = value;
    markNeedsLayout();
  }

  bool get leqno => _leqno;
  bool _leqno;
  set leqno(bool value) {
    if (_leqno == value) return;
    _leqno = value;
    markNeedsLayout();
  }

  double _baseline = 0;

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! TaggedParentData) {
      child.parentData = TaggedParentData();
    }
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => _baseline;

  @override
  double computeMinIntrinsicWidth(double height) =>
      _computeLayout(const BoxConstraints()).width;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _computeLayout(const BoxConstraints()).width;

  @override
  double computeMinIntrinsicHeight(double width) =>
      _computeLayout(const BoxConstraints()).height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _computeLayout(const BoxConstraints()).height;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _computeLayout(constraints);

  @override
  void performLayout() {
    size = _computeLayout(constraints, dry: false);
  }

  Size _computeLayout(BoxConstraints constraints, {bool dry = true}) {
    final body = firstChild!;
    final tag = childAfter(body)!;
    final bodySize = body.getLayoutSize(infiniteConstraint, dry: dry);
    final tagSize = tag.getLayoutSize(infiniteConstraint, dry: dry);
    final bodyAscent = dry
        ? bodySize.height
        : body.getDistanceToBaseline(TextBaseline.alphabetic)!;
    final tagAscent = dry
        ? tagSize.height
        : tag.getDistanceToBaseline(TextBaseline.alphabetic)!;
    final ascent = math.max(bodyAscent, tagAscent);
    final descent = math.max(
      bodySize.height - bodyAscent,
      tagSize.height - tagAscent,
    );

    final placement = placeTaggedBody(
      bodyWidth: bodySize.width,
      maxTagWidth: tagSize.width,
      gap: gap,
      maxWidth: constraints.maxWidth,
    );
    if (!dry) {
      _baseline = ascent;
      (body.parentData! as TaggedParentData).offset = Offset(
        placement.bodyX,
        ascent - bodyAscent,
      );
      (tag.parentData! as TaggedParentData).offset = Offset(
        leqno ? 0 : placement.width - tagSize.width,
        ascent - tagAscent,
      );
    }
    return constraints.constrain(Size(placement.width, ascent + descent));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}
