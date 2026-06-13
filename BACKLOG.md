# texterm backlog

Pending work, roughly prioritized. The performance/stability items were verified
against the current code (notes inline). Check items off as they ship.

## Performance

- [x] **GPU renderer** (high) — WebGL renderer (`@xterm/addon-webgl`) with graceful
      fallback to canvas then DOM, loaded in `terminal.html`. The image addon and the
      math overlay are renderer-agnostic (overlay reads buffer cells, not pixels).
- [x] **Coalesce PTY output** (high) — `PTY.startReading` now buffers reads and
      flushes once per ~8ms window on the main thread, instead of one dispatch +
      `evaluateJavaScript` per `read()` chunk.
- [x] **callAsyncJavaScript** (medium) — `writeOutput` passes the base64 as an
      argument via `callAsyncJavaScript`, so WebKit no longer recompiles a multi-KB
      script-source string per chunk.
- [x] **Cache KaTeX + diff overlay** (medium) — `renderMath` memoizes
      `katex.renderToString` by formula; `refreshMath` short-circuits the DOM rebuild
      when the visible math set + geometry are unchanged.

## Stability

- [x] **WebKit crash recovery** — `webViewWebContentProcessDidTerminate` reloads
      terminal.html; the PTY/shell live in Swift and reconnect to the fresh page
      (only on-screen scrollback is lost).
- [x] **Reap child process** — `waitpid` on EOF and in teardown, so exited shells
      don't linger as zombies.
- [x] **Minor** — window-resize fit is debounced (~60ms); broken-pipe writes are
      already non-fatal (the `Darwin.write` result is discarded).

## Tooling / dev (borrow #3 from md-lens)

- [x] **Tests** — `tests/mathdetect.test.js` covers `isMathContent` (extracted to
      `Resources/xterm/mathdetect.js`). Run with `make test`.
- [x] **Quality-gate hook** — `.claude/hooks/quality-check.sh` (PostToolUse) builds
      on Swift/C edits and runs the tests on math-detector edits. Advisory only.
- [x] **Project CLAUDE.md** — invariants recorded (math-overlay model, IME,
      stable signing, login shell, off-main-thread PTY close, stale-WKWebView).
- [~] **/release** — `make dmg` packages a signed `.dmg` (version from Info.plist).
      Remaining: automated version bump + `gh release` upload.

## Ideas / known limits

- Math is detected only via `$...$` / `$$...$$`. Prose `$$` from Claude Code has its
  backslashes stripped by markdown escaping — wrap math in backtick code.
- Images: only Sixel + iTerm2 IIP (addon-image); the kitty graphics protocol is not
  supported. Could advertise `TERM_PROGRAM=iTerm.app` so tools auto-pick IIP without
  `--force-iterm` (caveat: tools may then try other iTerm2 escapes texterm lacks).

## Done

See git history / README. Highlights: inline LaTeX rendering, CJK IME fix,
font + line-spacing controls (persisted), stable code signing, app icon,
clickable links, inline images, login shell + home cwd.
