#!/bin/bash
# Everything that can be checked without a phone.
#
#   ruff        -- style and dead code
#   unittest    -- the storage layer, which is deliberately GTK-free
#   a real run  -- the app, on a virtual screen, failing on any GTK warning
#
# That last one is the one that matters. A GTK layout error is not an
# exception: the app starts, the window appears, and one widget is the wrong
# size or missing entirely, with a single line on stderr as the only sign. On a
# phone that line goes to a journal nobody reads.
set -uo pipefail

status=0
run() { printf '\n==> %s\n' "$*"; "$@" || status=1; }

if command -v ruff >/dev/null; then
  run ruff check moarchy_keep tests scripts
  run ruff format --check moarchy_keep tests scripts
else
  echo "ruff not installed -- skipping lint"
fi

if ! command -v Xvfb >/dev/null; then
  # The widget tests skip themselves without a display, so this still checks
  # the storage layer -- which is the half that can lose someone's notes.
  echo "no Xvfb -- the widget tests will skip (use docker/Dockerfile.dev)"
  run python3 -m unittest discover -s tests -v
  exit $status
fi

DIR=$(mktemp -d)
export MOARCHY_KEEP_DIR="$DIR" DISPLAY=:98
Xvfb :98 -screen 0 360x720x24 -nolisten tcp >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null; rm -rf "$DIR"' EXIT
for _ in $(seq 30); do xdpyinfo >/dev/null 2>&1 && break; sleep 0.2; done

# With a display up, unittest picks up the widget tests as well as the storage
# ones.
run dbus-run-session -- python3 -m unittest discover -s tests -v

printf '\n==> a real run, at 360x720\n'
MOARCHY_KEEP_DIR="$DIR" python3 scripts/demo-notes.py >/dev/null

log="$DIR/run.log"
# Exercise both pages in one run: the grid, then an open note.
MOARCHY_KEEP_OPEN=Shopping dbus-run-session -- python3 -m moarchy_keep >"$log" 2>&1 &
app=$!
sleep "${SETTLE:-5}"
kill $app 2>/dev/null
wait $app 2>/dev/null

# The portal and a11y warnings belong to the container, not to us: there is no
# desktop session behind this X server for either to connect to. Everything
# else is ours.
complaints=$(grep -E 'WARNING|CRITICAL|ERROR|Traceback' "$log" | grep -vE 'portal|a11y|dbus-daemon|fuse' | sort -u)
if [[ -n $complaints ]]; then
  echo "the run complained:"
  printf '%s\n' "$complaints" | sed 's/^/    /'
  status=1
else
  echo "clean"
fi

exit $status
