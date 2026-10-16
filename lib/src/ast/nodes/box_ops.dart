import 'package:flutter/widgets.dart';

import '../../render/layout/reset_dimension.dart';
import '../../render/layout/shift_baseline.dart';
import '../options.dart';
import '../size.dart';
import '../style.dart';
import '../syntax_tree.dart';

/// `\smash[tb]{…}`: draws its body but reports zero height (`t`), zero depth
/// (`b`) or both, so it does not push neighbouring lines apart. Spaced as an
/// ordinary atom (KaTeX functions/smash.ts).
class SmashNode extends SlotableNode<EquationRowNode> {
  final EquationRowNode body;
  final bool smashHeight;
  final bool smashDepth;

  SmashNode({
    required this.body,
    this.smashHeight = true,
    this.smashDepth = true,
  });

  @override
  BuildResult buildWidget(
    MathOptions options,
    List<BuildResult?> childBuildResults,
  ) => BuildResult(
    options: options,
    widget: ResetDimension(
      height: smashHeight ? 0 : null,
      depth: smashDepth ? 0 : null,
      horizontalAlignment: CrossAxisAlignment.start,
      child: childBuildResults[0]!.widget,
    ),
  );

  @override
  List<MathOptions> computeChildOptions(MathOptions options) => [options];

  @override
  List<EquationRowNode> computeChildren() => [body];

  @override
  AtomType get leftType => AtomType.ord;

  @override
  AtomType get rightType => AtomType.ord;

  @override
  bool shouldRebuildWidget(MathOptions oldOptions, MathOptions newOptions) =>
      false;

  @override
  SmashNode updateChildren(List<EquationRowNode> newChildren) => SmashNode(
    body: newChildren[0],
    smashHeight: smashHeight,
    smashDepth: smashDepth,
  );

  @override
  Map<String, Object?> toJson() => super.toJson()
    ..addAll({
      'body': body.toJson(),
      if (!smashHeight) 'smashHeight': smashHeight,
      if (!smashDepth) 'smashDepth': smashDepth,
    });
}

/// Which way a [LapNode]'s content overhangs its zero-width box.
enum LapAlignment {
  /// `\mathllap`: content ends at the box, overhanging to the left.
  left,

  /// `\mathrlap`: content starts at the box, overhanging to the right.
  right,

  /// `\mathclap`: content centred on the box.
  center,
}

/// `\mathllap`, `\mathrlap`, `\mathclap`: content in a box of zero width
/// (KaTeX functions/lap.ts). Spaced as an ordinary atom.
class LapNode extends SlotableNode<EquationRowNode> {
  final EquationRowNode body;
  final LapAlignment alignment;

  LapNode({required this.body, required this.alignment});

  @override
  BuildResult buildWidget(
    MathOptions options,
    List<BuildResult?> childBuildResults,
  ) => BuildResult(
    options: options,
    widget: ResetDimension(
      width: 0,
      horizontalAlignment: switch (alignment) {
        LapAlignment.left => CrossAxisAlignment.end,
        LapAlignment.right => CrossAxisAlignment.start,
        LapAlignment.center => CrossAxisAlignment.center,
      },
      child: childBuildResults[0]!.widget,
    ),
  );

  @override
  List<MathOptions> computeChildOptions(MathOptions options) => [options];

  @override
  List<EquationRowNode> computeChildren() => [body];

  @override
  AtomType get leftType => AtomType.ord;

  @override
  AtomType get rightType => AtomType.ord;

  @override
  bool shouldRebuildWidget(MathOptions oldOptions, MathOptions newOptions) =>
      false;

  @override
  LapNode updateChildren(List<EquationRowNode> newChildren) =>
      LapNode(body: newChildren[0], alignment: alignment);

  @override
  Map<String, Object?> toJson() =>
      super.toJson()
        ..addAll({'body': body.toJson(), 'alignment': alignment.name});
}

/// `\vcenter{…}`: moves the body so the centre of its box sits on the math
/// axis (KaTeX functions/vcenter.ts).
class VCenterNode extends SlotableNode<EquationRowNode> {
  final EquationRowNode body;

  VCenterNode({required this.body});

  @override
  BuildResult buildWidget(
    MathOptions options,
    List<BuildResult?> childBuildResults,
  ) => BuildResult(
    options: options,
    widget: ShiftBaseline(
      relativePos: 0.5,
      offset: options.fontMetrics.axisHeight.cssEm.toLpUnder(options),
      child: childBuildResults[0]!.widget,
    ),
  );

  @override
  List<MathOptions> computeChildOptions(MathOptions options) => [options];

  @override
  List<EquationRowNode> computeChildren() => [body];

  @override
  AtomType get leftType => AtomType.ord;

  @override
  AtomType get rightType => AtomType.ord;

  @override
  bool shouldRebuildWidget(MathOptions oldOptions, MathOptions newOptions) =>
      false;

  @override
  VCenterNode updateChildren(List<EquationRowNode> newChildren) =>
      VCenterNode(body: newChildren[0]);

  @override
  Map<String, Object?> toJson() =>
      super.toJson()..addAll({'body': body.toJson()});
}

/// `\reflectbox` / `\mathreflectbox`: the body mirrored left to right
/// (KaTeX 0.18.7 functions/reflectbox.ts).
class ReflectNode extends SlotableNode<EquationRowNode> {
  final EquationRowNode body;

  ReflectNode({required this.body});

  @override
  BuildResult buildWidget(
    MathOptions options,
    List<BuildResult?> childBuildResults,
  ) => BuildResult(
    options: options,
    widget: Transform.flip(flipX: true, child: childBuildResults[0]!.widget),
  );

  @override
  List<MathOptions> computeChildOptions(MathOptions options) => [options];

  @override
  List<EquationRowNode> computeChildren() => [body];

  @override
  AtomType get leftType => AtomType.ord;

  @override
  AtomType get rightType => AtomType.ord;

  @override
  bool shouldRebuildWidget(MathOptions oldOptions, MathOptions newOptions) =>
      false;

  @override
  ReflectNode updateChildren(List<EquationRowNode> newChildren) =>
      ReflectNode(body: newChildren[0]);

  @override
  Map<String, Object?> toJson() =>
      super.toJson()..addAll({'body': body.toJson()});
}

/// `\mathchoice{D}{T}{S}{SS}`: renders the argument for the current style
/// — display, text, script or scriptscript (KaTeX functions/mathchoice.ts).
class MathChoiceNode extends SlotableNode<EquationRowNode> {
  final EquationRowNode display;
  final EquationRowNode text;
  final EquationRowNode script;
  final EquationRowNode scriptscript;

  MathChoiceNode({
    required this.display,
    required this.text,
    required this.script,
    required this.scriptscript,
  });

  @override
  BuildResult buildWidget(
    MathOptions options,
    List<BuildResult?> childBuildResults,
  ) {
    final chosen = childBuildResults[options.style.size.clamp(0, 3)]!;
    return BuildResult(
      options: options,
      widget: chosen.widget,
      italic: chosen.italic,
      skew: chosen.skew,
    );
  }

  @override
  List<MathOptions> computeChildOptions(MathOptions options) => [
    options,
    options,
    options,
    options,
  ];

  @override
  List<EquationRowNode> computeChildren() => [
    display,
    text,
    script,
    scriptscript,
  ];

  // The class of the chosen argument depends on the style, which is not
  // known here; the text-style argument stands in for it.
  @override
  AtomType get leftType => text.leftType;

  @override
  AtomType get rightType => text.rightType;

  @override
  bool shouldRebuildWidget(MathOptions oldOptions, MathOptions newOptions) =>
      oldOptions.style.size != newOptions.style.size;

  @override
  MathChoiceNode updateChildren(List<EquationRowNode> newChildren) =>
      MathChoiceNode(
        display: newChildren[0],
        text: newChildren[1],
        script: newChildren[2],
        scriptscript: newChildren[3],
      );

  @override
  Map<String, Object?> toJson() => super.toJson()
    ..addAll({
      'display': display.toJson(),
      'text': text.toJson(),
      'script': script.toJson(),
      'scriptscript': scriptscript.toJson(),
    });
}
