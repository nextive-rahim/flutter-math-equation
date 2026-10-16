// Ported from KaTeX 0.19.0 src/functions/def.ts and src/functions/relax.ts
// (MIT, Copyright (c) 2013-2020 Khan Academy and other contributors).

part of '../katex_base.dart';

const _defEntries = {
  ['\\global', '\\long', '\\\\globallong']: FunctionSpec(
    numArgs: 0,
    allowedInText: true,
    handler: _globalHandler,
  ),
  ['\\def', '\\gdef', '\\edef', '\\xdef']: FunctionSpec(
    numArgs: 0,
    allowedInText: true,
    handler: _defHandler,
  ),
  ['\\let', '\\\\globallet']: FunctionSpec(
    numArgs: 0,
    allowedInText: true,
    handler: _letHandler,
  ),
  ['\\futurelet', '\\\\globalfuture']: FunctionSpec(
    numArgs: 0,
    allowedInText: true,
    handler: _futureletHandler,
  ),
  // \relax does nothing; it only stops scanning. Greediness 3 lets it stand
  // where any argument is expected (KaTeX: allowedInArgument).
  ['\\relax']: FunctionSpec(
    numArgs: 0,
    greediness: 3,
    allowedInText: true,
    handler: _relaxHandler,
  ),
};

const _globalMap = {
  '\\global': '\\global',
  '\\long': '\\\\globallong',
  '\\\\globallong': '\\\\globallong',
  '\\def': '\\gdef',
  '\\gdef': '\\gdef',
  '\\edef': '\\xdef',
  '\\xdef': '\\xdef',
  '\\let': '\\\\globallet',
  '\\futurelet': '\\\\globalfuture',
};

final _notControlSequence = RegExp(r'^(?:[\\{}$&#^_]|EOF)$');

String _checkControlSequence(Token tok) {
  if (_notControlSequence.hasMatch(tok.text)) {
    throw ParseException('Expected a control sequence', tok);
  }
  return tok.text;
}

/// `<equals>` then one optional space, then the right-hand token.
Token _getRHS(TexParser parser) {
  var tok = parser.macroExpander.popToken();
  if (tok.text == '=') {
    tok = parser.macroExpander.popToken();
    if (tok.text == ' ') tok = parser.macroExpander.popToken();
  }
  return tok;
}

void _letCommand(TexParser parser, String name, Token tok, bool global) {
  var macro = parser.macroExpander.macros.get(tok.text);
  if (macro == null) {
    // Don't expand it later even if a macro with the same name is defined:
    // \let\foo=\frac \def\frac{\relax} \frac12
    tok.noexpand = true;
    macro = MacroDefinition.fromMacroExpansion(
      MacroExpansion(
        tokens: [tok],
        numArgs: 0,
        unexpandable: !parser.macroExpander.isExpandable(tok.text),
      ),
    );
  }
  parser.macroExpander.macros.set(name, macro, global: global);
}

// <assignment> -> <non-macro assignment>|<macro assignment>
// <prefix> -> \global|\long|\outer
GreenNode _globalHandler(TexParser parser, FunctionContext context) {
  parser.consumeSpaces();
  final token = parser.fetch();
  final global = _globalMap[token.text];
  if (global != null) {
    // There is no \par, so \long is ignored.
    if (context.funcName == '\\global' ||
        context.funcName == '\\\\globallong') {
      token.text = global;
    }
    final result = parser.parseFunction(null, null, null);
    if (result is! InternalNode) {
      throw ParseException('Invalid token after macro prefix', token);
    }
    return result;
  }
  throw ParseException('Invalid token after macro prefix', token);
}

// <definition> -> <def><control sequence><definition text>
// <definition text> -> <parameter text><left brace><balanced text><right brace>
GreenNode _defHandler(TexParser parser, FunctionContext context) {
  final gullet = parser.macroExpander;
  var tok = gullet.popToken();
  final name = tok.text;
  if (_notControlSequence.hasMatch(name)) {
    throw ParseException('Expected a control sequence', tok);
  }

  var numArgs = 0;
  Token? insert;
  final delimiters = <List<String>>[[]];
  // <parameter text> contains no braces.
  while (gullet.future().text != '{') {
    tok = gullet.popToken();
    if (tok.text == '#') {
      // A trailing # before { behaves as if the { were inserted at the end
      // of both the parameter text and the replacement text.
      if (gullet.future().text == '{') {
        insert = gullet.future();
        delimiters[numArgs].add('{');
        break;
      }
      // Parameters #1, #2 … #9, in order.
      tok = gullet.popToken();
      if (!RegExp(r'^[1-9]$').hasMatch(tok.text)) {
        throw ParseException('Invalid argument number "${tok.text}"');
      }
      if (int.parse(tok.text) != numArgs + 1) {
        throw ParseException('Argument number "${tok.text}" out of order');
      }
      numArgs++;
      delimiters.add([]);
    } else if (tok.text == 'EOF') {
      throw ParseException('Expected a macro definition');
    } else {
      delimiters[numArgs].add(tok.text);
    }
  }
  // Replacement text, enclosed in { } and properly nested.
  var tokens = gullet.consumeArg().tokens;
  // Stack order is reversed, so the inserted `{` goes first in the list —
  // last when read (KaTeX: tokens.unshift(insert)).
  if (insert != null) tokens = [insert, ...tokens];

  if (context.funcName == '\\edef' || context.funcName == '\\xdef') {
    tokens = gullet.expandTokens(tokens).reversed.toList();
  }
  gullet.macros.set(
    name,
    MacroDefinition.fromMacroExpansion(
      MacroExpansion(tokens: tokens, numArgs: numArgs, delimiters: delimiters),
    ),
    global: context.funcName == _globalMap[context.funcName],
  );
  return InternalNode(mode: parser.mode);
}

// <let assignment> -> \let<control sequence><equals><one optional space><token>
GreenNode _letHandler(TexParser parser, FunctionContext context) {
  final name = _checkControlSequence(parser.macroExpander.popToken());
  parser.macroExpander.consumeSpaces();
  final tok = _getRHS(parser);
  _letCommand(parser, name, tok, context.funcName == '\\\\globallet');
  return InternalNode(mode: parser.mode);
}

// \futurelet<control sequence><token><token>
GreenNode _futureletHandler(TexParser parser, FunctionContext context) {
  final name = _checkControlSequence(parser.macroExpander.popToken());
  final middle = parser.macroExpander.popToken();
  final tok = parser.macroExpander.popToken();
  _letCommand(parser, name, tok, context.funcName == '\\\\globalfuture');
  parser.macroExpander
    ..pushToken(tok)
    ..pushToken(middle);
  return InternalNode(mode: parser.mode);
}

GreenNode _relaxHandler(TexParser parser, FunctionContext context) =>
    InternalNode(mode: parser.mode);
