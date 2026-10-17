import 'package:flutter/material.dart';
import 'package:flutter_math_equation/flutter_math_equation.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('flutter_math_equation')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // An equation.
            Math.tex(
              r'\frac{-b \pm \sqrt{b^2 - 4ac}}{2a}',
              textStyle: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 16),
            // Selectable, with Copy (as TeX) and Select All.
            SelectableMath.tex(r'e^{i\pi} + 1 = 0'),
            const SizedBox(height: 16),
            // Bengali inside maths.
            Math.tex(r'x = \text{বাংলা}'),
            const SizedBox(height: 16),
            // An HTML body with equations.
            MathRender(htmlContent: r'<p>যদি $x^2 = 4$ হয়, তবে $x$ = ?</p>'),
            const SizedBox(height: 16),
            // Plain HTML.
            HtmlView('<p>নিচের কোনটি <b>সঠিক</b>?</p>'),
          ],
        ),
      ),
    );
  }
}
