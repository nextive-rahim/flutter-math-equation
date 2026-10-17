import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the package's real fonts so tests render actual glyphs instead of
/// the test-only Ahem boxes. Families are registered under the same names
/// the engine asks for at runtime.
Future<void> loadRealFonts() async {
  final katex = Directory('lib/katex_fonts/fonts');
  final byFamily = <String, List<File>>{};
  for (final file in katex.listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last;
    if (!name.endsWith('.ttf')) continue;
    final family = name.substring(0, name.indexOf('-'));
    byFamily
        .putIfAbsent('packages/flutter_math_equation/$family', () => [])
        .add(file);
  }
  byFamily['packages/flutter_math_equation/NotoSansBengali'] = Directory(
    'lib/fonts/noto_sans_bengali',
  ).listSync().whereType<File>().where((f) => f.path.endsWith('.ttf')).toList();
  // A plain family name, as an app would declare its own prose font.
  byFamily['AppBengali'] =
      byFamily['packages/flutter_math_equation/NotoSansBengali']!;

  for (final entry in byFamily.entries) {
    final loader = FontLoader(entry.key);
    for (final file in entry.value) {
      final bytes = file.readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}
