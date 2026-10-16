import 'package:flutter_equation_support/src/ast/nodes/symbol.dart';
import 'package:flutter_equation_support/src/ast/syntax_tree.dart';
import 'package:flutter_equation_support/src/ast/types.dart';
import 'package:flutter_equation_support/src/font/metrics/font_metrics.dart';
import 'package:flutter_equation_support/src/parser/tex/parser.dart';
import 'package:flutter_equation_support/src/parser/tex/settings.dart';
import 'package:flutter_equation_support/src/utils/math_alphanumeric.dart';
import 'package:flutter_test/flutter_test.dart';

SymbolNode symbol(String tex) {
  final node = TexParser(
    tex,
    const TexParserSettings(strict: Strict.ignore),
  ).parse().children.single;
  return node is SymbolNode
      ? node
      : node.children.single!.children.single! as SymbolNode;
}

void main() {
  group('KaTeX 0.19 symbols', () {
    test('typed Unicode operators are binary operators', () {
      for (final op in ['−', '∗', '∘', '∖', '∙', '◯']) {
        expect(symbol(op).atomType, AtomType.bin, reason: op);
      }
    });
    test('\\origof / \\imageof are relations', () {
      expect(symbol(r'\origof').atomType, AtomType.rel);
      expect(symbol('⊷').atomType, AtomType.rel);
    });
    test('\\P and \\S work in math and text mode', () {
      expect(symbol(r'\P').symbol, '¶');
      expect(symbol(r'\text{\S}').symbol, '§');
    });
    test('middle dot is punct in math and allowed in text', () {
      expect(symbol('·').atomType, AtomType.punct);
      expect(symbol(r'\text{·}').symbol, '⋅');
    });
    test('\\imath uses the private-use Math-Italic glyph', () {
      expect(symbol(r'\imath').symbol, '');
      expect(symbol(r'\jmath').symbol, '');
    });
  });

  group('math alphanumerics', () {
    test('Word-style italic letters map to plain letters in Math-Italic', () {
      final x = decodeMathAlphanumeric('𝑥')!;
      expect(x.base, 'x');
      expect(x.font.fontName, 'Math-Italic');
    });
    test('styles map to the matching KaTeX faces', () {
      expect(decodeMathAlphanumeric('𝐀')!.font.fontName, 'Main-Bold');
      expect(decodeMathAlphanumeric('𝔸')!.font.fontName, 'AMS-Regular');
      expect(decodeMathAlphanumeric('ℝ')!.base, 'R');
      expect(decodeMathAlphanumeric('𝔤')!.font.fontName, 'Fraktur-Regular');
      expect(decodeMathAlphanumeric('𝕬')!.font.fontName, 'Fraktur-Bold');
      expect(decodeMathAlphanumeric('𝟏')!.base, '1');
      expect(decodeMathAlphanumeric('ℎ')!.base, 'h');
    });
    test('Greek: 𝛼 is α, 𝚨 is bold Α', () {
      expect(decodeMathAlphanumeric('𝛼')!.base, 'α');
      expect(decodeMathAlphanumeric('𝚨')!.base, 'Α');
      expect(decodeMathAlphanumeric('𝟋')!.base, 'ϝ');
    });
    test('ordinary characters are not touched', () {
      expect(decodeMathAlphanumeric('x'), isNull);
      expect(decodeMathAlphanumeric('ℜ'), isNull, reason: 'owned by \\Re');
      expect(decodeMathAlphanumeric('😀'), isNull);
    });
    test('parser applies the mapping', () {
      final node = symbol('𝑥');
      expect(node.symbol, 'x');
      expect(node.overrideFont!.fontName, 'Math-Italic');
    });
  });

  group('font metrics lookup', () {
    test('Latin-1 and Cyrillic letters are measured via extraCharacterMap', () {
      for (final (char, base) in [('ç', 'c'), ('Ð', 'D'), ('д', 'y')]) {
        final m = getCharacterMetrics(
          character: char,
          fontName: 'Main-Regular',
          mode: Mode.text,
        );
        final plain = getCharacterMetrics(
          character: base,
          fontName: 'Main-Regular',
          mode: Mode.text,
        );
        expect(m, isNotNull, reason: char);
        expect(m!.width, plain!.width, reason: char);
      }
    });
    test('a face without its own table uses the Regular one', () {
      expect(
        getCharacterMetrics(
          character: 'x',
          fontName: 'Typewriter-Bold',
          mode: Mode.text,
        ),
        isNotNull,
      );
      expect(
        getCharacterMetrics(
          character: 'A',
          fontName: 'Fraktur-Bold',
          mode: Mode.math,
        ),
        isNotNull,
      );
    });
    test('an unknown family returns null instead of throwing', () {
      expect(
        getCharacterMetrics(
          character: 'x',
          fontName: 'Nope-Regular',
          mode: Mode.math,
        ),
        isNull,
      );
    });
  });
}
