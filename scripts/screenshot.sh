#!/bin/bash
# Run an app on a virtual 360x720 screen and photograph it.
#
#   scripts/screenshot.sh keep [output-dir]
#
# The point is not the pictures, it is that there is any way at all to see these
# apps without a phone. GTK4 needs a display server; Xvfb is one, and the cairo
# renderer draws the same pixels the PinePhone does, because a Mali-400 has no
# usable GL context either and GTK falls back to software there too.
#
# This file is the harness. *What* to photograph is apps/<app>/shots.sh, which
# runs with `shot`, `shot_click` and `shot_longpress` already defined -- because
# the list is the only part that differs between a notes app and a habit
# tracker, and it was the only part worth copying.
set -uo pipefail
cd "$(dirname "$0")/.."

app="${1:?usage: screenshot.sh <app> [out]}"
[[ -d "apps/$app" ]] || { echo "no such app: $app" >&2; exit 1; }

OUT="${2:-apps/$app/docs/screenshots}"
DIR="${DIR:-/tmp/moarchy-$app-shots}"
SIZE="${SIZE:-360x720}"
DISPLAY_NUM="${DISPLAY_NUM:-:99}"
UP=$(tr '[:lower:]' '[:upper:]' <<<"$app")
MODULE=$(basename "$(find "apps/$app" -maxdepth 1 -name 'moarchy_*' -type d)")

command -v Xvfb >/dev/null || { echo "no Xvfb -- run inside docker/Dockerfile.dev" >&2; exit 1; }

mkdir -p "$OUT" "$DIR"; rm -f "$DIR"/*.json
Xvfb "$DISPLAY_NUM" -screen 0 "${SIZE}x24" -nolisten tcp >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
for _ in $(seq 30); do DISPLAY="$DISPLAY_NUM" xdpyinfo >/dev/null 2>&1 && break; sleep 0.2; done

export DISPLAY="$DISPLAY_NUM" PYTHONPATH="$PWD/shared:$PWD/apps/$app"
export "MOARCHY_${UP}_DIR=$DIR"
# Demo data is dated relative to today, so pin today: a shot taken on a Sunday
# and one taken on a Monday would otherwise disagree about which column is
# which, for reasons that have nothing to do with the app.
export "MOARCHY_${UP}_TODAY=${TODAY:-2026-09-12}"

# THEME=/path/to/colors.toml photographs the app under a real Omarchy palette
# rather than the stand-in one. It is staged where omarchy-theme-set puts the
# active theme, because that is the only place an app looks.
if [[ -n ${THEME:-} ]]; then
  STAGE="$HOME/.local/state/omarchy/current/theme"
  mkdir -p "$STAGE"; cp "$THEME" "$STAGE/colors.toml"
  echo "==> theme: $THEME"
fi

python3 "apps/$app/demo.py" >/dev/null

# Wait for the window to be on screen rather than sleeping a guessed number of
# seconds. Sleeping was the cause of a popover that photographed as closed: on a
# slower start the tap landed before the button existed, and nothing said so.
wait_window() {
  for _ in $(seq 80); do
    xdotool search --onlyvisible --name "${WINDOW:-.}" >/dev/null 2>&1 && { sleep "${SETTLE:-2}"; return 0; }
    sleep 0.25
  done
  echo "    the window never appeared" >&2; return 1
}

_launch() {
  # dbus-run-session, because GApplication registers on the session bus and
  # complains at length when there is not one.
  env "$@" dbus-run-session -- python3 -m "$MODULE" >"$LOG" 2>&1 &
  APP_PID=$!
}

_finish() {
  local name="$1"
  import -window root "$OUT/$name.png" 2>/dev/null
  kill "$APP_PID" 2>/dev/null; wait "$APP_PID" 2>/dev/null
  printf '%-12s %s\n' "$name" "$OUT/$name.png"
  # `|| true`, because under pipefail a grep that finds nothing would make the
  # happy path exit non-zero.
  { grep -E 'WARNING|CRITICAL|Traceback' "$LOG" \
    | grep -vE 'portal|a11y|dbus-daemon|fuse|SpiRegistry' | sort -u | sed 's/^/    /'; } || true
}

shot() {
  local name="$1"; shift
  LOG="$DIR/$name.log"
  _launch "$@"
  wait_window
  # Park the pointer in the corner. It starts in the middle of the screen, which
  # is usually over something with a tooltip -- which photographed as a black
  # tooltip across the middle of the first list shot.
  xdotool mousemove 359 719
  sleep 0.6
  _finish "$name"
}

# One shot may need a tap: a popover is not something an environment variable
# can open. xdotool has a pointer, and the button is at a known place in a
# window of a known size.
shot_click() {
  local name="$1" x="$2" y="$3"; shift 3
  LOG="$DIR/$name.log"
  _launch "$@"
  wait_window
  # The pointer stays on the button it pressed. Moving it afterwards dismisses
  # the popover -- there is no window manager here, so focus follows the
  # pointer, and a pointer that leaves takes the focus with it.
  xdotool mousemove "$x" "$y" click 1
  sleep 1.2
  import -window root "$OUT/$name.png" 2>/dev/null
  # Dismiss before the app is killed. A process that dies with a popover open
  # leaves its pointer grab behind on this display, and the next app's first
  # click is swallowed by it -- which showed up as a popover that photographed
  # as closed, two shots later and with nothing in any log.
  xdotool key Escape; sleep 0.3
  kill "$APP_PID" 2>/dev/null; wait "$APP_PID" 2>/dev/null
  printf '%-12s %s\n' "$name" "$OUT/$name.png"
  { grep -E 'WARNING|CRITICAL|Traceback' "$LOG" \
    | grep -vE 'portal|a11y|dbus-daemon|fuse|SpiRegistry' | sort -u | sed 's/^/    /'; } || true
}

# Long press: mousedown, wait past the gesture's threshold, mouseup.
shot_longpress() {
  local name="$1" x="$2" y="$3"; shift 3
  LOG="$DIR/$name.log"
  _launch "$@"
  wait_window
  xdotool mousemove "$x" "$y" mousedown 1
  sleep 1.2
  xdotool mouseup 1
  sleep 1.2
  import -window root "$OUT/$name.png" 2>/dev/null
  xdotool key Escape; sleep 0.3
  kill "$APP_PID" 2>/dev/null; wait "$APP_PID" 2>/dev/null
  printf '%-12s %s\n' "$name" "$OUT/$name.png"
  { grep -E 'WARNING|CRITICAL|Traceback' "$LOG" \
    | grep -vE 'portal|a11y|dbus-daemon|fuse|SpiRegistry' | sort -u | sed 's/^/    /'; } || true
}

# shellcheck source=/dev/null
source "apps/$app/shots.sh"
