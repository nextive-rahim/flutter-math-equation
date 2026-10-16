import '../../render/layout/tagged.dart';
import '../options.dart';
import '../size.dart';
import '../syntax_tree.dart';

/// A formula carrying an equation tag: `\tag{…}` outside any environment
/// (KaTeX's "tag" node).
class TagNode extends SlotableNode<EquationRowNode> {
  /// The formula.
  final EquationRowNode body;

  /// The tag, already in its final text form, e.g. `(3)` or `(*)`.
  final EquationRowNode tag;

  /// Tag on the left (`leqno`) instead of the right.
  final bool leqno;

  TagNode({required this.body, required this.tag, this.leqno = false});

  @override
  BuildResult buildWidget(
    MathOptions options,
    List<BuildResult?> childBuildResults,
  ) => BuildResult(
    options: options,
    widget: TaggedLayout(
      body: childBuildResults[0]!.widget,
      tag: childBuildResults[1]!.widget,
      gap: 1.0.cssEm.toLpUnder(options),
      leqno: leqno,
    ),
  );

  @override
  List<MathOptions> computeChildOptions(MathOptions options) => [
    options,
    options,
  ];

  @override
  List<EquationRowNode> computeChildren() => [body, tag];

  @override
  AtomType get leftType => AtomType.ord;

  @override
  AtomType get rightType => AtomType.ord;

  @override
  bool shouldRebuildWidget(MathOptions oldOptions, MathOptions newOptions) =>
      false;

  @override
  TagNode updateChildren(List<EquationRowNode> newChildren) =>
      TagNode(body: newChildren[0], tag: newChildren[1], leqno: leqno);

  @override
  Map<String, Object?> toJson() => super.toJson()
    ..addAll({
      'body': body.toJson(),
      'tag': tag.toJson(),
      if (leqno) 'leqno': leqno,
    });
}
