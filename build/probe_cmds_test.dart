import 'package:flutter_equation_support/src/parser/tex/parse_error.dart';
import 'package:flutter_equation_support/src/parser/tex/parser.dart';
import 'package:flutter_equation_support/src/parser/tex/settings.dart';
import 'package:flutter_test/flutter_test.dart';
void main() {
  test('probe', () {
    for (final tex in [r'\vcentcolon', r'\textcircled{c}', r'\coppa', r'\text{\r A}', r'\angl{n}', r'\mapsto', r'\mbox{a}', r'\TextOrMath{a}{b}', r'\nobreakspace', r'\DOTSB', r'\char`a', r'\mathrel{=}', r'\kern0.5px x', r'\@ifstar', r'\mathpunct{:}', r'\mskip6mu', r'\tiny x']) {
      try {
        TexParser(tex, const TexParserSettings(strict: Strict.ignore)).parse();
        print('OK   $tex');
      } on ParseException catch (e) {
        print('FAIL $tex -> ${e.message}');
      }
    }
  });
}
