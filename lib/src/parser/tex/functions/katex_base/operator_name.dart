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

const _operatorNameEntries = {
  ['\\operatorname', '\\operatorname*', '\\operatornamewithlimits']:
      FunctionSpec(numArgs: 1, handler: _operatorNameHandler),
};
GreenNode _operatorNameHandler(TexParser parser, FunctionContext context) {
  var name = parser.parseArgNode(mode: null, optional: false)!;
  final withLimits = context.funcName != '\\operatorname';
  // \limits/\nolimits after plain \operatorname are accepted and ignored
  // (KaTeX 0.13.4); the starred form puts its limits above and below unless
  // told otherwise, like \lim (KaTeX 0.13.8 \operatornamewithlimits).
  final scripts = parser.parseScripts(allowLimits: true);
  final limits = withLimits ? (scripts.limits ?? true) : false;
  // The following atom, read like the built-in operators do (op.dart):
  // `\operatorname{rank}\quad A` must not take \hskip as an argument.
  final body =
      parser.parseAtom(context.breakOnTokenText) ?? EquationRowNode.empty();

  name = StyleNode(
    children: name.expandEquationRow(),
    optionsDiff: OptionsDiff(mathFontOptions: texMathFontOptions['\\mathrm']),
  );

  if (!scripts.empty) {
    if (limits) {
      name = scripts.superscript != null
          ? OverNode(
              base: name.wrapWithEquationRow(),
              above: scripts.superscript!,
            )
          : name;
      name = scripts.subscript != null
          ? UnderNode(
              base: name.wrapWithEquationRow(),
              below: scripts.subscript!,
            )
          : name;
    } else {
      name = MultiscriptsNode(
        base: name.wrapWithEquationRow(),
        sub: scripts.subscript,
        sup: scripts.superscript,
      );
    }
  }

  return FunctionNode(
    functionName: name.wrapWithEquationRow(),
    argument: body.wrapWithEquationRow(),
  );
}
