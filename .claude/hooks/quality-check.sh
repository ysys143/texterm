#!/bin/sh
# PostToolUse quality gate for texterm. When a source file is edited, run the
# relevant fast check and surface failures. Advisory: always exits 0 so it never
# blocks an edit -- it just reports, in the spirit of soft enforcement.
#
# Wired in .claude/settings.json on Edit|Write|MultiEdit.

input=$(cat)
# Pull "file_path":"..." out of the tool-input JSON without needing jq.
path=$(printf '%s' "$input" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -n "$path" ] || exit 0

root="${CLAUDE_PROJECT_DIR:-$(CDPATH= cd "$(dirname "$0")/../.." && pwd)}"
cd "$root" || exit 0

case "$path" in
  *.swift|*.c|*.h)
    echo "[texterm quality] ${path##*/} changed -> make build" >&2
    if make build 2>&1 | grep -iE 'error:' >&2; then
      echo "[texterm quality] BUILD ERRORS above" >&2
    else
      echo "[texterm quality] build OK" >&2
    fi
    ;;
  */mathdetect.js|*/tests/*.js)
    echo "[texterm quality] ${path##*/} changed -> make test" >&2
    node tests/mathdetect.test.js >&2 2>&1 || echo "[texterm quality] TESTS FAILED above" >&2
    ;;
  *) ;;  # other files (html, css, docs): no automated check
esac

exit 0
