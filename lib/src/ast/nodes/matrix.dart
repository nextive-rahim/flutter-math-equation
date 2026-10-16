import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';

import '../../render/layout/custom_layout.dart';
import '../../render/layout/shift_baseline.dart';
import '../../utils/iterable_extensions.dart';
import '../../utils/num_extension.dart';
import '../options.dart';
import '../size.dart';
import '../style.dart';
import '../syntax_tree.dart';

enum MatrixSeparatorStyle { solid, dashed, none }

enum MatrixColumnAlign { left, center, right }

enum MatrixRowAlign {
  top,
  bottom,
  center,
  baseline,
  // axis,
}

/// Matrix node
class MatrixNode extends SlotableNode<EquationRowNode?> {
  /// `arrayStretch` parameter from the context.
  ///
  /// Affects the minimum row height and row depth for each row.
  ///
  /// `\smallmatrix` has an `arrayStretch` of 0.5.
  final double arrayStretch;

  /// Whether to create an extra padding before the first column and after the
  /// last column.
  final bool hskipBeforeAndAfter;

  /// Special flags for `\smallmatrix`
  final bool isSmall;

  /// The `{CD}` layout (KaTeX cd.ts): a 3ex baselineskip, 0.25em on each
  /// side of every column, and `\jot` below each row but the last.
  final bool isCD;

  /// Align types for each column.
  final List<MatrixColumnAlign> columnAligns;

  /// Style for vertical separator lines.
  ///
  /// This includes outermost lines. Different from MathML!
  final List<MatrixSeparatorStyle> vLines;

  /// Spacings between rows;
  final List<Measurement> rowSpacings;

  /// Style for horizontal separator lines.
  ///
  /// This includes outermost lines. Different from MathML!
  final List<MatrixSeparatorStyle> hLines;

  /// Further `\hline`/`\hdashline`s in the same gap as [hLines] (for
  /// `\hline\hline`), each 0.25em below the previous one (KaTeX array.ts).
  final List<List<MatrixSeparatorStyle>> hLineExtras;

  /// Body of the matrix.
  ///
  /// First index is line number. Second index is column number.
  final List<List<EquationRowNode?>> body;

  /// Row number.
  final int rows;

  /// Column number.
  final int cols;

  MatrixNode._({
    required this.rows,
    required this.cols,
    this.arrayStretch = 1.0,
    this.hskipBeforeAndAfter = false,
    this.isSmall = false,
    this.isCD = false,
    required this.columnAligns,
    required this.vLines,
    required this.rowSpacings,
    // this.rowAligns,
    required this.hLines,
    required this.hLineExtras,
    required this.body,
  }) : assert(body.length == rows),
       assert(body.every((row) => row.length == cols)),
       assert(columnAligns.length == cols),
       assert(vLines.length == cols + 1),
       assert(rowSpacings.length == rows),
       assert(hLines.length == rows + 1);

  /// Factory constructor for [MatrixNode] that will sanitize inputs.
  factory MatrixNode({
    double arrayStretch = 1.0,
    bool hskipBeforeAndAfter = false,
    bool isSmall = false,
    bool isCD = false,
    List<MatrixColumnAlign> columnAligns = const [],
    List<MatrixSeparatorStyle> vLines = const [],
    List<Measurement> rowSpacings = const [],
    List<MatrixSeparatorStyle> hLines = const [],
    List<List<MatrixSeparatorStyle>> hLineExtras = const [],
    required List<List<EquationRowNode?>> body,
  }) {
    final cols = max3(
      body.map((row) => row.length).maxOrNull ?? 0,
      columnAligns.length,
      vLines.length - 1,
    );
    final sanitizedColumnAligns = columnAligns.extendToByFill(
      cols,
      MatrixColumnAlign.center,
    );
    final sanitizedVLines = vLines.extendToByFill(
      cols + 1,
      MatrixSeparatorStyle.none,
    );

    final rows = max3(body.length, rowSpacings.length, hLines.length - 1);

    final sanitizedBody = body
        .map((row) => row.extendToByFill(cols, null))
        .toList(growable: false)
        .extendToByFill(rows, List.filled(cols, null));
    final sanitizedRowSpacing = rowSpacings.extendToByFill(
      rows,
      Measurement.zero,
    );
    final sanitizedHLines = hLines.extendToByFill(
      rows + 1,
      MatrixSeparatorStyle.none,
    );

    return MatrixNode._(
      rows: rows,
      cols: cols,
      arrayStretch: arrayStretch,
      hskipBeforeAndAfter: hskipBeforeAndAfter,
      isSmall: isSmall,
      isCD: isCD,
      columnAligns: sanitizedColumnAligns,
      vLines: sanitizedVLines,
      rowSpacings: sanitizedRowSpacing,
      hLines: sanitizedHLines,
      hLineExtras: hLineExtras.extendToByFill(rows + 1, const []),
      body: sanitizedBody,
    );
  }

  @override
  BuildResult buildWidget(
    MathOptions options,
    List<BuildResult?> childBuildResults,
  ) {
    assert(childBuildResults.length == rows * cols);
    // Flutter's Table does not provide fine-grained control of borders
    return BuildResult(
      options: options,
      widget: ShiftBaseline(
        relativePos: 0.5,
        offset: options.fontMetrics.axisHeight.cssEm.toLpUnder(options),
        child: CustomLayout<int>(
          delegate: MatrixLayoutDelegate(
            rows: rows,
            cols: cols,
            ruleThickness: options.fontMetrics.defaultRuleThickness.cssEm
                .toLpUnder(options),
            arrayskip:
                arrayStretch *
                (isCD ? const Measurement(value: 3, unit: Unit.ex) : 12.0.pt)
                    .toLpUnder(options),
            jot: isCD ? 3.0.pt.toLpUnder(options) : 0.0,
            rowSpacings: rowSpacings
                .map((e) => e.toLpUnder(options))
                .toList(growable: false),
            hLines: hLines,
            hLineExtras: hLineExtras,
            hLineGap: 0.25.cssEm.toLpUnder(options),
            hskipBeforeAndAfter: hskipBeforeAndAfter,
            arraycolsep: isCD
                ? 0.25.cssEm.toLpUnder(options)
                : isSmall
                ? (5 / 18).cssEm.toLpUnder(
                    options.havingStyle(MathStyle.script),
                  )
                : 5.0.pt.toLpUnder(options),
            vLines: vLines,
            columnAligns: columnAligns,
          ),
          children: childBuildResults
              .mapIndexed(
                (index, result) => result == null
                    ? null
                    : CustomLayoutId(id: index, child: result.widget),
              )
              .nonNulls
              .toList(growable: false),
        ),
      ),
    );
  }

  @override
  List<MathOptions> computeChildOptions(MathOptions options) =>
      List.filled(rows * cols, options, growable: false);

  @override
  List<EquationRowNode?> computeChildren() =>
      body.expand((row) => row).toList(growable: false);

  @override
  AtomType get leftType => AtomType.ord;

  @override
  AtomType get rightType => AtomType.ord;

  @override
  bool shouldRebuildWidget(MathOptions oldOptions, MathOptions newOptions) =>
      false;

  @override
  MatrixNode updateChildren(List<EquationRowNode> newChildren) {
    assert(newChildren.length >= rows * cols);
    final body = List<List<EquationRowNode>>.generate(
      rows,
      (i) => newChildren.sublist(i * cols, (i + 1) * cols),
      growable: false,
    );
    return copyWith(body: body);
  }

  MatrixNode copyWith({
    double? arrayStretch,
    bool? hskipBeforeAndAfter,
    bool? isSmall,
    bool? isCD,
    List<MatrixColumnAlign>? columnAligns,
    List<MatrixSeparatorStyle>? columnLines,
    List<Measurement>? rowSpacing,
    List<MatrixSeparatorStyle>? rowLines,
    List<List<MatrixSeparatorStyle>>? hLineExtras,
    List<List<EquationRowNode?>>? body,
  }) => MatrixNode(
    arrayStretch: arrayStretch ?? this.arrayStretch,
    hskipBeforeAndAfter: hskipBeforeAndAfter ?? this.hskipBeforeAndAfter,
    isSmall: isSmall ?? this.isSmall,
    isCD: isCD ?? this.isCD,
    columnAligns: columnAligns ?? this.columnAligns,
    vLines: columnLines ?? vLines,
    rowSpacings: rowSpacing ?? rowSpacings,
    hLines: rowLines ?? hLines,
    hLineExtras: hLineExtras ?? this.hLineExtras,
    body: body ?? this.body,
  );

  @override
  Map<String, Object?> toJson() => super.toJson()
    ..addAll({
      'cols': cols,
      if (arrayStretch != 1) 'arrayStretch': arrayStretch,
      if (hskipBeforeAndAfter != false)
        'hskipBeforeAndAfter': hskipBeforeAndAfter,
      if (isSmall != false) 'isSmall': isSmall,
      if (isCD) 'isCD': isCD,
      'columnAligns': columnAligns.map((e) => e.toString()),
      'vLines': vLines.map((e) => e.toString()),
      if (!rowSpacings.every((element) => element.value == 0))
        'rowSpacings': rowSpacings.map((e) => e.toString()),
      if (!hLines.every((element) => element == MatrixSeparatorStyle.none))
        'hLines': hLines.map((e) => e.toString()),
      'body': body.map((e) => e.map((e) => e?.toJson())),
    });
}

class MatrixLayoutDelegate extends IntrinsicLayoutDelegate<int> {
  final int rows;
  final int cols;
  final double ruleThickness;
  final double arrayskip;
  final List<double> rowSpacings;
  final List<MatrixSeparatorStyle> hLines;
  final List<List<MatrixSeparatorStyle>> hLineExtras;
  final double hLineGap;
  final bool hskipBeforeAndAfter;
  final double arraycolsep;
  final List<MatrixSeparatorStyle> vLines;
  final List<MatrixColumnAlign> columnAligns;

  /// Added below every row but the last (`addJot` in KaTeX array.ts).
  final double jot;

  MatrixLayoutDelegate({
    required this.rows,
    required this.cols,
    required this.ruleThickness,
    required this.arrayskip,
    required this.rowSpacings,
    required this.hLines,
    this.hLineExtras = const [],
    this.hLineGap = 0.0,
    required this.hskipBeforeAndAfter,
    required this.arraycolsep,
    required this.vLines,
    required this.columnAligns,
    this.jot = 0.0,
  }) : vLinePos = List.filled(cols + 1, 0.0, growable: false),
       hLinePos = List.filled(rows + 1, 0.0, growable: false);

  List<double> hLinePos;
  List<double> vLinePos;

  /// Positions and styles of the [hLineExtras].
  List<(double, MatrixSeparatorStyle)> extraHLinePos = const [];

  var totalHeight = 0.0;
  var width = 0.0;

  @override
  double? computeDistanceToActualBaseline(
    TextBaseline baseline,
    // ignore: avoid_returning_null
    Map<int, RenderBox> childrenTable,
  ) => null;

  @override
  AxisConfiguration<int> performHorizontalIntrinsicLayout({
    required Map<int, double> childrenWidths,
    bool isComputingIntrinsics = false,
  }) {
    final childWidths = List.generate(
      cols * rows,
      (index) => childrenWidths[index] ?? 0.0,
      growable: false,
    );

    // Calculate width for each column
    final colWidths = List.filled(cols, 0.0, growable: false);
    for (var i = 0; i < cols; i++) {
      for (var j = 0; j < rows; j++) {
        colWidths[i] = math.max(colWidths[i], childWidths[j * cols + i]);
      }
    }

    // Layout each column
    final colPos = List.filled(cols, 0.0, growable: false);
    final vLinePos = List.filled(cols + 1, 0.0, growable: false);

    var pos = 0.0;
    vLinePos[0] = pos;
    pos += (vLines[0] != MatrixSeparatorStyle.none) ? ruleThickness : 0.0;
    pos += hskipBeforeAndAfter ? arraycolsep : 0.0;

    for (var i = 0; i < cols - 1; i++) {
      colPos[i] = pos;
      pos += colWidths[i] + arraycolsep;
      vLinePos[i + 1] = pos;
      pos += (vLines[i + 1] != MatrixSeparatorStyle.none) ? ruleThickness : 0.0;
      pos += arraycolsep;
    }

    // An empty matrix (`\begin{pmatrix}\end{pmatrix}`) has no columns
    // (KaTeX 0.13.11); indexing column -1 crashed.
    if (cols > 0) {
      colPos[cols - 1] = pos;
      pos += colWidths[cols - 1];
    }
    pos += hskipBeforeAndAfter ? arraycolsep : 0.0;
    vLinePos[cols] = pos;
    pos += (vLines[cols] != MatrixSeparatorStyle.none) ? ruleThickness : 0.0;

    width = pos;

    // Determine position of children
    final childPos = List.generate(rows * cols, (index) {
      final col = index % cols;
      switch (columnAligns[col]) {
        case MatrixColumnAlign.left:
          return colPos[col];
        case MatrixColumnAlign.right:
          return colPos[col] + colWidths[col] - childWidths[index];
        case MatrixColumnAlign.center:
          return colPos[col] + (colWidths[col] - childWidths[index]) / 2;
      }
    }, growable: false);

    if (!isComputingIntrinsics) {
      this.vLinePos = vLinePos;
    }

    return AxisConfiguration(size: width, offsetTable: childPos.asMap());
  }

  @override
  AxisConfiguration<int> performVerticalIntrinsicLayout({
    required Map<int, double> childrenHeights,
    required Map<int, double> childrenBaselines,
    bool isComputingIntrinsics = false,
  }) {
    final childHeights = List.generate(
      cols * rows,
      (index) => childrenBaselines[index] ?? 0.0,
      growable: false,
    );
    final childDepth = List.generate(cols * rows, (index) {
      final height = childrenBaselines[index];
      return height != null ? childrenHeights[index]! - height : 0.0;
    }, growable: false);

    // Calculate height and depth for each row
    // Minimum height and depth are 0.7 * arrayskip and 0.3 * arrayskip
    final rowHeights = List.filled(rows, 0.7 * arrayskip, growable: false);
    final rowDepth = List.filled(rows, 0.3 * arrayskip, growable: false);
    for (var i = 0; i < rows; i++) {
      for (var j = 0; j < cols; j++) {
        rowHeights[i] = math.max(rowHeights[i], childHeights[i * cols + j]);
        rowDepth[i] = math.max(rowDepth[i], childDepth[i * cols + j]);
      }
    }

    // Layout rows
    var pos = 0.0;
    final rowBaselinePos = List.filled(rows, 0.0, growable: false);
    final hLinePos = List.filled(rows + 1, 0.0, growable: false);

    final extraHLinePos = <(double, MatrixSeparatorStyle)>[];
    void addExtraHLines(int gap) {
      if (gap >= hLineExtras.length) return;
      for (final style in hLineExtras[gap]) {
        pos += hLineGap;
        extraHLinePos.add((pos, style));
      }
    }

    for (var i = 0; i < rows; i++) {
      hLinePos[i] = pos;
      pos += (hLines[i] != MatrixSeparatorStyle.none) ? ruleThickness : 0.0;
      addExtraHLines(i);
      pos += rowHeights[i];
      rowBaselinePos[i] = pos;
      // KaTeX array.ts: a positive `\\[gap]` only raises the row's depth to
      // gap + arstrut depth; a negative one is added. It applies to the last
      // row too (a trailing `\\[gap]` belongs to it).
      var depth = rowDepth[i];
      var gap = rowSpacings[i];
      if (gap > 0) {
        depth = math.max(depth, gap + 0.3 * arrayskip);
        gap = 0;
      }
      if (i < rows - 1) depth += jot;
      pos += depth + gap;
    }
    hLinePos[rows] = pos;
    pos += (hLines[rows] != MatrixSeparatorStyle.none) ? ruleThickness : 0.0;
    addExtraHLines(rows);

    totalHeight = pos;

    // Calculate position for each children
    final childPos = List.generate(rows * cols, (index) {
      final row = index ~/ cols;
      return rowBaselinePos[row] - childHeights[index];
    }, growable: false);

    if (!isComputingIntrinsics) {
      this.hLinePos = hLinePos;
      this.extraHLinePos = extraHLinePos;
    }

    return AxisConfiguration(size: totalHeight, offsetTable: childPos.asMap());
  }

  // Paint vlines and hlines
  @override
  void additionalPaint(PaintingContext context, Offset offset) {
    const dashSize = 4;
    final paint = Paint()..strokeWidth = ruleThickness;
    void drawHLine(double y, MatrixSeparatorStyle style) {
      switch (style) {
        case MatrixSeparatorStyle.solid:
          context.canvas.drawLine(
            Offset(offset.dx, offset.dy + y + ruleThickness / 2),
            Offset(offset.dx + width, offset.dy + y + ruleThickness / 2),
            paint,
          );
        case MatrixSeparatorStyle.dashed:
          for (var dx = 0.0; dx < width; dx += dashSize) {
            context.canvas.drawLine(
              Offset(offset.dx + dx, offset.dy + y + ruleThickness / 2),
              Offset(
                offset.dx + math.min(dx + dashSize / 2, width),
                offset.dy + y + ruleThickness / 2,
              ),
              paint,
            );
          }
        case MatrixSeparatorStyle.none:
      }
    }

    for (var i = 0; i < hLines.length; i++) {
      drawHLine(hLinePos[i], hLines[i]);
    }
    for (final (y, style) in extraHLinePos) {
      drawHLine(y, style);
    }

    for (var i = 0; i < vLines.length; i++) {
      switch (vLines[i]) {
        case MatrixSeparatorStyle.solid:
          context.canvas.drawLine(
            Offset(offset.dx + vLinePos[i] + ruleThickness / 2, offset.dy),
            Offset(
              offset.dx + vLinePos[i] + ruleThickness / 2,
              offset.dy + totalHeight,
            ),
            paint,
          );
          break;
        case MatrixSeparatorStyle.dashed:
          for (var dy = 0.0; dy < totalHeight; dy += dashSize) {
            context.canvas.drawLine(
              Offset(
                offset.dx + vLinePos[i] + ruleThickness / 2,
                offset.dy + dy,
              ),
              Offset(
                offset.dx + vLinePos[i] + ruleThickness / 2,
                offset.dy + math.min(dy + dashSize / 2, totalHeight),
              ),
              paint,
            );
          }
          break;
        default:
      }
    }
  }
}
