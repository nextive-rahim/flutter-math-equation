import 'package:flutter_equation_support/src/html/html_unescape.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decodeHtmlEntities', () {
    test('named references, with and without semicolon', () {
      expect(
        decodeHtmlEntities('2 &lt; 3 &amp;&amp; 4 &gt; 1'),
        '2 < 3 && 4 > 1',
      );
      expect(decodeHtmlEntities('a&nbsp;b'), 'a b');
      expect(decodeHtmlEntities('&amp'), '&', reason: 'legacy form');
    });
    test('longest match wins', () {
      expect(decodeHtmlEntities('&notin;'), '∉');
      expect(decodeHtmlEntities('&notit;'), '¬it;');
    });
    test('math entities common in exam HTML', () {
      expect(
        decodeHtmlEntities('&radic;2 &times; &pi; &le; &deg;'),
        '√2 × π ≤ °',
      );
      expect(decodeHtmlEntities('&NotGreaterFullEqual;'), '≧̸');
      expect(decodeHtmlEntities('&Aopf;'), '𝔸');
      expect(decodeHtmlEntities('&fjlig;'), 'fj');
    });
    test('numeric references', () {
      expect(decodeHtmlEntities('&#8730;&#x221A;&#X221A;'), '√√√');
      expect(decodeHtmlEntities('tail &#9;'), 'tail \t');
    });
    test('invalid numeric references become U+FFFD instead of throwing', () {
      expect(decodeHtmlEntities('&#0;'), '�');
      expect(decodeHtmlEntities('&#55296;'), '�');
      expect(decodeHtmlEntities('&#99999999;'), '�');
    });
    test('text that is not a reference is kept', () {
      expect(
        decodeHtmlEntities('AT&T fish &chips & co'),
        'AT&T fish &chips & co',
      );
      expect(decodeHtmlEntities('&#;&#x;&#12a;'), '&#;&#x;&#12a;');
      expect(decodeHtmlEntities('no entities'), 'no entities');
    });
  });
}
