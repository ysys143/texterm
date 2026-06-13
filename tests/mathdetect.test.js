// Unit tests for isMathContent (Resources/xterm/mathdetect.js). Pure JS, no deps.
// Run: node tests/mathdetect.test.js   (or `make test`)
//
// These encode the real false-positive / false-negative cases worked through
// during development: real math must render; shell vars, paths, prices, and code
// must not. The `inner` strings are what lands between the `$...$` delimiters.
'use strict';

const path = require('path');
const { isMathContent } = require(path.join(__dirname, '..', 'Resources', 'xterm', 'mathdetect.js'));

// [inner, expected, why]
const cases = [
  // --- real math: must render -------------------------------------------------
  ['\\theta', true, 'bare LaTeX command'],
  [' \\theta ', true, 'padded math (trimmed)'],
  ['\\frac{1}{2}', true, 'fraction'],
  ['\\|v\\|', true, 'norm (backslash bars)'],
  ['x = \\sqrt{2}', true, 'equation with sqrt'],
  ['p(x;\\theta)', true, 'semicolon inside backslash math'],
  ['a < b', false, 'inequality without backslash is ambiguous -> reject'],
  ['\\langle a, b \\rangle', true, 'angle brackets via commands'],
  ['E=mc^2', true, 'tight equation, no spaces'],
  ['E = mc^2', true, 'spaced equation with operator'],
  ['a + b', true, 'spaced sum'],
  ['n', true, 'single token variable'],
  ['x^2', true, 'superscript'],
  ['a_i', true, 'subscript'],
  // Ambiguous but renders by design: a single token ($n$, $x$) and a tight
  // assignment ($E=mc$) are indistinguishable from a stray $PATH$ / $FOO=bar$.
  // We favour rendering real one-symbol math; bare-token false positives are rare.
  ['PATH', true, 'single token renders (same shape as $n$)'],
  ['FOO=bar', true, 'tight assignment renders (same shape as $E=mc$)'],

  // --- shell / paths / code: must NOT render ----------------------------------
  ['', false, 'empty'],
  ['   ', false, 'whitespace only'],
  ['HOME and', false, 'prose between $HOME and ...'],
  ['5', false, 'price $5'],
  ['1', false, 'positional param $1'],
  ['5.00', false, 'decimal price'],
  ['FOO= bar', false, 'standalone shell assignment (name= followed by space)'],
  ['export FOO=', false, 'trailing assignment token'],
  ['base..head', false, 'git revision range'],
  ['../relative', false, 'relative path'],
  ['/usr/bin', false, 'absolute path (slash)'],
  ['a | b', false, 'pipe'],
  ['x & y', false, 'ampersand'],
  ['"quoted"', false, 'double quote'],
  ["'quoted'", false, 'single quote'],
  ['`cmd`', false, 'backtick command substitution'],
  ['HOME and PATH', false, 'multi-word prose, no math operator'],
];

let pass = 0, fail = 0;
for (const [inner, expected, why] of cases) {
  const got = isMathContent(inner);
  if (got === expected) {
    pass++;
  } else {
    fail++;
    console.error(`FAIL: isMathContent(${JSON.stringify(inner)}) = ${got}, expected ${expected}  (${why})`);
  }
}

console.log(`${pass}/${pass + fail} passed`);
process.exit(fail === 0 ? 0 : 1);
