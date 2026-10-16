import 'package:flutter/material.dart';
import 'package:flutter_equation_support/flutter_equation_support.dart';
import 'package:flutter_test/flutter_test.dart';

/// Layout rules shared with flutter_widget_from_html 0.17, checked against
/// it pixel for pixel during the port (see NOTICE).
void main() {
  const style = TextStyle(fontSize: 10, height: 1);

  Future<void> pump(WidgetTester tester, String html) => tester.pumpWidget(
    MaterialApp(
      home: Material(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 300, child: HtmlView(html, textStyle: style)),
        ),
      ),
    ),
  );

  List<String> texts(WidgetTester tester) => tester
      .widgetList<RichText>(find.byType(RichText))
      .map((r) => r.text.toPlainText())
      .toList();

  double heightOf(WidgetTester tester) =>
      tester.getSize(find.byType(HtmlView)).height;

  testWidgets('white space collapses and is trimmed per run', (tester) async {
    await pump(tester, '<p>  many   spaces\n here  </p>');
    expect(texts(tester), ['many spaces here']);
  });

  testWidgets('<br> breaks lines; the last one in a run is dropped', (
    tester,
  ) async {
    await pump(tester, 'a<br> b<br><br>c<br>');
    expect(texts(tester), ['a\nb\n\nc']);
  });

  testWidgets('a paragraph of only <br> is 1em tall', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: HtmlView('<p><br></p>', textStyle: TextStyle(fontSize: 30)),
          ),
        ),
      ),
    );
    expect(heightOf(tester), 30);
  });

  testWidgets('margins collapse and are dropped at the edges', (tester) async {
    // Two 10px lines, one 1em (10px) gap: the larger of the two margins.
    await pump(tester, '<p>a</p><h4>b</h4>');
    expect(heightOf(tester), 10 + 13.3 + 10, reason: 'h4 margin is 1.33em');
    await pump(tester, '<p>a</p><p>b</p>');
    expect(heightOf(tester), 30);
  });

  testWidgets('padding keeps children\'s margins inside', (tester) async {
    await pump(tester, '<div style="padding:5px"><p>a</p></div>');
    expect(heightOf(tester), 5 + 10 + 10 + 10 + 5);
  });

  testWidgets('adjacent same-style text is one span', (tester) async {
    await pump(tester, '<p>ক্<span>ষ</span></p>');
    final rich = tester.widget<RichText>(find.byType(RichText));
    expect(rich.text, isA<TextSpan>());
    expect((rich.text as TextSpan).children, isNull);
    expect(rich.text.toPlainText(), 'ক্ষ');
  });

  testWidgets('inline CSS applies', (tester) async {
    await pump(
      tester,
      '<p><span style="color: rgb(255, 0, 0); font-weight: 700">x</span></p>',
    );
    final span =
        tester.widget<RichText>(find.byType(RichText)).text as TextSpan;
    expect(span.style!.color, const Color(0xFFFF0000));
    expect(span.style!.fontWeight, FontWeight.bold);
  });

  testWidgets('lists get markers', (tester) async {
    await pump(tester, '<ol start="3"><li>a</li><li>b</li></ol>');
    expect(texts(tester), containsAll(['3.', '4.', 'a', 'b']));
  });

  testWidgets('links call onTapUrl', (tester) async {
    String? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: HtmlView(
            '<a href="https://x.org">link</a>',
            onTapUrl: (url) => tapped = url,
          ),
        ),
      ),
    );
    await tester.tapAt(
      tester.getTopLeft(find.byType(RichText)) + const Offset(5, 5),
    );
    expect(tapped, 'https://x.org');
  });
}
