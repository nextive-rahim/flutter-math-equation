/// Reports which commands and environments of a KaTeX release this
/// package's parser does not support.
///
/// ```sh
/// python3 tool/katex_commands.py path/to/KaTeX build/katex.json
/// KATEX_COMMANDS=build/katex.json \
///   flutter test tool/probe/katex_coverage_probe.dart
/// ```
///
/// The report is written to build/katex_coverage.json.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_math_equation/src/parser/tex/parse_error.dart';
import 'package:flutter_math_equation/src/parser/tex/parser.dart';
import 'package:flutter_math_equation/src/parser/tex/settings.dart';
import 'package:flutter_test/flutter_test.dart';

String? tryParse(String tex) {
  try {
    TexParser(tex, const TexParserSettings(strict: Strict.ignore)).parse();
    return null;
  } on ParseException catch (e) {
    return e.message;
  } catch (e) {
    return e.toString();
  }
}

bool isUndefined(String? e) =>
    e != null &&
    (e.contains('Undefined control sequence') ||
        e.contains('No such environment') ||
        e.contains('Unknown'));

void main() {
  test('probe KaTeX 0.19.0 coverage', () {
    final data = jsonDecode(
      File(Platform.environment['KATEX_COMMANDS']!).readAsStringSync(),
    );
    final missing = <String>[];
    final erroring = <String, String>{};
    for (final cmd in (data['commands'] as List).cast<String>()) {
      final attempts = [
        cmd,
        '$cmd{a}',
        '$cmd{a}{b}',
        '$cmd{a}{b}{c}',
        '$cmd[a]{b}',
        '$cmd[a]{b}{c}',
        '$cmd x',
        '$cmd(',
        '\\text{$cmd}',
        '\\text{$cmd{a}}',
        '$cmd{1}{a}{b}',
        '$cmd{2pt}',
        '$cmd{red}{a}',
        '$cmd{a}{b}{c}{d}',
        '\\left$cmd x \\right.',
      ];
      final errors = attempts.map(tryParse).toList();
      if (errors.any((e) => e == null)) continue;
      if (errors.every(isUndefined)) {
        missing.add(cmd);
      } else {
        erroring[cmd] = errors.firstWhere((e) => !isUndefined(e))!;
      }
    }
    final envMissing = <String>[];
    for (final env in (data['environments'] as List).cast<String>()) {
      final attempts = [
        '\\begin{$env}a\\end{$env}',
        '\\begin{$env}{c}a\\end{$env}',
        '\\begin{$env}{1}a&b\\end{$env}',
        '\\begin{$env}a&b\\\\c&d\\end{$env}',
      ];
      final errors = attempts.map(tryParse).toList();
      if (errors.any((e) => e == null)) continue;
      envMissing.add('$env :: ${errors.first}');
    }
    File(
      Platform.environment['KATEX_COVERAGE_OUT'] ?? 'build/katex_coverage.json',
    ).writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert({
        'missing': missing,
        'erroring': erroring,
        'envMissing': envMissing,
      }),
    );
  });
}
