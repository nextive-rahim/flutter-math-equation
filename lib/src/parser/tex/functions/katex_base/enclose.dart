// The MIT License (MIT)
//
// Copyright (c) 2013-2019 Khan Academy and other contributors
// Copyright (c) 2020 znjameswu <znjameswu@gmail.com>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

part of '../katex_base.dart';

const _encloseEntries = {
  ['\\colorbox']: FunctionSpec(
    numArgs: 2,
    allowedInText: true,
    greediness: 3,
    handler: _colorboxHandler,
  ),
  ['\\fcolorbox']: FunctionSpec(
    numArgs: 3,
    allowedInText: true,
    greediness: 3,
    handler: _fcolorboxHandler,
  ),
  ['\\fbox']: FunctionSpec(
    numArgs: 1,
    allowedInText: true,
    handler: _fboxHandler,
  ),
  ['\\cancel', '\\bcancel', '\\xcancel']: FunctionSpec(
    numArgs: 1,
    handler: _cancelHandler,
  ),
  // \sout works in text too (KaTeX 0.16.41) and has no padding.
  ['\\sout']: FunctionSpec(
    numArgs: 1,
    allowedInText: true,
    handler: _soutHandler,
  ),
  // Steinmetz phasor angle (KaTeX 0.13).
  ['\\phase']: FunctionSpec(numArgs: 1, handler: _phaseHandler),
  // Actuarial angle (KaTeX 0.13), on an hbox argument.
  ['\\angl']: FunctionSpec(numArgs: 1, handler: _anglHandler),
};

GreenNode _soutHandler(TexParser parser, FunctionContext context) {
  if (parser.mode == Mode.math) {
    parser.settings.reportNonstrict(
      'mathVsSout',
      "LaTeX's \\sout works only in text mode",
      context.token,
    );
  }
  final body = parser.parseArgNode(mode: null, optional: false)!;
  return EnclosureNode(
    notation: const ['horizontalstrike'],
    hasBorder: false,
    base: body.wrapWithEquationRow(),
  );
}

GreenNode _phaseHandler(TexParser parser, FunctionContext context) {
  final body = parser.parseArgNode(mode: null, optional: false)!;
  return EnclosureNode(
    notation: const ['phase'],
    hasBorder: false,
    base: body.wrapWithEquationRow(),
  );
}

GreenNode _anglHandler(TexParser parser, FunctionContext context) {
  final body = parser.parseArgHbox(optional: false);
  return EnclosureNode(
    notation: const ['angl'],
    hasBorder: false,
    base: body.wrapWithEquationRow(),
  );
}

GreenNode _colorboxHandler(TexParser parser, FunctionContext context) {
  final color = parser.parseArgColor(optional: false);
  // An hbox argument: text style, whatever the surroundings (KaTeX 0.13).
  final body = parser.parseArgHbox(optional: false);
  return EnclosureNode(
    backgroundcolor: color,
    base: body.wrapWithEquationRow(),
    hasBorder: false,
    // FontMetrics.fboxsep
    verticalPadding: 0.3.cssEm,
    // katex.less/.boxpad
    horizontalPadding: 0.3.cssEm,
  );
}

GreenNode _fcolorboxHandler(TexParser parser, FunctionContext context) {
  final borderColor = parser.parseArgColor(optional: false)!;
  final color = parser.parseArgColor(optional: false)!;
  final body = parser.parseArgHbox(optional: false);
  return EnclosureNode(
    hasBorder: true,
    bordercolor: borderColor,
    backgroundcolor: color,
    base: body.wrapWithEquationRow(),
    // FontMetrics.fboxsep
    verticalPadding: 0.3.cssEm,
    // katex.less/.boxpad
    horizontalPadding: 0.3.cssEm,
  );
}

GreenNode _fboxHandler(TexParser parser, FunctionContext context) {
  final body = parser.parseArgHbox(optional: false);
  return EnclosureNode(
    hasBorder: true,
    base: body.wrapWithEquationRow(),
    // FontMetrics.fboxsep
    verticalPadding: 0.3.cssEm,
    // katex.less/.boxpad
    horizontalPadding: 0.3.cssEm,
  );
}

GreenNode _cancelHandler(TexParser parser, FunctionContext context) {
  final body = parser.parseArgNode(mode: null, optional: false)!;
  // KaTeX enclose.ts: a single character gets 0.2em above and below, a
  // longer subject 0.2em on each side (.cancel-pad) instead, as the lines
  // of the cancel package are shaped differently for each.
  final row = body.wrapWithEquationRow();
  final isSingleChar =
      row.children.length == 1 && row.children.single is SymbolNode;
  return EnclosureNode(
    notation: const {
      '\\cancel': ['updiagonalstrike'],
      '\\bcancel': ['downdiagonalstrike'],
      '\\xcancel': ['updiagonalstrike', 'downdiagonalstrike'],
    }[context.funcName]!,
    hasBorder: false,
    base: row,
    verticalPadding: isSingleChar ? 0.2.cssEm : Measurement.zero,
    horizontalPadding: isSingleChar ? Measurement.zero : 0.2.cssEm,
  );
}
