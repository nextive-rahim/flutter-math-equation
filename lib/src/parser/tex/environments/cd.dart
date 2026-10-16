// Ported from KaTeX 0.19.0 src/environments/cd.ts
// (MIT, Copyright (c) 2013-2020 Khan Academy and other contributors).

import '../../../ast/nodes/cd_vert_arrow.dart';
import '../../../ast/nodes/matrix.dart';
import '../../../ast/nodes/stretchy_op.dart';
import '../../../ast/nodes/style.dart';
import '../../../ast/nodes/symbol.dart';
import '../../../ast/options.dart';
import '../../../ast/style.dart';
import '../../../ast/syntax_tree.dart';
import '../define_environment.dart';
import '../macros.dart';
import '../parse_error.dart';
import '../parser.dart';

const cdEntries = {
  // amscd commutative diagrams. Like the other AMS environments, display
  // mode is not enforced (a documented deviation from KaTeX).
  ['CD']: EnvSpec(numArgs: 0, handler: _cdHandler),
};

GreenNode _cdHandler(TexParser parser, EnvContext context) => parseCD(parser);

bool _isStartOfArrow(GreenNode node) =>
    node is SymbolNode && node.symbol == '@';

String? _arrowChar(GreenNode node) {
  if (node is! SymbolNode) return null;
  // `|` may come out as the divides sign.
  return node.symbol == '∣' ? '|' : node.symbol;
}

bool _isLabelEnd(GreenNode node, String endChar) =>
    node is SymbolNode && node.symbol == endChar;

/// CD is always display style.
EquationRowNode _cell(List<GreenNode> body) => StyleNode(
  children: body,
  optionsDiff: const OptionsDiff(style: MathStyle.display),
).wrapWithEquationRow();

GreenNode _cdArrow(String arrowChar, List<List<GreenNode>> labels) {
  EquationRowNode? label(int i) =>
      labels[i].isEmpty ? null : labels[i].wrapWithEquationRow();
  switch (arrowChar) {
    case '>':
    case '<':
      return StretchyOpNode(
        above: labels[0].wrapWithEquationRow(),
        below: label(1),
        symbol: arrowChar == '>' ? '→' : '←',
        isCD: true,
      );
    case '=':
      return StretchyOpNode(
        above: EquationRowNode.empty(),
        below: null,
        symbol: '=',
        isCD: true,
      );
    case 'A':
    case 'V':
      return CdVertArrowNode(
        delim: arrowChar == 'A' ? '↑' : '↓',
        left: label(0),
        right: label(1),
      );
    case '|':
      return CdVertArrowNode(delim: '∥');
    default: // '.': no arrow
      return EquationRowNode.empty();
  }
}

/// Parses the body of `\begin{CD}…\end{CD}` (KaTeX parseCD): rows split at
/// `\\`; within a row, `@` starts an arrow and everything else falls into
/// the implicit object cells between arrows.
MatrixNode parseCD(TexParser parser) {
  final expander = parser.macroExpander;
  final parsedRows = <List<GreenNode>>[];
  expander.beginGroup();
  // Here `\\` is a macro for \newline; inside CD both it and \cr end a
  // row, as in KaTeX (which maps \cr to `\\\relax`).
  expander.macros.set('\\\\', MacroDefinition.fromString('\\cr'));
  expander.beginGroup();
  while (true) {
    parsedRows.add(
      parser.parseExpression(breakOnInfix: false, breakOnTokenText: '\\cr'),
    );
    expander.endGroup();
    expander.beginGroup();
    final next = parser.fetch().text;
    if (next == '&' || next == '\\cr') {
      parser.consume();
    } else if (next == '\\end') {
      if (parsedRows.last.isEmpty) parsedRows.removeLast(); // ended in \\
      break;
    } else {
      throw ParseException('Expected \\\\ or \\cr or \\end', parser.nextToken);
    }
  }

  var row = <EquationRowNode>[];
  final body = [row];
  for (var i = 0; i < parsedRows.length; i++) {
    final rowNodes = parsedRows[i];
    var cell = <GreenNode>[];
    for (var j = 0; j < rowNodes.length; j++) {
      if (!_isStartOfArrow(rowNodes[j])) {
        cell.add(rowNodes[j]);
        continue;
      }
      row.add(_cell(cell));

      // The character after @ gives the kind of arrow.
      j += 1;
      final arrowChar = j < rowNodes.length ? _arrowChar(rowNodes[j]) : null;
      if (arrowChar == null || !'<>AV=|.'.contains(arrowChar)) {
        throw ParseException('Expected one of "<>AV=|." after @');
      }
      final labels = <List<GreenNode>>[[], []];
      if ('<>AV'.contains(arrowChar)) {
        // @>{above}>{below}> : two labels, each closed by the arrow char.
        for (var labelNum = 0; labelNum < 2; labelNum++) {
          var inLabel = true;
          for (var k = j + 1; k < rowNodes.length; k++) {
            if (_isLabelEnd(rowNodes[k], arrowChar)) {
              inLabel = false;
              j = k;
              break;
            }
            if (_isStartOfArrow(rowNodes[k])) {
              throw ParseException(
                'Missing a $arrowChar character to complete a CD arrow.',
              );
            }
            labels[labelNum].add(rowNodes[k]);
          }
          if (inLabel) {
            throw ParseException(
              'Missing a $arrowChar character to complete a CD arrow.',
            );
          }
        }
      }
      row.add(_cell([_cdArrow(arrowChar, labels)]));
      cell = <GreenNode>[];
    }
    if (i.isEven) {
      // Object rows: cell, arrow, cell, arrow, … cell.
      row.add(_cell(cell));
    } else if (row.isNotEmpty) {
      // Arrow rows: vertical arrow, empty cell, vertical arrow, …
      row.removeAt(0);
    }
    row = [];
    body.add(row);
  }
  // KaTeX keeps the empty row opened after the last one; it still takes a
  // strut's height, so it is kept here too for the same vertical placement.

  expander.endGroup();
  expander.endGroup();

  return MatrixNode(body: body, isCD: true, hskipBeforeAndAfter: true);
}
