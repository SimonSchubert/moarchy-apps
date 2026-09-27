#!/bin/bash
# The README's screenshots, on a headless sway, of demo.py's recorded phone.
#
#   docker run --rm -v "$PWD:/src" moarchy-qml apps/vitals/dev/shots.sh [out]
#
# scripts/qml-shot.sh is this for the plugins in plugins/, at one size. This
# app has two layouts, so each shot names the screen size it is taken at, and
# the machine is always the recording: a system monitor photographed against
# a container is a flat line and five processes.
#
# The image needs quickshell, sway, grim, jq, python and the JetBrains Mono
# Nerd Font the icons are drawn in.
set -uo pipefail
cd "$(dirname "$0")/.."
APP=$PWD
OUT="${1:-$APP/docs/screenshots}"
mkdir -p "$OUT"
for tool in quickshell sway grim jq python3; do
  command -v $tool >/dev/null || { echo "no $tool -- run in the moarchy-qml image" >&2; exit 1; }
done

WORK=$(mktemp -d)
export XDG_RUNTIME_DIR="$WORK/run"
mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
export WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman
export XDG_SESSION_TYPE=wayland QT_QPA_PLATFORM=wayland
unset DISPLAY

# A copy: Arch's sway carries cap_sys_nice, which a container refuses to exec.
cp "$(command -v sway)" "$WORK/sway"; chmod +x "$WORK/sway"
printf 'default_border none\noutput HEADLESS-1 resolution 360x720\n' >"$WORK/sway.conf"
"$WORK/sway" -c "$WORK/sway.conf" >"$WORK/sway.log" 2>&1 &
SWAY=$!
trap 'kill $SWAY 2>/dev/null; rm -rf "$WORK"' EXIT
for _ in $(seq 40); do ls "$XDG_RUNTIME_DIR"/wayland-[0-9] >/dev/null 2>&1 && break; sleep 0.25; done
WAYLAND_DISPLAY=$(basename "$(ls "$XDG_RUNTIME_DIR"/wayland-[0-9] | head -1)")
SWAYSOCK=$(ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock | head -1)
export WAYLAND_DISPLAY SWAYSOCK

REEL="$WORK/reel"
mkdir -p "$REEL"
MOARCHY_VITALS_DIR="$REEL" python3 dev/demo.py >/dev/null

status=0
# shot <name> <WxH> <light|dark> [VAR=value ...]
shot() {
  local name=$1 size=$2 look=$3; shift 3
  swaymsg output HEADLESS-1 resolution "$size" >/dev/null
  local home="$WORK/home-$name"
  mkdir -p "$home/.local/state/moarchy-vitals"
  printf '{"version":1,"appearance":"%s"}\n' "$look" >"$home/.local/state/moarchy-vitals/prefs.json"
  env HOME="$home" MOARCHY_VITALS_DIR="$REEL" NO_COLOR=1 "$@" \
    quickshell --no-color -p "$APP/shell.qml" >"$WORK/$name.log" 2>&1 &
  local pid=$!
  for _ in $(seq 60); do
    swaymsg -t get_tree | jq -e '..|objects|select(.app_id? == "org.quickshell")' >/dev/null 2>&1 && break
    sleep 0.25
  done
  # The reel plays through in about three seconds, then holds.
  sleep "${SETTLE:-4}"
  grim "$OUT/$name.png" && printf '%-16s %s\n' "$name" "$OUT/$name.png" || status=1
  kill "$pid"; wait "$pid" 2>/dev/null
  grep -E '^\s*(WARN|ERROR|FATAL)\b' "$WORK/$name.log" \
    | grep -vE 'qt\.qpa|MESA|libEGL|zink|wl_display|window masks|qt\.core\.qobject\.connect' \
    | sort -u | sed "s/^/    /" | grep . && status=1
  return 0
}

shot desktop 1280x820 dark
shot desktop-tasks 1280x820 light MOARCHY_VITALS_PAGE=tasks MOARCHY_VITALS_PICK=firefox
shot phone 360x720 dark
shot phone-processor 360x720 dark MOARCHY_VITALS_PAGE=processor
shot phone-tasks 360x720 dark MOARCHY_VITALS_PAGE=tasks
shot phone-network 360x720 light MOARCHY_VITALS_PAGE=network
exit $status
