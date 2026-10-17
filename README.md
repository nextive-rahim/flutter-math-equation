# flutter_math_equation

TeX/LaTeX math rendering for Flutter, compatible with KaTeX 0.19, plus a
renderer for exam-style HTML with embedded equations. Built for Bengali
content. Owned and maintained independently, with no third-party runtime
dependencies besides `meta` and `collection`.

- **Math engine**: parses and lays out TeX the way KaTeX 0.19.0 does, with
  KaTeX 0.19 fonts, metrics and symbol tables. It covers every command and
  environment KaTeX 0.19 defines, including `align`, `gather`, `alignat`,
  `split`, `equation`, equation numbering and `\tag`, `{CD}` commutative
  diagrams, `\def`/`\let`, `\smash`, `\mathllap`, `\phase`, `\angl`,
  `\overbracket`, `\boldsymbol` and Unicode math letters (𝑥, ℝ, 𝔤).
- **Bengali**: Bengali and other Indic text inside maths (`\text{বাংলা}`,
  `$ক + খ$`) is shaped as whole words with a bundled Noto Sans Bengali, or
  with your own font.
- **HTML**: `MathRender` renders HTML bodies with `$…$` maths, MathML, KaTeX
  annotations, MS Office maths, tables and images. Plain HTML goes through
  `HtmlView`, which matches flutter_widget_from_html 0.17's layout pixel for
  pixel.

Requires Flutter 3.47 or later.

## Install

```sh
flutter pub add flutter_math_equation
```

or in `pubspec.yaml`:

```yaml
dependencies:
  flutter_math_equation: ^0.1.0
```

## Usage

```dart
import 'package:flutter_math_equation/flutter_math_equation.dart';

// An equation.
Math.tex(
  r'\frac{-b \pm \sqrt{b^2 - 4ac}}{2a}',
  textStyle: const TextStyle(fontSize: 18),
);

// Selectable, with Copy (as TeX) and Select All.
SelectableMath.tex(r'e^{i\pi} + 1 = 0');

// An HTML body with equations, as it comes from the exam API.
MathRender(htmlContent: r'<p>যদি $x^2 = 4$ হয়, তবে $x$ = ?</p>');

// Plain HTML.
HtmlView('<p>নিচের কোনটি <b>সঠিক</b>?</p>');
```

### Bengali inside maths

Bengali runs in maths are shaped together in the first non-KaTeX family of
`textStyle` (its `fontFamily`, then `fontFamilyFallback`), or in the bundled
Noto Sans Bengali:

```dart
Math.tex(
  r'x = \text{বাংলা}',
  textStyle: const TextStyle(fontSize: 18, fontFamily: 'NotoSerifBengali'),
);
```

### Configuring MathRender

`MathRenderTheme` sets the prose font of the default style, the colour
behind images, the image loading placeholder and link taps:

```dart
MathRenderTheme(
  data: MathRenderThemeData(
    fontFamily: 'NotoSerifBengali',
    imageLoadingBuilder: (context) => const MyShimmer(),
    onTapUrl: (url) => launchUrl(Uri.parse(url)),
  ),
  child: MaterialApp(...),
)
```

### Parser settings

`Math.tex(..., settings: TexParserSettings(...))`:

| Setting | Default | |
| --- | --- | --- |
| `macros` | `{}` | Extra macros, as KaTeX's `macros` option. |
| `strict` | `Strict.warn` | What to do with non-LaTeX input. |
| `trust` | `false` | Render `\href`, `\url`, `\includegraphics` and `\htmlClass`…; otherwise they show as unsupported commands. |
| `leqno` | `false` | Equation numbers on the left. |
| `firstEquationNumber` | `1` | Where automatic numbering starts. |
| `errorColor` | `#cc0000` | Colour of unsupported commands. |
| `maxExpand` | `1000` | Limit on macro expansions. |

## Differences from KaTeX

- Display-only environments (`align`, `gather`, `equation`, `{CD}`, top-level
  `\tag`) also work in inline maths rather than raising an error.
- Equation numbers are assigned when parsing, per `Math` widget.
- Function arguments use TeX's greediness rules from KaTeX 0.12. Big
  operators can still be arguments (`\mathop\int`).
- `\pmb` uses KaTeX 0.12's form.

## Tests

```sh
flutter test                   # unit, widget and golden tests
flutter test --update-goldens  # after an intended rendering change
```

Golden tests render with the real KaTeX and Noto fonts and compare against
`test/goldens/` at a 0.3% pixel tolerance. Review new images before
committing them.

## Tools

- `tool/gen_font_metrics.py`: regenerates font metrics from KaTeX's fonts.
- `tool/gen_html_entities.py`: regenerates the HTML entity table from the
  WHATWG list.
- `tool/katex_commands.py` and `tool/probe/katex_coverage_probe.dart`: list
  the commands of a KaTeX release and report any this package lacks.

## License

Apache-2.0; see [LICENSE](LICENSE). Third-party notices, including for the
original flutter_math engine, KaTeX and the bundled fonts, are in
[NOTICE](NOTICE).
