// ignore_for_file: prefer_initializing_formals
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

// Ported from flutter_widget_from_html_core 0.17.4
// (lib/src/widgets/html_list_item.dart and html_list_marker.dart),
// MIT License, Copyright (c) 2020 Dao Hoang Son. See NOTICE.

const _kGapVsMarker = 5.0;

/// A list item widget.
class HtmlListItem extends MultiChildRenderObjectWidget {
  /// The alignment of the item contents.
  final TextAlign? textAlign;

  /// The directionality of the item.
  final TextDirection textDirection;

  /// Creates a list item widget.
  HtmlListItem({
    Widget? child,
    super.key,
    Widget? marker,
    this.textAlign,
    required this.textDirection,
  }) : super(
         children: child != null
             ? [child, if (marker != null) marker]
             : const [],
       );

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ListItemRenderObject(textAlign: textAlign, textDirection: textDirection);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty('textAlign', textAlign, defaultValue: null));
    properties.add(DiagnosticsProperty('textDirection', textDirection));
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    renderObject as _ListItemRenderObject
      ..textAlign = textAlign
      ..textDirection = textDirection;
  }
}

class _ListItemData extends ContainerBoxParentData<RenderBox> {}

class _ListItemRenderObject extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ListItemData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ListItemData> {
  _ListItemRenderObject({
    TextAlign? textAlign,
    required TextDirection textDirection,
  }) : _textAlign = textAlign,
       _textDirection = textDirection;

  TextAlign? get textAlign => _textAlign;
  TextAlign? _textAlign;
  set textAlign(TextAlign? value) {
    if (_textAlign == value) {
      return;
    }

    _textAlign = value;
    markNeedsLayout();
  }

  TextDirection get textDirection => _textDirection;
  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) {
      return;
    }

    _textDirection = value;
    markNeedsLayout();
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToFirstActualBaseline(baseline);

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final child = firstChild;
    if (child == null) {
      return null;
    }

    final childConstraints = constraints.maxWidth.isFinite && textAlign != null
        ? constraints.tighten(width: constraints.maxWidth)
        : constraints;
    // The first child's offset is always Offset.zero in _compute
    return child.getDryBaseline(childConstraints, baseline);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _compute(firstChild, constraints, ChildLayoutHelper.dryLayoutChild);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      firstChild?.computeMaxIntrinsicHeight(width) ??
      super.computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      firstChild?.computeMaxIntrinsicWidth(height) ??
      super.computeMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) =>
      firstChild?.computeMinIntrinsicHeight(width) ??
      super.computeMinIntrinsicHeight(width);

  @override
  double computeMinIntrinsicWidth(double height) =>
      firstChild?.getMinIntrinsicWidth(height) ??
      super.computeMinIntrinsicWidth(height);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  void performLayout() =>
      size = _compute(firstChild, constraints, ChildLayoutHelper.layoutChild);

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ListItemData) {
      child.parentData = _ListItemData();
    }
  }

  Size _compute(RenderBox? child, BoxConstraints bc, ChildLayouter fn) {
    if (child == null) {
      return bc.smallest;
    }

    final childData = child.parentData! as _ListItemData;
    final childConstraints = bc.maxWidth.isFinite && textAlign != null
        ? bc.tighten(width: bc.maxWidth)
        : bc;
    final childSize = fn(child, childConstraints);
    final marker = childData.nextSibling;
    final markerSize = marker != null ? fn(marker, bc.loosen()) : Size.zero;
    final height = childSize.height > 0 ? childSize.height : markerSize.height;
    final size = bc.constrain(Size(childSize.width, height));

    if (identical(fn, ChildLayoutHelper.layoutChild)) {
      childData.offset = Offset.zero;

      if (marker != null) {
        const baseline = TextBaseline.alphabetic;
        final markerDistance =
            marker.getDistanceToBaseline(baseline, onlyReal: true) ??
            markerSize.height;
        final childDistance =
            child.getDistanceToBaseline(baseline, onlyReal: true) ??
            markerDistance;

        final markerData = marker.parentData! as _ListItemData;
        markerData.offset = Offset(
          textDirection == TextDirection.ltr
              ? -markerSize.width - _kGapVsMarker
              : childSize.width + _kGapVsMarker,
          childDistance - markerDistance,
        );
      }
    }

    return size;
  }
}

/// A list marker.
class HtmlListMarker extends LeafRenderObjectWidget {
  /// The marker type.
  final HtmlListMarkerType markerType;

  /// The [TextStyle] to apply to this marker.
  final TextStyle textStyle;

  /// Creates a marker.
  const HtmlListMarker({
    required this.markerType,
    required this.textStyle,
    super.key,
  });

  /// Creates a circle marker.
  const HtmlListMarker.circle(this.textStyle, {super.key})
    : markerType = HtmlListMarkerType.circle;

  /// Creates a disc marker.
  const HtmlListMarker.disc(this.textStyle, {super.key})
    : markerType = HtmlListMarkerType.disc;

  /// Creates a square marker.
  const HtmlListMarker.square(this.textStyle, {super.key})
    : markerType = HtmlListMarkerType.square;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ListMarkerRenderObject(markerType, textStyle);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty('markerType', markerType));
    properties.add(DiagnosticsProperty('textStyle', textStyle));
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _ListMarkerRenderObject)
      ..markerType = markerType
      ..textStyle = textStyle;
  }
}

class _ListMarkerRenderObject extends RenderBox {
  _ListMarkerRenderObject(this._markerType, this._textStyle);

  HtmlListMarkerType _markerType;
  HtmlListMarkerType get markerType => _markerType;
  set markerType(HtmlListMarkerType v) {
    if (v == _markerType) {
      return;
    }

    _markerType = v;
    markNeedsLayout();
  }

  TextPainter? __textPainter;
  final _textMetrics = <LineMetrics>[];
  TextPainter get _textPainter {
    final existingPainter = __textPainter;
    if (existingPainter != null) {
      return existingPainter;
    }

    final newPainter = __textPainter = TextPainter(
      text: TextSpan(style: _textStyle, text: '1.'),
      textDirection: TextDirection.ltr,
    )..layout();

    _textMetrics
      ..clear()
      ..addAll(newPainter.computeLineMetrics());

    return newPainter;
  }

  TextStyle _textStyle;
  TextStyle get textStyle => _textStyle;
  set textStyle(TextStyle v) {
    if (v == _textStyle) {
      return;
    }

    __textPainter = null;
    _textStyle = v;
    markNeedsLayout();
  }

  @override
  double computeDistanceToActualBaseline(TextBaseline baseline) =>
      _textPainter.computeDistanceToActualBaseline(baseline);

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) => _textPainter.computeDistanceToActualBaseline(baseline);

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_textPainter.size);

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;

    final m = _textMetrics.isNotEmpty ? _textMetrics.first : null;
    final center =
        offset +
        Offset(
          size.width / 2,
          (m != null && m.descent.isFinite && m.unscaledAscent.isFinite)
              ? size.height -
                    m.descent -
                    m.unscaledAscent +
                    m.unscaledAscent * .7
              : size.height / 2,
        );

    final color = _textStyle.color;
    final fontSize = _textStyle.fontSize;
    if (color == null || fontSize == null) {
      return;
    }

    final radius = fontSize * .2;
    switch (_markerType) {
      case HtmlListMarkerType.circle:
        canvas.drawCircle(
          center,
          radius * .9,
          Paint()
            ..color = color
            ..strokeWidth = 1
            ..style = PaintingStyle.stroke,
        );
      case HtmlListMarkerType.disc:
        canvas.drawCircle(center, radius, Paint()..color = color);
      case HtmlListMarkerType.disclosureClosed:
        final d = radius * 2;
        canvas
          ..save()
          ..translate(center.dx - d / 2, center.dy - d / 2)
          ..drawPath(
            Path()
              ..lineTo(d, d / 2)
              ..lineTo(0, d),
            Paint()
              ..color = color
              ..style = PaintingStyle.fill,
          )
          ..restore();
      case HtmlListMarkerType.disclosureOpen:
        final d = radius * 2;
        canvas
          ..save()
          ..translate(center.dx - d / 2, center.dy - d / 2)
          ..drawPath(
            Path()
              ..lineTo(d, 0)
              ..lineTo(d / 2, d),
            Paint()
              ..color = color
              ..style = PaintingStyle.fill,
          )
          ..restore();
      case HtmlListMarkerType.square:
        canvas.drawRect(
          Rect.fromCircle(center: center, radius: radius * .8),
          Paint()..color = color,
        );
    }
  }

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }
}

/// List marker types.
enum HtmlListMarkerType {
  /// The circle marker type.
  circle,

  /// The disc marker type.
  disc,

  /// The disclosure-closed marker type.
  disclosureClosed,

  /// The disclosure-open marker type.
  disclosureOpen,

  /// The square marker type.
  square,
}
