@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_math_equation/flutter_math_equation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/exam_corpus.dart';
import 'support/real_fonts.dart';
import 'support/tolerant_comparator.dart';

/// Renders exam-style bodies through [MathRender] at phone width and
/// compares them with test/goldens/exam_*.png.
void main() {
  setUpAll(() async {
    goldenFileComparator = TolerantGoldenComparator(
      Uri.parse('test/math_render_test.dart'),
    );
    await loadRealFonts();
  });

  const style = TextStyle(
    fontFamily: 'AppBengali',
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.65,
    color: Color(0xFF1A1F2C),
  );

  for (final MapEntry(key: name, value: html) in examCorpus.entries) {
    for (final full in [false, true]) {
      final label = 'exam_$name${full ? '_full' : ''}';
      testWidgets(label, (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 800));
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Material(
              color: Colors.white,
              child: Align(
                alignment: Alignment.topLeft,
                child: RepaintBoundary(
                  key: key,
                  child: Container(
                    color: Colors.white,
                    width: 360,
                    child: MathRenderTheme(
                      data: const MathRenderThemeData(fontFamily: 'AppBengali'),
                      child: MathRender(
                        htmlContent: html,
                        style: style,
                        fullContainerScroll: full,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byKey(key),
          matchesGoldenFile('goldens/$label.png'),
        );
      });
    }
  }

  testWidgets('the default style uses the theme font', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: MathRenderTheme(
            data: MathRenderThemeData(fontFamily: 'AppBengali'),
            child: MathRender(htmlContent: '<p>বাংলা</p>'),
          ),
        ),
      ),
    );
    final rich = tester.widget<RichText>(find.byType(RichText).first);
    expect(rich.text.style?.fontFamily ?? '', 'AppBengali');
  });
}
