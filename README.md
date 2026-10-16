# flutter_equation_support

TeX/LaTeX math rendering for Flutter, owned and maintained independently.

The rendering engine is a fork of [flutter_math](https://github.com/znjameswu/flutter_math)
(via `flutter_math_fork` 0.7.4), which is no longer actively developed. This
package has **no third-party runtime dependencies** besides `meta` and
`collection`. The upstream `tuple`, `provider` and `flutter_svg` dependencies
have been replaced with Dart records, an `InheritedWidget` and a built-in SVG
path renderer.

## Usage

```dart
import 'package:flutter_equation_support/flutter_equation_support.dart';

Math.tex(r'\frac{-b \pm \sqrt{b^2 - 4ac}}{2a}', textStyle: TextStyle(fontSize: 18));
```

The API is the same as `flutter_math_fork`, so migrating is an import change.
KaTeX fonts are bundled under the family names
`packages/flutter_equation_support/KaTeX_*`.

## Install (private git dependency)

```yaml
dependencies:
  flutter_equation_support:
    git:
      url: <your repo url>
      ref: v0.1.0
```

## Tests

`flutter test` runs `test/engine_parity_test.dart`, which renders a set of
equations with both the upstream engine and this one and checks the pixels
match.

## Roadmap

- Bengali shaping inside math (`\text{}` and Bengali digits).
- HTML + equation renderer (`MathRender`) moved in from the app.
- Clean up deprecated Flutter API usage.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE). KaTeX fonts: MIT
(`lib/katex_fonts/LICENSE`).
