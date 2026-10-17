import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_equation/flutter_math_equation.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  // simpleclub/flutter_math#132: a script whose base was missing from the
  // intrinsic-size pass threw "Null check operator used on a null value".
  testWidgets('scripts survive intrinsic sizing', (tester) async {
    await tester.pumpWidget(
      host(
        IntrinsicWidth(
          child: IntrinsicHeight(
            child: Math.tex(
              r'\mathrm{CL_r = CL_{tot} \times f_e}',
              textStyle: const TextStyle(fontSize: 20),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(Math), findsOneWidget);
  });

  // simpleclub/flutter_math#121: \left…\right under unbounded constraints.
  testWidgets('delimiters survive unbounded constraints', (tester) async {
    await tester.pumpWidget(
      host(
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: UnconstrainedBox(
              child: Math.tex(
                r'\left( \frac{\left[ a \right]}{b} \right)',
                textStyle: const TextStyle(fontSize: 20),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  intrinsicHostTests();

  // \bcancel was misspelled and \xcancel passed one joined notation
  // string, so neither drew its strike.
  testWidgets('every cancel variant draws its own strikes', (tester) async {
    final plain = await capture(tester, 'y');
    final drawn = <String, Uint8List>{
      for (final command in [r'\cancel', r'\bcancel', r'\xcancel'])
        command: await capture(tester, '$command{y}'),
    };
    for (final entry in drawn.entries) {
      expect(entry.value, isNot(equals(plain)), reason: entry.key);
    }
    expect(drawn[r'\cancel'], isNot(equals(drawn[r'\bcancel'])));
    expect(drawn[r'\xcancel'], isNot(equals(drawn[r'\cancel'])));
    expect(drawn[r'\xcancel'], isNot(equals(drawn[r'\bcancel'])));
  });
}

Future<Uint8List> capture(WidgetTester tester, String tex) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    host(
      Center(
        child: RepaintBoundary(
          key: key,
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(8),
            child: Math.tex(
              tex,
              textStyle: const TextStyle(fontSize: 24, color: Colors.black),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return Uint8List.fromList([
      ...bytes!.buffer.asUint8List(),
      image.width >> 8,
      image.width & 255,
      image.height >> 8,
      image.height & 255,
    ]);
  }))!;
}

// The app's layouts: equations inside WidgetSpans of a RichText, measured
// intrinsically by IntrinsicWidth and by Table's IntrinsicColumnWidth.
void intrinsicHostTests() {
  for (final tex in [
    r'\mathrm{CL_r = CL_{tot} \times f_e}',
    r'x^2_i + {}^{14}_{6}\mathrm{C}',
    r'\sum_{i=1}^{n} a_i^2',
  ]) {
    testWidgets('WidgetSpan in IntrinsicWidth: $tex', (tester) async {
      await tester.pumpWidget(
        host(
          IntrinsicWidth(
            child: RichText(
              text: TextSpan(
                children: [
                  const TextSpan(text: 'x '),
                  WidgetSpan(
                    child: Math.tex(
                      tex,
                      textStyle: const TextStyle(fontSize: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Table cell: $tex', (tester) async {
      await tester.pumpWidget(
        host(
          Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: [
              TableRow(
                children: [
                  Math.tex(tex, textStyle: const TextStyle(fontSize: 20)),
                  const Text('cell'),
                ],
              ),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
