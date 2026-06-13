// Math-vs-shell detection, extracted so it can be unit-tested under Node
// (tests/mathdetect.test.js) and loaded as a global by terminal.html. No deps.
//
// In a terminal `$` is overloaded (shell sigil, prompt, currency), so deciding
// whether a `$...$` candidate is real LaTeX vs. a shell variable / path / price /
// code fragment is the crux of avoiding mis-rendered output. Keep this logic here,
// covered by tests, rather than buried in the page script.
(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) {
    module.exports = api;                 // Node: require('.../mathdetect.js')
  } else {
    root.MathDetect = api;                // browser: window.MathDetect
    root.isMathContent = api.isMathContent;
  }
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  // Source pattern for $$...$$ / $...$ candidates. Callers build a fresh global
  // RegExp from it (a shared /g regex carries lastIndex state between scans).
  const MATH_PATTERN = '(\\$\\$[^$]+?\\$\\$|\\$[^$\\n]+?\\$)';

  // Decide whether the inside of a `$...$` pair is real math. Errs toward NOT
  // rendering: per the user, paths/code don't need typesetting, but mis-rendering
  // them is wrong.
  function isMathContent(inner) {
    // Surrounding padding ("$ \theta $") is just formatting; trim it and judge
    // the real content (KaTeX ignores leading/trailing whitespace anyway).
    inner = inner.trim();
    if (!inner) return false;
    // A LaTeX backslash command (\sqrt, \frac, \langle, \|, \infty, \theta,
    // \mathbb, \!, \,...) is an unambiguous math signal: shell/paths/code in a
    // terminal don't put backslashes inside a $...$ pair. Accept immediately so
    // real math can freely use |, <, >, ;, and padding (norms \|v\|, |x|,
    // inequalities a < b, args p(x;\theta), display `$$ ... $$`).
    if (inner.indexOf('\\') !== -1) return true;
    // No backslash below: be strict, because this is where shell false-positives
    // live. These chars are pervasive in terminal output (paths "$VAR"/a/b,
    // pipes, redirects, command substitution, quotes) but never appear in math.
    if (/["'`\/;|&<>]/.test(inner)) return false;
    // Shell assignment token (`name=` as a standalone word, e.g. `FOO=$BAR baz=`).
    // Inline math assigns `=` to an expression (`A=\pi`), never to whitespace/end.
    if (/(^|\s)[A-Za-z_][A-Za-z0-9_]*=(\s|$)/.test(inner)) return false;
    // Consecutive dots = git revision range ($base..$head) or a relative path,
    // never inline math (which uses \dots / \ldots, not literal `..`).
    if (/\.\./.test(inner)) return false;
    // A bare number is currency ($5) or a positional param ($1), not math.
    if (/^[\d.,]+$/.test(inner)) return false;
    // Multi-word prose / shell with no math structure ("$HOME and $PATH" ->
    // "HOME and", "$5 and the $" -> "5 and the"): a space but no math operator
    // means it isn't math. Tight tokens ("E=mc^2", "n") and operator-bearing
    // expressions ("E = mc^2", "a + b") still pass.
    if (/\s/.test(inner) && !/[=^_{}+]/.test(inner)) return false;
    return true;
  }

  return { isMathContent, MATH_PATTERN };
});
