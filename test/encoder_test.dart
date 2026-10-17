import 'package:flutter_math_equation/src/encoder/tex/encoder.dart';
import 'package:flutter_math_equation/src/parser/tex/parser.dart';
import 'package:flutter_math_equation/src/parser/tex/settings.dart';
import 'package:flutter_test/flutter_test.dart';

String encode(String tex) {
  final settings = const TexParserSettings(trust: true);
  return TexParser(
    tex,
    settings,
  ).parse().encodeTeX(conf: const TexEncodeConf(strict: Strict.error));
}

void main() {
  // Each formula encodes without loss, and re-encoding its encoding gives
  // the same TeX.
  const formulas = <String, String>{
    'spaces': r'a\,b\;c\quad d\qquad e\!f\hspace{2em}g',
    'rule': r'x\rule[1pt]{2em}{0.5em}y',
    'array': r'\begin{array}{c|l}a&b\\\hline c&d\end{array}',
    'pmatrix': r'\begin{pmatrix}1&2\\3&4\end{pmatrix}',
    'aligned': r'\begin{aligned}a&=b\\c&=d\end{aligned}',
    'boxes': r'\boxed{x}\colorbox{red}{y}\fcolorbox{blue}{red}{z}',
    'cancel': r'\cancel{a}\bcancel{b}\xcancel{c}\sout{d}\phase{e}\angl{n}',
    'box_ops': r'\smash[t]{a}\mathllap{b}\mathclap{c}\vcenter{d}',
    'choice': r'\mathchoice{a}{b}{c}{d}\mathreflectbox{e}',
    'sized_delims': r'\bigl(\Big[\biggm|\Biggr)',
    'accents': r'\text{\c{c}\textcircled{a}}',
    'graphics': r'\includegraphics[height=1em,alt=x]{a.png}',
    'cd': r'\begin{CD}A@>f>>B\\@VgVV@AAhA\\C@=D\end{CD}',
  };
  for (final MapEntry(key: name, value: tex) in formulas.entries) {
    test(name, () {
      final once = encode(tex);
      expect(encode(once), once, reason: 'encoded as $once');
    });
  }
}
