/// Exam-style HTML bodies: prose with inline maths, environments, MathML,
/// tables and rich text, as they reach MathRender from the API.
const examCorpus = <String, String>{
  'plain_p': '<p>নিচের কোনটি সঠিক? Choose the correct one.</p>',
  'inline_math': r'<p>যদি $x^2 + 2x + 1 = 0$ হয়, তবে $x$ এর মান কত?</p>',
  'frac_sqrt': r'<p>সরল কর: $\frac{a+b}{c-d} + \sqrt{2} - \sqrt[3]{x}$</p>',
  'matrix':
      r'<p>$A = \begin{bmatrix}1 & 2\\3 & 4\end{bmatrix}$ হলে $|A|$ = ?</p>',
  'det':
      r'<p>$\begin{vmatrix}a & b & c\\d & e & f\\g & h & i\end{vmatrix}$</p>',
  'cases':
      r'<p>$f(x) = \begin{cases} x^2, & x > 0 \\ 0, & x \le 0 \end{cases}$</p>',
  'aligned': r'<p>$\begin{aligned} a &= b + c \\ &= d \end{aligned}$</p>',
  'calculus': r'<p>$\int_0^1 x^2\,dx$, $\sum_{i=1}^{n} i = \frac{n(n+1)}{2}$, $\lim_{x \to 0} \frac{\sin x}{x} = 1$</p>',
  'greek': r'<p>$\alpha + \beta = \gamma$, $\theta = 30^\circ$, $\pi r^2$, $\Delta ABC$</p>',
  'bengali_in_math': r'<p>$x = \text{বাংলা}$ এবং $ক + খ = গ$</p>',
  'mathml': '<p>মান: <math><mi>x</mi><mo>=</mo><mfrac><mn>1</mn><mn>2</mn></mfrac></math></p>',
  'katex_annotation': '<p><span class="katex"><span class="katex-mathml"><math><semantics><mrow><mi>y</mi></mrow><annotation encoding="application/x-tex">y = mx + c</annotation></semantics></math></span></span></p>',
  'table': r'<table><tr><td>রাশি</td><td>মান</td></tr><tr><td>$x^2$</td><td>4</td></tr></table>',
  'sup_sub_html_math': r'<p>H<sub>2</sub>O এবং $E = mc^2$, a<sup>3</sup></p>',
  'chem': r'<p>$\text{H}_2\text{SO}_4 + 2\text{NaOH} \rightarrow \text{Na}_2\text{SO}_4 + 2\text{H}_2\text{O}$</p>',
  'long_eq': r'<p>$a_1 + a_2 + a_3 + a_4 + a_5 + a_6 + a_7 + a_8 + a_9 + a_{10} + a_{11} + a_{12} + a_{13} + a_{14}$</p>',
  'lines_text': 'প্রশ্ন: a = 1 + √3 হলে a3 - 6√3 = কত?\n\nসমাধান:\nদেওয়া আছে,\na = 1 + √3',
  'ul_math': r'<ul><li>$x = 1$</li><li>$y = 2$</li></ul>',
  'html_only_rich': '<p><strong>উত্তর:</strong> <span style="color:#c00">ক</span></p><ol><li>প্রথম</li><li>দ্বিতীয়</li></ol>',
  'vec_bar':
      r'<p>$\vec{AB} \cdot \overline{CD} = |\vec{a}||\vec{b}|\cos\theta$</p>',
  'log_trig': r'<p>$\log_2 8 = 3$, $\tan^{-1} x$, $\sin^2\theta + \cos^2\theta = 1$</p>',
  'inequality': r'<p>$x \geq 2$, $y \neq 0$, $a \approx b$, $A \subseteq B$, $x \in \mathbb{R}$</p>',
};
