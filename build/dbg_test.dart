import 'package:flutter_equation_support/src/parser/tex/parse_error.dart';
import 'package:flutter_equation_support/src/parser/tex/parser.dart';
import 'package:flutter_equation_support/src/parser/tex/settings.dart';
import 'package:flutter_test/flutter_test.dart';
void main() {
  test('x', () {
    for (final tex in [r'\sin\,x', r'\log \quad x', r'\operatorname{rank}\quad A', r'\lim_{x} \, f', r'\sin\!x', r'\max_i \; a_i', r'\sin', r'\sin \frac12', r'\det\left(A\right)']) {
      try { TexParser(tex, const TexParserSettings(strict: Strict.ignore)).parse(); print('OK   $tex'); }
      on ParseException catch (e) { print('FAIL $tex -> ${e.message}'); }
    }
  });
}
