import 'package:flutter/painting.dart';

import '../ast/nodes/symbol.dart';
import '../ast/syntax_tree.dart';

/// Font family bundled with this package for complex scripts (Bengali). Used
/// as the last fallback, after any family the caller's text style names.
const String bundledComplexScriptFontFamily =
    'packages/flutter_math_equation/NotoSansBengali';

/// Whether [codeUnit] belongs to a script whose glyphs only come out right
/// when a whole run is shaped together — conjuncts, vowel signs and other
/// combining marks attach to their neighbours (Bengali `ক্র`, `কি`).
///
/// Covers the Indic blocks (Devanagari through Sinhala), Thai, Lao and
/// Myanmar, plus the joiners and the danda that Bengali text uses.
bool isComplexScriptCodeUnit(int codeUnit) =>
    (codeUnit >= 0x0900 && codeUnit <= 0x0DFF) || // Devanagari … Sinhala
    (codeUnit >= 0x0E00 && codeUnit <= 0x0EFF) || // Thai, Lao
    (codeUnit >= 0x1000 && codeUnit <= 0x109F) || // Myanmar
    codeUnit == 0x200C || // zero-width non-joiner
    codeUnit == 0x200D || // zero-width joiner
    codeUnit == 0x25CC; // dotted circle, shown under a lone vowel sign

/// Whether every character of [text] is a complex-script character. All of
/// these blocks sit in the Basic Multilingual Plane, so code units suffice.
bool isComplexScriptText(String text) {
  if (text.isEmpty) return false;
  for (var i = 0; i < text.length; i++) {
    if (!isComplexScriptCodeUnit(text.codeUnitAt(i))) return false;
  }
  return true;
}

/// Bengali digits ০–৯ (U+09E6–U+09EF).
bool isBengaliDigit(int codeUnit) => codeUnit >= 0x09E6 && codeUnit <= 0x09EF;

/// Joins each run of adjacent complex-script [SymbolNode]s in [nodes] into a
/// single node, so the run is drawn as one shaped piece of text.
///
/// The parser emits one [SymbolNode] per character, and a node is drawn on
/// its own: `ক্রয়` came out as the five separate glyphs `ক ্ র য ়`, with
/// every conjunct and vowel sign broken. Merging happens after parsing, so
/// TeX's scoping is untouched — `x^১২` still raises only the `১` because the
/// `১` is already inside the script by the time this runs.
///
/// Nodes only merge when they would render identically on their own: same
/// mode, font, atom type, and no variant form.
List<GreenNode> mergeComplexScriptRuns(List<GreenNode> nodes) {
  if (nodes.length < 2) return nodes;
  final out = <GreenNode>[];
  var merged = false;
  for (final node in nodes) {
    final previous = out.isEmpty ? null : out.last;
    if (previous is SymbolNode &&
        node is SymbolNode &&
        _canMerge(previous, node)) {
      out[out.length - 1] = SymbolNode(
        symbol: previous.symbol + node.symbol,
        overrideAtomType: previous.overrideAtomType,
        overrideFont: previous.overrideFont,
        mode: previous.mode,
      );
      merged = true;
    } else {
      out.add(node);
    }
  }
  // Most rows have nothing to merge; hand back the original list for those.
  return merged ? out : nodes;
}

bool _canMerge(SymbolNode a, SymbolNode b) =>
    !a.variantForm &&
    !b.variantForm &&
    a.mode == b.mode &&
    a.overrideFont == b.overrideFont &&
    a.overrideAtomType == b.overrideAtomType &&
    isComplexScriptText(a.symbol) &&
    isComplexScriptText(b.symbol);

/// The prose fonts in [style], to draw complex-script runs and any other
/// character the KaTeX fonts lack. A KaTeX family is skipped: callers often
/// hand over a style already pointed at one, and it has no such glyphs.
List<String> fallbackFamiliesOf(TextStyle style) => [
  if (style.fontFamily != null && !_isKatexFamily(style.fontFamily!))
    style.fontFamily!,
  for (final family in style.fontFamilyFallback ?? const <String>[])
    if (!_isKatexFamily(family)) family,
];

bool _isKatexFamily(String family) =>
    family.startsWith('KaTeX_') || family.contains('/KaTeX_');
