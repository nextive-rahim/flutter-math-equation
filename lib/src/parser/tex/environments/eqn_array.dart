// The MIT License (MIT)
//
// Copyright (c) 2013-2019 Khan Academy and other contributors
// Copyright (c) 2020 znjameswu <znjameswu@gmail.com>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import 'package:collection/collection.dart';

import '../../../ast/nodes/equation_array.dart';
import '../../../ast/nodes/left_right.dart';
import '../../../ast/nodes/matrix.dart';
import '../../../ast/nodes/space.dart';
import '../../../ast/nodes/style.dart';
import '../../../ast/nodes/symbol.dart';
import '../../../ast/options.dart';
import '../../../ast/size.dart';
import '../../../ast/style.dart';
import '../../../ast/syntax_tree.dart';
import '../../../ast/types.dart';
import '../define_environment.dart';
import '../functions/katex_base.dart';
import '../macros.dart';
import '../parse_error.dart';
import '../parser.dart';
import 'array.dart';

const eqnArrayEntries = {
  ['cases', 'dcases', 'rcases', 'drcases']: EnvSpec(
    numArgs: 0,
    handler: _casesHandler,
  ),
  // align is numbered, align* takes \tag only, aligned and split have no
  // tags. (KaTeX restricts the AMS display environments to display mode;
  // they are accepted everywhere here, like \tag.)
  ['aligned', 'align', 'align*', 'split']: EnvSpec(
    numArgs: 0,
    handler: _alignedHandler,
  ),
  ['alignedat', 'alignat', 'alignat*']: EnvSpec(
    numArgs: 1,
    handler: _alignedAtHandler,
  ),
  ['gathered', 'gather', 'gather*']: EnvSpec(
    numArgs: 0,
    handler: _gatheredHandler,
  ),
  ['equation', 'equation*']: EnvSpec(numArgs: 0, handler: _equationHandler),
};

/// KaTeX getAutoTag: numbered unless starred, for the AMS display
/// environments; no tags at all for the `…ed` inner environments.
bool? _autoTag(String envName) =>
    envName.contains('ed') ? null : !envName.contains('*');

GreenNode _casesHandler(TexParser parser, EnvContext context) {
  final display = context.envName == 'dcases' || context.envName == 'drcases';
  final body = parseEqnArray(
    parser,
    // KaTeX array.ts: {cases} is an array with \arraystretch 1.2.
    arrayStretch: 1.2,
    concatRow: (cells) {
      final children = [
        SpaceNode.alignerOrSpacer(),
        if (cells.isNotEmpty) ...cells[0].children,
        if (cells.length > 1) SpaceNode.alignerOrSpacer(),
        if (cells.length > 1)
          SpaceNode(height: Measurement.zero, width: 1.0.em, mode: Mode.math),
      ];
      for (var i = 1; i < cells.length; i++) {
        children.add(SpaceNode.alignerOrSpacer());
        children.addAll(cells[i].children);
        children.add(SpaceNode.alignerOrSpacer());
      }
      // Cells are set in text style ({cases}) or display style ({dcases}),
      // whatever the surrounding style is.
      return EquationRowNode(
        children: [
          StyleNode(
            optionsDiff: OptionsDiff(
              style: display ? MathStyle.display : MathStyle.text,
            ),
            children: children,
          ),
        ],
      );
    },
  );
  if (context.envName == 'rcases' || context.envName == 'drcases') {
    return LeftRightNode(
      leftDelim: null,
      rightDelim: '}',
      body: [body.wrapWithEquationRow()],
    );
  } else {
    return LeftRightNode(
      leftDelim: '{',
      rightDelim: null,
      body: [body.wrapWithEquationRow()],
    );
  }
}

GreenNode _alignedHandler(TexParser parser, EnvContext context) {
  final isSplit = context.envName == 'split';
  return parseEqnArray(
    parser,
    addJot: true,
    emptySingleRow: true,
    autoTag: isSplit ? null : _autoTag(context.envName),
    maxNumCols: isSplit ? 2 : null,
    concatRow: (cells) => alignRow(cells, pairGap: true),
  );
}

/// One centred column per row, display style, \jot between rows.
GreenNode _gatheredHandler(TexParser parser, EnvContext context) =>
    parseEqnArray(
      parser,
      addJot: true,
      emptySingleRow: true,
      autoTag: _autoTag(context.envName),
      concatRow: (cells) => EquationRowNode(
        children: [
          StyleNode(
            optionsDiff: const OptionsDiff(style: MathStyle.display),
            children: [
              for (final cell in cells) ...[
                ...cell.children,
                SpaceNode.alignerOrSpacer(),
              ],
            ],
          ),
        ],
      ),
    );

/// A single display formula, numbered ({equation}) or taking \tag
/// ({equation*}); `&` is an error.
GreenNode _equationHandler(TexParser parser, EnvContext context) =>
    parseEqnArray(
      parser,
      emptySingleRow: true,
      singleRow: true,
      maxNumCols: 1,
      autoTag: _autoTag(context.envName),
      concatRow: (cells) => EquationRowNode(
        children: [
          StyleNode(
            optionsDiff: const OptionsDiff(style: MathStyle.display),
            children: cells.single.children,
          ),
        ],
      ),
    );

/// One row of an aligning environment: cells alternate right/left aligned
/// columns, set in display style (KaTeX array.ts `alignedHandler`). With
/// [pairGap], every column pair after the first starts 1em further right
/// ({aligned}, {align}); {alignedat}/{alignat} put no space between pairs.
EquationRowNode alignRow(List<EquationRowNode> cells, {required bool pairGap}) {
  final children = <GreenNode>[];
  for (var i = 0; i < cells.length; i++) {
    if (pairGap && i > 0 && i.isEven) {
      children.add(
        SpaceNode(height: Measurement.zero, width: 1.0.em, mode: Mode.math),
      );
    }
    children
      ..addAll(cells[i].children)
      ..add(SpaceNode.alignerOrSpacer());
  }
  return EquationRowNode(
    children: [
      StyleNode(
        optionsDiff: const OptionsDiff(style: MathStyle.display),
        children: children,
      ),
    ],
  );
}

// GreenNode _gatheredHandler(TexParser parser, EnvContext context) {}

GreenNode _alignedAtHandler(TexParser parser, EnvContext context) {
  final arg = parser.parseArgNode(mode: null, optional: false);
  final numNode = assertNodeType<EquationRowNode>(arg);
  final string = numNode.children
      .map((e) => assertNodeType<SymbolNode>(e).symbol)
      .join('');
  final cols = RegExp(r'^[0-9]+$').hasMatch(string) ? int.parse(string) : null;
  if (cols == null || cols < 1) {
    throw ParseException('Number of columns should be a positive integer');
  }
  return parseEqnArray(
    parser,
    addJot: true,
    emptySingleRow: true,
    autoTag: _autoTag(context.envName),
    concatRow: (cells) {
      if (cells.length > 2 * cols) {
        throw ParseException(
          'Too many math in a row: '
          'expected ${2 * cols}, but got ${cells.length}',
        );
      }
      return alignRow(cells, pairGap: false);
    },
  );
}

/// Parses the body of an aligning environment into an [EquationArrayNode]
/// (KaTeX environments/array.ts `parseArray`, for the engine's equation
/// arrays).
///
/// [autoTag]: null for no tags at all ({aligned}, {gathered}, {split}),
/// true for automatic numbering ({align}, {gather}, {equation}), false for
/// `\tag` only (the starred forms). [singleRow] parses up to `\end` with no
/// row breaks ({equation}); [maxNumCols] limits the cells per row.
EquationArrayNode parseEqnArray(
  TexParser parser, {
  bool addJot = false,
  bool emptySingleRow = false,
  double? arrayStretch,
  bool? autoTag,
  bool singleRow = false,
  int? maxNumCols,
  required EquationRowNode Function(List<EquationRowNode> cells) concatRow,
}) {
  final macros = parser.macroExpander.macros;
  // Parse body of array with \\ temporarily mapped to \cr
  parser.macroExpander.beginGroup();
  if (!singleRow) {
    macros.set('\\\\', MacroDefinition.fromString('\\cr'));
  }

  // Get current arraystretch if it's not set by the environment
  if (arrayStretch == null) {
    final stretch = parser.macroExpander.expandMacroAsText('\\arraystretch');
    if (stretch == null) {
      // Default \arraystretch from lttab.dtx
      arrayStretch = 1.0;
    } else {
      arrayStretch = double.tryParse(stretch);
      if (arrayStretch == null || arrayStretch < 0) {
        throw ParseException('Invalid \\arraystretch: $stretch');
      }
    }
  }

  // Start group for first cell
  parser.macroExpander.beginGroup();

  var row = <EquationRowNode>[];
  final body = [row];
  final rowGaps = <Measurement>[];
  final hLinesBeforeRow = <MatrixSeparatorStyle>[];
  final hLineExtras = <List<MatrixSeparatorStyle>>[];
  void addHLines(List<MatrixSeparatorStyle> lines) {
    hLinesBeforeRow.add(lines.firstOrNull ?? MatrixSeparatorStyle.none);
    hLineExtras.add(lines.skip(1).toList(growable: false));
  }

  // One entry per row: a manual tag, an automatic one (true) or none.
  final tags = autoTag != null ? <Object>[] : null;

  // amsmath tracks with \global\@eqnswtrue/false whether a row gets a
  // number; simulated with a \@eqnsw macro set to 1 or 0.
  void beginRow() {
    if (autoTag == true) {
      macros.set('\\@eqnsw', MacroDefinition.fromString('1'), global: true);
    }
  }

  void endRow() {
    if (tags == null) return;
    final manual = parser.takeManualTag();
    if (manual != null) {
      tags.add(manual);
    } else {
      tags.add(
        autoTag == true &&
            parser.macroExpander.expandMacroAsText('\\@eqnsw') == '1',
      );
    }
  }

  beginRow();

  // Test for \hline at the top of the array.
  addHLines(getHLines(parser));

  while (true) {
    // Parse each cell in its own group (namespace)
    final cellBody = parser.parseExpression(
      breakOnInfix: false,
      breakOnTokenText: singleRow ? '\\end' : '\\cr',
    );
    parser.macroExpander.endGroup();
    parser.macroExpander.beginGroup();

    final cell = cellBody.wrapWithEquationRow();
    row.add(cell);

    final next = parser.fetch().text;
    if (next == '&') {
      if (maxNumCols != null && row.length == maxNumCols) {
        throw ParseException('Too many tab characters: &', parser.nextToken);
      }
      parser.consume();
    } else if (next == '\\end') {
      endRow();
      // Arrays terminate newlines with `\crcr` which consumes a `\cr` if
      // the last line is empty. AMS environments keep the empty row when it
      // is the only one, has a manual tag, or is an automatically numbered
      // row explicitly ended with `\\` (KaTeX 0.13.3, 0.18.6, 0.18.8). The
      // ported check tested for a StyleNode, which a cell never is, so a
      // trailing `\\` always left a blank row.
      final lastTag = tags?.lastOrNull;
      if (row.length == 1 &&
          cell.children.isEmpty &&
          (body.length > 1 || !emptySingleRow) &&
          lastTag is! EquationRowNode &&
          !(autoTag == true && lastTag == true)) {
        body.removeLast();
        tags?.removeLast();
      }
      if (hLinesBeforeRow.length < body.length + 1) {
        addHLines(const []);
      }
      break;
    } else if (next == '\\cr') {
      final cr = assertNodeType<CrNode>(parser.parseFunction(null, null, null));
      rowGaps.add(cr.size ?? Measurement.zero);
      endRow();

      // check for \hline(s) following the row separator
      addHLines(getHLines(parser));

      row = [];
      body.add(row);
      beginRow();
    } else {
      throw ParseException(
        'Expected & or \\\\ or \\cr or \\end',
        parser.nextToken,
      );
    }
  }

  // End cell group
  parser.macroExpander.endGroup();
  // End array group defining \\
  parser.macroExpander.endGroup();

  final rows = body.map<EquationRowNode>(concatRow).toList();

  return EquationArrayNode(
    arrayStretch: arrayStretch,
    hlines: hLinesBeforeRow,
    hLineExtras: hLineExtras,
    rowSpacings: rowGaps,
    addJot: addJot,
    body: rows,
    tags: tags == null
        ? null
        : [
            for (final tag in tags)
              tag is EquationRowNode
                  ? tag
                  : tag == true
                  ? parser.takeEquationNumber()
                  : null,
          ],
    leqno: parser.settings.leqno,
  );
}
