import 'package:flutter_equation_support/src/ast/nodes/symbol.dart';
import 'package:flutter_equation_support/src/parser/tex/parse_error.dart';
import 'package:flutter_equation_support/src/parser/tex/parser.dart';
import 'package:flutter_equation_support/src/parser/tex/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('symbols', () {
    for (final tex in [r'\P', r'\S', r'\text{\P}', r'\text{\S}', '·', r'\text{·}',
        '∗', '−', '∘', '∖', '∙', '◯', r'\origof', r'\imageof', '⊶', '⊷',
        r'\varvdots', r'\text{\varvdots}', r'\text{\vdots}', '*', '-']) {
      try {
        final row = TexParser(tex, const TexParserSettings(strict: Strict.ignore)).parse();
        final n = row.children.single;
        final inner = n is SymbolNode ? n : (n.children.single?.children.single);
        if (inner is SymbolNode) {
          print('$tex => ${inner.symbol.runes.map((r) => r.toRadixString(16)).join(' ')} ${inner.atomType} ${inner.mode}');
        } else {
          print('$tex => ${n.runtimeType}');
        }
      } on ParseException catch (e) {
        print('$tex => ERROR ${e.message}');
      }
    }
  });
}
