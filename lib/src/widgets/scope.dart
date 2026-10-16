import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'mode.dart';
import 'selectable.dart' show SelectionStyle;

/// Carries rendering mode and, for [FlutterMathMode.select], the selection
/// state from [Math] / [SelectableMath] down to every equation row.
///
/// Replaces the `provider` package the original engine used.
class MathScope extends InheritedWidget {
  final FlutterMathMode mode;

  /// The fields below are only set in [FlutterMathMode.select].
  final MathController? controller;
  final SelectionStyle? selectionStyle;
  final (LayerLink, LayerLink)? handleLayerLinks;
  final AnimationController? cursorBlinkOpacityController;

  const MathScope({
    super.key,
    required this.mode,
    this.controller,
    this.selectionStyle,
    this.handleLayerLinks,
    this.cursorBlinkOpacityController,
    required super.child,
  });

  /// The nearest scope; a bare equation tree with none above it renders in
  /// [FlutterMathMode.view].
  static MathScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MathScope>();

  @override
  bool updateShouldNotify(MathScope old) =>
      old.mode != mode ||
      old.controller != controller ||
      old.selectionStyle != selectionStyle ||
      old.handleLayerLinks != handleLayerLinks ||
      old.cursorBlinkOpacityController != cursorBlinkOpacityController;
}

/// Listens to [listenable] and rebuilds only when [selector]'s result changes —
/// the job `provider`'s `Selector` did, so a selection change elsewhere in
/// the equation does not rebuild every row.
class ListenableSelector<T> extends StatefulWidget {
  final Listenable listenable;
  final T Function() selector;
  final Widget Function(BuildContext context, T value) builder;

  const ListenableSelector({
    super.key,
    required this.listenable,
    required this.selector,
    required this.builder,
  });

  @override
  State<ListenableSelector<T>> createState() => _ListenableSelectorState<T>();
}

class _ListenableSelectorState<T> extends State<ListenableSelector<T>> {
  late T _value = widget.selector();

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_onChange);
  }

  @override
  void didUpdateWidget(ListenableSelector<T> old) {
    super.didUpdateWidget(old);
    if (old.listenable != widget.listenable) {
      old.listenable.removeListener(_onChange);
      widget.listenable.addListener(_onChange);
    }
    // The selector closure may read new inputs from the parent rebuild.
    _value = widget.selector();
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    final next = widget.selector();
    if (next != _value) setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}
