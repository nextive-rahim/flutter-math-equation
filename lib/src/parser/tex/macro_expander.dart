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

import '../../ast/types.dart';
import 'functions.dart';
import 'lexer.dart';
import 'macros.dart';
import 'namespace.dart';
import 'parse_error.dart';
import 'settings.dart';
import 'symbols.dart';
import 'token.dart';

// List of commands that act like macros but aren't defined as a macro,
// function, or symbol.  Used in `isDefined`.
const implicitCommands = {
  '^', // Parser.js
  '_', // Parser.js
  '\\limits', // Parser.js
  '\\nolimits', // Parser.js
};

class MacroExpander implements MacroContext {
  MacroExpander(this.input, this.settings, this.mode)
    : macros = Namespace(builtinMacros, settings.macros),
      lexer = Lexer(input, settings);

  String input;
  TexParserSettings settings;
  @override
  Mode mode;
  int expansionCount = 0;
  var stack = <Token>[];
  Lexer lexer;
  @override
  Namespace<MacroDefinition> macros;

  @override
  Token expandAfterFuture() {
    expandOnce();
    return future();
  }

  @override
  Token expandNextToken() {
    while (true) {
      if (expandOnce() != null) {
        final token = stack.removeLast();
        // The token after \noexpand is interpreted as if its meaning were
        // \relax.
        if (token.treatAsRelax) token.text = '\\relax';
        return token;
      }
    }
  }

  // switchMode is replaced by a plain setter

  void beginGroup() {
    macros.beginGroup();
  }

  void endGroup() {
    macros.endGroup();
  }

  /// Increments the expansion count, throwing past `maxExpand` (KaTeX
  /// countExpansion).
  void countExpansion(int amount) {
    expansionCount += amount;
    if (expansionCount > settings.maxExpand) {
      throw ParseException(
        'Too many expansions: infinite loop or '
        'need to increase maxExpand setting',
      );
    }
  }

  /// Expands the next token once if it can be. Returns the token, left on
  /// top of the stack, when it was not expanded, or null after an expansion.
  ///
  /// With [expandableOnly], only expandable tokens are expanded and an
  /// undefined control sequence is an error.
  @override
  Token? expandOnce([bool expandableOnly = false]) {
    final topToken = popToken();
    final name = topToken.text;
    final expansion = !topToken.noexpand ? _getExpansion(name) : null;
    if (expansion == null || (expandableOnly && expansion.unexpandable)) {
      // (The ported check read `isDefined(name)`, inverted, so
      // \expandafter\x\frac threw "Undefined control sequence: \frac".)
      if (expandableOnly &&
          expansion == null &&
          name[0] == '\\' &&
          !isDefined(name)) {
        throw ParseException('Undefined control sequence: $name');
      }
      pushToken(topToken);
      return topToken;
    }
    countExpansion(1);
    var tokens = expansion.tokens;
    // Delimiters following the macro name are consumed even without
    // arguments (KaTeX 0.16.23).
    final args = consumeArgs(expansion.numArgs, expansion.delimiters);
    if (expansion.numArgs != 0) {
      tokens = tokens.toList();
      for (var i = tokens.length - 1; i >= 0; --i) {
        var tok = tokens[i];
        if (tok.text == '#') {
          if (i == 0) {
            throw ParseException(
              'Incomplete placeholder at end of macro body',
              tok,
            );
          }
          --i;
          tok = tokens[i];
          if (tok.text == '#') {
            tokens.removeAt(i + 1);
          } else if (RegExp(r'^[1-9]$').hasMatch(tok.text)) {
            tokens.replaceRange(i, i + 2, args[int.parse(tok.text) - 1]);
          } else {
            throw ParseException('Not a valid argument number', tok);
          }
        }
      }
    }
    pushTokens(tokens);
    return null;
  }

  @override
  void pushToken(Token token) {
    stack.add(token);
  }

  @override
  void pushTokens(List<Token> tokens) {
    stack.addAll(tokens);
  }

  @override
  Token popToken() {
    future();
    return stack.removeLast();
  }

  @override
  Token future() {
    if (stack.isEmpty) {
      stack.add(lexer.lex());
    }
    return stack.last;
  }

  MacroExpansion? _getExpansion(String name) {
    // A single character only expands while it is active (catcode 13), so
    // `~` stays literal inside a URL.
    if (name.length == 1) {
      final catcode = lexer.catCodes[name];
      if (catcode != null && catcode != 13) return null;
    }
    final definition = macros.get(name);
    if (definition == null) {
      return null;
    }
    return definition.expand(this);
  }

  /// Consumes one macro argument (KaTeX MacroExpander.consumeArg): the
  /// next token or `{…}` group, or — with [delims] — the shortest balanced
  /// token sequence followed by [delims]. Tokens are returned in stack
  /// (reversed) order.
  @override
  ({List<Token> tokens, Token start, Token end}) consumeArg([
    List<String>? delims,
  ]) {
    final tokens = <Token>[];
    final isDelimited = delims != null && delims.isNotEmpty;
    if (!isDelimited) {
      // TeX ignores spaces between undelimited arguments.
      consumeSpaces();
    }
    final start = future();
    Token tok;
    var depth = 0;
    var match = 0;
    do {
      tok = popToken();
      tokens.add(tok);
      if (tok.text == '{') {
        ++depth;
      } else if (tok.text == '}') {
        --depth;
        if (depth == -1) throw ParseException('Extra }', tok);
      } else if (tok.text == 'EOF') {
        throw ParseException(
          'Unexpected end of input in a macro argument, expected '
          "'${isDelimited ? delims[match] : '}'}'",
          tok,
        );
      }
      if (isDelimited) {
        if ((depth == 0 || (depth == 1 && delims[match] == '{')) &&
            tok.text == delims[match]) {
          ++match;
          if (match == delims.length) {
            // Delimiters are not part of the argument.
            tokens.removeRange(tokens.length - match, tokens.length);
            break;
          }
        } else {
          match = 0;
        }
      }
    } while (depth != 0 || isDelimited);
    // An argument of the form {…} loses its outermost braces.
    if (start.text == '{' && tokens.isNotEmpty && tokens.last.text == '}') {
      tokens
        ..removeLast()
        ..removeAt(0);
    }
    return (tokens: tokens.reversed.toList(), start: start, end: tok);
  }

  /// Consumes [numArgs] arguments, matching [delimiters] (see
  /// [MacroExpansion.delimiters]) when given.
  @override
  List<List<Token>> consumeArgs(int numArgs, [List<List<String>>? delimiters]) {
    if (delimiters != null) {
      if (delimiters.length != numArgs + 1) {
        throw ParseException(
          "The length of delimiters doesn't match the number of args!",
        );
      }
      for (final delim in delimiters[0]) {
        final tok = popToken();
        if (delim != tok.text) {
          throw ParseException(
            "Use of the macro doesn't match its definition",
            tok,
          );
        }
      }
    }
    return [
      for (var i = 0; i < numArgs; i++) consumeArg(delimiters?[i + 1]).tokens,
    ];
  }

  @override
  void consumeSpaces() {
    while (true) {
      final token = future();
      if (token.text == ' ') {
        stack.removeLast();
      } else {
        break;
      }
    }
  }

  @override
  bool isDefined(String name) =>
      macros.has(name) ||
      texSymbolCommandConfigs[Mode.math]!.containsKey(name) ||
      texSymbolCommandConfigs[Mode.text]!.containsKey(name) ||
      functions.containsKey(name) ||
      implicitCommands.contains(name);

  @override
  bool isExpandable(String name) {
    final macro = macros.get(name);
    return macro?.expandable ?? functions.containsKey(name);
  }

  @override
  Lexer getNewLexer(String input) => Lexer(input, settings);

  String? expandMacroAsText(String name) {
    final tokens = expandMacro(name);
    if (tokens != null) {
      return tokens.map((token) => token.text).join('');
    }
    return null;
  }

  List<Token>? expandMacro(String name) =>
      macros.has(name) ? expandTokens([Token(name)]) : null;

  /// Fully expands [tokens] (given in stack order) and returns the result in
  /// reading order. Every output token counts as an expansion, so linearly
  /// many \edef's cannot blow up exponentially (KaTeX 0.16.10).
  @override
  List<Token> expandTokens(List<Token> tokens) {
    final output = <Token>[];
    final oldStackLength = stack.length;
    pushTokens(tokens);
    while (stack.length > oldStackLength) {
      // Expand only expandable tokens.
      if (expandOnce(true) != null) {
        final token = stack.removeLast();
        if (token.treatAsRelax) {
          // The expansion of \noexpand is the token itself.
          token
            ..noexpand = false
            ..treatAsRelax = false;
        }
        output.add(token);
      }
    }
    countExpansion(output.length);
    return output;
  }
}

abstract class MacroContext {
  Mode get mode;
  Namespace<MacroDefinition> get macros;
  Token future();
  Token popToken();
  void consumeSpaces();
  //  Token expandAfterFuture();
  // ignore: avoid_positional_boolean_parameters
  Token? expandOnce([bool expandableOnly]);
  Token expandAfterFuture();
  Token expandNextToken();
  //
  List<List<Token>> consumeArgs(int numArgs, [List<List<String>>? delimiters]);
  ({List<Token> tokens, Token start, Token end}) consumeArg([
    List<String>? delims,
  ]);
  List<Token> expandTokens(List<Token> tokens);
  void pushToken(Token token);
  void pushTokens(List<Token> tokens);
  bool isDefined(String name);
  bool isExpandable(String name);

  Lexer getNewLexer(String input);
}
