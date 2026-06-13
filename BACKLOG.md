# texterm backlog

Pending work, roughly prioritized. The performance/stability items were verified
against the current code (notes inline). Check items off as they ship.

## Performance

- [ ] **GPU renderer** (high) — texterm loads no renderer addon, so it uses the
      default DOM renderer (the slowest). Add `@xterm/addon-canvas` (safe with the
      image addon) or `@xterm/addon-webgl` (fastest; verify image-addon compat
      first). Biggest win for heavy output (build logs, `cat` large files, `ls -R`).
- [ ] **Coalesce PTY output** (high) — `PTY.startReading` does one
      `DispatchQueue.main.async` + `evaluateJavaScript` per `read()` chunk. Batch
      reads into ~1 frame (8-16ms) windows to cut eval count and main-thread load.
- [ ] **callAsyncJavaScript** (medium) — `writeOutput` interpolates the base64 into
      a script string (`writeOutput('<~85KB>')`) that WebKit recompiles every call.
      Pass the base64 as an argument via `callAsyncJavaScript` instead.
- [ ] **Cache KaTeX + diff overlay** (medium) — `buildLineHtml` calls
      `katex.renderToString` for every formula on every scan, and `refreshMath`
      rebuilds the whole overlay (`innerHTML=''`). Cache HTML by formula string and
      update only changed rows.

## Stability

- [ ] **WebKit crash recovery** — no `webViewWebContentProcessDidTerminate`; if the
      web content process dies (OOM, etc.) the terminal goes blank permanently.
      Implement it to reload terminal.html and reconnect the PTY.
- [ ] **Reap child process** — no `waitpid`/`SIGCHLD`; exited shells linger as
      zombies. Reap them.
- [ ] **Minor** — debounce window-resize fit; ignore broken-pipe write errors.

## Tooling / dev (borrow #3 from md-lens)

- [ ] **Tests** — none yet. Start with `isMathContent` (pure function, easy to unit
      test) — port the Node checks used during development.
- [ ] **Quality-gate hook** — PostToolUse hook that builds + lints edited Swift/JS
      (cf. md-lens `.claude/hooks/go-quality.sh`).
- [ ] **Project CLAUDE.md** — record invariants: math-overlay model, IME via
      `compositionend`, stable signing, login shell, and the stale-WKWebView gotcha
      (a running WKWebView keeps the terminal.html it loaded at launch).
- [ ] **/release skill** — codesign + package `.dmg`, version bump, GitHub release.

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
