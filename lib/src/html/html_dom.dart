import 'html_unescape.dart';

/// A node of the small HTML tree [parseHtmlFragment] builds.
sealed class HtmlNode {
  const HtmlNode();
}

/// Character data, with character references already decoded.
final class HtmlText extends HtmlNode {
  final String text;
  const HtmlText(this.text);

  @override
  String toString() =>
      'HtmlText(${text.length > 40 ? text.substring(0, 40) : text})';
}

/// An element. [name] is lower case (`o:p` keeps its prefix); attribute
/// names are lower case and their values decoded.
final class HtmlElement extends HtmlNode {
  final String name;
  final Map<String, String> attributes;
  final List<HtmlNode> children = [];

  HtmlElement(this.name, [Map<String, String>? attributes])
    : attributes = attributes ?? {};

  /// Concatenated text of this element and its descendants.
  String get text {
    final out = StringBuffer();
    void walk(HtmlNode node) {
      switch (node) {
        case HtmlText(:final text):
          out.write(text);
        case HtmlElement(:final children):
          children.forEach(walk);
      }
    }

    walk(this);
    return out.toString();
  }

  @override
  String toString() => '<$name ${attributes.isEmpty ? '' : attributes}>';
}

/// Elements that never have content or an end tag.
const _voidElements = {
  'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', //
  'meta', 'param', 'source', 'track', 'wbr',
};

/// Elements whose content is raw text up to their end tag.
const _rawTextElements = {'script', 'style', 'title', 'textarea', 'xmp'};

/// Elements whose start tag closes an open `<p>`, as in the HTML spec.
const _closesParagraph = {
  'address', 'article', 'aside', 'blockquote', 'center', 'details', //
  'dialog', 'dir', 'div', 'dl', 'fieldset', 'figcaption', 'figure', 'footer',
  'form', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'hgroup', 'hr',
  'main', 'menu', 'nav', 'ol', 'p', 'pre', 'section', 'summary', 'table',
  'ul',
};

/// For an element that closes a still-open element of the same family when
/// it starts (`<li>…<li>`): the elements it closes, and the elements that
/// bound the search (a nested list must not close its parent's `<li>`).
const _impliedEnd = <String, (Set<String>, Set<String>)>{
  'li': ({'li'}, {'ul', 'ol', 'menu'}),
  'dt': ({'dt', 'dd'}, {'dl'}),
  'dd': ({'dt', 'dd'}, {'dl'}),
  'tr': ({'tr', 'td', 'th'}, {'table', 'thead', 'tbody', 'tfoot'}),
  'td': ({'td', 'th'}, {'tr', 'table'}),
  'th': ({'td', 'th'}, {'tr', 'table'}),
  'thead': ({'thead', 'tbody', 'tfoot', 'tr', 'td', 'th'}, {'table'}),
  'tbody': ({'thead', 'tbody', 'tfoot', 'tr', 'td', 'th'}, {'table'}),
  'tfoot': ({'thead', 'tbody', 'tfoot', 'tr', 'td', 'th'}, {'table'}),
  'option': ({'option'}, {'select', 'datalist'}),
};

/// Parses an HTML fragment into a tree rooted at a synthetic `body` element.
///
/// A tolerant subset of the HTML5 tree builder, sized for rich-text editor
/// and MS Office output: missing end tags are implied (`<p>`, `<li>`, table
/// parts), stray end tags are ignored, void elements need no end tag,
/// attributes may be unquoted or valueless, comments (including Office's
/// conditional comments) and `<script>`/`<style>` content are dropped.
HtmlElement parseHtmlFragment(String html) {
  final root = HtmlElement('body');
  final stack = <HtmlElement>[root];
  HtmlElement current() => stack.last;

  void popTo(int index) => stack.removeRange(index, stack.length);

  int openIndex(String name, {Set<String> boundary = const {}}) {
    for (var i = stack.length - 1; i > 0; i--) {
      final open = stack[i].name;
      if (open == name) return i;
      if (boundary.contains(open)) return -1;
    }
    return -1;
  }

  void addText(String text) {
    if (text.isEmpty) return;
    final children = current().children;
    if (children.isNotEmpty && children.last is HtmlText) {
      // Keep text contiguous: separate runs would shape separately, which
      // splits Bengali conjuncts.
      children[children.length - 1] = HtmlText(
        (children.last as HtmlText).text + text,
      );
    } else {
      children.add(HtmlText(text));
    }
  }

  var i = 0;
  final length = html.length;
  while (i < length) {
    final lt = html.indexOf('<', i);
    if (lt < 0) {
      addText(decodeHtmlEntities(html.substring(i)));
      break;
    }
    if (lt > i) addText(decodeHtmlEntities(html.substring(i, lt)));
    i = lt;

    // Comments, including <!--[if …]> … <![endif]--> blocks.
    if (html.startsWith('<!--', i)) {
      final end = html.indexOf('-->', i + 4);
      i = end < 0 ? length : end + 3;
      continue;
    }
    // <!DOCTYPE>, <![CDATA[ ]]>, <![endif]>, <?xml ?> and other markup
    // declarations carry nothing to render.
    if (html.startsWith('<!', i) || html.startsWith('<?', i)) {
      final end = html.indexOf('>', i + 2);
      i = end < 0 ? length : end + 1;
      continue;
    }

    final tag = _readTag(html, i);
    if (tag == null) {
      // A `<` that starts no tag (`a < b`) is text.
      addText('<');
      i++;
      continue;
    }
    i = tag.end;

    if (tag.isEnd) {
      final index = openIndex(tag.name);
      if (index > 0) popTo(index);
      // A stray end tag with nothing to close is ignored, except </br>,
      // which browsers treat as <br>.
      if (index < 0 && tag.name == 'br') {
        current().children.add(HtmlElement('br'));
      }
      continue;
    }

    final name = tag.name;
    if (_closesParagraph.contains(name)) {
      final p = openIndex('p', boundary: const {'td', 'th', 'li', 'table'});
      if (p > 0) popTo(p);
    }
    final implied = _impliedEnd[name];
    if (implied != null) {
      for (var j = stack.length - 1; j > 0; j--) {
        final open = stack[j].name;
        if (implied.$2.contains(open)) break;
        if (implied.$1.contains(open)) {
          popTo(j);
          break;
        }
      }
    }

    final element = HtmlElement(name, tag.attributes);
    current().children.add(element);

    if (_rawTextElements.contains(name)) {
      final close = html.toLowerCase().indexOf('</$name', i);
      final content = html.substring(i, close < 0 ? length : close);
      if (name == 'textarea' || name == 'title' || name == 'xmp') {
        element.children.add(HtmlText(decodeHtmlEntities(content)));
      }
      if (close < 0) break;
      final gt = html.indexOf('>', close);
      i = gt < 0 ? length : gt + 1;
      continue;
    }
    if (!_voidElements.contains(name) && !tag.selfClosing) {
      stack.add(element);
    }
  }
  return root;
}

class _Tag {
  final String name;
  final bool isEnd;
  final bool selfClosing;
  final Map<String, String> attributes;
  final int end;

  const _Tag(
    this.name,
    this.isEnd,
    this.selfClosing,
    this.attributes,
    this.end,
  );
}

bool _isNameChar(int c) =>
    (c >= 0x61 && c <= 0x7A) || // a-z
    (c >= 0x41 && c <= 0x5A) || // A-Z
    (c >= 0x30 && c <= 0x39) || // 0-9
    c == 0x2D || // -
    c == 0x5F || // _
    c == 0x3A || // : (o:p, m:oMath)
    c == 0x2E; // .

bool _isSpace(int c) =>
    c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D;

/// Reads the tag starting at [start] (which holds `<`), or null when the
/// text there does not form a tag.
_Tag? _readTag(String html, int start) {
  var i = start + 1;
  final isEnd = i < html.length && html.codeUnitAt(i) == 0x2F; // /
  if (isEnd) i++;
  final nameStart = i;
  if (i >= html.length) return null;
  final first = html.codeUnitAt(i);
  final isLetter =
      (first >= 0x61 && first <= 0x7A) || (first >= 0x41 && first <= 0x5A);
  if (!isLetter) return null;
  while (i < html.length && _isNameChar(html.codeUnitAt(i))) {
    i++;
  }
  final name = html.substring(nameStart, i).toLowerCase();

  final attributes = <String, String>{};
  var selfClosing = false;
  while (i < html.length) {
    while (i < html.length && _isSpace(html.codeUnitAt(i))) {
      i++;
    }
    if (i >= html.length) return null; // unterminated tag
    final c = html.codeUnitAt(i);
    if (c == 0x3E) {
      // >
      i++;
      break;
    }
    if (c == 0x2F) {
      // /
      selfClosing = true;
      i++;
      continue;
    }
    // Attribute name.
    final attrStart = i;
    while (i < html.length) {
      final d = html.codeUnitAt(i);
      if (_isSpace(d) || d == 0x3D || d == 0x3E || d == 0x2F) break;
      i++;
    }
    final attrName = html.substring(attrStart, i).toLowerCase();
    if (attrName.isEmpty) {
      i++; // skip a stray character such as a lone quote
      continue;
    }
    while (i < html.length && _isSpace(html.codeUnitAt(i))) {
      i++;
    }
    var value = '';
    if (i < html.length && html.codeUnitAt(i) == 0x3D) {
      // =
      i++;
      while (i < html.length && _isSpace(html.codeUnitAt(i))) {
        i++;
      }
      if (i < html.length &&
          (html.codeUnitAt(i) == 0x22 || html.codeUnitAt(i) == 0x27)) {
        final quote = html[i];
        final close = html.indexOf(quote, i + 1);
        if (close < 0) return null;
        value = html.substring(i + 1, close);
        i = close + 1;
      } else {
        final valueStart = i;
        while (i < html.length &&
            !_isSpace(html.codeUnitAt(i)) &&
            html.codeUnitAt(i) != 0x3E) {
          i++;
        }
        value = html.substring(valueStart, i);
      }
    }
    attributes.putIfAbsent(attrName, () => decodeHtmlEntities(value));
  }
  return _Tag(name, isEnd, selfClosing, attributes, i);
}
