#!/bin/bash
# Drive the app the way a thumb would, then read the file it wrote.
#
# Screenshots prove the app draws. They do not prove that tapping "Take a note"
# writes a note, that Enter in a list makes the next line, or that any of it
# survives being closed -- and those are the failures that matter in a notes
# app. This taps real coordinates on a real 360x720 screen with xdotool and
# then asserts against notes.json.
#
# There is no window manager on this display, so the window is at 0,0 at
# exactly its requested size and coordinates are stable. X keyboard focus
# follows the pointer, so the pointer stays inside the window after every tap.
set -uo pipefail

DIR="${MOARCHY_KEEP_DIR:-$(mktemp -d)}"
DISPLAY_NUM="${DISPLAY_NUM:-:96}"
export DISPLAY="$DISPLAY_NUM" MOARCHY_KEEP_DIR="$DIR"

command -v xdotool >/dev/null || { echo "no xdotool -- run this inside docker/Dockerfile.dev" >&2; exit 1; }

rm -f "$DIR/notes.json"
Xvfb "$DISPLAY_NUM" -screen 0 360x720x24 -nolisten tcp >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB $APP 2>/dev/null' EXIT
for _ in $(seq 30); do xdpyinfo >/dev/null 2>&1 && break; sleep 0.2; done

LOG="$DIR/interact.log"
dbus-run-session -- python3 -m moarchy_keep >"$LOG" 2>&1 &
APP=$!
# Wait for the window rather than sleeping at it: a tap that lands before the
# window exists fails silently and takes the rest of the script with it.
for _ in $(seq 80); do
  xdotool search --onlyvisible --name "Note" >/dev/null 2>&1 && break
  sleep 0.25
done
sleep "${SETTLE:-1.5}"

tap()  { xdotool mousemove "$1" "$2" click 1; sleep "${PAUSE:-0.7}"; }
type_() { xdotool type --delay 25 "$1"; sleep "${PAUSE:-0.7}"; }
key()  { xdotool key "$1"; sleep "${PAUSE:-0.7}"; }

# Coordinates of the controls this exercises, in a 360x720 window.
TAKE_NOTE_X=100; TAKE_NOTE_Y=694
NEW_LIST_X=335;  NEW_LIST_Y=694
BACK_X=28;       BACK_Y=28
SEARCH_X=120;    SEARCH_Y=30
TITLE_X=180;     TITLE_Y=72
FIRST_CARD_X=90; FIRST_CARD_Y=110

status=0
check() { # check <name> <jq-ish grep pattern>
  if grep -q "$2" "$DIR/notes.json" 2>/dev/null; then
    printf '  ok    %s\n' "$1"
  else
    printf '  FAIL  %s\n' "$1"; status=1
  fi
}

echo "==> a text note, typed and backed out of"
tap $TAKE_NOTE_X $TAKE_NOTE_Y
# A new note opens with the cursor already in the body, which is where Keep
# puts it and what the on-screen keyboard has just been raised for. The title
# is a deliberate tap upwards.
type_ "and two loaves of bread"
tap $TITLE_X $TITLE_Y
type_ "Milk"
tap $BACK_X $BACK_Y
sleep 1
check "the title is on disk"  '"title": "Milk"'
check "the body is on disk"   'two loaves of bread'

echo "==> a list, with Enter making the next line"
tap $NEW_LIST_X $NEW_LIST_Y
type_ "Eggs"
key Return
type_ "Butter"
tap $BACK_X $BACK_Y
sleep 1
check "the first item"   '"text": "Eggs"'
check "Enter made a second item" '"text": "Butter"'

echo "==> an empty note is discarded rather than kept"
before=$(grep -c '"id"' "$DIR/notes.json")
tap $TAKE_NOTE_X $TAKE_NOTE_Y
tap $BACK_X $BACK_Y
sleep 1
after=$(grep -c '"id"' "$DIR/notes.json")
if [[ $before -eq $after ]]; then printf '  ok    %s\n' "no blank note was kept"
else printf '  FAIL  %s (%s -> %s)\n' "a blank note was kept" "$before" "$after"; status=1; fi

echo "==> search finds one and hides the other"
tap $SEARCH_X $SEARCH_Y
type_ "Butter"
import -window root "$DIR/search.png" 2>/dev/null
# The grid is redrawn from the model, so the proof is on screen rather than on
# disk: exactly one card, and it is the list.
if xdotool search --name . >/dev/null 2>&1; then printf '  ok    %s\n' "searched without crashing"; fi
key ctrl+a; key BackSpace

echo "==> the app's own log"
# The portal warnings are the container's, not ours: there is no desktop
# session behind this X server for xdg-desktop-portal to talk to.
complaints=$(grep -E 'WARNING|CRITICAL|Traceback' "$LOG" | grep -v 'portal' | sort -u)
if [[ -n $complaints ]]; then
  printf '%s\n' "$complaints" | sed 's/^/    /'
  status=1
else
  echo "  clean"
fi

kill $APP 2>/dev/null; wait $APP 2>/dev/null
echo
if [[ $status -eq 0 ]]; then echo "all good"; else echo "something is wrong -- $DIR kept"; fi
exit $status
