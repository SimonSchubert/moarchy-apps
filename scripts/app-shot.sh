#!/bin/bash
# Photograph a Quickshell app in apps/ on a headless sway, at a phone's size
# and a desktop's, in a light look and a dark one.
#
#   scripts/app-shot.sh habits [out]
#   docker run --rm -v "$PWD:/src" moarchy-qml scripts/app-shot.sh habits .shots/habits
#
# What to photograph is apps/<name>/dev/shots, if there is one: lines run
# with `shot` already defined --
#
#   shot phone                                   # 360x720, dark
#   shot phone-light LOOK=light
#   shot desktop SIZE=1280x820
#   shot store SIZE=540x1044 SCALE=1.5          # a phone's 360 px at its density
#   shot phone-week MOARCHY_HABITS_PAGE=week
#   shot latte THEME=.themes/catppuccin-latte/colors.toml
#
# -- and otherwise those four without the page. SHOTS=<file> reads another
# list instead, for a look at one screen without editing the app's. LOOK is the app's own
# Appearance setting (light, dark, system or theme); THEME stages a
# colors.toml where omarchy-theme-set puts the live one and sets LOOK=theme.
# Every other NAME=value is an environment variable for that run.
#
# apps/<name>/dev/demo.py, if there is one, writes a fixture into a scratch
# MOARCHY_<APP>_DIR before each shot, so nothing here reads anybody's data.
set -uo pipefail
cd "$(dirname "$0")/.."

NAME="${1:?usage: app-shot.sh <app> [out]}"
DIR="apps/$NAME"
# A path rather than a name: shared/kit-gallery, which is not an app.
if [[ $NAME == */* ]]; then DIR=${NAME%/}; NAME=$(basename "$DIR"); fi
[[ -f $DIR/shell.qml ]] || { echo "no such app: $NAME" >&2; exit 1; }
OUT="${2:-.shots/$NAME}"
UP=$(tr '[:lower:]-' '[:upper:]_' <<<"$NAME")
for tool in quickshell sway grim jq; do
  command -v $tool >/dev/null || { echo "no $tool -- run in docker/Dockerfile.qml" >&2; exit 1; }
done
fc-list : family | grep -i "JetBrainsMono Nerd" >/dev/null || echo "warning: no JetBrains Mono Nerd Font -- every icon will be a box" >&2

WORK=$(mktemp -d)
mkdir -p "$OUT"
cp -RL "$DIR" "$WORK/app"

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
WAYLAND_DISPLAY=$(basename "$(ls "$XDG_RUNTIME_DIR"/wayland-[0-9] 2>/dev/null | head -1)")
[[ -n $WAYLAND_DISPLAY ]] || { echo "sway never came up:"; tail -5 "$WORK/sway.log"; exit 1; }
SWAYSOCK=$(ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock | head -1)
export WAYLAND_DISPLAY SWAYSOCK

status=0
shot() {
  local name="${1:?shot needs a name}"; shift
  local size=360x720 scale=1 look=dark theme="" env=()
  for pair in "$@"; do
    case $pair in
      SIZE=*) size=${pair#SIZE=} ;;
      SCALE=*) scale=${pair#SCALE=} ;;
      LOOK=*) look=${pair#LOOK=} ;;
      THEME=*) theme=${pair#THEME=}; look=theme ;;
      *) env+=("$pair") ;;
    esac
  done
  swaymsg output HEADLESS-1 resolution "$size" scale "$scale" >/dev/null

  # A home per shot: its own theme, its own preferences, no leftovers.
  local home="$WORK/home-$name"
  mkdir -p "$home/.local/state/moarchy-$NAME" "$home/.local/state/omarchy/current/theme" "$home/.local/share/moarchy-$NAME"
  printf '{"version":1,"appearance":"%s","launcherAdded":true}\n' "$look" \
    >"$home/.local/state/moarchy-$NAME/prefs.json"
  [[ -n $theme ]] && cp "$theme" "$home/.local/state/omarchy/current/theme/colors.toml"
  local data="$home/.local/share/moarchy-$NAME"
  if [[ -f $DIR/dev/demo.py ]]; then
    env HOME="$home" "MOARCHY_${UP}_DIR=$data" "${env[@]}" python3 "$DIR/dev/demo.py" >/dev/null 2>&1
  fi

  local log="$WORK/$name.log"
  env HOME="$home" XDG_STATE_HOME="$home/.local/state" XDG_DATA_HOME="$home/.local/share" \
      "MOARCHY_${UP}_DIR=$data" "MOARCHY_${UP}_OFFLINE=1" NO_COLOR=1 "${env[@]}" \
      quickshell --no-color -p "$WORK/app/shell.qml" >"$log" 2>&1 &
  local pid=$! up=0
  for _ in $(seq 60); do
    swaymsg -t get_tree 2>/dev/null | jq -e '..|objects|select(.app_id? == "org.quickshell")' >/dev/null 2>&1 && { up=1; break; }
    sleep 0.25
  done
  if [[ $up -eq 0 ]]; then
    echo "    $name: the window never appeared" >&2
    sed 's/^/        /' "$log" | tail -6
    kill "$pid" 2>/dev/null; status=1; return
  fi
  sleep "${SETTLE:-2}"
  grim "$OUT/$name.png" && printf '%-20s %s\n' "$name" "$OUT/$name.png" || status=1
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  grep -E '^\s*(WARN|ERROR|FATAL)\b' "$log" \
    | grep -vE 'qt\.qpa|MESA|libEGL|zink|wl_display|window masks|qt\.core\.qobject\.connect' \
    | sort -u | sed "s/^/    /" | grep . && status=1
  return 0
}

# SHOTS=file for a one-off list, without touching the app's own.
LIST="${SHOTS:-$DIR/dev/shots}"
if [[ -f $LIST ]]; then
  # shellcheck source=/dev/null
  . "$LIST"
else
  shot phone
  shot phone-light LOOK=light
  shot desktop SIZE=1280x820
  shot desktop-light SIZE=1280x820 LOOK=light
fi
exit $status
