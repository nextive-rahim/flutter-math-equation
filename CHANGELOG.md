## 0.1.0

First release.

### Engine

* KaTeX 0.19.0 compatibility: fonts, font metrics, symbols, macros and
  layout rules ported from KaTeX 0.19.0. Every command and environment that
  KaTeX 0.19 defines parses.
* New environments: `align`, `align*`, `alignat`, `alignat*`, `gather`,
  `gather*`, `gathered`, `split`, `equation`, `equation*` and `{CD}`, with
  automatic equation numbers, `\tag`, `\tag*`, `\notag`, `\nonumber` and the
  `leqno` / `firstEquationNumber` settings.
* `cases`, `aligned` and arrays follow KaTeX 0.19: array stretch, `\jot`,
  `\\[gap]`, several `\hline`s per gap, dashed lines in aligned
  environments, starred matrices with a column type.
* Macro definitions: `\def`, `\gdef`, `\edef`, `\xdef`, `\let`,
  `\futurelet`, `\global`, `\long`, `\relax`, delimited parameters.
* New commands: `\smash`, `\mathllap`, `\mathrlap`, `\mathclap`, `\vcenter`,
  `\reflectbox`, `\mathchoice`, `\hbox`, `\phase`, `\angl`, `\angln`,
  `\overbracket`, `\underbracket`, `\overgroup`, `\overlinesegment`,
  `\underlinesegment`, `\c`, `\textcircled`, `\mathnormal`, `\mathsfit`,
  `\href`, `\url`, `\includegraphics`, `\htmlClass` and others (behind the
  `trust` setting), and 68 KaTeX 0.19 macros (`\coloneqq`, `\Set`, `\Braket`
  …).
* Unicode maths letters (𝑥 𝐀 ℝ 𝔤 𝕬), Unicode sub/superscripts, Armenian.
* `\bigl(` and friends size correctly; braced `\big{(}`; tall delimiters
  drawn as KaTeX draws them.
* `\not` before any character, `\mathop\int`, `\operatorname{rank}\quad A`,
  negative kerns, `\colorbox` backgrounds, `\bcancel` and `\xcancel`,
  accents on italic letters, and other rendering fixes.
* Unsupported commands are shown in red (`errorColor`) instead of failing.
* Copying from `SelectableMath` keeps matrices, aligned rows, spaces, boxes,
  `\smash`, tags, `{CD}` and the other layout commands; `\xrightarrow`
  labels no longer swap sides.

### Bengali

* Bengali and other Indic runs in maths are shaped together, in the
  `textStyle` font or the bundled Noto Sans Bengali.

### HTML

* `MathRender`, `EquationSolver` and `ZoomableImage`: the exam HTML renderer,
  moved in from the e-testpaper app, with `MathRenderTheme` for the prose
  font, image background, image placeholder and link taps.
* `HtmlView`: an HTML renderer matching flutter_widget_from_html 0.17's
  column layout pixel for pixel.
* `decodeHtmlEntities` (all 2231 WHATWG entities) and `parseHtmlFragment`.

### Widgets

* `SelectableMath`: Copy and Select All in the adaptive toolbar and with
  Ctrl/Cmd+C and Ctrl/Cmd+A; `MathToolbarOptions` replaces the removed
  `ToolbarOptions`.
* Updated for Flutter 3.47 (`TextScaler`, no deprecated APIs).

### Dependencies

* Only `meta` and `collection`. No `tuple`, `provider`, `flutter_svg`,
  `flutter_widget_from_html` or `html_unescape`.
