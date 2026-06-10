<h1 align="center">texterm</h1>

<p align="center">
  <b>English</b> · <a href="./README.ko.md">한국어</a>
</p>

<p align="center">
  A macOS terminal that renders the math from Claude Code and Codex as <b>inline LaTeX</b>.<br/>
  When <code>$...$</code> / <code>$$...$$</code> shows up in the output, it's typeset in place with KaTeX.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13+-000000?logo=apple&logoColor=white" alt="macOS 13+" />
  <img src="https://img.shields.io/badge/Swift-AppKit_%2B_WebKit-F05138?logo=swift&logoColor=white" alt="Swift + WebKit" />
  <img src="https://img.shields.io/badge/terminal-xterm.js-2ea043" alt="xterm.js" />
  <img src="https://img.shields.io/badge/math-KaTeX-0a7ea4" alt="KaTeX" />
</p>

<p align="center">
  <img src="./docs/hero.png" alt="texterm rendering inline LaTeX in the terminal" width="700" />
</p>

---

A terminal shows `\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}` as literal backslashes. texterm keeps a real terminal (a full VT emulator) underneath and paints typeset math over any line that contains `$...$`.

## Features

- **Inline math rendering** — visible rows are scanned for `$...$` / `$$...$$` and typeset with KaTeX, debounced so it keeps up with fast output.
- **Real terminal** — [xterm.js](https://xtermjs.org/) handles cursor addressing, line editing, scrollback, selection, and alternate-screen TUIs, so full-screen apps like `claude` and `codex` work as-is.
- **Correct CJK/IME input** — Korean/Japanese/Chinese composition is handled explicitly so it doesn't break under WebKit.
- **Font & line spacing** — `Cmd +/-` for font size, `Cmd+Shift +/-` for line spacing, so tall math (fractions, integrals, matrices) gets room to breathe. Both settings persist across launches.
- **Stable code signing** — one `make cert` keeps macOS permission grants from resetting on every rebuild.

## Preview

<p align="center">
  <img src="./docs/screenshot.png" alt="Claude Code running inside texterm" width="520" />
</p>

## Install

Requirements: macOS 13+, Xcode command-line tools (`swiftc`, `clang`, `codesign`), and `npm` for downloading assets.

```sh
make setup     # download KaTeX + xterm.js into Resources/ (once)
make cert      # create a stable self-signed signing identity (once; see Permissions)
make build     # build the .app
make install   # install to ~/Applications/texterm.app
```

`make run` builds and launches in one step.

## Using with Claude Code / Codex

By default `claude` and `codex` print math as Unicode (`²`, `√`, `±`), which has no `$` delimiters, and bare `$...$` in prose gets mangled because the terminal's markdown strips LaTeX backslashes (`\\`, `\!`, `\,`). So wrap math in **backtick code** to preserve the raw LaTeX — then texterm renders it correctly.

Drop one paragraph into `~/.claude/CLAUDE.md` (global) or a project `CLAUDE.md` so you don't have to repeat it:

```
Always output math as raw LaTeX wrapped in inline code (backticks).
  inline: `$ ... $`      display / matrices: `$$ ... $$`
Don't convert to Unicode/ASCII art; use \frac for fractions; keep each formula on one line.
```

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `Cmd +` / `Cmd =` | Zoom in (font) |
| `Cmd -` | Zoom out (font) |
| `Cmd 0` | Reset font size |
| `Cmd+Shift +` / `Cmd+Shift -` | Line spacing |
| `Cmd+Shift 0` | Reset line spacing |
| `Cmd C` / `Cmd V` | Copy / paste |

## Full Disk Access

A terminal is the responsible app for everything it runs, so when a child process (shell init, `claude`, a plugin) reads `~/Pictures`, `~/Music`, or another app's data, macOS attributes it to texterm and prompts.

`make cert` gives the app a **stable, certificate-based identity**, so a permission you grant survives rebuilds (ad-hoc signing changes the binary hash every build, and macOS then re-prompts every time). After `make install`, grant it once:

> System Settings → Privacy & Security → Full Disk Access → `+` → `~/Applications/texterm.app`

To undo the signing setup: `security delete-keychain ~/Library/Keychains/texterm-codesign.keychain-db`

## How it works

Swift + AppKit + WebKit, compiled directly with `swiftc` (no Xcode project).

- **PTY** — `pty_spawn.c` does `fork()` + `exec()` (Swift can't call `fork()` because of GCD); `PTY.swift` wraps it with `posix_openpt`.
- **Terminal** — vendored xterm.js is the VT emulator. Output is sent as base64 across the JS bridge into `term.write()`.
- **Input** — xterm.js owns the keyboard. IME is handled separately: xterm derives composed text by diffing its hidden textarea, which under WebKit loses all but the first jamo of each Korean syllable, so texterm sends the fully-composed string from the `compositionend` event straight to the PTY.
- **Math** — on each render/scroll the visible rows are scanned, wrapped logical lines are rejoined, candidates are filtered (math vs. shell/path/code), and survivors are typeset with KaTeX into absolutely-positioned overlay rows whose opaque background hides the raw source on the canvas.

## Limitations

- Math is detected only by `$...$` / `$$...$$` delimiters in the output.
- Bare `$$` in prose can be mangled by Claude Code stripping backslashes — wrap it in code.
- Tall math overflows above/below its row, so it looks best when the formula is on its own line (use `Cmd+Shift +` for more spacing).
- Not sandboxed (a PTY needs `fork`/`exec`) — intended as a personal terminal, not for distribution.
