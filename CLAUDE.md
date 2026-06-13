# texterm — project notes for AI assistants

A macOS terminal (Swift + AppKit + WKWebView + xterm.js) that renders inline LaTeX
math. This file records the non-obvious invariants. Respect them or things break in
subtle, hard-to-debug ways.

## Build / run / test

```
make setup     # one-time: download KaTeX + xterm.js (+ addons) into Resources/
make cert      # one-time: stable self-signed code-signing identity (see below)
make build     # compile + bundle + sign  ->  .build/texterm.app
make install   # copy to ~/Applications (TCC/Full Disk Access is path-bound)
make test      # node unit tests (isMathContent)
make dmg       # package a distributable .dmg
```

There is no Xcode project; the Makefile drives `swiftc` + `clang` directly.
Rebuild+reinstall after source changes:
`killall texterm; make build && make install`.

## Architecture

- **PTY** (`PTY.swift` + `pty_spawn.c`): `posix_openpt` + a C `fork`/`exec` shim
  (Swift can't `fork` safely because the runtime spawns GCD threads). The shell is
  launched as a **login shell** — `argv[0] = "-zsh"` — so `~/.zprofile` runs and
  Homebrew's PATH (ffmpeg/node/...) is present. A non-login shell loses those tools.
- **Renderer bridge** (`TerminalWebView.swift`): WKWebView hosts xterm.js. Three
  `WKScriptMessageHandler` channels: `pty` (input), `resize` (winsize), `openURL`
  (clickable links). Output goes Swift -> JS via `writeOutput(base64)`.
- **Windows/tabs/splits** (`TerminalWindowController.swift`): native NSWindow
  tabbing + recursive `NSSplitView` panes. `AppDelegate` retains every controller.

## Invariants — do not break these

- **Math overlay reads buffer cells, not pixels.** Math is rendered by an absolutely
  positioned DOM overlay (`refreshMath` in `terminal.html`) layered over xterm's
  canvas; it re-scans only the visible rows for `$...$` on each render/scroll. This
  is why the renderer (DOM/canvas/WebGL) can change freely without touching the math
  path. `isMathContent` (in `Resources/xterm/mathdetect.js`, unit-tested) decides
  math vs. shell — edit it there, not inline, and keep `make test` green.
- **IME (CJK) is handled manually.** xterm's own `onData` loses all but the first
  jamo under WebKit, so composition is driven by `compositionstart`/`compositionend`
  and xterm's emission is suppressed while composing. Don't route IME through xterm.
- **Stable code signing.** Ad-hoc signing gives a new cdhash each build, so macOS
  re-prompts for TCC (Full Disk Access, Photos, ...) every rebuild. `make cert`
  creates a dedicated keychain + self-signed cert for a stable designated
  requirement; the build uses it automatically and falls back to ad-hoc if absent.
- **Close the PTY master fd off the main thread.** `close()` on a PTY master blocks
  in the kernel while the reader thread is still in `read()`, which hangs window
  close. `PTY.teardown` does `kill` + `waitpid` + `close` on a background queue.
- **Break the WKWebView script-handler retain cycle on teardown.** The
  userContentController strongly retains its handlers and the view owns the
  controller; `TerminalWebView.teardown()` must remove them or the window leaks.
- **A running WKWebView keeps the terminal.html it loaded at launch.** Editing
  `terminal.html` requires a rebuild+reinstall *and* relaunch to take effect —
  there is no live reload.

## Output path performance (already implemented)

- PTY reads are **coalesced** (~8ms windows) in `PTY.swift` before crossing to the
  main thread, so a busy shell doesn't fire one `evaluateJavaScript` per `read()`.
- Output crosses the bridge via **`callAsyncJavaScript`** with the base64 as an
  *argument* (not interpolated into the script source, which WebKit would recompile).
- KaTeX renders are **cached by formula**; `refreshMath` skips the DOM rebuild when
  the visible math set is unchanged.

## Known limits

- Math is detected only via `$...$` / `$$...$$`. Prose `$$` from Claude Code has its
  backslashes stripped by markdown escaping — wrap math in backtick code blocks.
- Inline images: Sixel + iTerm2 IIP only (addon-image); no kitty graphics protocol.

See `BACKLOG.md` for remaining ideas.
