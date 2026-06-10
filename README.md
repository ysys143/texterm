# texterm

A macOS terminal that renders inline LaTeX math. When a program you run prints
`$...$` or `$$...$$`, texterm typesets it with [KaTeX](https://katex.org/)
directly over the terminal grid — so math from Claude Code, Codex, or a plain
`cat file.tex` shows up as real notation instead of raw source.

![texterm rendering inline LaTeX from Claude Code](docs/screenshot.png)

## Why

Terminals show `\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}` as literal
backslashes. texterm keeps the real terminal underneath (it is a full VT
emulator) but paints typeset math on top of any line that contains `$...$`.

## Features

- **Inline math rendering** — `$...$` and `$$...$$` are detected on visible
  rows and rendered with KaTeX, debounced so it keeps up with fast output.
- **Real terminal core** — [xterm.js](https://xtermjs.org/) handles cursor
  addressing, line editing, scrollback, selection, and alternate-screen TUIs.
- **Correct CJK/IME input** — Korean/Japanese/Chinese composition is handled
  explicitly so it doesn't break under WebKit (see Architecture).
- **Font zoom** — `Cmd +` / `Cmd -` / `Cmd 0`, which reflows the PTY.
- **Stable code signing** — one `make cert` keeps macOS permission grants from
  resetting on every rebuild.

## Requirements

- macOS 13+
- Xcode command-line tools (`swiftc`, `clang`, `codesign`)
- `npm` (only for `make setup`, to vendor KaTeX + xterm.js)

## Build and run

```sh
make setup     # download KaTeX + xterm.js into Resources/ (once)
make cert      # create a stable self-signed signing identity (once; see below)
make build     # compile the .app
make run       # build + launch
```

Install to a fixed location (recommended for daily use):

```sh
make install   # copies to ~/Applications/texterm.app
```

## Permissions (Full Disk Access)

A terminal is the "responsible app" for everything it runs, so when a child
process (your shell init, `claude`, a plugin) reads `~/Pictures`, `~/Music`, or
another app's data, macOS attributes it to texterm and prompts.

`make cert` gives the app a **stable, certificate-based identity**, so a
permission you grant survives rebuilds (ad-hoc `codesign -s -` changes the
binary hash every build and macOS re-prompts forever). After `make install`,
grant the app **Full Disk Access** once:

> System Settings -> Privacy & Security -> Full Disk Access -> `+` ->
> `~/Applications/texterm.app`

Then quit and relaunch. Reverse the signing setup any time with
`security delete-keychain ~/Library/Keychains/texterm-codesign.keychain-db`.

## Using it with Claude Code / Codex

By default these tools print math as Unicode/ASCII art (`²`, `√`, `±`), which has
no `$` delimiters for texterm to detect. To get rendered math, ask for **raw
LaTeX**:

```
Output the math wrapped in backtick inline code as raw LaTeX `$...$`.
Use \frac (not a / slash) for fractions.
```

To make it automatic, add a line to your `CLAUDE.md`:

```
Always write math as $...$ (inline) or $$...$$ (display) LaTeX.
Do not convert to Unicode/ASCII art. Use \frac for fractions.
```

Note: the detector deliberately ignores `$...$` spans that look like shell
variables, paths, or code (`"`, `/`, `;`, `name=`, `..`), so paths like
`"$CLAUDE_PLUGIN_ROOT"/scripts` are left untouched. Use `\frac` rather than a
literal `/` so fractions aren't skipped.

## Keyboard

| Shortcut | Action |
|----------|--------|
| `Cmd +` / `Cmd =` | Zoom in |
| `Cmd -` | Zoom out |
| `Cmd 0` | Reset zoom |
| `Cmd C` / `Cmd V` | Copy / paste |

## Architecture

Swift + AppKit + WebKit, compiled with `swiftc` (no Xcode project).

- **PTY** — `pty_spawn.c` does `fork()` + `exec()` (Swift marks `fork()`
  unavailable because GCD-after-fork is unsafe); `PTY.swift` wraps it with
  `posix_openpt`.
- **Terminal** — xterm.js (vendored) is the VT emulator. Output is sent as
  base64 over the JS bridge and handed to `term.write()`.
- **Input** — xterm.js owns the keyboard via its hidden textarea; `onData` ->
  WKScriptMessageHandler -> PTY. **IME is custom-handled**: xterm derives
  composed text by diffing the textarea across deferred reads, which loses all
  but the first jamo of each Korean syllable under WebKit, so texterm instead
  reads the fully-composed string from the `compositionend` event and sends it
  directly.
- **Math** — on each render/scroll, visible rows are scanned for `$...$`,
  wrapped logical lines are rejoined, candidates are filtered (math vs.
  shell/path/code), and survivors are rendered into absolutely-positioned
  overlay rows whose opaque background hides the raw source on the canvas.

## Limitations

- Math is detected only by `$...$` / `$$...$$` delimiters in the output.
- Tall math (`\dfrac`, integrals) overflows above/below its row, so it looks
  best when the formula is on its own line.
- Not sandboxed (a PTY needs `fork`/`exec`); intended as a personal terminal,
  not for distribution.
