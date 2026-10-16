import 'html_entities.dart';

/// Decodes HTML character references (`&amp;`, `&nbsp;`, `&#8730;`,
/// `&#x221A;`) in [data].
///
/// Matching follows the HTML spec's longest-match rule over the full WHATWG
/// entity list, including the legacy forms without a semicolon (`&amp`), so
/// `&notin;` is `∉` while `&notit;` is `¬it;`. An `&` that starts no known
/// reference is kept as written. Numeric references outside Unicode decode
/// to U+FFFD instead of throwing.
String decodeHtmlEntities(String data) {
  if (!data.contains('&')) return data;

  final out = StringBuffer();
  var offset = 0;
  while (true) {
    final amp = data.indexOf('&', offset);
    if (amp < 0) {
      out.write(data.substring(offset));
      break;
    }
    out.write(data.substring(offset, amp));
    offset = amp;

    final numeric = _decodeNumeric(data, amp);
    if (numeric != null) {
      out.write(numeric.$1);
      offset = numeric.$2;
      continue;
    }

    final named = _decodeNamed(data, amp);
    if (named != null) {
      out.write(named.$1);
      offset = named.$2;
      continue;
    }

    out.write('&');
    offset = amp + 1;
  }
  return out.toString();
}

/// `&#123;` / `&#x7B;` / `&#X7B;` starting at [amp]: the decoded text and the
/// index just past the `;`. Null when [amp] does not start one.
(String, int)? _decodeNumeric(String data, int amp) {
  if (amp + 3 >= data.length || data.codeUnitAt(amp + 1) != 0x23) return null;
  final hex = data[amp + 2] == 'x' || data[amp + 2] == 'X';
  final digitsStart = amp + (hex ? 3 : 2);
  final semicolon = data.indexOf(';', digitsStart);
  if (semicolon < 0 || semicolon - digitsStart > 8) return null;
  final digits = data.substring(digitsStart, semicolon);
  if (digits.isEmpty || !(hex ? _hexDigits : _decimalDigits).hasMatch(digits)) {
    return null;
  }
  final code = int.parse(digits, radix: hex ? 16 : 10);
  final valid =
      code > 0 &&
      code <= 0x10FFFF &&
      !(code >= 0xD800 && code <= 0xDFFF); // lone surrogates
  return (String.fromCharCode(valid ? code : 0xFFFD), semicolon + 1);
}

final _hexDigits = RegExp(r'^[0-9a-fA-F]+$');
final _decimalDigits = RegExp(r'^[0-9]+$');

/// The longest named reference starting at [amp]: its text and the index
/// just past it.
(String, int)? _decodeNamed(String data, int amp) {
  final longest = data.length - amp < htmlEntityMaxLength
      ? data.length - amp
      : htmlEntityMaxLength;
  for (var length = longest; length >= 2; length--) {
    final value = htmlNamedEntities[data.substring(amp, amp + length)];
    if (value != null) return (value, amp + length);
  }
  return null;
}
