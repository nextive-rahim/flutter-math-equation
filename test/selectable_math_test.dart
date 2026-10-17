import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_equation/flutter_math_equation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> clipboard;

  setUp(() {
    clipboard = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          if (call.method == 'Clipboard.hasStrings') {
            return {'value': false};
          }
          return null;
        });
  });

  Widget app(Widget child, {FocusNode? focusNode}) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets(
    'long-press shows a toolbar whose Copy puts TeX on the clipboard',
    (tester) async {
      await tester.pumpWidget(
        app(
          SelectableMath.tex(r'a+b', textStyle: const TextStyle(fontSize: 40)),
        ),
      );
      await tester.longPress(find.byType(SelectableMath));
      await tester.pumpAndSettle();

      // Long-press selects the atom under the finger — the `+` in the middle.
      expect(find.text('Copy'), findsOneWidget);
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(clipboard.last.trim(), '+');

      // Select all from the menu, then copy the whole equation.
      await tester.longPress(find.byType(SelectableMath));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      expect(
        find.text('Select all'),
        findsNothing,
        reason: 'everything is selected already',
      );
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(clipboard.last.replaceAll(' ', ''), 'a+b');
      // Copy closes the menu.
      expect(find.text('Copy'), findsNothing);
    },
  );

  testWidgets('copy can be turned off', (tester) async {
    await tester.pumpWidget(
      app(
        SelectableMath.tex(
          r'a+b',
          textStyle: const TextStyle(fontSize: 40),
          toolbarOptions: const MathToolbarOptions(copy: false),
        ),
      ),
    );
    await tester.longPress(find.byType(SelectableMath));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('Ctrl+A then Ctrl+C copies the whole equation', (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      app(
        SelectableMath.tex(
          r'\frac{1}{2}',
          focusNode: focusNode,
          textStyle: const TextStyle(fontSize: 40),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(clipboard, hasLength(1));
    expect(clipboard.single.replaceAll(' ', ''), contains(r'\frac{1}{2}'));
  });

  testWidgets('a key handler the caller set on the focus node still runs', (
    tester,
  ) async {
    var callerSawKey = false;
    final focusNode = FocusNode(
      onKeyEvent: (node, event) {
        callerSawKey = true;
        return KeyEventResult.ignored;
      },
    );
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      app(
        SelectableMath.tex(
          r'x',
          focusNode: focusNode,
          textStyle: const TextStyle(fontSize: 40),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    expect(callerSawKey, isTrue);

    // And the caller gets its handler back once the widget is gone.
    await tester.pumpWidget(const SizedBox());
    callerSawKey = false;
    focusNode.onKeyEvent!(
      focusNode,
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyQ,
        logicalKey: LogicalKeyboardKey.keyQ,
        timeStamp: Duration.zero,
      ),
    );
    expect(callerSawKey, isTrue);
  });
}
