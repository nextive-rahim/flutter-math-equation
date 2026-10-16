import 'package:flutter/widgets.dart';

import '../utils/complex_script.dart';
import 'math_render.dart';

/// Settings for [MathRender], [EquationSolver] and [ZoomableImage] below a
/// [MathRenderTheme].
@immutable
class MathRenderThemeData {
  /// Font family of the default prose style, used when a [MathRender] gets
  /// no `style`. Defaults to the bundled Noto Sans Bengali.
  final String fontFamily;

  /// Backing colour behind images, which are often scans with transparent
  /// areas drawn for a white page.
  final Color imageBackgroundColor;

  /// Shown while a network image loads. Defaults to a 100px grey box with
  /// rounded corners.
  final WidgetBuilder? imageLoadingBuilder;

  /// Called with a link's `href` when it is tapped; links are not tappable
  /// when null.
  final void Function(String url)? onTapUrl;

  const MathRenderThemeData({
    this.fontFamily = bundledComplexScriptFontFamily,
    this.imageBackgroundColor = const Color(0xFFFFFFFF),
    this.imageLoadingBuilder,
    this.onTapUrl,
  });

  /// The image loading placeholder.
  Widget buildImagePlaceholder(BuildContext context) =>
      imageLoadingBuilder?.call(context) ??
      Container(
        width: double.infinity,
        height: 100,
        decoration: BoxDecoration(
          color: const Color(0x1F9E9E9E),
          borderRadius: BorderRadius.circular(10),
        ),
      );

  MathRenderThemeData copyWith({
    String? fontFamily,
    Color? imageBackgroundColor,
    WidgetBuilder? imageLoadingBuilder,
    void Function(String url)? onTapUrl,
  }) => MathRenderThemeData(
    fontFamily: fontFamily ?? this.fontFamily,
    imageBackgroundColor: imageBackgroundColor ?? this.imageBackgroundColor,
    imageLoadingBuilder: imageLoadingBuilder ?? this.imageLoadingBuilder,
    onTapUrl: onTapUrl ?? this.onTapUrl,
  );

  @override
  bool operator ==(Object other) =>
      other is MathRenderThemeData &&
      other.fontFamily == fontFamily &&
      other.imageBackgroundColor == imageBackgroundColor &&
      other.imageLoadingBuilder == imageLoadingBuilder &&
      other.onTapUrl == onTapUrl;

  @override
  int get hashCode => Object.hash(
    fontFamily,
    imageBackgroundColor,
    imageLoadingBuilder,
    onTapUrl,
  );
}

/// Provides [MathRenderThemeData] to the [MathRender]s below it.
///
/// ```dart
/// MathRenderTheme(
///   data: MathRenderThemeData(fontFamily: 'NotoSerifBengali'),
///   child: MaterialApp(...),
/// )
/// ```
class MathRenderTheme extends InheritedWidget {
  final MathRenderThemeData data;

  const MathRenderTheme({super.key, required this.data, required super.child});

  /// The closest theme's data, or the defaults.
  static MathRenderThemeData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MathRenderTheme>()?.data ??
      const MathRenderThemeData();

  @override
  bool updateShouldNotify(MathRenderTheme oldWidget) => data != oldWidget.data;
}
