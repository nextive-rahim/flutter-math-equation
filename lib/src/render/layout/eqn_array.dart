import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../ast/nodes/matrix.dart';
import '../constants.dart';
import '../utils/render_box_offset.dart';
import '../utils/render_box_layout.dart';
import 'line.dart';
import 'tagged.dart';

class EqnArrayParentData extends ContainerBoxParentData<RenderBox> {}

class EqnArray extends MultiChildRenderObjectWidget {
  /// The rows that have a tag; the tag widgets follow the row widgets in
  /// [children], in this order.
  final List<int> tagRows;

  /// Minimum space between the rows and their tags.
  final double tagGap;

  /// Tags on the left instead of the right.
  final bool leqno;

  /// Further rules in each gap, and the space between them.
  final List<List<MatrixSeparatorStyle>> hLineExtras;
  final double hLineGap;

  final double ruleThickness;
  final double jotSize;
  final double arrayskip;
  final List<MatrixSeparatorStyle> hlines;
  final List<double> rowSpacings;

  const EqnArray({
    super.key,
    this.tagRows = const [],
    this.tagGap = 0,
    this.leqno = false,
    this.hLineExtras = const [],
    this.hLineGap = 0,
    required this.ruleThickness,
    required this.jotSize,
    required this.arrayskip,
    required this.hlines,
    required this.rowSpacings,
    required super.children,
  });

  @override
  RenderObject createRenderObject(BuildContext context) => RenderEqnArray(
    tagRows: tagRows,
    tagGap: tagGap,
    leqno: leqno,
    hLineExtras: hLineExtras,
    hLineGap: hLineGap,
    ruleThickness: ruleThickness,
    jotSize: jotSize,
    arrayskip: arrayskip,
    hlines: hlines,
    rowSpacings: rowSpacings,
  );

  // Missing in the port: a rebuilt equation array (new font size, text
  // scale …) kept its old spacing and rules.
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderEqnArray renderObject,
  ) => renderObject
    ..tagRows = tagRows
    ..tagGap = tagGap
    ..leqno = leqno
    ..hLineExtras = hLineExtras
    ..hLineGap = hLineGap
    ..ruleThickness = ruleThickness
    ..jotSize = jotSize
    ..arrayskip = arrayskip
    ..hlines = hlines
    ..rowSpacings = rowSpacings;
}

class RenderEqnArray extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, EqnArrayParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, EqnArrayParentData>,
        DebugOverflowIndicatorMixin {
  RenderEqnArray({
    List<RenderBox>? children,
    this._tagRows = const [],
    this._tagGap = 0,
    this._leqno = false,
    this._hLineExtras = const [],
    this._hLineGap = 0,
    required this._ruleThickness,
    required this._jotSize,
    required this._arrayskip,
    required this._hlines,
    required this._rowSpacings,
  }) {
    addAll(children);
  }

  List<int> get tagRows => _tagRows;
  List<int> _tagRows;
  set tagRows(List<int> value) {
    if (_tagRows != value) {
      _tagRows = value;
      markNeedsLayout();
    }
  }

  double get tagGap => _tagGap;
  double _tagGap;
  set tagGap(double value) {
    if (_tagGap != value) {
      _tagGap = value;
      markNeedsLayout();
    }
  }

  bool get leqno => _leqno;
  bool _leqno;
  set leqno(bool value) {
    if (_leqno != value) {
      _leqno = value;
      markNeedsLayout();
    }
  }

  double get ruleThickness => _ruleThickness;
  double _ruleThickness;
  set ruleThickness(double value) {
    if (_ruleThickness != value) {
      _ruleThickness = value;
      markNeedsLayout();
    }
  }

  double get jotSize => _jotSize;
  double _jotSize;
  set jotSize(double value) {
    if (_jotSize != value) {
      _jotSize = value;
      markNeedsLayout();
    }
  }

  double get arrayskip => _arrayskip;
  double _arrayskip;
  set arrayskip(double value) {
    if (_arrayskip != value) {
      _arrayskip = value;
      markNeedsLayout();
    }
  }

  List<MatrixSeparatorStyle> get hlines => _hlines;
  List<MatrixSeparatorStyle> _hlines;
  set hlines(List<MatrixSeparatorStyle> value) {
    if (_hlines != value) {
      _hlines = value;
      markNeedsLayout();
    }
  }

  List<double> get rowSpacings => _rowSpacings;
  List<double> _rowSpacings;
  set rowSpacings(List<double> value) {
    if (_rowSpacings != value) {
      _rowSpacings = value;
      markNeedsLayout();
    }
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! EqnArrayParentData) {
      child.parentData = EqnArrayParentData();
    }
  }

  List<double> hlinePos = [];

  /// Positions and styles of the [hLineExtras].
  List<(double, MatrixSeparatorStyle)> extraHLinePos = const [];

  /// Further rules in each gap (`\hline\hline`), 0.25em apart.
  List<List<MatrixSeparatorStyle>> get hLineExtras => _hLineExtras;
  List<List<MatrixSeparatorStyle>> _hLineExtras;
  set hLineExtras(List<List<MatrixSeparatorStyle>> value) {
    if (_hLineExtras != value) {
      _hLineExtras = value;
      markNeedsLayout();
    }
  }

  double get hLineGap => _hLineGap;
  double _hLineGap;
  set hLineGap(double value) {
    if (_hLineGap != value) {
      _hLineGap = value;
      markNeedsLayout();
    }
  }

  double width = 0.0;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _computeLayout(constraints);

  @override
  void performLayout() {
    size = _computeLayout(constraints, dry: false);
  }

  Size _computeLayout(BoxConstraints constraints, {bool dry = true}) {
    final rowCount = childCount - tagRows.length;
    final tagChildren = <RenderBox>[];
    var tagChild = firstChild;
    for (var i = 0; tagChild != null; i++) {
      if (i >= rowCount) tagChildren.add(tagChild);
      tagChild = (tagChild.parentData as EqnArrayParentData).nextSibling;
    }
    final rowBaselines = <double>[];

    final nonAligningSizes = <Size>[];
    // First pass, calculate width for each column.
    var child = rowCount > 0 ? firstChild : null;
    var width = 0.0;
    final colWidths = <double>[];
    final sizeMap = <RenderBox, Size>{};
    while (child != null) {
      Size childSize = Size.zero;
      if (child is RenderLine) {
        child.alignColWidth = null;
        childSize = child.getLayoutSize(infiniteConstraint, dry: dry);
        final childColWidth = child.alignColWidth;
        if (childColWidth != null) {
          for (var i = 0; i < childColWidth.length; i++) {
            if (i >= colWidths.length) {
              colWidths.add(childColWidth[i]);
            } else {
              colWidths[i] = math.max(colWidths[i], childColWidth[i]);
            }
          }
        } else {
          nonAligningSizes.add(childSize);
        }
      } else {
        childSize = child.getLayoutSize(infiniteConstraint, dry: dry);
        nonAligningSizes.add(childSize);
      }
      sizeMap[child] = childSize;
      child = (child.parentData as EqnArrayParentData).nextSibling;
      if (sizeMap.length == rowCount) break;
    }

    final nonAligningChildrenWidth =
        nonAligningSizes.map((size) => size.width).maxOrNull ?? 0.0;
    final aligningChildrenWidth = colWidths.sum;
    width = math.max(nonAligningChildrenWidth, aligningChildrenWidth);

    // Second pass, re-layout each RenderLine using column width constraint
    var index = 0;
    var vPos = 0.0;
    final extraPos = <(double, MatrixSeparatorStyle)>[];
    void addExtraHLines(int gap) {
      if (gap >= hLineExtras.length) return;
      for (final style in hLineExtras[gap]) {
        vPos += hLineGap;
        extraPos.add((vPos, style));
      }
    }

    // Recomputed on every layout (it used to grow, leaving rules at the
    // positions of the first layout).
    final hlinePos = <double>[vPos];
    vPos += hlines[0] != MatrixSeparatorStyle.none ? ruleThickness : 0.0;
    addExtraHLines(0);
    index++;
    child = rowCount > 0 ? firstChild : null;
    while (child != null && index - 1 < rowCount) {
      final childParentData = child.parentData as EqnArrayParentData;
      var hPos = 0.0;
      final childSize = sizeMap[child] ?? Size.zero;
      if (child is RenderLine && child.alignColWidth != null) {
        child.alignColWidth = colWidths;
        // Hack: We use a different constraint to trigger another layout or
        // else it would be bypassed
        child.layout(
          BoxConstraints(maxWidth: aligningChildrenWidth),
          parentUsesSize: true,
        );
        hPos =
            (width - aligningChildrenWidth) / 2 +
            colWidths[0] -
            child.alignColWidth![0];
      } else {
        hPos = (width - childSize.width) / 2;
      }
      final layoutHeight = dry ? 0 : child.layoutHeight;
      final layoutDepth = dry ? childSize.height : child.layoutDepth;

      vPos += math.max(layoutHeight, 0.7 * arrayskip);
      rowBaselines.add(vPos);
      if (!dry) {
        childParentData.offset = Offset(hPos, vPos - child.layoutHeight);
      }
      // KaTeX array.ts: \jot only separates rows (none after the last, KaTeX
      // 0.16.44); a positive `\\[gap]` raises the depth to gap + arstrut
      // depth, a negative one is added.
      var depth = math.max(layoutDepth, 0.3 * arrayskip);
      if (index - 1 < rowCount - 1) depth += jotSize;
      var gap = rowSpacings[index - 1];
      if (gap > 0) {
        depth = math.max(depth, gap + 0.3 * arrayskip);
        gap = 0;
      }
      vPos += depth + gap;
      hlinePos.add(vPos);
      vPos += hlines[index] != MatrixSeparatorStyle.none ? ruleThickness : 0.0;
      addExtraHLines(index);
      index++;

      child = childParentData.nextSibling;
    }

    // Equation tags: each on its row's baseline, pinned to the edge, with
    // the rows centred (KaTeX display layout; see placeTaggedBody).
    var maxTagWidth = 0.0;
    final tagSizes = [
      for (final tag in tagChildren)
        tag.getLayoutSize(infiniteConstraint, dry: dry),
    ];
    for (final size in tagSizes) {
      maxTagWidth = math.max(maxTagWidth, size.width);
    }
    final placement = placeTaggedBody(
      bodyWidth: width,
      maxTagWidth: maxTagWidth,
      gap: tagGap,
      maxWidth: constraints.maxWidth,
    );
    if (!dry) {
      if (placement.bodyX != 0) {
        var row = rowCount > 0 ? firstChild : null;
        for (var i = 0; i < rowCount && row != null; i++) {
          final data = row.parentData as EqnArrayParentData;
          data.offset = data.offset.translate(placement.bodyX, 0);
          row = data.nextSibling;
        }
      }
      for (var i = 0; i < tagChildren.length; i++) {
        final tag = tagChildren[i];
        final rowIndex = tagRows[i];
        final baseline = rowIndex < rowBaselines.length
            ? rowBaselines[rowIndex]
            : 0.0;
        (tag.parentData as EqnArrayParentData).offset = Offset(
          leqno ? 0 : placement.width - tagSizes[i].width,
          baseline - tag.getDistanceToBaseline(TextBaseline.alphabetic)!,
        );
      }
      this.width = width;
      bodyX = placement.bodyX;
      this.hlinePos = hlinePos;
      extraHLinePos = extraPos;
    }

    return Size(placement.width, vPos);
  }

  /// Left edge of the rows inside the box (non-zero when tags widen it).
  double bodyX = 0.0;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
    final paint = Paint()..strokeWidth = ruleThickness;
    const dashSize = 4.0;
    void drawHLine(double y, MatrixSeparatorStyle style) {
      final dy = y + ruleThickness / 2;
      switch (style) {
        case MatrixSeparatorStyle.solid:
          context.canvas.drawLine(
            offset + Offset(bodyX, dy),
            offset + Offset(bodyX + width, dy),
            paint,
          );
        case MatrixSeparatorStyle.dashed:
          for (var dx = 0.0; dx < width; dx += dashSize) {
            context.canvas.drawLine(
              offset + Offset(bodyX + dx, dy),
              offset + Offset(bodyX + math.min(dx + dashSize / 2, width), dy),
              paint,
            );
          }
        case MatrixSeparatorStyle.none:
      }
    }

    for (var i = 0; i < hlines.length && i < hlinePos.length; i++) {
      drawHLine(hlinePos[i], hlines[i]);
    }
    for (final (y, style) in extraHLinePos) {
      drawHLine(y, style);
    }
  }
}
