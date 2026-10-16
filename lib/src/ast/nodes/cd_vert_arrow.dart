import 'package:flutter/widgets.dart';

import '../../render/constants.dart';
import '../../render/layout/custom_layout.dart';
import '../../render/utils/render_box_layout.dart';
import '../../render/utils/render_box_offset.dart';
import '../options.dart';
import '../size.dart';
import '../syntax_tree.dart';
import '../style.dart';
import 'sized_delim.dart';

/// A vertical `{CD}` arrow (`@AAA`, `@VVV`, `@|`) with its optional labels
/// (KaTeX cd.ts, `\\cdparent` / `\\cdleft` / `\\cdright`).
///
/// The arrow is `\Big` [delim]. The labels are in script style and take no
/// room: each sits 0.3em out from the arrow's centre line, its baseline
/// 0.8em above the bottom of the arrow (katex.scss .cd-label-left/right).
class CdVertArrowNode extends SlotableNode<EquationRowNode?> {
  /// `↑`, `↓` or `∥`.
  final String delim;
  final EquationRowNode? left;
  final EquationRowNode? right;

  CdVertArrowNode({required this.delim, this.left, this.right});

  @override
  BuildResult buildWidget(
    MathOptions options,
    List<BuildResult?> childBuildResults,
  ) {
    final arrow = SizedDelimNode(
      delim: delim,
      size: 2,
      atomType: AtomType.ord,
    ).buildWidget(options, const []);
    return BuildResult(
      options: options,
      widget: CustomLayout<int>(
        delegate: _CdVertArrowDelegate(
          gap: 0.3.cssEm.toLpUnder(options),
          raise: 0.8.cssEm.toLpUnder(options),
        ),
        children: [
          CustomLayoutId(id: 0, child: arrow.widget),
          if (childBuildResults[0] != null)
            CustomLayoutId(id: 1, child: childBuildResults[0]!.widget),
          if (childBuildResults[1] != null)
            CustomLayoutId(id: 2, child: childBuildResults[1]!.widget),
        ],
      ),
    );
  }

  @override
  List<MathOptions> computeChildOptions(MathOptions options) {
    final labelOptions = options.havingStyle(options.style.sup());
    return [labelOptions, labelOptions];
  }

  @override
  List<EquationRowNode?> computeChildren() => [left, right];

  @override
  AtomType get leftType => AtomType.ord;

  @override
  AtomType get rightType => AtomType.ord;

  @override
  bool shouldRebuildWidget(MathOptions oldOptions, MathOptions newOptions) =>
      oldOptions.sizeMultiplier != newOptions.sizeMultiplier ||
      oldOptions.color != newOptions.color;

  @override
  CdVertArrowNode updateChildren(List<EquationRowNode?> newChildren) =>
      CdVertArrowNode(
        delim: delim,
        left: newChildren[0],
        right: newChildren[1],
      );

  @override
  Map<String, Object?> toJson() => super.toJson()
    ..addAll({
      'delim': delim,
      if (left != null) 'left': left!.toJson(),
      if (right != null) 'right': right!.toJson(),
    });
}

class _CdVertArrowDelegate extends CustomLayoutDelegate<int> {
  final double gap;
  final double raise;

  _CdVertArrowDelegate({required this.gap, required this.raise});

  var _ascent = 0.0;

  @override
  double computeDistanceToActualBaseline(
    TextBaseline baseline,
    Map<int, RenderBox> childrenTable,
  ) => _ascent;

  // Only the arrow takes room.
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
    final arrow = childrenTable[0]!;
    final size = arrow.getLayoutSize(infiniteConstraint, dry: dry);
    if (dry) return size;

    _ascent = arrow.layoutHeight;
    arrow.offset = Offset.zero;
    final labelBaseline = size.height - raise;
    final centre = size.width / 2;
    final left = childrenTable[1];
    if (left != null) {
      left.layout(infiniteConstraint, parentUsesSize: true);
      left.offset = Offset(
        centre - gap - left.size.width,
        labelBaseline - left.layoutHeight,
      );
    }
    final right = childrenTable[2];
    if (right != null) {
      right.layout(infiniteConstraint, parentUsesSize: true);
      right.offset = Offset(centre + gap, labelBaseline - right.layoutHeight);
    }
    return size;
  }
}
