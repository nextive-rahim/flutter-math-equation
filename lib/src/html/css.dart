import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Inline CSS (`style="…"`) as property → value, properties lower case and
/// `!important` dropped. Later declarations win.
Map<String, String> parseCssDeclarations(String? style) {
  final result = <String, String>{};
  if (style == null || style.isEmpty) return result;
  for (final declaration in style.split(';')) {
    final colon = declaration.indexOf(':');
    if (colon <= 0) continue;
    final property = declaration.substring(0, colon).trim().toLowerCase();
    var value = declaration.substring(colon + 1).trim();
    value = value.replaceFirst(
      RegExp(r'\s*!important\s*$', caseSensitive: false),
      '',
    );
    if (property.isEmpty || value.isEmpty) continue;
    result[property] = value;
  }
  return result;
}

/// A CSS colour: `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, `rgb()`/`rgba()`,
/// `hsl()`/`hsla()`, `transparent` and the named colours. `currentcolor`
/// and anything unknown give null.
Color? parseCssColor(String value) {
  final v = value.trim().toLowerCase();
  if (v.startsWith('#')) {
    final hex = v.substring(1);
    if (!RegExp(r'^[0-9a-f]+$').hasMatch(hex)) return null;
    String x2(String s) => s.split('').map((c) => '$c$c').join();
    switch (hex.length) {
      case 3:
        return Color(int.parse('FF${x2(hex)}', radix: 16));
      case 4:
        return Color(
          int.parse('${x2(hex[3])}${x2(hex.substring(0, 3))}', radix: 16),
        );
      case 6:
        return Color(int.parse('FF$hex', radix: 16));
      case 8:
        return Color(
          int.parse('${hex.substring(6)}${hex.substring(0, 6)}', radix: 16),
        );
    }
    return null;
  }
  final function = RegExp(r'^(rgba?|hsla?)\((.*)\)$').firstMatch(v);
  if (function != null) {
    final params = function[2]!
        .split(RegExp(r'[\s,/]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (params.length < 3) return null;
    double? alpha = 1;
    if (params.length >= 4) {
      final a = params[3];
      alpha = a.endsWith('%')
          ? double.tryParse(a.substring(0, a.length - 1))?.let((n) => n / 100)
          : double.tryParse(a);
      if (alpha == null) return null;
      alpha = alpha.clamp(0, 1).toDouble();
    }
    if (function[1]!.startsWith('rgb')) {
      int? channel(String p) {
        if (p.endsWith('%')) {
          final n = double.tryParse(p.substring(0, p.length - 1));
          return n == null ? null : (n * 2.55).ceil().clamp(0, 255);
        }
        return double.tryParse(p)?.ceil().clamp(0, 255);
      }

      final r = channel(params[0]);
      final g = channel(params[1]);
      final b = channel(params[2]);
      if (r == null || g == null || b == null) return null;
      return Color.fromARGB((alpha * 255).ceil(), r, g, b);
    }
    final h = _hue(params[0]);
    final s = _percent(params[1]);
    final l = _percent(params[2]);
    if (h == null || s == null || l == null) return null;
    return HSLColor.fromAHSL(alpha, h, s, l).toColor();
  }
  if (v == 'transparent') return const Color(0x00000000);
  final named = cssNamedColors[v];
  return named == null ? null : Color(named);
}

double? _percent(String p) {
  if (!p.endsWith('%')) return null;
  return double.tryParse(p.substring(0, p.length - 1))
      ?.let((n) => (n / 100).clamp(0, 1).toDouble());
}

double? _hue(String p) {
  final match = RegExp(r'^(-?[\d.]+)(deg|rad|grad|turn)?$').firstMatch(p);
  if (match == null) return null;
  var deg = double.tryParse(match[1]!);
  if (deg == null) return null;
  switch (match[2]) {
    case 'rad':
      deg = deg * 180 / math.pi;
    case 'grad':
      deg = deg * 0.9;
    case 'turn':
      deg = deg * 360;
  }
  while (deg! < 0) {
    deg += 360;
  }
  return deg % 360;
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// A CSS length resolved to logical pixels: `px`, `pt` (96/72 px), `em`
/// (of [fontSize]) and `%` (of [percentBase]); a bare 0 is 0. Null for
/// `auto` and anything unparsable.
double? parseCssLength(
  String value, {
  required double fontSize,
  double? percentBase,
}) {
  final match = RegExp(r'^(-?[\d.]+)\s*(px|pt|em|rem|%)?$')
      .firstMatch(value.trim().toLowerCase());
  if (match == null) return null;
  final number = double.tryParse(match[1]!);
  if (number == null) return null;
  switch (match[2]) {
    case 'px':
      return number;
    case 'pt':
      return number * 96 / 72;
    case 'em':
    case 'rem':
      return number * fontSize;
    case '%':
      return percentBase == null ? null : percentBase * number / 100;
    default:
      return number == 0 ? 0 : null;
  }
}

/// The CSS named colours (CSS Color Module Level 4).
const cssNamedColors = <String, int>{
  'aliceblue': 0xFFF0F8FF,
  'antiquewhite': 0xFFFAEBD7,
  'aqua': 0xFF00FFFF,
  'aquamarine': 0xFF7FFFD4,
  'azure': 0xFFF0FFFF,
  'beige': 0xFFF5F5DC,
  'bisque': 0xFFFFE4C4,
  'black': 0xFF000000,
  'blanchedalmond': 0xFFFFEBCD,
  'blue': 0xFF0000FF,
  'blueviolet': 0xFF8A2BE2,
  'brown': 0xFFA52A2A,
  'burlywood': 0xFFDEB887,
  'cadetblue': 0xFF5F9EA0,
  'chartreuse': 0xFF7FFF00,
  'chocolate': 0xFFD2691E,
  'coral': 0xFFFF7F50,
  'cornflowerblue': 0xFF6495ED,
  'cornsilk': 0xFFFFF8DC,
  'crimson': 0xFFDC143C,
  'cyan': 0xFF00FFFF,
  'darkblue': 0xFF00008B,
  'darkcyan': 0xFF008B8B,
  'darkgoldenrod': 0xFFB8860B,
  'darkgray': 0xFFA9A9A9,
  'darkgreen': 0xFF006400,
  'darkgrey': 0xFFA9A9A9,
  'darkkhaki': 0xFFBDB76B,
  'darkmagenta': 0xFF8B008B,
  'darkolivegreen': 0xFF556B2F,
  'darkorange': 0xFFFF8C00,
  'darkorchid': 0xFF9932CC,
  'darkred': 0xFF8B0000,
  'darksalmon': 0xFFE9967A,
  'darkseagreen': 0xFF8FBC8F,
  'darkslateblue': 0xFF483D8B,
  'darkslategray': 0xFF2F4F4F,
  'darkslategrey': 0xFF2F4F4F,
  'darkturquoise': 0xFF00CED1,
  'darkviolet': 0xFF9400D3,
  'deeppink': 0xFFFF1493,
  'deepskyblue': 0xFF00BFFF,
  'dimgray': 0xFF696969,
  'dimgrey': 0xFF696969,
  'dodgerblue': 0xFF1E90FF,
  'firebrick': 0xFFB22222,
  'floralwhite': 0xFFFFFAF0,
  'forestgreen': 0xFF228B22,
  'fuchsia': 0xFFFF00FF,
  'gainsboro': 0xFFDCDCDC,
  'ghostwhite': 0xFFF8F8FF,
  'gold': 0xFFFFD700,
  'goldenrod': 0xFFDAA520,
  'gray': 0xFF808080,
  'green': 0xFF008000,
  'greenyellow': 0xFFADFF2F,
  'grey': 0xFF808080,
  'honeydew': 0xFFF0FFF0,
  'hotpink': 0xFFFF69B4,
  'indianred': 0xFFCD5C5C,
  'indigo': 0xFF4B0082,
  'ivory': 0xFFFFFFF0,
  'khaki': 0xFFF0E68C,
  'lavender': 0xFFE6E6FA,
  'lavenderblush': 0xFFFFF0F5,
  'lawngreen': 0xFF7CFC00,
  'lemonchiffon': 0xFFFFFACD,
  'lightblue': 0xFFADD8E6,
  'lightcoral': 0xFFF08080,
  'lightcyan': 0xFFE0FFFF,
  'lightgoldenrodyellow': 0xFFFAFAD2,
  'lightgray': 0xFFD3D3D3,
  'lightgreen': 0xFF90EE90,
  'lightgrey': 0xFFD3D3D3,
  'lightpink': 0xFFFFB6C1,
  'lightsalmon': 0xFFFFA07A,
  'lightseagreen': 0xFF20B2AA,
  'lightskyblue': 0xFF87CEFA,
  'lightslategray': 0xFF778899,
  'lightslategrey': 0xFF778899,
  'lightsteelblue': 0xFFB0C4DE,
  'lightyellow': 0xFFFFFFE0,
  'lime': 0xFF00FF00,
  'limegreen': 0xFF32CD32,
  'linen': 0xFFFAF0E6,
  'magenta': 0xFFFF00FF,
  'maroon': 0xFF800000,
  'mediumaquamarine': 0xFF66CDAA,
  'mediumblue': 0xFF0000CD,
  'mediumorchid': 0xFFBA55D3,
  'mediumpurple': 0xFF9370DB,
  'mediumseagreen': 0xFF3CB371,
  'mediumslateblue': 0xFF7B68EE,
  'mediumspringgreen': 0xFF00FA9A,
  'mediumturquoise': 0xFF48D1CC,
  'mediumvioletred': 0xFFC71585,
  'midnightblue': 0xFF191970,
  'mintcream': 0xFFF5FFFA,
  'mistyrose': 0xFFFFE4E1,
  'moccasin': 0xFFFFE4B5,
  'navajowhite': 0xFFFFDEAD,
  'navy': 0xFF000080,
  'oldlace': 0xFFFDF5E6,
  'olive': 0xFF808000,
  'olivedrab': 0xFF6B8E23,
  'orange': 0xFFFFA500,
  'orangered': 0xFFFF4500,
  'orchid': 0xFFDA70D6,
  'palegoldenrod': 0xFFEEE8AA,
  'palegreen': 0xFF98FB98,
  'paleturquoise': 0xFFAFEEEE,
  'palevioletred': 0xFFDB7093,
  'papayawhip': 0xFFFFEFD5,
  'peachpuff': 0xFFFFDAB9,
  'peru': 0xFFCD853F,
  'pink': 0xFFFFC0CB,
  'plum': 0xFFDDA0DD,
  'powderblue': 0xFFB0E0E6,
  'purple': 0xFF800080,
  'red': 0xFFFF0000,
  'rosybrown': 0xFFBC8F8F,
  'royalblue': 0xFF4169E1,
  'saddlebrown': 0xFF8B4513,
  'salmon': 0xFFFA8072,
  'sandybrown': 0xFFF4A460,
  'seagreen': 0xFF2E8B57,
  'seashell': 0xFFFFF5EE,
  'sienna': 0xFFA0522D,
  'silver': 0xFFC0C0C0,
  'skyblue': 0xFF87CEEB,
  'slateblue': 0xFF6A5ACD,
  'slategray': 0xFF708090,
  'slategrey': 0xFF708090,
  'snow': 0xFFFFFAFA,
  'springgreen': 0xFF00FF7F,
  'steelblue': 0xFF4682B4,
  'tan': 0xFFD2B48C,
  'teal': 0xFF008080,
  'thistle': 0xFFD8BFD8,
  'tomato': 0xFFFF6347,
  'turquoise': 0xFF40E0D0,
  'violet': 0xFFEE82EE,
  'wheat': 0xFFF5DEB3,
  'white': 0xFFFFFFFF,
  'whitesmoke': 0xFFF5F5F5,
  'yellow': 0xFFFFFF00,
  'yellowgreen': 0xFF9ACD32,
};
