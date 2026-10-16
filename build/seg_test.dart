import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_equation_support/flutter_equation_support.dart';
import 'package:flutter_test/flutter_test.dart';
import '../test/support/real_fonts.dart';
void main() {
  setUpAll(loadRealFonts);
  for (final (name, tex) in [('combo', r'\overlinesegment{AB} \quad \underlinesegment{CD}'), ('combo2', r'\overlinesegment{AB} \underlinesegment{CD}'), ('combo3', r'AB \quad \underlinesegment{CD}'), ('combo4', r'\overlinesegment{AB} \quad CD')]) {
    testWidgets(name, (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(home: Scaffold(backgroundColor: Colors.white, body: Align(alignment: Alignment.topLeft, child: RepaintBoundary(key: key, child: Container(color: Colors.white, padding: const EdgeInsets.all(6), child: Math.tex(tex, textStyle: const TextStyle(fontSize: 22, color: Colors.black))))))));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await b.toImage();
        final bytes = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        var dark = 0;
        for (var x = 0; x < img.width; x++) { if (bytes.getUint8(((img.height - 1) * img.width + x) * 4) < 100) dark++; }
        print('$name size=${img.width}x${img.height} darkBottomRow=$dark');
        File('build/seg_$name.png').writeAsBytesSync((await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());
      });
    });
  }
}
