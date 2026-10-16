import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Draws a KaTeX SVG path (`d` attribute syntax, in [viewBox] units) into a
/// box of [viewPort] size, scaled the way an `<svg viewBox=…
/// preserveAspectRatio=…>` element would scale it.
///
/// Replaces the original `flutter_svg` round-trip (path → SVG string → parsed
/// picture) with a direct [CustomPaint], so the engine has no third-party
/// rendering dependency.
Widget svgWidgetFromPath(
  String path,
  Size viewPort,
  Rect viewBox,
  Color color, {
  Alignment align = Alignment.topLeft,
  BoxFit fit = BoxFit.fill,
}) {
  assert(fit == BoxFit.fill || fit == BoxFit.contain || fit == BoxFit.cover);
  return SizedBox(
    width: viewPort.width,
    height: viewPort.height,
    child: CustomPaint(
      size: viewPort,
      painter: _SvgPathPainter(
        path: parseSvgPathData(path),
        viewBox: viewBox,
        color: color,
        align: align,
        fit: fit,
      ),
    ),
  );
}

class _SvgPathPainter extends CustomPainter {
  final Path path;
  final Rect viewBox;
  final Color color;
  final Alignment align;
  final BoxFit fit;

  const _SvgPathPainter({
    required this.path,
    required this.viewBox,
    required this.color,
    required this.align,
    required this.fit,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (viewBox.width <= 0 || viewBox.height <= 0) return;
    var sx = size.width / viewBox.width;
    var sy = size.height / viewBox.height;
    var tx = 0.0, ty = 0.0;
    if (fit != BoxFit.fill) {
      // preserveAspectRatio: `meet` (contain) or `slice` (cover), placed by
      // [align] inside the viewport.
      final s = fit == BoxFit.contain ? math.min(sx, sy) : math.max(sx, sy);
      sx = sy = s;
      tx = (size.width - viewBox.width * s) * (align.x + 1) / 2;
      ty = (size.height - viewBox.height * s) * (align.y + 1) / 2;
    }
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..translate(tx - viewBox.left * sx, ty - viewBox.top * sy)
      ..scale(sx, sy)
      ..drawPath(path, Paint()..color = color)
      ..restore();
  }

  @override
  bool shouldRepaint(_SvgPathPainter old) =>
      old.path != path ||
      old.viewBox != viewBox ||
      old.color != color ||
      old.align != align ||
      old.fit != fit;
}

final Map<String, Path> _pathCache = <String, Path>{};

/// Parses SVG path data (`M`, `L`, `H`, `V`, `C`, `S`, `Q`, `T`, `A`, `Z` and
/// their relative forms) into a [Path]. Results are cached: KaTeX reuses a
/// small set of glyph paths for every delimiter and radical.
Path parseSvgPathData(String data) {
  final cached = _pathCache[data];
  if (cached != null) return cached;
  final path = _SvgPathParser(data).parse();
  if (_pathCache.length >= 256) _pathCache.remove(_pathCache.keys.first);
  _pathCache[data] = path;
  return path;
}

class _SvgPathParser {
  final String s;
  int i = 0;

  _SvgPathParser(this.s);

  final Path path = Path();
  double x = 0, y = 0; // current point
  double startX = 0, startY = 0; // start of the current subpath
  double ctrlX = 0, ctrlY = 0; // last control point, for S / T reflection
  String lastCommand = '';

  static bool _isCommand(int c) => 'MmLlHhVvCcSsQqTtAaZz'.codeUnits.contains(c);

  void _skipSeparators() {
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      // space, tab, CR, LF, comma
      if (c == 0x20 || c == 0x09 || c == 0x0D || c == 0x0A || c == 0x2C) {
        i++;
      } else {
        break;
      }
    }
  }

  bool _atNumber() {
    _skipSeparators();
    if (i >= s.length) return false;
    final c = s.codeUnitAt(i);
    return (c >= 0x30 && c <= 0x39) || c == 0x2D || c == 0x2B || c == 0x2E;
  }

  double _number() {
    _skipSeparators();
    final start = i;
    if (i < s.length && (s[i] == '-' || s[i] == '+')) i++;
    var seenDot = false;
    while (i < s.length) {
      final ch = s[i];
      if (ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39) {
        i++;
      } else if (ch == '.' && !seenDot) {
        seenDot = true;
        i++;
      } else {
        break;
      }
    }
    if (i < s.length && (s[i] == 'e' || s[i] == 'E')) {
      i++;
      if (i < s.length && (s[i] == '-' || s[i] == '+')) i++;
      while (i < s.length &&
          s.codeUnitAt(i) >= 0x30 &&
          s.codeUnitAt(i) <= 0x39) {
        i++;
      }
    }
    return double.parse(s.substring(start, i));
  }

  // Arc flags may be written without separators (`a1,1 0 01…`).
  bool _flag() {
    _skipSeparators();
    final f = s[i] == '1';
    i++;
    return f;
  }

  Path parse() {
    while (true) {
      _skipSeparators();
      if (i >= s.length) break;
      String cmd;
      if (_isCommand(s.codeUnitAt(i))) {
        cmd = s[i];
        i++;
      } else {
        // Implicit repeat: a command letter may be followed by several
        // coordinate sets, and extra coordinates after `M` mean `L`.
        if (lastCommand.isEmpty || !_atNumber()) break;
        cmd = lastCommand == 'M'
            ? 'L'
            : lastCommand == 'm'
            ? 'l'
            : lastCommand;
      }
      _run(cmd);
      lastCommand = cmd;
    }
    return path;
  }

  void _run(String cmd) {
    final rel = cmd.toLowerCase() == cmd;
    final dx = rel ? x : 0.0, dy = rel ? y : 0.0;
    switch (cmd.toUpperCase()) {
      case 'M':
        x = _number() + dx;
        y = _number() + dy;
        path.moveTo(x, y);
        startX = x;
        startY = y;
        ctrlX = x;
        ctrlY = y;
      case 'L':
        x = _number() + dx;
        y = _number() + dy;
        path.lineTo(x, y);
        ctrlX = x;
        ctrlY = y;
      case 'H':
        x = _number() + dx;
        path.lineTo(x, y);
        ctrlX = x;
        ctrlY = y;
      case 'V':
        y = _number() + dy;
        path.lineTo(x, y);
        ctrlX = x;
        ctrlY = y;
      case 'C':
        final x1 = _number() + dx, y1 = _number() + dy;
        final x2 = _number() + dx, y2 = _number() + dy;
        x = _number() + dx;
        y = _number() + dy;
        path.cubicTo(x1, y1, x2, y2, x, y);
        ctrlX = x2;
        ctrlY = y2;
      case 'S':
        final reflect = 'CcSs'.contains(lastCommand);
        final x1 = reflect ? 2 * x - ctrlX : x;
        final y1 = reflect ? 2 * y - ctrlY : y;
        final x2 = _number() + dx, y2 = _number() + dy;
        x = _number() + dx;
        y = _number() + dy;
        path.cubicTo(x1, y1, x2, y2, x, y);
        ctrlX = x2;
        ctrlY = y2;
      case 'Q':
        final x1 = _number() + dx, y1 = _number() + dy;
        x = _number() + dx;
        y = _number() + dy;
        path.quadraticBezierTo(x1, y1, x, y);
        ctrlX = x1;
        ctrlY = y1;
      case 'T':
        final reflect = 'QqTt'.contains(lastCommand);
        final x1 = reflect ? 2 * x - ctrlX : x;
        final y1 = reflect ? 2 * y - ctrlY : y;
        x = _number() + dx;
        y = _number() + dy;
        path.quadraticBezierTo(x1, y1, x, y);
        ctrlX = x1;
        ctrlY = y1;
      case 'A':
        final rx = _number(), ry = _number(), rotation = _number();
        final largeArc = _flag(), sweep = _flag();
        x = _number() + dx;
        y = _number() + dy;
        path.arcToPoint(
          Offset(x, y),
          radius: Radius.elliptical(rx, ry),
          rotation: rotation,
          largeArc: largeArc,
          clockwise: sweep,
        );
        ctrlX = x;
        ctrlY = y;
      case 'Z':
        path.close();
        x = startX;
        y = startY;
        ctrlX = x;
        ctrlY = y;
    }
  }
}
