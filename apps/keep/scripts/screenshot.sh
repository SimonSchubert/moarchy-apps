#!/bin/bash
# Run the app on a virtual 360x720 screen and photograph it.
#
# The point is not the pictures, it is that there is any way at all to see this
# app without a phone. GTK4 needs a display server; Xvfb is one, and the cairo
# renderer draws the same pixels the PinePhone does, because a Mali-400 has no
# usable GL context either and GTK falls back to software there too.
#
#   ./scripts/screenshot.sh [output-dir]
#
# Each shot is a separate run of the app, driven by MOARCHY_KEEP_OPEN rather
# than by synthesised taps: a headless X server has no pointer worth clicking
# with, and a run that opens straight into the note it should photograph needs
# none.
set -uo pipefail

OUT="${1:-docs/screenshots}"
DIR="${MOARCHY_KEEP_DIR:-/tmp/moarchy-keep-shots}"
SIZE="${SIZE:-360x720}"
DISPLAY_NUM="${DISPLAY_NUM:-:99}"

mkdir -p "$OUT" "$DIR"
rm -f "$DIR"/notes.json

command -v Xvfb >/dev/null || { echo "no Xvfb -- run this inside docker/Dockerfile.dev" >&2; exit 1; }

Xvfb "$DISPLAY_NUM" -screen 0 "${SIZE}x24" -nolisten tcp >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
for _ in $(seq 30); do
  DISPLAY="$DISPLAY_NUM" xdpyinfo >/dev/null 2>&1 && break
  sleep 0.2
done

export DISPLAY="$DISPLAY_NUM" MOARCHY_KEEP_DIR="$DIR"

# THEME=/path/to/colors.toml photographs the app under a real Omarchy palette
# rather than the stand-in one. It is staged where omarchy-theme-set puts the
# active theme, because that is the only place the app looks.
if [[ -n ${THEME:-} ]]; then
  STAGE="$HOME/.local/state/omarchy/current/theme"
  mkdir -p "$STAGE"
  cp "$THEME" "$STAGE/colors.toml"
  echo "==> theme: $THEME"
fi
MOARCHY_KEEP_DIR="$DIR" python3 scripts/demo-notes.py >/dev/null

# Wait for the window to be on screen rather than sleeping a guessed number of
# seconds. Sleeping was the cause of a popover that photographed as closed: on
# a slower start the tap landed before the button existed, and nothing said so.
wait_window() {
  for _ in $(seq 80); do
    xdotool search --onlyvisible --name "Note" >/dev/null 2>&1 && { sleep "${SETTLE:-1.5}"; return 0; }
    sleep 0.25
  done
  echo "    the window never appeared" >&2
  return 1
}

shot() {
  local name="$1"; shift
  local log="$DIR/$name.log"
  # dbus-run-session, because GApplication registers itself on the session bus
  # and complains at length when there is not one.
  env "$@" dbus-run-session -- python3 -m moarchy_keep >"$log" 2>&1 &
  local app=$!
  wait_window
  import -window root "$OUT/$name.png" 2>/dev/null
  kill $app 2>/dev/null
  wait $app 2>/dev/null
  printf '%-16s %s\n' "$name" "$OUT/$name.png"
  # Any GTK complaint is a real defect in a layout this simple; print it here
  # rather than leaving it in a log nobody opens.
  grep -E 'WARNING|CRITICAL|Traceback' "$log" | sort -u | sed 's/^/    /'
}

# One shot needs a tap: the colour picker is a popover, and there is no
# environment variable that opens a popover. xdotool has a pointer, and the
# button is at a known place in a window of a known size.
shot_click() {
  local name="$1" x="$2" y="$3"; shift 3
  local log="$DIR/$name.log"
  env "$@" dbus-run-session -- python3 -m moarchy_keep >"$log" 2>&1 &
  local app=$!
  wait_window
  # The pointer stays on the button it pressed. Moving it afterwards dismisses
  # the popover -- there is no window manager here, so focus follows the
  # pointer, and a pointer that leaves takes the focus with it. GTK suppresses
  # the button's tooltip from the press until the pointer leaves and returns,
  # so staying put is also what keeps the tooltip out of the picture.
  xdotool mousemove "$x" "$y" click 1
  sleep 1.2
  import -window root "$OUT/$name.png" 2>/dev/null
  # Dismiss the popover before the app is killed. A process that dies with one
  # open leaves its pointer grab behind on this display, and the next app's
  # first click is swallowed by it -- which showed up as a popover that
  # photographed as closed, two shots later and with nothing in any log.
  xdotool key Escape
  sleep 0.3
  kill $app 2>/dev/null
  wait $app 2>/dev/null
  printf '%-16s %s\n' "$name" "$OUT/$name.png"
  grep -E 'WARNING|CRITICAL|Traceback' "$log" | sort -u | sed 's/^/    /'
}

# Long press, which is how a card is pinned, recoloured or deleted without
# opening it. mousedown, wait past the gesture's threshold, mouseup.
shot_longpress() {
  local name="$1" x="$2" y="$3"; shift 3
  local log="$DIR/$name.log"
  env "$@" dbus-run-session -- python3 -m moarchy_keep >"$log" 2>&1 &
  local app=$!
  wait_window
  xdotool mousemove "$x" "$y" mousedown 1
  sleep 1.2
  xdotool mouseup 1
  sleep 1.2
  import -window root "$OUT/$name.png" 2>/dev/null
  # Dismiss the popover before the app is killed. A process that dies with one
  # open leaves its pointer grab behind on this display, and the next app's
  # first click is swallowed by it -- which showed up as a popover that
  # photographed as closed, two shots later and with nothing in any log.
  xdotool key Escape
  sleep 0.3
  kill $app 2>/dev/null
  wait $app 2>/dev/null
  printf '%-16s %s\n' "$name" "$OUT/$name.png"
  grep -E 'WARNING|CRITICAL|Traceback' "$log" | sort -u | sed 's/^/    /'
}

shot grid
shot_longpress card-menu 90 130
shot note-list  MOARCHY_KEEP_OPEN=Shopping
shot note-text  MOARCHY_KEEP_OPEN=Sourdough
shot_click colours "${COLOUR_BUTTON_X:-178}" 28 MOARCHY_KEEP_OPEN=Sourdough
