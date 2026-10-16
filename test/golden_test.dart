@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_equation_support/flutter_equation_support.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/corpus.dart';
import 'support/real_fonts.dart';
import 'support/tolerant_comparator.dart';

/// Renders every corpus equation with the real fonts and compares it with
/// its golden image under test/goldens/. After an intended rendering change,
/// review the new images and run `flutter test --update-goldens`.
void main() {
  setUpAll(() async {
    goldenFileComparator = TolerantGoldenComparator(
      Uri.parse('test/golden_test.dart'),
    );
    await loadRealFonts();
  });

  Future<void> expectGolden(
    WidgetTester tester,
    String name,
    String tex, {
    String? fontFamily,
  }) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(6),
                child: Math.tex(
                  tex,
                  textStyle: TextStyle(
                    fontSize: 22,
                    color: Colors.black,
                    fontFamily: fontFamily,
                  ),
                  onErrorFallback: (e) => Text(
                    'ERROR ${e.message}',
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('ERROR'), findsNothing, reason: tex);
    await expectLater(find.byKey(key), matchesGoldenFile('goldens/$name.png'));
  }

  for (final entry in engineCorpus.entries) {
    testWidgets(entry.key, (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 400));
      await expectGolden(tester, entry.key, entry.value);
    });
  }

  for (final entry in bengaliCorpus.entries) {
    testWidgets(entry.key, (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 400));
      await expectGolden(
        tester,
        entry.key,
        entry.value,
        fontFamily: 'AppBengali',
      );
    });
  }
}
