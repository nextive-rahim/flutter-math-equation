import 'package:flutter/painting.dart';
import 'package:flutter_equation_support/src/ast/nodes/multiscripts.dart';
import 'package:flutter_equation_support/src/ast/nodes/symbol.dart';
import 'package:flutter_equation_support/src/ast/syntax_tree.dart';
import 'package:flutter_equation_support/src/parser/tex/parser.dart';
import 'package:flutter_equation_support/src/parser/tex/settings.dart';
import 'package:flutter_equation_support/src/utils/complex_script.dart';
import 'package:flutter_test/flutter_test.dart';

EquationRowNode parse(String tex) =>
    TexParser(tex, const TexParserSettings()).parse();

List<String> symbols(EquationRowNode row) => [
  for (final child in row.children)
    if (child is SymbolNode) child.symbol else '<${child.runtimeType}>',
];

void main() {
  group('mergeComplexScriptRuns', () {
    test('joins a Bengali word into one shaped run', () {
      expect(symbols(parse(r'\text{ক্রয়মূল্য}')), ['ক্রয়মূল্য']);
    });

    test('joins Bengali digits in math mode but keeps operators apart', () {
      expect(symbols(parse('১২৩+৪৫')), ['১২৩', '+', '৪৫']);
    });

    test('leaves Latin characters one per node', () {
      expect(symbols(parse('abc')), ['a', 'b', 'c']);
    });

    test('keeps TeX scoping: x^১২ raises only the first digit', () {
      final row = parse('x^১২');
      expect(row.children, hasLength(2));
      final scripts = row.children[0] as MultiscriptsNode;
      expect(symbols(scripts.sup!), ['১']);
      expect((row.children[1] as SymbolNode).symbol, '২');
    });

    test('merges inside groups, fractions and array cells', () {
      final row = parse(r'\frac{১০০}{১২০}');
      final frac = row.children.single;
      final rows = frac.children.whereType<EquationRowNode>().toList();
      expect(symbols(rows[0]), ['১০০']);
      expect(symbols(rows[1]), ['১২০']);
    });

    test('does not merge across different modes', () {
      // `\text{ক}` is text mode, the following `খ` is math mode.
      final row = parse(r'\text{ক}খ');
      expect(row.children.length, 2);
    });

    test('merged runs are plain ord atoms', () {
      final node = parse('১২').children.single as SymbolNode;
      expect(node.atomType, AtomType.ord);
    });
  });

  group('isComplexScriptText', () {
    test('accepts Bengali letters, signs, digits and joiners', () {
      expect(isComplexScriptText('ক্‍ষ'), isTrue);
      expect(isComplexScriptText('০১২৩৪৫৬৭৮৯'), isTrue);
    });
    test('rejects Latin, digits and mixed text', () {
      expect(isComplexScriptText('a'), isFalse);
      expect(isComplexScriptText('1'), isFalse);
      expect(isComplexScriptText('ক1'), isFalse);
      expect(isComplexScriptText(''), isFalse);
    });
  });

  group('fallbackFamiliesOf', () {
    test('uses the prose family and its fallbacks', () {
      expect(
        fallbackFamiliesOf(
          const TextStyle(fontFamily: 'Prose', fontFamilyFallback: ['Extra']),
        ),
        ['Prose', 'Extra'],
      );
    });
    test('skips KaTeX families', () {
      expect(
        fallbackFamiliesOf(
          const TextStyle(
            fontFamily: 'packages/flutter_equation_support/KaTeX_Main',
            fontFamilyFallback: ['Prose'],
          ),
        ),
        ['Prose'],
      );
    });
  });
}
