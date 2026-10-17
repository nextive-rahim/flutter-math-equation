/// Basic utilities to render math equations.
///
/// Please refer to README for usage.
library;

export 'src/ast/options.dart' show MathOptions, FontOptions;
export 'src/html/html_dom.dart'
    show HtmlNode, HtmlElement, HtmlText, parseHtmlFragment;
export 'src/html/html_unescape.dart' show decodeHtmlEntities;
export 'src/html/html_view.dart' show HtmlView, HtmlCustomWidgetBuilder;
export 'src/math_render/math_render.dart'
    show
        MathRender,
        EquationSolver,
        ZoomableImage,
        hasEquation,
        hasTable,
        applySourceLineBreaks,
        extractKatexAnnotation,
        extractMathML,
        fixInlineExamMath,
        fixUndefinedLatexCommands,
        supportHtmlLists,
        convertMsOfficeMathToLatex;
export 'src/math_render/theme.dart';
export 'src/ast/size.dart' show MathSize;
export 'src/ast/style.dart' show MathStyle;
export 'src/encoder/exception.dart';
export 'src/parser/tex/parse_error.dart';
export 'src/parser/tex/settings.dart';
export 'src/widgets/exception.dart';
export 'src/widgets/math.dart';
export 'src/widgets/selectable.dart' show SelectableMath, MathToolbarOptions;
