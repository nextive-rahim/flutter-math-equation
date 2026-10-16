import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';

/// A golden comparator that accepts a tiny share of differing pixels, so
/// sub-pixel antialiasing noise does not fail a test while any real layout or
/// glyph change still does.
class TolerantGoldenComparator extends LocalFileComparator {
  TolerantGoldenComparator(super.testFile, {this.tolerance = 0.003});

  /// Largest accepted fraction of differing pixels (0.003 = 0.3%).
  final double tolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= tolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
