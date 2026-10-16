import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../../render/layout/reset_dimension.dart';
import '../options.dart';
import '../size.dart';
import '../syntax_tree.dart';
import '../types.dart';

/// `\includegraphics[height=…,width=…,totalheight=…,alt=…]{url}` (KaTeX
/// functions/includegraphics.ts): an image standing on the baseline,
/// [height] above it and `totalheight - height` below. Network and
/// `data:image/…;base64,` URLs are supported.
class IncludeGraphicsNode extends LeafNode {
  final String src;
  final String alt;
  final Measurement height;

  /// Zero for the image's own aspect ratio.
  final Measurement width;

  /// Zero when not given.
  final Measurement totalHeight;

  @override
  final Mode mode;

  IncludeGraphicsNode({
    required this.src,
    required this.alt,
    required this.height,
    required this.width,
    required this.totalHeight,
    this.mode = Mode.math,
  });

  @override
  BuildResult buildWidget(
    MathOptions options,
    List<BuildResult?> childBuildResults,
  ) {
    final height = this.height.toLpUnder(options);
    final depth = totalHeight.value > 0
        ? totalHeight.toLpUnder(options) - height
        : 0.0;
    final width = this.width.value > 0 ? this.width.toLpUnder(options) : null;
    Widget fallback(BuildContext context, Object error, StackTrace? stack) =>
        Text(
          alt,
          style: TextStyle(color: options.color, fontSize: height),
        );
    final Widget image;
    if (src.startsWith('data:image/') && src.contains('base64,')) {
      image = Image.memory(
        base64Decode(src.substring(src.indexOf('base64,') + 7)),
        height: height + depth,
        width: width,
        fit: BoxFit.contain,
        semanticLabel: alt,
        errorBuilder: fallback,
      );
    } else {
      image = Image.network(
        src,
        height: height + depth,
        width: width,
        fit: BoxFit.contain,
        semanticLabel: alt,
        errorBuilder: fallback,
      );
    }
    return BuildResult(
      options: options,
      widget: ResetDimension(
        height: height,
        depth: depth,
        horizontalAlignment: CrossAxisAlignment.start,
        child: image,
      ),
    );
  }

  @override
  AtomType get leftType => AtomType.ord;

  @override
  AtomType get rightType => AtomType.ord;

  @override
  bool shouldRebuildWidget(MathOptions oldOptions, MathOptions newOptions) =>
      oldOptions.sizeMultiplier != newOptions.sizeMultiplier;

  @override
  Map<String, Object?> toJson() => super.toJson()
    ..addAll({
      'src': src,
      'alt': alt,
      'height': height.toString(),
      'width': width.toString(),
      'totalHeight': totalHeight.toString(),
    });
}
