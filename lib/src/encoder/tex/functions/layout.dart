part of '../functions.dart';

/// TeX built by a function of the configuration, for constructs whose
/// arguments are not plain command arguments (environments, `\rule`, …).
class _TexTemplateEncodeResult extends EncodeResult {
  final String Function(TexEncodeConf conf) build;

  const _TexTemplateEncodeResult(this.build);

  @override
  String stringify(TexEncodeConf conf) => build(conf);
}

/// A braced math argument.
String _mathArg(GreenNode? node, TexEncodeConf conf) =>
    node == null ? '{}' : '{${encodeTex(node).stringify(conf.mathParam())}}';

/// A braced text argument.
String _textArg(GreenNode node, TexEncodeConf conf) =>
    '{${encodeTex(node).stringify(conf.textParam())}}';

/// [m] in units TeX understands (`cssEm` is written as `em`).
String _texLength(Measurement m) {
  final value = m.value == m.value.roundToDouble()
      ? m.value.toInt().toString()
      : m.value.toString();
  final unit = switch (m.unit) {
    Unit.cssEm => 'em',
    Unit.lp => 'px',
    final unit => unit.name,
  };
  return '$value$unit';
}

String _color(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

const _namedSpaces = {
  '3mu': '\\,',
  '4mu': '\\:',
  '5mu': r'\;',
  '-3mu': '\\!',
  '-4mu': '\\negmedspace',
  '-5mu': '\\negthickspace',
  '1em': '\\quad',
  '2em': '\\qquad',
};

EncodeResult _spaceEncoder(GreenNode node) {
  final space = node as SpaceNode;
  if (space.alignerOrSpacer) return const StaticEncodeResult('&');
  if (space.fill) {
    // \rule[raise]{width}{height}
    return _TexTemplateEncodeResult(
      (conf) =>
          '\\rule'
          '${space.shift.value == 0 ? '' : '[${_texLength(space.shift)}]'}'
          '{${_texLength(space.width)}}{${_texLength(space.height)}}',
    );
  }
  if (space.breakPenalty != null && space.width.value == 0) {
    return StaticEncodeResult(switch (space.breakPenalty!) {
      10000 => '\\nobreak',
      0 => '\\allowbreak',
      final penalty => '\\penalty$penalty',
    });
  }
  final length = _texLength(space.width);
  final named = _namedSpaces[length];
  if (named != null) return StaticEncodeResult(named);
  return StaticEncodeResult(
    space.mode == Mode.math ? '\\mkern$length' : '\\kern$length',
  );
}

/// The children of [row] without the [style] wrapper that an environment or
/// an hbox argument put around them; null when there is no such wrapper.
List<GreenNode>? _unwrapStyle(EquationRowNode row, MathStyle style) {
  if (row.children.length != 1) return null;
  final only = row.children.single;
  if (only is! StyleNode) return null;
  final diff = only.optionsDiff;
  final onlyStyle =
      diff.style == style &&
      diff.size == null &&
      diff.color == null &&
      diff.textFontOptions == null &&
      diff.mathFontOptions == null;
  return onlyStyle ? only.children : null;
}

EquationRowNode _withoutStyle(EquationRowNode row, MathStyle style) {
  final inner = _unwrapStyle(row, style);
  return inner == null ? row : EquationRowNode(children: inner);
}

String _matrixRows(
  List<List<GreenNode?>> rows,
  List<MatrixSeparatorStyle> hLines,
  List<Measurement> rowSpacings,
  TexEncodeConf conf,
) {
  String hline(int i) => i >= hLines.length
      ? ''
      : switch (hLines[i]) {
          MatrixSeparatorStyle.solid => '\\hline ',
          MatrixSeparatorStyle.dashed => '\\hdashline ',
          MatrixSeparatorStyle.none => '',
        };
  final out = StringBuffer(hline(0));
  for (var i = 0; i < rows.length; i++) {
    out.write(
      rows[i]
          .map(
            (cell) =>
                cell == null ? '' : encodeTex(cell).stringify(conf.mathParam()),
          )
          .join(' & '),
    );
    final gap = i < rowSpacings.length && rowSpacings[i].value != 0
        ? '[${_texLength(rowSpacings[i])}]'
        : '';
    if (i < rows.length - 1 || gap.isNotEmpty) out.write(' \\\\$gap ');
    out.write(hline(i + 1));
  }
  return out.toString().trim();
}

EncodeResult _matrixEncoder(GreenNode node) {
  final matrix = node as MatrixNode;
  return _TexTemplateEncodeResult((conf) {
    final spec = StringBuffer();
    for (var i = 0; i <= matrix.cols; i++) {
      spec.write(switch (matrix.vLines[i]) {
        MatrixSeparatorStyle.solid => '|',
        MatrixSeparatorStyle.dashed => ':',
        MatrixSeparatorStyle.none => '',
      });
      if (i < matrix.cols) {
        spec.write(switch (matrix.columnAligns[i]) {
          MatrixColumnAlign.left => 'l',
          MatrixColumnAlign.center => 'c',
          MatrixColumnAlign.right => 'r',
        });
      }
    }
    if (matrix.isCD) return _cdEncode(matrix, conf);
    final env = matrix.isSmall ? 'smallmatrix' : 'array';
    final cellStyle = matrix.isSmall ? MathStyle.script : MathStyle.text;
    final body = _matrixRows(
      [
        for (final row in matrix.body)
          [
            for (final cell in row)
              cell == null ? null : _withoutStyle(cell, cellStyle),
          ],
      ],
      matrix.hLines,
      matrix.rowSpacings,
      conf,
    );
    return env == 'array'
        ? '\\begin{array}{$spec}$body\\end{array}'
        : '\\begin{smallmatrix}$body\\end{smallmatrix}';
  });
}

EncodeResult _equationArrayEncoder(GreenNode node) {
  final array = node as EquationArrayNode;
  return _TexTemplateEncodeResult((conf) {
    final rows = [
      for (var i = 0; i < array.body.length; i++)
        <GreenNode?>[
          _TaggedRowNode(_alignedRow(array.body[i]), array.tags?[i]),
        ],
    ];
    final body = _matrixRows(rows, array.hlines, array.rowSpacings, conf);
    return '\\begin{aligned}$body\\end{aligned}';
  });
}

/// An [EquationArrayNode] row as written: without the display-style
/// wrapper, the aligner closing the last column, or the 1em gaps the parser
/// puts between column pairs.
EquationRowNode _alignedRow(EquationRowNode row) {
  final children = _unwrapStyle(row, MathStyle.display) ?? row.children;
  final out = <GreenNode>[];
  for (final child in children) {
    final previous = out.lastOrNull;
    if (child is SpaceNode &&
        !child.alignerOrSpacer &&
        child.width.value == 1 &&
        child.width.unit == Unit.em &&
        previous is SpaceNode &&
        previous.alignerOrSpacer) {
      continue;
    }
    out.add(child);
  }
  final last = out.lastOrNull;
  if (last is SpaceNode && last.alignerOrSpacer) out.removeLast();
  return EquationRowNode(children: out);
}

/// A row of an [EquationArrayNode] with its tag, so that [_matrixRows] can
/// treat it as a single cell.
class _TaggedRowNode extends EquationRowNode {
  _TaggedRowNode(EquationRowNode row, EquationRowNode? tag)
    : super(
        children: [
          ...row.children,
          if (tag != null) TagNode(body: EquationRowNode.empty(), tag: tag),
        ],
      );
}

EncodeResult _tagEncoder(GreenNode node) {
  final tag = node as TagNode;
  return _TexTemplateEncodeResult(
    (conf) =>
        '${encodeTex(tag.body).stringify(conf.mathParam())}'
        '\\tag*${_textArg(tag.tag, conf)}',
  );
}

EncodeResult _enclosureEncoder(GreenNode node) {
  final enclosure = node as EnclosureNode;
  return _TexTemplateEncodeResult((conf) {
    for (final (notation, command) in const [
      ('phase', '\\phase'),
      ('horizontalstrike', '\\sout'),
    ]) {
      if (enclosure.notation.contains(notation)) {
        return '$command${_mathArg(enclosure.base, conf)}';
      }
    }
    if (enclosure.notation.contains('angl')) {
      final base = _withoutStyle(enclosure.base, MathStyle.text);
      return '\\angl${_mathArg(base, conf)}';
    }
    final up = enclosure.notation.contains('updiagonalstrike');
    final down = enclosure.notation.contains('downdiagonalstrike');
    if (up || down) {
      final command = up && down
          ? '\\xcancel'
          : up
          ? '\\cancel'
          : '\\bcancel';
      return '$command${_mathArg(enclosure.base, conf)}';
    }
    final background = enclosure.backgroundcolor;
    // \fbox, \colorbox, \fcolorbox and \angl take an hbox argument, which
    // the parser wrapped in text style.
    final base = _withoutStyle(enclosure.base, MathStyle.text);
    if (background != null) {
      final text = _textArg(base, conf);
      return enclosure.hasBorder
          ? '\\fcolorbox{${_color(enclosure.bordercolor ?? const Color(0xFF000000))}}'
                '{${_color(background)}}$text'
          : '\\colorbox{${_color(background)}}$text';
    }
    // \boxed{x} is \fbox{$\displaystyle{x}$}.
    final math = _unwrapStyle(base, MathStyle.text);
    final display = math == null
        ? null
        : _unwrapStyle(EquationRowNode(children: math), MathStyle.display);
    if (display != null) {
      return '\\boxed${_mathArg(EquationRowNode(children: display), conf)}';
    }
    return '\\fbox${_textArg(base, conf)}';
  });
}

EncodeResult _smashEncoder(GreenNode node) {
  final smash = node as SmashNode;
  final option = smash.smashHeight && smash.smashDepth
      ? ''
      : smash.smashHeight
      ? '[t]'
      : '[b]';
  return _TexTemplateEncodeResult(
    (conf) => '\\smash$option${_mathArg(smash.body, conf)}',
  );
}

EncodeResult _lapEncoder(GreenNode node) {
  final lap = node as LapNode;
  final command = switch (lap.alignment) {
    LapAlignment.left => '\\mathllap',
    LapAlignment.right => '\\mathrlap',
    LapAlignment.center => '\\mathclap',
  };
  return _TexTemplateEncodeResult(
    (conf) => '$command${_mathArg(lap.body, conf)}',
  );
}

EncodeResult _vcenterEncoder(GreenNode node) => _TexTemplateEncodeResult(
  (conf) => '\\vcenter${_mathArg((node as VCenterNode).body, conf)}',
);

EncodeResult _reflectEncoder(GreenNode node) => _TexTemplateEncodeResult(
  (conf) => '\\mathreflectbox${_mathArg((node as ReflectNode).body, conf)}',
);

EncodeResult _mathChoiceEncoder(GreenNode node) {
  final choice = node as MathChoiceNode;
  return _TexTemplateEncodeResult(
    (conf) =>
        '\\mathchoice${_mathArg(choice.display, conf)}'
        '${_mathArg(choice.text, conf)}${_mathArg(choice.script, conf)}'
        '${_mathArg(choice.scriptscript, conf)}',
  );
}

EncodeResult _sizedDelimEncoder(GreenNode node) {
  final delim = node as SizedDelimNode;
  final size = const ['\\big', '\\Big', '\\bigg', '\\Bigg'][delim.size - 1];
  final suffix = switch (delim.atomType) {
    AtomType.open => 'l',
    AtomType.close => 'r',
    AtomType.rel => 'm',
    _ => '',
  };
  return TransparentTexEncodeResult(<dynamic>[
    '$size$suffix',
    _delimEncoder(delim.delim),
  ]);
}

EncodeResult _glyphAccentEncoder(GreenNode node) {
  final accent = node as GlyphAccentNode;
  final command = accent.placement == GlyphAccentPlacement.below
      ? '\\c'
      : '\\textcircled';
  return _TexTemplateEncodeResult(
    (conf) => '$command${_textArg(accent.base, conf)}',
  );
}

EncodeResult _includeGraphicsEncoder(GreenNode node) {
  final image = node as IncludeGraphicsNode;
  final options = [
    'height=${_texLength(image.height)}',
    if (image.width.value > 0) 'width=${_texLength(image.width)}',
    if (image.totalHeight.value > 0)
      'totalheight=${_texLength(image.totalHeight)}',
    'alt=${image.alt}',
  ].join(',');
  return StaticEncodeResult('\\includegraphics[$options]{${image.src}}');
}

EncodeResult _cdVertArrowEncoder(GreenNode node) {
  final arrow = node as CdVertArrowNode;
  if (arrow.delim == '∥') return const StaticEncodeResult('@|');
  final char = arrow.delim == '↑' ? 'A' : 'V';
  return _TexTemplateEncodeResult((conf) {
    String label(EquationRowNode? row) =>
        row == null ? '' : encodeTex(row).stringify(conf.mathParam());
    return '@$char${label(arrow.left)}$char${label(arrow.right)}$char';
  });
}

EncodeResult _internalEncoder(GreenNode node) => const StaticEncodeResult('');

/// `{CD}`: object rows alternate objects and horizontal arrows, arrow rows
/// alternate vertical arrows and (empty) gaps; a missing arrow is `@.`.
String _cdEncode(MatrixNode matrix, TexEncodeConf conf) {
  final rows = matrix.body.toList();
  // The empty row KaTeX's parser leaves after the last one.
  if (rows.isNotEmpty && rows.last.every((cell) => cell == null)) {
    rows.removeLast();
  }
  String content(EquationRowNode? cell) => cell == null
      ? ''
      : encodeTex(_withoutStyle(cell, MathStyle.display))
            .stringify(conf.mathParam());
  bool isArrow(EquationRowNode? cell) {
    final inner = cell == null ? null : _withoutStyle(cell, MathStyle.display);
    return inner != null &&
        inner.children.length == 1 &&
        (inner.children.single is StretchyOpNode ||
            inner.children.single is CdVertArrowNode);
  }

  final out = <String>[];
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    final parts = <String>[];
    for (var j = 0; j < row.length; j++) {
      final arrowSlot = i.isEven ? j.isOdd : j.isEven;
      if (arrowSlot) {
        parts.add(isArrow(row[j]) ? content(row[j]) : '@.');
      } else {
        parts.add(content(row[j]));
      }
    }
    // Trailing @. in arrow rows and empty trailing cells add nothing.
    while (parts.isNotEmpty &&
        (parts.last.isEmpty || (i.isOdd && parts.last == '@.'))) {
      parts.removeLast();
    }
    out.add(parts.join(' '));
  }
  return '\\begin{CD}${out.join(' \\\\ ')}\\end{CD}';
}

EncodeResult _cdArrowEncoder(StretchyOpNode arrow) {
  if (arrow.symbol == '=') return const StaticEncodeResult('@=');
  final char = arrow.symbol == '\u2190' ? '<' : '>';
  return _TexTemplateEncodeResult((conf) {
    String label(EquationRowNode? row) =>
        row == null ? '' : encodeTex(row).stringify(conf.mathParam());
    return '@$char${label(arrow.above)}$char${label(arrow.below)}$char';
  });
}
