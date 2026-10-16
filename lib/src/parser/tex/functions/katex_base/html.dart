// Ported from KaTeX 0.19.0 src/functions/{href,html,includegraphics}.ts
// (MIT, Copyright (c) 2013-2020 Khan Academy and other contributors).
//
// Gated by TexParserSettings.trust, as in KaTeX. When rendered, links are
// not followed and HTML attributes have nothing to attach to, so these show
// their content only.

part of '../katex_base.dart';

const _htmlEntries = {
  ['\\href']: FunctionSpec(
    numArgs: 2,
    allowedInText: true,
    handler: _hrefHandler,
  ),
  ['\\url']: FunctionSpec(
    numArgs: 1,
    allowedInText: true,
    handler: _urlHandler,
  ),
  ['\\htmlClass', '\\htmlId', '\\htmlStyle', '\\htmlData']: FunctionSpec(
    numArgs: 2,
    allowedInText: true,
    handler: _htmlHandler,
  ),
  ['\\includegraphics']: FunctionSpec(
    numArgs: 1,
    numOptionalArgs: 1,
    handler: _includeGraphicsHandler,
  ),
};

GreenNode _hrefHandler(TexParser parser, FunctionContext context) {
  parser.parseArgUrl(optional: false);
  final body = parser.parseArgNode(mode: null, optional: false)!;
  if (!parser.settings.trust) return parser.formatUnsupportedCmd('\\href');
  return body;
}

GreenNode _urlHandler(TexParser parser, FunctionContext context) {
  final url = parser.parseArgUrl(optional: false)!;
  if (!parser.settings.trust) return parser.formatUnsupportedCmd('\\url');
  // The URL as typewriter text, character by character.
  return EquationRowNode(
    children: [
      for (final char in url.runes.map(String.fromCharCode))
        SymbolNode(
          symbol: char,
          mode: Mode.text,
          overrideFont: const FontOptions(fontFamily: 'Typewriter'),
        ),
    ],
  );
}

GreenNode _htmlHandler(TexParser parser, FunctionContext context) {
  parser.parseArgRaw(optional: false); // class / id / style / data
  final body = parser.parseArgNode(mode: null, optional: false)!;
  if (!parser.settings.trust) {
    return parser.formatUnsupportedCmd(context.funcName);
  }
  return body;
}

final _sizeNumberOnly = RegExp(r'^[-+]? *(\d+(\.\d*)?|\.\d+)$');
final _sizeWithUnit = RegExp(r'([-+]?) *(\d+(?:\.\d*)?|\.\d+) *([a-z]{2})');

Measurement _sizeData(String str) {
  if (_sizeNumberOnly.hasMatch(str)) {
    // No unit: bp, as in the graphicx package.
    return Measurement(
      value: double.parse(str.replaceAll(' ', '')),
      unit: Unit.bp,
    );
  }
  final match = _sizeWithUnit.firstMatch(str);
  if (match == null) {
    throw ParseException("Invalid size: '$str' in \\includegraphics");
  }
  final unit = match[3]!.parseUnit();
  if (unit == null) {
    throw ParseException("Invalid unit: '${match[3]}' in \\includegraphics.");
  }
  return Measurement(value: double.parse('${match[1]}${match[2]}'), unit: unit);
}

GreenNode _includeGraphicsHandler(TexParser parser, FunctionContext context) {
  final attributes = parser.parseArgRaw(optional: true);
  final src = parser.parseArgUrl(optional: false)!;
  var width = Measurement.zero;
  var height = const Measurement(value: 0.9, unit: Unit.em);
  var totalHeight = Measurement.zero;
  var alt = '';
  if (attributes != null) {
    for (final attribute in attributes.split(',')) {
      final keyVal = attribute.split('=');
      if (keyVal.length != 2) continue;
      final value = keyVal[1].trim();
      switch (keyVal[0].trim()) {
        case 'alt':
          alt = value;
        case 'width':
          width = _sizeData(value);
        case 'height':
          height = _sizeData(value);
        case 'totalheight':
          totalHeight = _sizeData(value);
        default:
          throw ParseException(
            "Invalid key: '${keyVal[0]}' in \\includegraphics.",
          );
      }
    }
  }
  if (alt.isEmpty) {
    // The file name without its path or extension.
    alt = src.replaceFirst(RegExp(r'^.*[\\/]'), '');
    final dot = alt.lastIndexOf('.');
    if (dot >= 0) alt = alt.substring(0, dot);
  }
  if (!parser.settings.trust) {
    return parser.formatUnsupportedCmd('\\includegraphics');
  }
  return IncludeGraphicsNode(
    src: src,
    alt: alt,
    height: height,
    width: width,
    totalHeight: totalHeight,
    mode: parser.mode,
  );
}
