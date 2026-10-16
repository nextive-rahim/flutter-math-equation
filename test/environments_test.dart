import 'package:flutter_equation_support/src/ast/nodes/cd_vert_arrow.dart';
import 'package:flutter_equation_support/src/ast/nodes/equation_array.dart';
import 'package:flutter_equation_support/src/ast/nodes/matrix.dart';
import 'package:flutter_equation_support/src/ast/nodes/stretchy_op.dart';
import 'package:flutter_equation_support/src/ast/nodes/symbol.dart';
import 'package:flutter_equation_support/src/ast/nodes/tag.dart';
import 'package:flutter_equation_support/src/ast/syntax_tree.dart';
import 'package:flutter_equation_support/src/parser/tex/parse_error.dart';
import 'package:flutter_equation_support/src/parser/tex/parser.dart';
import 'package:flutter_equation_support/src/parser/tex/settings.dart';
import 'package:flutter_test/flutter_test.dart';

TexParser parser(String tex, {int first = 1}) => TexParser(
  tex,
  TexParserSettings(strict: Strict.ignore, firstEquationNumber: first),
);

GreenNode root(String tex) => parser(tex).parse().children.single;

EquationArrayNode array(String tex) {
  GreenNode node = root(tex);
  while (node is! EquationArrayNode) {
    node = node.children.firstWhere((c) => c != null)!;
  }
  return node;
}

String text(EquationRowNode? row) {
  if (row == null) return '';
  final out = StringBuffer();
  void walk(GreenNode? n) {
    if (n is SymbolNode) {
      out.write(n.symbol);
    } else {
      n?.children.forEach(walk);
    }
  }

  walk(row);
  return out.toString();
}

void main() {
  group('equation numbering', () {
    test('{align} numbers every row', () {
      final a = array(r'\begin{align} a&=b \\ c&=d \end{align}');
      expect(a.tags!.map(text), ['(1)', '(2)']);
    });
    test('\\notag and \\nonumber skip a row; \\tag overrides it', () {
      final a = array(
        r'\begin{align} a&=b \notag \\ c&=d \tag{*} \\ e&=f \nonumber \\ g \end{align}',
      );
      expect(a.tags!.map(text), ['', '(*)', '', '(1)']);
    });
    test('starred forms only take \\tag', () {
      final a = array(r'\begin{align*} a&=b \\ c&=d \tag{x} \end{align*}');
      expect(a.tags!.map(text), ['', '(x)']);
      expect(array(r'\begin{gather*} a \\ b \end{gather*}').tags, isNull);
    });
    test('\\tag* has no parentheses', () {
      final a = array(r'\begin{align} a \tag*{A} \end{align}');
      expect(a.tags!.map(text), ['A']);
    });
    test('numbering starts at firstEquationNumber and continues', () {
      final p = parser(r'\begin{gather} a \\ b \end{gather}', first: 7);
      GreenNode node = p.parse().children.single;
      while (node is! EquationArrayNode) {
        node = node.children.firstWhere((c) => c != null)!;
      }
      expect(node.tags!.map(text), ['(7)', '(8)']);
      expect(p.nextEquationNumber, 9);
    });
    test('{equation} is one numbered row; & is an error', () {
      expect(array(r'\begin{equation} E=mc^2 \end{equation}').tags!.map(text), [
        '(1)',
      ]);
      expect(
        () => root(r'\begin{equation} a & b \end{equation}'),
        throwsA(isA<ParseException>()),
      );
    });
    test('inner environments have no tags', () {
      expect(array(r'\begin{aligned} a&=b \\ c&=d \end{aligned}').tags, isNull);
      expect(array(r'\begin{gathered} a \\ b \end{gathered}').tags, isNull);
      expect(array(r'\begin{split} a&=b \\ c&=d \end{split}').tags, isNull);
    });
    test('{split} allows at most two columns', () {
      expect(
        () => root(r'\begin{split} a&=b&c \end{split}'),
        throwsA(isA<ParseException>()),
      );
    });
    test('a top-level \\tag tags the whole formula', () {
      final node = root(r'E = mc^2 \tag{3.1}');
      expect(node, isA<TagNode>());
      expect(text((node as TagNode).tag), '(3.1)');
    });
    test('two \\tags is an error', () {
      expect(() => root(r'a \tag{1} \tag{2}'), throwsA(isA<ParseException>()));
    });
  });

  group('trailing rows (KaTeX 0.13.3 / 0.18.6 / 0.18.8)', () {
    test('a trailing \\\\ does not add a blank row', () {
      expect(array(r'\begin{aligned} a \\ b \\ \end{aligned}').body.length, 2);
    });
    test('the only, empty row of an AMS environment is kept', () {
      expect(array(r'\begin{aligned}\end{aligned}').body.length, 1);
    });
    test('a numbered trailing row explicitly ended is kept', () {
      expect(array(r'\begin{align} a \\ \end{align}').body.length, 2);
      expect(array(r'\begin{align*} a \\ \end{align*}').body.length, 1);
    });
    test('alignat validates its argument', () {
      expect(
        () => root(r'\begin{alignat}{0} a \end{alignat}'),
        throwsA(isA<ParseException>()),
      );
      expect(
        array(r'\begin{alignat}{2} a&=b & c&=d \end{alignat}').tags!.map(text),
        ['(1)'],
      );
    });
  });

  group('{CD}', () {
    MatrixNode cd(String body) =>
        root('\\begin{CD}$body\\end{CD}') as MatrixNode;
    Iterable<GreenNode> all(GreenNode node) sync* {
      yield node;
      for (final child in node.children) {
        if (child != null) yield* all(child);
      }
    }

    test('object rows alternate cells and arrows', () {
      final m = cd(r'A @>f>> B \\ @VgVV @AAhA \\ C @<<< D');
      expect(m.isCD, isTrue);
      // 3 parsed rows plus KaTeX's trailing empty row; 3 columns.
      expect(m.rows, 4);
      expect(m.cols, 3);
      final arrows = all(m).whereType<StretchyOpNode>().toList();
      expect(arrows.map((a) => a.symbol), ['→', '←']);
      expect(arrows.every((a) => a.isCD), isTrue);
      final vert = all(m).whereType<CdVertArrowNode>().toList();
      expect(vert.map((a) => a.delim), ['↓', '↑']);
      expect(vert.first.left, isNotNull);
      expect(vert.first.right, isNull);
      expect(vert.last.right, isNotNull);
    });
    test('equals, parallel and empty arrows', () {
      final m = cd(r'A @= B @. C \\ @| @. @|');
      expect(all(m).whereType<StretchyOpNode>().single.symbol, '=');
      expect(all(m).whereType<CdVertArrowNode>().length, 2);
    });
    test('malformed arrows are parse errors', () {
      expect(() => cd(r'A @>f> B'), throwsA(isA<ParseException>()));
      expect(() => cd(r'A @x B'), throwsA(isA<ParseException>()));
    });
  });
}
