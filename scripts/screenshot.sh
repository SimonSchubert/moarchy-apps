#!/bin/bash
# Run an app on a virtual 360x720 screen and photograph it.
#
#   scripts/screenshot.sh habits [output-dir]
#
# The point is not the pictures, it is that there is any way at all to see these
# apps without a phone. GTK4 needs a display server; Xvfb is one, and the cairo
# renderer draws the same pixels the PinePhone does, because a Mali-400 has no
# usable GL context either and GTK falls back to software there too.
#
# Each shot is a separate run, driven by MOARCHY_<APP>_OPEN rather than by
# synthesised taps: a headless X server has no pointer worth clicking with, and
# a run that opens straight into the page it should photograph needs none.
set -uo pipefail
cd "$(dirname "$0")/.."

app="${1:?usage: screenshot.sh <app> [out]}"
OUT="${2:-apps/$app/docs/screenshots}"
DIR="${DIR:-/tmp/moarchy-$app-shots}"
SIZE="${SIZE:-360x720}"
DISPLAY_NUM="${DISPLAY_NUM:-:99}"
UP=$(tr '[:lower:]' '[:upper:]' <<<"$app")
module=$(basename "$(find "apps/$app" -maxdepth 1 -name 'moarchy_*' -type d)")

command -v Xvfb >/dev/null || { echo "no Xvfb -- run inside docker/Dockerfile.dev" >&2; exit 1; }

mkdir -p "$OUT" "$DIR"; rm -f "$DIR"/*.json
Xvfb "$DISPLAY_NUM" -screen 0 "${SIZE}x24" -nolisten tcp >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
for _ in $(seq 30); do DISPLAY="$DISPLAY_NUM" xdpyinfo >/dev/null 2>&1 && break; sleep 0.2; done

export DISPLAY="$DISPLAY_NUM" PYTHONPATH="$PWD/shared:$PWD/apps/$app"
export "MOARCHY_${UP}_DIR=$DIR"
# The demo data is dated relative to today, so pin today: a shot taken on a
# Sunday and one taken on a Monday would otherwise disagree about which column
# is which, for reasons that have nothing to do with the app.
export "MOARCHY_${UP}_TODAY=${TODAY:-2026-09-12}"

# THEME=/path/to/colors.toml photographs the app under a real Omarchy palette
# rather than the stand-in one. It is staged where omarchy-theme-set puts the
# active theme, because that is the only place the app looks.
if [[ -n ${THEME:-} ]]; then
  STAGE="$HOME/.local/state/omarchy/current/theme"
  mkdir -p "$STAGE"; cp "$THEME" "$STAGE/colors.toml"
  echo "==> theme: $THEME"
fi

python3 "apps/$app/demo.py" >/dev/null

# Wait for the window rather than sleeping a guessed number of seconds.
wait_window() {
  for _ in $(seq 80); do
    xdotool search --onlyvisible --name "${WINDOW:-.}" >/dev/null 2>&1 && { sleep "${SETTLE:-2}"; return 0; }
    sleep 0.25
  done
  echo "    the window never appeared" >&2; return 1
}

shot() {
  local name="$1"; shift
  local log="$DIR/$name.log"
  # dbus-run-session, because GApplication registers on the session bus and
  # complains at length when there is not one.
  env "$@" dbus-run-session -- python3 -m "$module" >"$log" 2>&1 &
  local pid=$!
  wait_window
  # Park the pointer in the corner. It starts in the middle of the screen,
  # which is a mark -- and a mark under the pointer raises its tooltip, which
  # photographed as a black tooltip across the middle of the first list shot.
  xdotool mousemove 359 719
  sleep 0.6
  import -window root "$OUT/$name.png" 2>/dev/null
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  printf '%-12s %s\n' "$name" "$OUT/$name.png"
  # `|| true`, because under `pipefail` a grep that finds nothing makes the
  # function -- and then the script -- exit non-zero for the happy path.
  { grep -E 'WARNING|CRITICAL|Traceback' "$log" \
    | grep -vE 'portal|a11y|dbus-daemon|fuse|SpiRegistry' | sort -u | sed 's/^/    /'; } || true
}

shot list
shot detail "MOARCHY_${UP}_OPEN=Read"
shot editor "MOARCHY_${UP}_NEW=1"
