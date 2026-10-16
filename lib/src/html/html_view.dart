import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'css.dart';
import 'html_dom.dart';
import 'html_list.dart';

/// Builds a widget for [element] in place of the default rendering, or
/// returns null to keep it. The widget is laid out as a block.
typedef HtmlCustomWidgetBuilder = Widget? Function(HtmlElement element);

/// Renders an HTML fragment as Flutter widgets: a column of blocks, each
/// run of inline content one [RichText].
///
/// The layout follows flutter_widget_from_html 0.17 (`RenderMode.column`)
/// so that content keeps its look when moving off that package: the same
/// default stylesheet (`p` margin 1em 0, headings, 40px list indent …),
/// vertical margins that collapse into their neighbours and parents and are
/// dropped at the very top and bottom, `<sup>`/`<sub>` raised by 0.4em,
/// `font-size` scaled by the text scale factor, and the same list markers.
///
/// Inline CSS is supported for colour, background colour, font family, size,
/// style and weight, line height, text alignment and decoration, white
/// space, display, vertical alignment, margin and padding.
///
/// Adjacent text with the same style is drawn as one span, so Bengali and
/// other complex scripts shape across element boundaries.
class HtmlView extends StatefulWidget {
  /// The HTML fragment.
  final String html;

  /// The base style, merged over the ambient [DefaultTextStyle].
  final TextStyle? textStyle;

  /// Overrides the rendering of chosen elements (`<img>`, say).
  final HtmlCustomWidgetBuilder? customWidgetBuilder;

  /// Called with a link's `href` when it is tapped. Links are not tappable
  /// when this is null.
  final void Function(String url)? onTapUrl;

  const HtmlView(
    this.html, {
    super.key,
    this.textStyle,
    this.customWidgetBuilder,
    this.onTapUrl,
  });

  @override
  State<HtmlView> createState() => _HtmlViewState();
}

class _HtmlViewState extends State<HtmlView> {
  late HtmlElement _document = parseHtmlFragment(widget.html);
  final _recognizers = <GestureRecognizer>[];

  @override
  void didUpdateWidget(HtmlView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html) {
      _document = parseHtmlFragment(widget.html);
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    var style = DefaultTextStyle.of(context).style.merge(widget.textStyle);
    final textScaleFactor = MediaQuery.textScalerOf(context).scale(1);
    if (textScaleFactor != 1 && style.fontSize != null) {
      style = style.copyWith(fontSize: style.fontSize! * textScaleFactor);
    }
    final builder = _HtmlBuilder(
      linkColor: Theme.of(context).colorScheme.primary,
      textScaleFactor: textScaleFactor,
      rootStyle: style,
      customWidgetBuilder: widget.customWidgetBuilder,
      onTapUrl: widget.onTapUrl,
      recognizers: _recognizers,
      selectionRegistrar: SelectionContainer.maybeOf(context),
      selectionColor:
          DefaultSelectionStyle.of(context).selectionColor ??
          DefaultSelectionStyle.defaultColor,
    );
    final root = _Props(
      style: style,
      rootFontSize: style.fontSize ?? 14,
      normalHeight: style.height,
    );
    final items = builder.blockContent(_document.children, root);
    // Margins at the very top and bottom are dropped.
    _trimGaps(items);
    return _column(items, root.align) ?? const SizedBox.shrink();
  }
}

// ---------------------------------------------------------------------------
// Inherited properties

class _Props {
  final TextStyle style;
  final double rootFontSize;

  /// `line-height: normal`: the root style's height.
  final double? normalHeight;
  final TextAlign? align;
  final _WhiteSpace whiteSpace;
  final String? href;

  const _Props({
    required this.style,
    required this.rootFontSize,
    this.normalHeight,
    this.align,
    this.whiteSpace = _WhiteSpace.normal,
    this.href,
  });

  double get fontSize => style.fontSize ?? rootFontSize;

  _Props copyWith({
    TextStyle? style,
    TextAlign? align,
    _WhiteSpace? whiteSpace,
    String? href,
  }) => _Props(
    style: style ?? this.style,
    rootFontSize: rootFontSize,
    normalHeight: normalHeight,
    align: align ?? this.align,
    whiteSpace: whiteSpace ?? this.whiteSpace,
    href: href ?? this.href,
  );
}

enum _WhiteSpace { normal, pre, nowrap }

// ---------------------------------------------------------------------------
// Block items: widgets, and vertical margins still free to collapse.

sealed class _Item {
  const _Item();
}

class _Gap extends _Item {
  final double height;
  const _Gap(this.height);
}

class _Block extends _Item {
  final Widget widget;
  const _Block(this.widget);
}

void _trimGaps(List<_Item> items) {
  while (items.isNotEmpty && items.first is _Gap) {
    items.removeAt(0);
  }
  while (items.isNotEmpty && items.last is _Gap) {
    items.removeLast();
  }
}

/// [items] as a column, adjacent margins collapsed to the largest.
Widget? _column(List<_Item> items, TextAlign? align) {
  final children = <Widget>[];
  double? gap;
  void flushGap() {
    if (gap != null && gap! > 0) children.add(SizedBox(height: gap));
    gap = null;
  }

  for (final item in items) {
    switch (item) {
      case _Gap(:final height):
        gap = math.max(gap ?? 0, height);
      case _Block(:final widget):
        flushGap();
        children.add(widget);
    }
  }
  flushGap();
  if (children.isEmpty) return null;
  if (children.length == 1) return children.single;
  return Column(
    crossAxisAlignment: switch (align) {
      TextAlign.center => CrossAxisAlignment.center,
      TextAlign.right || TextAlign.end => CrossAxisAlignment.end,
      _ => CrossAxisAlignment.start,
    },
    mainAxisSize: MainAxisSize.min,
    children: children,
  );
}

// ---------------------------------------------------------------------------
// Inline pieces

sealed class _Piece {
  const _Piece();
}

class _TextPiece extends _Piece {
  String text;
  final TextStyle style;
  final GestureRecognizer? recognizer;
  final bool preserveSpace;
  _TextPiece(this.text, this.style, this.recognizer, this.preserveSpace);
}

class _BreakPiece extends _Piece {
  final TextStyle style;
  const _BreakPiece(this.style);
}

class _WidgetPiece extends _Piece {
  final InlineSpan span;
  const _WidgetPiece(this.span);
}

final _collapsibleSpace = RegExp(r'[ \t\n\r\f]+');

// ---------------------------------------------------------------------------

/// Elements that are blocks by default (flutter_widget_from_html's
/// stylesheet).
const _blockElements = {
  'address', 'article', 'aside', 'blockquote', 'center', 'dd', 'div', //
  'dl', 'dt', 'figcaption', 'figure', 'footer', 'h1', 'h2', 'h3', 'h4',
  'h5', 'h6', 'header', 'hr', 'li', 'main', 'nav', 'ol', 'p', 'pre',
  'section', 'ul', 'details', 'summary', 'table', 'body', 'html',
};

/// Elements whose content is never shown.
const _hiddenElements = {
  'head', 'link', 'meta', 'script', 'style', 'template', 'title', //
};

/// The default stylesheet, as CSS declarations per element.
Map<String, String> _defaultStyles(HtmlElement element, int listDepth) {
  final attrs = element.attributes;
  switch (element.name) {
    case 'p':
      return const {'margin': '1em 0'};
    case 'h1':
      return const {
        'font-size': '2em',
        'font-weight': 'bold',
        'margin': '0.67em 0',
      };
    case 'h2':
      return const {
        'font-size': '1.5em',
        'font-weight': 'bold',
        'margin': '0.83em 0',
      };
    case 'h3':
      return const {
        'font-size': '1.17em',
        'font-weight': 'bold',
        'margin': '1em 0',
      };
    case 'h4':
      return const {'font-weight': 'bold', 'margin': '1.33em 0'};
    case 'h5':
      return const {
        'font-size': '0.83em',
        'font-weight': 'bold',
        'margin': '1.67em 0',
      };
    case 'h6':
      return const {
        'font-size': '0.67em',
        'font-weight': 'bold',
        'margin': '2.33em 0',
      };
    case 'blockquote' || 'figure':
      return const {'margin': '1em 40px'};
    case 'dd':
      return const {'margin': '0 0 1em 40px'};
    case 'dt':
      return const {'font-weight': 'bold'};
    case 'address':
      return const {'font-style': 'italic'};
    case 'center':
      return const {'text-align': 'center'};
    case 'hr':
      return const {'margin': '0.5em 0'};
    case 'ul' || 'ol':
      return {'padding-left': '40px', if (listDepth == 0) 'margin': '1em 0'};
    case 'b' || 'strong' || 'th':
      return const {'font-weight': 'bold'};
    case 'i' || 'em' || 'cite' || 'dfn' || 'var':
      return const {'font-style': 'italic'};
    case 'u' || 'ins':
      return const {'text-decoration': 'underline'};
    case 's' || 'strike' || 'del':
      return const {'text-decoration': 'line-through'};
    case 'abbr' || 'acronym':
      return const {'text-decoration': 'underline dotted'};
    case 'big':
      return const {'font-size': 'larger'};
    case 'small':
      return const {'font-size': 'smaller'};
    case 'sup':
      return const {'vertical-align': 'super', 'font-size': 'smaller'};
    case 'sub':
      return const {'vertical-align': 'sub', 'font-size': 'smaller'};
    case 'code' || 'kbd' || 'samp' || 'tt':
      return const {'font-family': 'Courier, monospace'};
    case 'pre':
      return const {'font-family': 'Courier, monospace', 'white-space': 'pre'};
    case 'mark':
      return const {'background-color': '#ff0', 'color': '#000'};
    case 'a':
      return attrs.containsKey('href')
          ? const {'text-decoration': 'underline'}
          : const {};
    case 'font':
      const sizes = {
        '1': 'xx-small',
        '2': 'x-small',
        '3': 'small',
        '4': 'medium',
        '5': 'large',
        '6': 'x-large',
        '7': 'xx-large',
      };
      final size = sizes[attrs['size'] ?? ''];
      return {
        if (attrs['color'] != null) 'color': attrs['color']!,
        if (attrs['face'] != null) 'font-family': attrs['face']!,
        if (size != null) 'font-size': size,
      };
  }
  return const {};
}

class _HtmlBuilder {
  final Color linkColor;
  final double textScaleFactor;
  final TextStyle rootStyle;
  final HtmlCustomWidgetBuilder? customWidgetBuilder;
  final void Function(String url)? onTapUrl;
  final List<GestureRecognizer> recognizers;
  final SelectionRegistrar? selectionRegistrar;
  final Color selectionColor;

  _HtmlBuilder({
    required this.linkColor,
    required this.textScaleFactor,
    required this.rootStyle,
    required this.customWidgetBuilder,
    required this.onTapUrl,
    required this.recognizers,
    required this.selectionRegistrar,
    required this.selectionColor,
  });

  var _listDepth = 0;

  /// The CSS that applies to [element]: defaults, presentational attributes,
  /// then its `style` attribute.
  Map<String, String> _cssOf(HtmlElement element) {
    final css = <String, String>{..._defaultStyles(element, _listDepth)};
    final align = element.attributes['align'];
    if (align != null) css['text-align'] = align.toLowerCase();
    css.addAll(parseCssDeclarations(element.attributes['style']));
    return css;
  }

  /// [props] with [css]'s inherited properties applied.
  _Props _inherit(_Props props, Map<String, String> css, HtmlElement element) {
    var style = props.style;
    var align = props.align;
    var whiteSpace = props.whiteSpace;
    String? href;
    final parentSize = props.fontSize;

    final fontSize = css['font-size'];
    if (fontSize != null) {
      final size = _fontSize(fontSize, parentSize, props.rootFontSize);
      if (size != null) style = style.copyWith(fontSize: size);
    }
    final color = css['color'];
    if (color != null) {
      final c = parseCssColor(color);
      if (c != null) style = style.copyWith(color: c);
    }
    final family = css['font-family'];
    if (family != null) {
      final families = family
          .split(',')
          .map((f) => f.trim().replaceAll(RegExp('^["\']|["\']\$'), ''))
          .where((f) => f.isNotEmpty)
          .toList();
      style = style.copyWith(
        fontFamily: families.isEmpty ? null : families.first,
        fontFamilyFallback: families.skip(1).toList(),
      );
    }
    final fontStyle = css['font-style'];
    if (fontStyle != null) {
      switch (fontStyle.toLowerCase()) {
        case 'italic' || 'oblique':
          style = style.copyWith(fontStyle: FontStyle.italic);
        case 'normal':
          style = style.copyWith(fontStyle: FontStyle.normal);
      }
    }
    final weight = css['font-weight'];
    if (weight != null) {
      final w = _fontWeight(weight);
      if (w != null) style = style.copyWith(fontWeight: w);
    }
    final lineHeight = css['line-height'];
    if (lineHeight != null) {
      final height = _lineHeight(lineHeight, props.normalHeight, style);
      if (height != null) style = style.copyWith(height: height.$1);
    }
    final decoration = css['text-decoration-line'] ?? css['text-decoration'];
    if (decoration != null) {
      style = _decorate(style, decoration);
    }
    final background = css['background-color'] ?? css['background'];
    if (background != null && !_isBlock(element, css)) {
      final c = parseCssColor(background.split(RegExp(r'\s+')).first);
      if (c != null) style = style.copyWith(backgroundColor: c);
    }
    final textAlign = css['text-align'];
    if (textAlign != null) {
      align = switch (textAlign.toLowerCase()) {
        'center' || '-webkit-center' => TextAlign.center,
        'right' => TextAlign.right,
        'left' => TextAlign.left,
        'justify' => TextAlign.justify,
        'end' => TextAlign.end,
        'start' => TextAlign.start,
        _ => align,
      };
    }
    switch (css['white-space']?.toLowerCase()) {
      case 'pre' || 'pre-wrap' || 'pre-line' || 'break-spaces':
        whiteSpace = _WhiteSpace.pre;
      case 'nowrap':
        whiteSpace = _WhiteSpace.nowrap;
      case 'normal':
        whiteSpace = _WhiteSpace.normal;
    }
    if (element.name == 'a' && element.attributes.containsKey('href')) {
      href = element.attributes['href'];
      if (css['color'] == null) style = style.copyWith(color: linkColor);
    }
    return props.copyWith(
      style: style,
      align: align,
      whiteSpace: whiteSpace,
      href: href,
    );
  }

  double? _fontSize(String value, double parent, double root) {
    switch (value.trim().toLowerCase()) {
      case 'xxx-large':
        return root * 3;
      case 'xx-large':
        return root * 2;
      case 'x-large':
        return root * 1.5;
      case 'large':
        return root * 1.125;
      case 'medium':
        return root;
      case 'small':
        return root * .8125;
      case 'x-small':
        return root * .625;
      case 'xx-small':
        return root * .5625;
      case 'larger':
        return parent * 1.2;
      case 'smaller':
        return parent * 15 / 18;
    }
    final v = value.trim().toLowerCase();
    final px = parseCssLength(v, fontSize: parent, percentBase: parent);
    if (px == null) return null;
    // Absolute lengths follow the text scale factor; relative ones already
    // do through their base.
    return v.endsWith('px') || v.endsWith('pt') ? px * textScaleFactor : px;
  }

  FontWeight? _fontWeight(String value) {
    switch (value.trim().toLowerCase()) {
      case 'bold' || 'bolder':
        return FontWeight.bold;
      case 'normal':
        return FontWeight.normal;
      case 'lighter':
        return FontWeight.w300;
    }
    final n = int.tryParse(value.trim());
    if (n == null) return null;
    return FontWeight.values[((n / 100).round() - 1).clamp(0, 8)];
  }

  (double?,)? _lineHeight(String value, double? normal, TextStyle style) {
    final v = value.trim().toLowerCase();
    if (v == 'normal') return (normal,);
    final number = double.tryParse(v);
    if (number != null) return number > 0 ? (number,) : null;
    final fontSize = style.fontSize ?? 14;
    if (v.endsWith('%')) {
      final p = double.tryParse(v.substring(0, v.length - 1));
      return p == null ? null : (p / 100,);
    }
    final px = parseCssLength(v, fontSize: fontSize);
    return px == null ? null : (px / fontSize,);
  }

  TextStyle _decorate(TextStyle style, String value) {
    final parts = value.toLowerCase().split(RegExp(r'\s+'));
    if (parts.contains('none')) {
      return style.copyWith(decoration: TextDecoration.none);
    }
    final lines = <TextDecoration>[
      if (style.decoration != null) style.decoration!,
      if (parts.contains('underline')) TextDecoration.underline,
      if (parts.contains('line-through')) TextDecoration.lineThrough,
      if (parts.contains('overline')) TextDecoration.overline,
    ];
    if (lines.isEmpty) return style;
    return style.copyWith(
      decoration: TextDecoration.combine(lines),
      decorationStyle: parts.contains('dotted')
          ? TextDecorationStyle.dotted
          : parts.contains('dashed')
          ? TextDecorationStyle.dashed
          : parts.contains('double')
          ? TextDecorationStyle.double
          : parts.contains('wavy')
          ? TextDecorationStyle.wavy
          : style.decorationStyle,
    );
  }

  bool _isBlock(HtmlElement element, Map<String, String> css) {
    final display = css['display']?.toLowerCase();
    if (display != null) {
      return display == 'block' ||
          display == 'flex' ||
          display == 'list-item' ||
          display == 'table';
    }
    return _blockElements.contains(element.name);
  }

  // -------------------------------------------------------------------------
  // Blocks

  /// The block-level content of [nodes].
  List<_Item> blockContent(List<HtmlNode> nodes, _Props props) {
    final context = _BlockContext(this, props);
    for (final node in nodes) {
      context.visit(node, props);
    }
    context.flush();
    return context.items;
  }

  /// [element] laid out as a block: its margins, then the box.
  List<_Item> block(HtmlElement element, Map<String, String> css, _Props p) {
    final props = _inherit(p, css, element);
    final fontSize = props.fontSize;

    double length(String? value, {double? percentBase}) => value == null
        ? 0
        : parseCssLength(value, fontSize: fontSize, percentBase: percentBase) ??
              0;
    final margin = _box(css, 'margin');
    final padding = _box(css, 'padding');

    List<_Item> content;
    if (element.name == 'hr') {
      content = [
        _Block(
          SizedBox(
            width: double.infinity,
            height: 1,
            child: ColoredBox(
              color: props.style.color ?? const Color(0xFF000000),
            ),
          ),
        ),
      ];
    } else if (element.name == 'ul' || element.name == 'ol') {
      _listDepth++;
      try {
        content = _list(element, props);
      } finally {
        _listDepth--;
      }
    } else {
      content = blockContent(element.children, props);
    }

    final pad = EdgeInsets.fromLTRB(
      math.max(0, length(padding.$4)),
      math.max(0, length(padding.$1)),
      math.max(0, length(padding.$2)),
      math.max(0, length(padding.$3)),
    );

    // Margins of the first and last child collapse through this box, unless
    // it has padding (which includes the indent of a list).
    final leading = <_Item>[];
    final trailing = <_Item>[];
    if (pad == EdgeInsets.zero) {
      while (content.isNotEmpty && content.first is _Gap) {
        leading.add(content.removeAt(0));
      }
      while (content.isNotEmpty && content.last is _Gap) {
        trailing.insert(0, content.removeLast());
      }
    }

    Widget? box = content.any((item) => item is _Block)
        ? _column(content, props.align)
        : null;
    if (box != null) {
      final background = css['background-color'] ?? css['background'];
      final backgroundColor = background == null
          ? null
          : parseCssColor(background.split(RegExp(r'\s+')).first);
      if (pad != EdgeInsets.zero) box = Padding(padding: pad, child: box);
      box = _CssBlock(child: box);
      if (backgroundColor != null) {
        box = ColoredBox(color: backgroundColor, child: box);
      }
      final ml = math.max(0.0, length(margin.$4));
      final mr = math.max(0.0, length(margin.$2));
      if (ml > 0 || mr > 0) {
        box = Padding(
          padding: EdgeInsets.only(left: ml, right: mr),
          child: box,
        );
      }
    }
    final mt = length(margin.$1);
    final mb = length(margin.$3);
    return [
      if (mt > 0) _Gap(mt),
      ...leading,
      if (box != null) _Block(box),
      ...trailing,
      if (mb > 0) _Gap(mb),
    ];
  }

  /// `margin` / `padding` shorthand and longhands as (top, right, bottom,
  /// left).
  (String?, String?, String?, String?) _box(
    Map<String, String> css,
    String property,
  ) {
    String? top, right, bottom, left;
    final shorthand = css[property];
    if (shorthand != null) {
      final v = shorthand.trim().split(RegExp(r'\s+'));
      switch (v.length) {
        case 1:
          top = right = bottom = left = v[0];
        case 2:
          top = bottom = v[0];
          right = left = v[1];
        case 3:
          top = v[0];
          right = left = v[1];
          bottom = v[2];
        default:
          top = v[0];
          right = v[1];
          bottom = v[2];
          left = v[3];
      }
    }
    // Longhands override the shorthand regardless of order, which is what
    // the stylesheet defaults rely on.
    top = css['$property-top'] ?? css['$property-block-start'] ?? top;
    bottom = css['$property-bottom'] ?? css['$property-block-end'] ?? bottom;
    left = css['$property-left'] ?? css['$property-inline-start'] ?? left;
    right = css['$property-right'] ?? css['$property-inline-end'] ?? right;
    return (top, right, bottom, left);
  }

  List<_Item> _list(HtmlElement list, _Props props) {
    final ordered = list.name == 'ol';
    final reversed = list.attributes.containsKey('reversed');
    final start = int.tryParse(list.attributes['start'] ?? '');
    final listCss = _cssOf(list);
    final listType =
        listCss['list-style-type'] ??
        (ordered
            ? _typeFromAttribute(list.attributes['type']) ?? 'decimal'
            : switch (_listDepth - 1) {
                0 => 'disc',
                1 => 'circle',
                _ => 'square',
              });
    final itemCount = list.children
        .whereType<HtmlElement>()
        .where((e) => e.name == 'li')
        .length;

    final items = <_Item>[];
    final loose = <HtmlNode>[];
    void flushLoose() {
      if (loose.isEmpty) return;
      items.addAll(blockContent(List.of(loose), props));
      loose.clear();
    }

    var index = 0;
    for (final child in list.children) {
      if (child is! HtmlElement || child.name != 'li') {
        loose.add(child);
        continue;
      }
      flushLoose();
      final itemCss = _cssOf(child);
      if (itemCss['display'] == 'none') continue;
      final number = reversed
          ? (start ?? itemCount) - index
          : (start ?? 1) + index;
      index++;
      final itemType =
          itemCss['list-style-type'] ??
          _typeFromAttribute(child.attributes['type']) ??
          listType;
      final itemItems = block(child, itemCss, props);
      final itemProps = _inherit(props, itemCss, child);
      final marker = _marker(itemType, number, itemProps);
      for (final item in itemItems) {
        if (item is _Block && marker != null) {
          items.add(
            _Block(
              HtmlListItem(
                marker: marker,
                textAlign: itemProps.align,
                textDirection: TextDirection.ltr,
                child: item.widget,
              ),
            ),
          );
        } else {
          items.add(item);
        }
      }
    }
    flushLoose();
    return items;
  }

  String? _typeFromAttribute(String? type) => switch (type) {
    'a' => 'lower-alpha',
    'A' => 'upper-alpha',
    '1' => 'decimal',
    'i' => 'lower-roman',
    'I' => 'upper-roman',
    _ => null,
  };

  Widget? _marker(String type, int number, _Props props) {
    final style = props.style;
    switch (type) {
      case 'none':
        return null;
      case 'disc':
        return HtmlListMarker.disc(style);
      case 'circle':
        return HtmlListMarker.circle(style);
      case 'square':
        return HtmlListMarker.square(style);
    }
    final text = switch (type) {
      'lower-alpha' || 'lower-latin' => '${_alpha(number)}.',
      'upper-alpha' || 'upper-latin' => '${_alpha(number).toUpperCase()}.',
      'lower-roman' => '${_roman(number)}.',
      'upper-roman' => '${_roman(number).toUpperCase()}.',
      'bengali' => '${_bengali(number)}.',
      'decimal-leading-zero' => '${number.toString().padLeft(2, '0')}.',
      _ => '$number.',
    };
    return RichText(
      maxLines: 1,
      softWrap: false,
      text: TextSpan(style: style, text: text),
    );
  }

  static String _alpha(int n) {
    if (n < 1) return '$n';
    var out = '';
    while (n > 0) {
      n--;
      out = String.fromCharCode(0x61 + n % 26) + out;
      n ~/= 26;
    }
    return out;
  }

  static String _roman(int n) {
    if (n < 1 || n > 3999) return '$n';
    const values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
    const symbols = [
      'm', 'cm', 'd', 'cd', 'c', 'xc', 'l', 'xl', 'x', 'ix', 'v', 'iv', 'i', //
    ];
    final out = StringBuffer();
    for (var i = 0; i < values.length; i++) {
      while (n >= values[i]) {
        out.write(symbols[i]);
        n -= values[i];
      }
    }
    return out.toString();
  }

  static String _bengali(int n) => n
      .toString()
      .split('')
      .map((d) => String.fromCharCode(0x09E6 + int.parse(d)))
      .join();

  // -------------------------------------------------------------------------
  // Inline runs

  GestureRecognizer? _recognizer(String? href) {
    if (href == null || onTapUrl == null) return null;
    final recognizer = TapGestureRecognizer()..onTap = () => onTapUrl!(href);
    recognizers.add(recognizer);
    return recognizer;
  }

  /// [pieces] as one [RichText], or null when they hold nothing visible.
  Widget? text(List<_Piece> pieces, _Props props) {
    final span = _span(pieces, props.style);
    if (span == null) return null;
    return RichText(
      text: span,
      textAlign: props.align ?? TextAlign.start,
      softWrap: props.whiteSpace != _WhiteSpace.nowrap,
      selectionRegistrar: selectionRegistrar,
      selectionColor: selectionRegistrar == null ? null : selectionColor,
    );
  }

  /// Collapses white space as CSS does and joins [pieces] into a span:
  /// runs of spaces become one, spaces at the start and end of the run and
  /// around line breaks go, and neighbouring text of the same style merges.
  InlineSpan? _span(List<_Piece> pieces, TextStyle style) {
    final out = <InlineSpan>[];
    var afterSpace = true;
    _TextPiece? pending; // the last text piece, for merging and trimming

    void trimTrailingSpace() {
      final last = pending;
      if (last != null && !last.preserveSpace && last.text.endsWith(' ')) {
        last.text = last.text.substring(0, last.text.length - 1);
      }
    }

    void emitPending() {
      final last = pending;
      if (last != null && last.text.isNotEmpty) {
        out.add(
          TextSpan(
            text: last.text,
            style: last.style,
            recognizer: last.recognizer,
          ),
        );
      }
      pending = null;
    }

    for (final piece in pieces) {
      switch (piece) {
        case _TextPiece():
          var text = piece.text;
          if (!piece.preserveSpace) {
            text = text.replaceAll(_collapsibleSpace, ' ');
            if (afterSpace && text.startsWith(' ')) text = text.substring(1);
          }
          if (text.isEmpty) continue;
          afterSpace = text.endsWith(' ') || text.endsWith('\n');
          final last = pending;
          if (last != null &&
              last.style == piece.style &&
              last.recognizer == piece.recognizer &&
              last.preserveSpace == piece.preserveSpace) {
            last.text += text;
          } else {
            emitPending();
            pending = _TextPiece(
              text,
              piece.style,
              piece.recognizer,
              piece.preserveSpace,
            );
          }
        case _BreakPiece():
          trimTrailingSpace();
          final last = pending;
          if (last != null && last.style == piece.style) {
            last.text += '\n';
          } else {
            emitPending();
            pending = _TextPiece('\n', piece.style, null, false);
          }
          afterSpace = true;
        case _WidgetPiece(:final span):
          emitPending();
          out.add(span);
          afterSpace = false;
      }
    }
    trimTrailingSpace();
    // The run's last line break ends the line rather than starting another
    // (white-space: pre keeps it).
    final last = pending;
    var droppedBreak = false;
    if (last != null && !last.preserveSpace && last.text.endsWith('\n')) {
      last.text = last.text.substring(0, last.text.length - 1);
      droppedBreak = true;
    }
    emitPending();
    if (out.isEmpty) {
      // A run that is nothing but one <br> (`<p><br></p>`) still takes 1em.
      if (droppedBreak && pieces.whereType<_BreakPiece>().length == 1) {
        // As the root span: no text, so no line height around it.
        return WidgetSpan(child: SizedBox(height: style.fontSize ?? 14));
      }
      return null;
    }
    if (out.length == 1 && out.single is TextSpan) {
      final only = out.single as TextSpan;
      final text = only.text!;
      if (text.trim().isEmpty &&
          !text.contains('\u00A0') &&
          !text.contains('\n')) {
        return null; // only collapsible white space
      }
      return only;
    }
    return TextSpan(style: style, children: out);
  }
}

/// Collects the items of one block's content: inline runs between the
/// block-level children.
class _BlockContext {
  final _HtmlBuilder builder;
  final _Props props;
  final items = <_Item>[];
  final _pieces = <_Piece>[];

  _BlockContext(this.builder, this.props);

  void flush() {
    if (_pieces.isEmpty) return;
    final widget = builder.text(_pieces, props);
    _pieces.clear();
    if (widget != null) items.add(_Block(widget));
  }

  void visit(HtmlNode node, _Props props) {
    switch (node) {
      case HtmlText(:final text):
        _pieces.add(
          _TextPiece(
            text,
            props.style,
            builder._recognizer(props.href),
            props.whiteSpace == _WhiteSpace.pre,
          ),
        );
      case HtmlElement():
        _element(node, props);
    }
  }

  void _element(HtmlElement element, _Props props) {
    if (_hiddenElements.contains(element.name)) return;
    final custom = builder.customWidgetBuilder?.call(element);
    if (custom != null) {
      flush();
      items.add(_Block(custom));
      return;
    }
    final css = builder._cssOf(element);
    if (css['display']?.toLowerCase() == 'none') return;

    if (element.name == 'br') {
      _pieces.add(_BreakPiece(props.style));
      return;
    }
    if (element.name == 'img') {
      final image = _image(element, props);
      if (image != null) {
        flush();
        items.add(_Block(image));
      }
      return;
    }
    if (builder._isBlock(element, css)) {
      flush();
      items.addAll(builder.block(element, css, props));
      return;
    }

    final inner = builder._inherit(props, css, element);
    final verticalAlign = css['vertical-align']?.toLowerCase();
    if (verticalAlign == 'super' || verticalAlign == 'sub') {
      _script(element, inner, superscript: verticalAlign == 'super');
      return;
    }
    if (element.name == 'q') {
      _pieces.add(_TextPiece('“', inner.style, null, false));
    }
    for (final child in element.children) {
      visit(child, inner);
    }
    if (element.name == 'q') {
      _pieces.add(_TextPiece('”', inner.style, null, false));
    }
  }

  /// `<sup>` / `<sub>`: the content raised (or lowered) by 0.4 of its own
  /// font size in a widget span.
  void _script(HtmlElement element, _Props props, {required bool superscript}) {
    final context = _BlockContext(builder, props.copyWith());
    for (final child in element.children) {
      context.visit(child, props);
    }
    final span = builder._span(context._pieces, props.style);
    if (span == null) return;
    final shift = props.fontSize * .4;
    _pieces.add(
      _WidgetPiece(
        WidgetSpan(
          alignment: superscript
              ? PlaceholderAlignment.bottom
              : PlaceholderAlignment.top,
          child: Align(
            alignment: superscript
                ? Alignment.topCenter
                : Alignment.bottomCenter,
            widthFactor: 1,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: superscript ? shift : 0,
                top: superscript ? 0 : shift,
              ),
              child: RichText(text: span),
            ),
          ),
        ),
      ),
    );
  }

  Widget? _image(HtmlElement element, _Props props) {
    final src = element.attributes['src'];
    if (src == null || src.isEmpty) return null;
    final alt = element.attributes['alt'];
    Widget fallback(BuildContext context, Object error, StackTrace? stack) =>
        alt == null ? const SizedBox.shrink() : Text(alt, style: props.style);
    if (src.startsWith('data:image/') && src.contains('base64,')) {
      try {
        return Image.memory(
          base64Decode(src.substring(src.indexOf('base64,') + 7)),
          errorBuilder: fallback,
        );
      } on FormatException {
        return null;
      }
    }
    return Image.network(src, errorBuilder: fallback);
  }
}

/// A `display: block` box: as wide as its parent allows (flutter_widget
/// _from_html's CssBlock).
class _CssBlock extends SingleChildRenderObjectWidget {
  const _CssBlock({super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderCssBlock();
}

class _RenderCssBlock extends RenderProxyBox {
  BoxConstraints _childConstraints(BoxConstraints constraints) =>
      constraints.hasBoundedWidth
      ? constraints.tighten(width: constraints.maxWidth)
      : constraints;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_childConstraints(constraints), parentUsesSize: true);
    size = constraints.constrain(child.size);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    return constraints.constrain(
      child.getDryLayout(_childConstraints(constraints)),
    );
  }

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) => child?.getDryBaseline(_childConstraints(constraints), baseline);
}
