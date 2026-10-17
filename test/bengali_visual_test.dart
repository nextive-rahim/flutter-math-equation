@Tags(['visual'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_equation/flutter_math_equation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/real_fonts.dart';

const samples = <String>[
  r'\text{ক্রয়মূল্য} = ১২০ \text{ টাকা}',
  r'\frac{১০০}{১২০} \times ১০০',
  r'\sqrt{৬২৫} = ২৫',
  r'x^২ + ২৫x - ৭৫০০ = ০',
  r'(৪+৫+৩)^২ = ১৪৪',
  r'\frac{\text{লাভ}}{\text{ক্রয়মূল্য}} \times ১০০\%',
  r'\textbf{সমাধান:}\ a = ১ + \sqrt{৩}',
  r'\begin{array}{cc} \text{শ্রেণি} & \text{গণসংখ্যা} \\ ১০-২০ & ৫ \end{array}',
  r'\sum_{i=১}^{n} x_i = \text{মোট}',
  r'\text{The quick brown fox} \; a^2+b^2=c^2',
];

void main() {
  testWidgets('bengali visual sheet', (tester) async {
    await tester.runAsync(loadRealFonts);
    final key = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(900, 1100));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: RepaintBoundary(
            key: key,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final tex in samples)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Math.tex(
                        tex,
                        textStyle: const TextStyle(
                          fontSize: 26,
                          color: Colors.black,
                          fontFamily: 'AppBengali',
                        ),
                        onErrorFallback: (e) => Text(
                          'ERROR: ${e.message}',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('build').createSync(recursive: true);
      File('build/bengali_visual.png')
          .writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}
