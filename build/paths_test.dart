import 'dart:convert';
import 'dart:io';
import 'package:flutter_equation_support/src/render/svg/svg_geomertry.dart';
import 'package:flutter_test/flutter_test.dart';
void main() {
  test('paths match KaTeX', () {
    final expected = (jsonDecode(File('/private/tmp/claude-501/-Users-abdulrahim-flutter-projects-etestpaper-app/6c7d47bf-a6b6-435f-a0b3-2dd0306083fa/scratchpad/pathcheck/katex_paths.json').readAsStringSync()) as Map).cast<String, String>();
    var mismatches = 0;
    for (final h in [0, 1, 517, 2400]) {
      for (final n in ['⎜','∣','∥','⎟','⎢','⎥','⎪','⏐','‖']) {
        final key = 'inner ${n.codeUnitAt(0).toRadixString(16)} $h';
        if (innerPath(n, h) != expected[key]) { mismatches++; print('MISMATCH $key'); }
      }
      for (final l in ['lbrack','rbrack','vert','doublevert','lfloor','rfloor','lceil','rceil','lparen','rparen']) {
        final key = 'tall $l $h';
        if (tallDelim(l, h) != expected[key]) { mismatches++; print('MISMATCH $key'); }
      }
    }
    print('checked ${expected.length} mismatches $mismatches');
  });
}
