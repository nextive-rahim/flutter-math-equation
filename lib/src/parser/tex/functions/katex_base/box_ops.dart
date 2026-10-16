// Ported from KaTeX 0.19.0 src/functions/{smash,lap,vcenter,reflectbox,
// mathchoice,hbox,htmlmathml,mclass}.ts (MIT, Copyright (c) 2013-2020 Khan
// Academy and other contributors).

part of '../katex_base.dart';

const _boxOpsEntries = {
  ['\\smash']: FunctionSpec(
    numArgs: 1,
    numOptionalArgs: 1,
    allowedInText: true,
    handler: _smashHandler,
  ),
  ['\\mathllap', '\\mathrlap', '\\mathclap']: FunctionSpec(
    numArgs: 1,
    allowedInText: true,
    handler: _lapHandler,
  ),
  ['\\vcenter']: FunctionSpec(numArgs: 1, handler: _vcenterHandler),
  ['\\reflectbox', '\\mathreflectbox']: FunctionSpec(
    numArgs: 1,
    allowedInText: true,
    handler: _reflectHandler,
  ),
  ['\\mathchoice']: FunctionSpec(numArgs: 4, handler: _mathChoiceHandler),
  ['\\hbox']: FunctionSpec(
    numArgs: 1,
    allowedInText: true,
    handler: _hboxHandler,
  ),
  // \html@mathml{html}{mathml}: only the first form is drawn. Used by many
  // KaTeX macros; greediness 3 so it can stand as an argument.
  ['\\html@mathml']: FunctionSpec(
    numArgs: 2,
    greediness: 3,
    allowedInText: true,
    handler: _htmlMathmlHandler,
  ),
  // \@binrel{x}{y}: y, spaced as a bin or rel if x is one.
  ['\\@binrel']: FunctionSpec(numArgs: 2, handler: _binrelHandler),
};

GreenNode _smashHandler(TexParser parser, FunctionContext context) {
  var smashHeight = true;
  var smashDepth = true;
  final tb = parser.parseArgNode(mode: null, optional: true);
  if (tb != null) {
    // [t], [b] or [tb]: smash only what is listed; anything else smashes
    // nothing.
    smashHeight = false;
    smashDepth = false;
    for (final letter in tb.expandEquationRow()) {
      final text = letter is SymbolNode ? letter.symbol : '';
      if (text == 't') {
        smashHeight = true;
      } else if (text == 'b') {
        smashDepth = true;
      } else {
        smashHeight = false;
        smashDepth = false;
        break;
      }
    }
  }
  final body = parser.parseArgNode(mode: null, optional: false)!;
  return SmashNode(
    body: body.wrapWithEquationRow(),
    smashHeight: smashHeight,
    smashDepth: smashDepth,
  );
}

GreenNode _lapHandler(TexParser parser, FunctionContext context) {
  final body = parser.parseArgNode(mode: null, optional: false)!;
  return LapNode(
    body: body.wrapWithEquationRow(),
    alignment: switch (context.funcName) {
      '\\mathllap' => LapAlignment.left,
      '\\mathrlap' => LapAlignment.right,
      _ => LapAlignment.center,
    },
  );
}

GreenNode _vcenterHandler(TexParser parser, FunctionContext context) =>
    VCenterNode(
      body: parser
          .parseArgNode(mode: null, optional: false)!
          .wrapWithEquationRow(),
    );

GreenNode _reflectHandler(TexParser parser, FunctionContext context) {
  final body = context.funcName == '\\reflectbox'
      ? parser.parseArgHbox(optional: false)
      : parser.parseArgNode(mode: Mode.math, optional: false)!;
  return ReflectNode(body: body.wrapWithEquationRow());
}

GreenNode _mathChoiceHandler(TexParser parser, FunctionContext context) {
  EquationRowNode arg() =>
      parser.parseArgNode(mode: null, optional: false)!.wrapWithEquationRow();
  return MathChoiceNode(
    display: arg(),
    text: arg(),
    script: arg(),
    scriptscript: arg(),
  );
}

GreenNode _hboxHandler(TexParser parser, FunctionContext context) =>
    parser.parseArgHbox(optional: false);

GreenNode _htmlMathmlHandler(TexParser parser, FunctionContext context) {
  final html = parser.parseArgNode(mode: null, optional: false)!;
  parser.parseArgNode(mode: null, optional: false); // the MathML form
  return html;
}

/// KaTeX mclass.ts binrelClass: bin or rel when the argument (or the first
/// atom of a group) is one, else ord.
AtomType binrelClass(GreenNode arg) {
  final atom = arg is EquationRowNode && arg.children.isNotEmpty
      ? arg.children.first
      : arg;
  if (atom is SymbolNode &&
      (atom.atomType == AtomType.bin || atom.atomType == AtomType.rel)) {
    return atom.atomType;
  }
  return AtomType.ord;
}

GreenNode _binrelHandler(TexParser parser, FunctionContext context) {
  final x = parser.parseArgNode(mode: null, optional: false)!;
  final y = parser.parseArgNode(mode: null, optional: false)!;
  return EquationRowNode(
    children: y.expandEquationRow(),
    overrideType: binrelClass(x),
  );
}
