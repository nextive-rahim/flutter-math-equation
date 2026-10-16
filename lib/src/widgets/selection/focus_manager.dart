import 'package:flutter/widgets.dart';

mixin FocusManagerMixin<T extends StatefulWidget> on State<T> {
  FocusNode get focusNode;

  /// Handles a key event while [focusNode] has focus. The node's own
  /// [FocusNode.onKeyEvent], if the caller set one, runs first.
  KeyEventResult handleKeyEvent(FocusNode node, KeyEvent event) =>
      KeyEventResult.ignored;

  FocusOnKeyEventCallback? _callerOnKeyEvent;

  FocusAttachment _attach(FocusNode node) {
    _callerOnKeyEvent = node.onKeyEvent;
    return node.attach(context, onKeyEvent: _onKeyEvent);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final callerResult =
        _callerOnKeyEvent?.call(node, event) ?? KeyEventResult.ignored;
    if (callerResult != KeyEventResult.ignored) return callerResult;
    return handleKeyEvent(node, event);
  }

  late FocusNode _oldFocusNode;

  late FocusAttachment _focusAttachment;

  @override
  void initState() {
    super.initState();

    _focusAttachment = _attach(focusNode);
    _oldFocusNode = focusNode;
  }

  @override
  void didUpdateWidget(T oldWidget) {
    if (focusNode != _oldFocusNode) {
      _focusAttachment.detach();
      _oldFocusNode.onKeyEvent = _callerOnKeyEvent;
      _focusAttachment = _attach(focusNode);
      _oldFocusNode = focusNode;
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _focusAttachment.detach();
    // Hand a caller-owned node back with its own handler.
    focusNode.onKeyEvent = _callerOnKeyEvent;
    super.dispose();
  }

  @mustCallSuper
  @override
  Widget build(BuildContext context) {
    super.build(context);
    _focusAttachment.reparent();
    return _NullWidget();
  }
}

class _NullWidget extends StatelessWidget {
  const _NullWidget();

  @override
  Widget build(BuildContext context) {
    throw FlutterError(
      'Widgets that mix FocusManagerMixin into their State must call'
      'super.build() but must ignore the return value of the superclass.',
    );
  }
}
