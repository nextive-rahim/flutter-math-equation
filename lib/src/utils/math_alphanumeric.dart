import 'dart:ui' show FontStyle, FontWeight;

import '../ast/options.dart';

/// A Unicode mathematical alphanumeric character (𝑥, 𝐀, ℝ, 𝔤, 𝟙 …) resolved
/// to the plain character it styles and the KaTeX font that draws that style.
class MathAlphanumeric {
  /// The plain letter, digit or Greek character, e.g. `x` for `𝑥`.
  final String base;

  /// The font that gives [base] the style the code point encodes.
  final FontOptions font;

  const MathAlphanumeric(this.base, this.font);
}

const _bold = FontOptions(fontWeight: FontWeight.bold);
const _italic = FontOptions(fontFamily: 'Math', fontShape: FontStyle.italic);
const _boldItalic = FontOptions(
  fontFamily: 'Math',
  fontWeight: FontWeight.bold,
  fontShape: FontStyle.italic,
  fallback: [
    FontOptions(fontWeight: FontWeight.bold, fontShape: FontStyle.italic),
  ],
);
const _script = FontOptions(fontFamily: 'Script');
const _fraktur = FontOptions(fontFamily: 'Fraktur');
const _boldFraktur = FontOptions(
  fontFamily: 'Fraktur',
  fontWeight: FontWeight.bold,
);
const _doubleStruck = FontOptions(fontFamily: 'AMS');
const _sans = FontOptions(fontFamily: 'SansSerif');
const _boldSans = FontOptions(
  fontFamily: 'SansSerif',
  fontWeight: FontWeight.bold,
);
const _italicSans = FontOptions(
  fontFamily: 'SansSerif',
  fontShape: FontStyle.italic,
);
const _boldItalicSans = FontOptions(
  fontFamily: 'SansSerif',
  fontWeight: FontWeight.bold,
  fallback: [_italicSans],
);
const _mono = FontOptions(fontFamily: 'Typewriter');

/// Rows of 26 letters from U+1D400, alternating capitals and small letters,
/// in the order of the Unicode chart. Same grouping as KaTeX's
/// wide-character.ts, but every style is drawn from a real KaTeX face by
/// mapping to the plain letter, rather than leaving the platform to find a
/// font that has the code point.
const _latinRows = <FontOptions>[
  _bold, _bold, //
  _italic, _italic,
  _boldItalic, _boldItalic,
  _script, _script, // KaTeX's script face has capitals only
  _script, _script, // bold script: no bold face, use regular
  _fraktur, _fraktur,
  _doubleStruck, _doubleStruck,
  _boldFraktur, _boldFraktur,
  _sans, _sans,
  _boldSans, _boldSans,
  _italicSans, _italicSans,
  _boldItalicSans, _boldItalicSans,
  _mono, _mono,
];

/// Digit rows of ten from U+1D7CE.
const _digitRows = <FontOptions>[
  _bold,
  _doubleStruck, // no double-struck digits in KaTeX's fonts; AMS falls back
  _sans,
  _boldSans,
  _mono,
];

/// The 58 characters of each Greek group, in chart order.
const _greek = 'ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡϴΣΤΥΦΧΨΩ∇αβγδεζηθικλμνξοπρςστυφχψω∂ϵϑϰϕϱϖ';

/// Greek groups from U+1D6A8: bold, italic, bold italic, sans bold, sans
/// bold italic.
const _greekGroups = <FontOptions>[
  FontOptions(
    fontWeight: FontWeight.bold,
    fallback: [
      FontOptions(
        fontFamily: 'Math',
        fontWeight: FontWeight.bold,
        fontShape: FontStyle.italic,
      ),
    ],
  ),
  _italic,
  _boldItalic,
  FontOptions(
    fontFamily: 'SansSerif',
    fontWeight: FontWeight.bold,
    fallback: [FontOptions(fontWeight: FontWeight.bold)],
  ),
  FontOptions(
    fontFamily: 'SansSerif',
    fontWeight: FontWeight.bold,
    fallback: [_boldItalic],
  ),
];

/// Letterlike-block characters that fill the holes Unicode left in the
/// alphanumeric block (ℝ for the missing double-struck R, ℎ for italic h …).
/// ℜ and ℑ are not listed: TeX's \Re and \Im already own them.
const _letterlike = <int, MathAlphanumeric>{
  0x210E: MathAlphanumeric('h', _italic), // ℎ planck constant
  0x212C: MathAlphanumeric('B', _script), // ℬ
  0x2130: MathAlphanumeric('E', _script), // ℰ
  0x2131: MathAlphanumeric('F', _script), // ℱ
  0x210B: MathAlphanumeric('H', _script), // ℋ
  0x2110: MathAlphanumeric('I', _script), // ℐ
  0x2112: MathAlphanumeric('L', _script), // ℒ
  0x2133: MathAlphanumeric('M', _script), // ℳ
  0x211B: MathAlphanumeric('R', _script), // ℛ
  0x212D: MathAlphanumeric('C', _fraktur), // ℭ
  0x210C: MathAlphanumeric('H', _fraktur), // ℌ
  0x2128: MathAlphanumeric('Z', _fraktur), // ℨ
  0x2102: MathAlphanumeric('C', _doubleStruck), // ℂ
  0x210D: MathAlphanumeric('H', _doubleStruck), // ℍ
  0x2115: MathAlphanumeric('N', _doubleStruck), // ℕ
  0x2119: MathAlphanumeric('P', _doubleStruck), // ℙ
  0x211A: MathAlphanumeric('Q', _doubleStruck), // ℚ
  0x211D: MathAlphanumeric('R', _doubleStruck), // ℝ
  0x2124: MathAlphanumeric('Z', _doubleStruck), // ℤ
};

/// Resolves [character] (one code point, possibly a surrogate pair) when it
/// is a mathematical alphanumeric symbol; null otherwise.
MathAlphanumeric? decodeMathAlphanumeric(String character) {
  final runes = character.runes;
  if (runes.length != 1) return null;
  final cp = runes.first;

  final letterlike = _letterlike[cp];
  if (letterlike != null) return letterlike;

  if (cp >= 0x1D400 && cp <= 0x1D6A3) {
    final offset = cp - 0x1D400;
    final row = offset ~/ 26;
    final index = offset % 26;
    final base = String.fromCharCode(
      (row.isEven ? 0x41 : 0x61) + index, // A–Z on even rows, a–z on odd
    );
    return MathAlphanumeric(base, _latinRows[row]);
  }
  // Mathematical italic dotless i / j: KaTeX's \imath / \jmath glyphs.
  if (cp == 0x1D6A4) return const MathAlphanumeric('', _italic);
  if (cp == 0x1D6A5) return const MathAlphanumeric('', _italic);

  if (cp >= 0x1D6A8 && cp <= 0x1D7C9) {
    final offset = cp - 0x1D6A8;
    final group = offset ~/ 58;
    return MathAlphanumeric(
      String.fromCharCode(_greek.codeUnitAt(offset % 58)),
      _greekGroups[group],
    );
  }
  // U+1D7CA/1D7CB: bold Ϝ ϝ (digamma).
  if (cp == 0x1D7CA) return const MathAlphanumeric('Ϝ', _bold);
  if (cp == 0x1D7CB) return const MathAlphanumeric('ϝ', _bold);

  if (cp >= 0x1D7CE && cp <= 0x1D7FF) {
    final offset = cp - 0x1D7CE;
    return MathAlphanumeric(
      String.fromCharCode(0x30 + offset % 10),
      _digitRows[offset ~/ 10],
    );
  }
  return null;
}
