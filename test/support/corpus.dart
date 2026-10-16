/// Equations rendered by the golden tests. Each entry is a stable file name
/// and the TeX source. Add to the end of a group; never rename an entry, or
/// its golden image is orphaned.
const engineCorpus = <String, String>{
  // Basics and spacing
  'ord_bin_rel': r'a + b - c = d \times e \div f',
  'relations': r'a \le b \ge c \ne d \approx e \equiv f \sim g \cong h',
  'spaces': r'a\,b\:c\;d\quad e\qquad f\!g',
  'greek': r'\alpha\beta\gamma\delta\epsilon\varepsilon\theta\vartheta\pi\varpi\Omega\Sigma',
  'digits_text': r'123 + 4.56 = 579.56',
  'punct': r'f(x), g(y); h: A \to B',
  'dots': r'1, 2, \ldots, n \quad a + \cdots + z \quad \vdots \quad \ddots',
  // Scripts
  'scripts': r'x^2 + y_1 + z_{ij}^{2k}',
  'nested_scripts': r'e^{x^{2}} + a_{b_{c}}',
  'prescripts': r'{}_{6}^{14}\mathrm{C} + {}^{235}_{92}U',
  'primes': r"f'(x) + g''(x) + h^{\prime}",
  'limits': r'\lim_{x \to 0} \frac{\sin x}{x} = 1',
  'sum_display': r'\sum_{i=1}^{n} i = \frac{n(n+1)}{2}',
  'int': r'\int_0^1 x^2\,dx + \iint_D f + \oint_C g',
  'prod_coprod': r'\prod_{k=1}^{n} k \quad \coprod_i A_i',
  'bigops': r'\bigcup_{i} A_i \cap \bigcap_j B_j \oplus \bigoplus_k C_k',
  // Fractions
  'frac': r'\frac{a}{b} + \dfrac{1}{2} + \tfrac{3}{4}',
  'nested_frac': r'\frac{1}{1+\frac{1}{1+\frac{1}{x}}}',
  'cfrac': r'\cfrac{1}{2+\cfrac{1}{3}}',
  'binom': r'\binom{n}{k} + \dbinom{n}{2} + \tbinom{a}{b}',
  'genfrac': r'\genfrac{(}{)}{0pt}{}{n}{k}',
  'over_choose': r'{a \over b} + {n \choose k}',
  // Roots
  'sqrt': r'\sqrt{2} + \sqrt[3]{x} + \sqrt[n]{a^n}',
  'sqrt_tall': r'\sqrt{\frac{a^2+b^2}{c^2}}',
  'sqrt_nested': r'\sqrt{1+\sqrt{1+\sqrt{1+x}}}',
  // Delimiters
  'left_right':
      r'\left( \frac{a}{b} \right) \left[ x \right] \left\{ y \right\}',
  'left_right_tall': r'\left( \frac{\frac{a}{b}}{\frac{c}{d}} \right)',
  'middle': r'\left\{ x \;\middle|\; x > 0 \right\}',
  'abs_norm': r'\left| x \right| + \left\| v \right\|',
  'angle_floor_ceil': r'\langle a, b \rangle \lfloor x \rfloor \lceil y \rceil',
  'big_sizes': r'\big( \Big( \bigg( \Bigg( x \Bigg) \bigg) \Big) \big)',
  'big_brackets': r'\big[ \Big[ \bigg[ \Bigg[ x \Bigg] \bigg] \Big] \big]',
  'big_braces':
      r'\big\{ \Big\{ \bigg\{ \Bigg\{ x \Bigg\} \bigg\} \Big\} \big\}',
  'left_dot': r'\left. \frac{dy}{dx} \right|_{x=0}',
  // Matrices and arrays
  'pmatrix': r'\begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}',
  'bmatrix': r'\begin{bmatrix} a & b & c \\ d & e & f \end{bmatrix}',
  'vmatrix': r'\begin{vmatrix} a & b \\ c & d \end{vmatrix} = ad - bc',
  'Vmatrix_Bmatrix':
      r'\begin{Vmatrix} x \end{Vmatrix} \begin{Bmatrix} y \end{Bmatrix}',
  'matrix_plain': r'\begin{matrix} 1 & 0 \\ 0 & 1 \end{matrix}',
  'smallmatrix':
      r'\left( \begin{smallmatrix} a & b \\ c & d \end{smallmatrix} \right)',
  'array': r'\begin{array}{l|c|r} a & b & c \\ \hline 1 & 22 & 333 \end{array}',
  'array_dashed': r'\begin{array}{cc} a & b \\ \hdashline c & d \end{array}',
  'cases': r'f(x) = \begin{cases} x & x \ge 0 \\ -x & x < 0 \end{cases}',
  'dcases_rcases': r'\begin{dcases} \frac{1}{2} & a \\ b & c \end{dcases}',
  'aligned': r'\begin{aligned} a &= b + c \\ d &= e \end{aligned}',
  'alignedat': r'\begin{alignedat}{2} a &= b & c &= d \end{alignedat}',
  'darray': r'\begin{darray}{cc} \frac{1}{2} & 3 \end{darray}',
  // Accents
  'accents': r'\hat{a} \check{b} \tilde{c} \acute{d} \grave{e} \dot{f} \ddot{g} \breve{h} \bar{i} \vec{j} \mathring{k}',
  'wide_accents': r'\widehat{ABC} \widetilde{xyz} \widecheck{pqr}',
  'over_under_line': r'\overline{AB} + \underline{CD}',
  'arrows_over':
      r'\overrightarrow{AB} \overleftarrow{CD} \overleftrightarrow{EF}',
  'arrows_under':
      r'\underrightarrow{AB} \underleftarrow{CD} \underleftrightarrow{EF}',
  'harpoons_over':
      r'\overleftharpoon{ab} \overrightharpoon{cd} \Overrightarrow{ef}',
  'braces': r'\overbrace{a+b+c}^{n} \underbrace{x+y}_{m}',
  'utilde': r'\utilde{AB}',
  // Extensible arrows
  'xarrows': r'\xrightarrow[below]{above} \xleftarrow{abc} \xLeftarrow{n} \xRightarrow{m}',
  'xarrows_more':
      r'\xleftrightarrow{a} \xhookleftarrow{b} \xhookrightarrow{c} \xmapsto{d}',
  'xharpoons': r'\xrightharpoonup{a} \xrightharpoondown{b} \xrightleftharpoons{c} \xleftrightharpoons{d}',
  'xtofrom': r'\xtofrom{a} \xlongequal{b} \xtwoheadrightarrow{c}',
  // Arrows and symbols
  'arrows': r'\to \gets \leftrightarrow \Rightarrow \Leftarrow \Leftrightarrow \mapsto \hookrightarrow \longrightarrow',
  'sets': r'\in \notin \ni \subset \supset \subseteq \supseteq \emptyset \varnothing \cup \cap',
  'logic': r'\forall x \exists y \neg p \land q \lor r \implies s \iff t',
  'misc_symbols': r'\infty \partial \nabla \hbar \ell \aleph \Re \Im \wp \angle \triangle \degree',
  'ams_symbols': r'\leqslant \geqslant \lesssim \gtrsim \therefore \because \square \blacksquare',
  'negations': r'\not= \not\in \nleq \ngeq \nsubseteq \nmid \nparallel',
  'binary_ops':
      r'\pm \mp \cdot \circ \bullet \oplus \otimes \odot \wedge \vee \setminus',
  'unicode_math': r'α + β ≤ γ → ∞ × ÷ ± ∑',
  // Fonts
  'mathrm_bf_it': r'\mathrm{d}x + \mathbf{v} + \mathit{word}',
  'mathbb_cal_frak': r'\mathbb{R} \mathcal{L} \mathfrak{g} \mathscr{F}',
  'mathsf_tt': r'\mathsf{ABC} \mathtt{code}',
  'boldsymbol': r'\boldsymbol{\alpha + x} \bm{y}',
  'text_modes':
      r'\text{if } x > 0 \textbf{ bold } \textit{italic} \texttt{mono}',
  'operatorname': r'\operatorname{rank} A + \operatorname*{argmax}_x f',
  'log_like': r'\sin x \cos y \tan z \log n \ln e \exp t \max_i \min_j \sup \inf \det \gcd',
  // Styles, sizes and colour
  'styles': r'\displaystyle\sum x \textstyle\sum x \scriptstyle\sum x',
  'sizes': r'\tiny a \small b \normalsize c \large d \Large e \huge f',
  'color': r'\color{red} x + \textcolor{blue}{y} + \colorbox{yellow}{z}',
  'boxed_fbox': r'\boxed{E = mc^2} \fbox{text}',
  // Enclosures and phantoms
  'cancel': r'\cancel{x}',
  'sout': r'\sout{abc}',
  'phantom': r'a\phantom{bbb}c \hphantom{x} \vphantom{y}',
  'raisebox_rule': r'a\raisebox{0.5em}{b}c \rule{1em}{0.5em}',
  'kern': r'a\kern1em b\mkern18mu c\hskip2em d',
  // Ops with limits
  'stackrel_overset':
      r'\stackrel{\text{def}}{=} \overset{!}{=} \underset{x}{\arg}',
  'limits_nolimits': r'\int\limits_0^1 \sum\nolimits_i',
  'substack': r'\sum_{\substack{0<i<m \\ 0<j<n}} P(i,j)',
  // Real exam content (Bengali digits and words go through their own tests)
  'quadratic': r'x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}',
  'trig_identity': r'\sin^2\theta + \cos^2\theta = 1',
  'chem': r'\mathrm{H_2O} + \mathrm{CO_2} \rightleftharpoons \mathrm{H_2CO_3}',
  'physics': r'F = G\frac{m_1 m_2}{r^2}, \quad v = u + at',
  'percent': r'\frac{20}{100} \times 100\% = 20\%',
  'determinant': r'\Delta = \begin{vmatrix} 1 & 2 & 3 \\ 4 & 5 & 6 \\ 7 & 8 & 9 \end{vmatrix}',
  'vector': r'\vec{A} = A_x\hat{i} + A_y\hat{j} + A_z\hat{k}',
  'angle_degree': r'\angle ABC = 90^\circ',
  'long_division_like':
      r'\begin{array}{r} 125 \\ \times\ 3 \\ \hline 375 \end{array}',
  'set_builder': r'A = \{ x \in \mathbb{N} : x < 10 \}',
  'log_rules': r'\log_a(xy) = \log_a x + \log_a y',
  'limit_e': r'\lim_{n \to \infty} \left(1 + \frac{1}{n}\right)^n = e',
  'derivative': r'\frac{d}{dx}\left(x^n\right) = nx^{n-1}',
  'integral_parts': r'\int u\,dv = uv - \int v\,du',
  'matrix_product': r'\begin{pmatrix} a & b \\ c & d \end{pmatrix}\begin{pmatrix} x \\ y \end{pmatrix}',
  'recurring': r'0.\dot{3} = \frac{1}{3}',
  // KaTeX 0.19 symbol and font updates
  'unicode_operators': r'a − b ∗ c ∘ d ∖ e ∙ f ◯ g',
  'pilcrow_section': r'\S 3.1 \quad \P 2 \quad \text{\S\P}',
  'origof_imageof': r'f \origof g \imageof h',
  'middle_dot': r'a · b \quad \text{a·b}',
  'imath_jmath': r'\vec{\imath} + \hat{\jmath} \quad \mathrm{\imath}',
  'pounds_cong': r'\pounds 5 \quad a \cong b \quad \boldsymbol{\cong}',
  'mathnormal_sfit': r'\mathnormal{x2024} \quad \mathsfit{ABC}',
  'accented_text': r'\text{café, naïve, Ångström, Москва}',
  'texttt_bold': r'\texttt{\textbf{code}}',
  // Unicode math alphanumerics, as MS Word pastes them
  'word_italic_vars': r'𝑥² + 𝑦 = 𝑎𝑏𝑐',
  'word_greek': r'𝛼 + 𝛽 = 𝜃, \quad 𝜋𝑟^2',
  'alnum_styles': r'𝐀𝐁 𝑨𝑩 𝒜 𝔄𝔤 𝕬 𝔸 ℝℕℤ 𝖠 𝗔 𝘈 𝙰 𝟎𝟏 ℎ',
  'vmatrix_double': r'\begin{Vmatrix} a & b \\ c & d \end{Vmatrix}',
  // AMS display environments and equation numbering
  'align_numbered': r'\begin{align} a &= b + c \\ d &= e \notag \\ f &= g \tag{*} \end{align}',
  'gather_numbered':
      r'\begin{gather} x^2 + y^2 = z^2 \\ e^{i\pi} + 1 = 0 \end{gather}',
  'equation_tag': r'\begin{equation} E = mc^2 \end{equation}',
  'toplevel_tag': r'F = ma \tag{2.1}',
  'split_in_equation': r'\begin{equation} \begin{split} a &= b \\ &= c \end{split} \end{equation}',
  'aligned_pairs':
      r'\begin{aligned} a &= 1 & b &= 2 \\ c &= 3 & d &= 4 \end{aligned}',
  'gathered':
      r'\left\{ \begin{gathered} x + y = 1 \\ x - y = 3 \end{gathered} \right.',
  // KaTeX 0.13–0.19 commands
  'negative_space':
      r'\int\!\!\int_D f \quad a\kern-0.3em b \quad \negthinspace x',
  'colon_relations': r'x \coloneqq y \quad a \Coloneqq b \quad c \eqqcolon d \quad f\colon A \to B',
  'unicode_scripts': r'x² + y³ = z⁻¹, \quad H₂O, \quad a₁ + aₙ',
  'smash_lap_vcenter':
      r'\smash{\frac{a}{b}} \quad \mathrlap{/}{=} \quad \vcenter{\hbox{box}}',
  'braket_set': r'\Braket{ \phi | \psi } \quad \set{ x | x > 0 }',
  'emph_text': r'\text{\emph{em} \textit{ital \emph{up} ital}}',
  'dddot_underbar': r'\dddot{x} \quad \ddddot{y} \quad \underbar{z}',
  'llbracket_minuso':
      r'\llbracket a \rrbracket \quad \lBrace b \rBrace \quad a \minuso b',
  'angstrom_copyright': r'1\,\AA \quad \text{\aa}',
  'mathchoice': r'\mathchoice{D}{T}{S}{SS} \quad x^{\mathchoice{D}{T}{S}{SS}}',
  'reflect_pmb': r'\reflectbox{abc} \quad \pmb{x} x',
  'rule_text': r'\text{Answer: \rule{2cm}{0.4pt}} \quad x = \rule{1cm}{0.4pt}',
  'injlim_varlim': r'\injlim_{n} \quad \varlimsup_{n} \quad \varliminf_{n} \quad \varinjlim_n',
  'defined_by': r'a ≝ b \quad c ≟ d',
  'color_alpha': r'\color{#ff000080} x \textcolor{#00f8}{y}',
  'big_lr': r'\bigl( \Bigl[ \biggl\{ \Biggl\langle x \Biggr\rangle \biggr\} \Bigr] \bigr)',
  'big_bars': r'\big| \Big| \bigg| \Bigg| \quad \big\| \Big\| \bigg\| \Bigg\| \quad a \biggm| b',
  'big_braced': r'\big{(} x \big{)} \quad \Bigl\uparrow \Bigr\downarrow',
  'double_hline':
      r'\begin{array}{c} a \\ \hline\hline b \\ \hdashline c \end{array}',
  'aligned_rules': r'\begin{aligned} a &= b \\ \hline c &= d \\ \hdashline e &= f \end{aligned}',
  'starred_matrix': r'\begin{pmatrix*}[r] -1 & 2 \\ 3 & -4 \end{pmatrix*} \begin{bmatrix*}[l] 10 & 2 \\ 3 & 40 \end{bmatrix*}',
  'empty_matrix': r'a \begin{pmatrix}\end{pmatrix} b',
  'brackets_groups': r'\overbracket{a+b}^{n} \underbracket{c+d}_{m} \overgroup{AB} \undergroup{CD}',
  'line_segments': r'\overlinesegment{AB} \quad \underlinesegment{CD}',
  'cedilla_circled': r'\text{\c{c}a\c{C}\c{s}} \quad \text{\textcircled{a}} \quad \copyright \quad \textregistered',
  'brace_spacing': r'x + \overbrace{a+b}^{2} = \underbrace{c}_{1}',
  'phase_angl':
      r'V = 10\phase{-60^\circ} \quad a_{\angl{n}} \quad \ddot{a}_{\angln}',
  'cancel_padding': r'\cancel{x} + \cancel{abc} + \xcancel{5}',
  'sout_text': r'\text{a \sout{wrong} answer}',
  'colorbox_script': r'x^{\colorbox{yellow}{hi}} \fcolorbox{red}{white}{ok}',
  'cd_square': r'\begin{CD} A @>a>> B \\ @VbVV @AAcA \\ C @= D \end{CD}',
  'cd_labels': r'\begin{CD} X @<f<g< Y @. Z \\ @| @. @VVhV \\ X @>>> Y @>{\alpha+\beta}>> W \end{CD}',
  'not_mathop': r'a \not= b \not\in C \not a \not\subset D \quad \mathop\int_0^1 \mathop{\sum}\limits_k',
};

/// Bengali content, rendered with a Bengali prose font.
const bengaliCorpus = <String, String>{
  'bn_text_word': r'\text{ক্রয়মূল্য} = ১২০ \text{ টাকা}',
  'bn_frac_digits': r'\frac{১০০}{১২০} \times ১০০',
  'bn_sqrt': r'\sqrt{৬২৫} = ২৫',
  'bn_poly': r'x^২ + ২৫x - ৭৫০০ = ০',
  'bn_power_group': r'(৪+৫+৩)^২ = ১৪৪',
  'bn_frac_words': r'\frac{\text{লাভ}}{\text{ক্রয়মূল্য}} \times ১০০\%',
  'bn_bold': r'\textbf{সমাধান:}\ a = ১ + \sqrt{৩}',
  'bn_array': r'\begin{array}{cc} \text{শ্রেণি} & \text{গণসংখ্যা} \\ ১০-২০ & ৫ \end{array}',
  'bn_sum': r'\sum_{i=১}^{n} x_i = \text{মোট}',
  'bn_mixed_latin': r'\text{The quick brown fox} \; a^2+b^2=c^2',
};
