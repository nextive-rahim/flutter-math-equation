import 'package:flutter_equation_support/src/ast/nodes/multiscripts.dart';
import 'package:flutter_equation_support/src/ast/nodes/symbol.dart';
import 'package:flutter_equation_support/src/ast/syntax_tree.dart';
import 'package:flutter_equation_support/src/parser/tex/parse_error.dart';
import 'package:flutter_equation_support/src/parser/tex/parser.dart';
import 'package:flutter_equation_support/src/parser/tex/settings.dart';
import 'package:flutter_test/flutter_test.dart';

EquationRowNode parse(String tex) =>
    TexParser(tex, const TexParserSettings(strict: Strict.ignore)).parse();

/// The symbols of [tex], flattened (groups and styles ignored).
String text(String tex) {
  final out = StringBuffer();
  void walk(GreenNode? node) {
    if (node == null) return;
    if (node is SymbolNode) {
      out.write(node.symbol);
    } else {
      node.children.forEach(walk);
    }
  }

  walk(parse(tex));
  return out.toString();
}

void main() {
  group('\\def family (KaTeX 0.19 def.ts)', () {
    test('plain macro with arguments', () {
      expect(text(r'\def\pair#1#2{(#1,#2)}\pair ab'), '(a,b)');
    });
    test('delimited parameters', () {
      expect(text(r'\def\x#1.#2;{[#1|#2]}\x abc.de;'), '[abc|de]');
    });
    test('# before { inserts a brace', () {
      // The replacement text becomes `y{`, so `\x{z}` reads as `y{z}`.
      expect(text(r'\def\x#{y}\x{z}'), 'yz');
    });
    test('\\def is local to its group, \\gdef is global', () {
      expect(text(r'\def\a{1}{\def\a{2}\def\a{3}}\a'), '1');
      expect(text(r'\def\a{1}{\gdef\a{2}}\a'), '2');
      expect(text(r'\def\a{1}{\global\def\a{3}}\a'), '3');
    });
    test('\\let copies the current meaning', () {
      expect(text(r'\def\a{x}\let\b=\a \def\a{y}\b\a'), 'xy');
      expect(text(r'\let\myfrac\frac \myfrac12'), '12');
    });
    test('\\edef expands at definition time', () {
      expect(text(r'\def\a{x}\edef\b{\a\a}\def\a{y}\b'), 'xx');
    });
    test('\\futurelet', () {
      expect(text(r'\futurelet\x\relax a'), 'a');
    });
    test('\\expandafter expands the token after next first', () {
      expect(text(r'\def\a{b}\def\x#1{[#1]}\expandafter\x\a'), '[b]');
      // A defined, non-macro command is left alone (the ported check was
      // inverted and threw "Undefined control sequence: \frac" here).
      expect(
        () => parse(r'\def\x#1{#1}\expandafter\x\frac12'),
        returnsNormally,
      );
      expect(
        () => parse(r'\expandafter\x\nosuch'),
        throwsA(isA<ParseException>()),
      );
    });
    test('mismatched macro use is an error', () {
      expect(
        () => parse(r'\def\x#1.{#1}\x abc'),
        throwsA(isA<ParseException>()),
      );
    });
  });

  group('\\relax (KaTeX 0.15 function)', () {
    test('disappears from the output', () {
      expect(text(r'a\relax b'), 'ab');
    });
    test('in a script base or exponent', () {
      final row = parse(r'x^\relax 2');
      final scripts = row.children.single as MultiscriptsNode;
      expect((scripts.sup!.children.single as SymbolNode).symbol, '2');
    });
    test('quad still works (uses \\hskip...\\relax)', () {
      expect(() => parse(r'a\quad b\qquad c'), returnsNormally);
    });
  });

  group('Unicode sub/superscripts (KaTeX 0.15.4)', () {
    MultiscriptsNode scripts(String tex) =>
        parse(tex).children.first as MultiscriptsNode;
    String row(EquationRowNode? r) =>
        r!.children.map((c) => (c as SymbolNode).symbol).join();

    test('x² is x^{2}', () {
      expect(row(scripts('x²').sup), '2');
    });
    test('a run of the same kind is one script', () {
      expect(row(scripts('x²³').sup), '23');
      expect(row(scripts('a⁻¹').sup), '-1');
      expect(row(scripts('H₂O').sub), '2');
      expect(parse('H₂O').children.length, 2, reason: 'H₂ then O');
    });
    test('Word-style 𝑥² works', () {
      expect(row(scripts('𝑥²').sup), '2');
    });
    test('mixed sub and sup', () {
      final s = scripts('x₁²');
      expect(row(s.sub), '1');
      expect(row(s.sup), '2');
    });
    test('text mode leaves the character alone', () {
      expect(text(r'\text{cm²}'), 'cm²');
    });
  });

  test('U+FE0F no longer becomes ®', () {
    expect(text('✔️'), '✔');
  });

  test('unknown commands render as text when throwOnError is false', () {
    final row = TexParser(
      r'\nosuchcommand x',
      const TexParserSettings(throwOnError: false),
    ).parse();
    expect(row.children, isNotEmpty);
  });
}
