#!/bin/bash
# Run a plugin on a virtual 360x720 phone screen and photograph it.
#
#   scripts/qml-shot.sh org.moarchy.weather [out]
#   THEMES=/tmp/omarchy-themes scripts/qml-shot.sh org.moarchy.weather
#
# scripts/screenshot.sh is this for the GTK apps and cannot be this for a
# plugin: it photographs an X server with `import`, and Quickshell is a Wayland
# client. So the compositor here is the one the phone runs -- headless sway,
# with `grim` taking the picture the same way `omarchy-screenshot` does.
#
# Same division of labour as the GTK harness, for the same reason: *what* to
# photograph is plugins/<id>/shots.sh, because the list of screens is the only
# part that differs between a weather app and a calculator. That file runs with
# `shot` already defined:
#
#   shot today                          # the plugin as it opens
#   shot places MOARCHY_WEATHER_PAGE=places
#   shot latte THEME=/tmp/omarchy-themes/catppuccin-latte/colors.toml
#
# Every name after the first is an environment variable for that run. THEME is
# the one the harness reads itself: it stages a colors.toml where
# omarchy-theme-set puts the live one, which is the only place an app looks.
# CORNERS is the other: large, modest or square, written to the ui.toml
# `moarchy-ui corners` writes. It can also be set for the whole run --
#
#   CORNERS=square scripts/qml-shot.sh org.moarchy.calendar .shots/square
#
# -- which is how every screen of an app is looked at with square corners
# without a shots.sh that names them twice.
#
# plugins/<id>/demo.py, if there is one, runs before each shot with
# MOARCHY_<APP>_DIR pointed at a scratch directory -- so the pictures are of a
# fixture rather than of whatever the machine happens to have, and nothing here
# touches anybody's real data.
set -uo pipefail
cd "$(dirname "$0")/.."

ID="${1:?usage: qml-shot.sh <plugin-id> [out]}"
DIR="plugins/$ID"
[[ -d $DIR ]] || { echo "no such plugin: $ID" >&2; exit 1; }
OUT="${2:-$DIR/docs/screenshots}"
APP=${ID##*.}
UP=$(tr '[:lower:]' '[:upper:]' <<<"$APP")

command -v quickshell >/dev/null || { echo "no quickshell -- run in docker/Dockerfile.qml" >&2; exit 1; }
command -v sway >/dev/null || { echo "no sway -- run in docker/Dockerfile.qml" >&2; exit 1; }
command -v grim >/dev/null || { echo "no grim -- run in docker/Dockerfile.qml" >&2; exit 1; }

WORK=$(mktemp -d)
mkdir -p "$OUT"

# Vendored exactly as install-on-device.sh does, so the thing photographed is
# the thing shipped.
cp "$DIR"/*.qml "$DIR"/*.js "$DIR"/*.svg "$DIR/manifest.json" "$WORK/" 2>/dev/null
mkdir -p "$WORK/ui"
cp shared/qs_ui/*.qml shared/qs_ui/*.js shared/qs_ui/qmldir "$WORK/ui/"

export XDG_RUNTIME_DIR="$WORK/run"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
export WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM=wayland
unset DISPLAY

cat > "$WORK/sway.conf" <<CONF
# One window, no furniture, and the screen a PinePhone has.
default_border none
output HEADLESS-1 resolution 360x720
CONF

# A copy, because Arch's sway carries cap_sys_nice and a container refuses to
# exec a file with capabilities it cannot grant -- "Operation not permitted",
# with nothing to say that capabilities are what it means. This is
# text-input-check.sh's scar, and it is the same binary.
cp "$(command -v sway)" "$WORK/sway"
chmod +x "$WORK/sway"

"$WORK/sway" -c "$WORK/sway.conf" >"$WORK/sway.log" 2>&1 &
SWAY=$!
trap 'kill $SWAY 2>/dev/null; rm -rf "$WORK"' EXIT

for _ in $(seq 40); do
  [[ -n $(ls "$XDG_RUNTIME_DIR"/wayland-[0-9] 2>/dev/null | head -1) ]] && break
  sleep 0.25
done
WAYLAND_DISPLAY=$(basename "$(ls "$XDG_RUNTIME_DIR"/wayland-[0-9] 2>/dev/null | head -1)")
export WAYLAND_DISPLAY
[[ -n ${WAYLAND_DISPLAY:-} ]] || { echo "sway never came up:"; tail -5 "$WORK/sway.log"; exit 1; }
SWAYSOCK=$(ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null | head -1)
export SWAYSOCK

status=0

shot() {
  local name="${1:?shot needs a name}"; shift
  local theme="" corners="${CORNERS:-}" env=()
  for pair in "$@"; do
    [[ $pair == THEME=* ]] && { theme="${pair#THEME=}"; continue; }
    [[ $pair == CORNERS=* ]] && { corners="${pair#CORNERS=}"; continue; }
    env+=("$pair")
  done

  # A palette is staged per shot, and cleared when a shot does not name one, so
  # the picture after a themed one is not still wearing its colours.
  local stage="$HOME/.local/state/omarchy/current/theme"
  mkdir -p "$stage"
  rm -f "$stage/colors.toml"
  [[ -n $theme ]] && cp "$theme" "$stage/colors.toml"

  # The same for the shape, and for the same reason. No file is large.
  local chrome="$HOME/.config/omarchy"
  mkdir -p "$chrome"
  rm -f "$chrome/ui.toml"
  [[ -n $corners ]] && printf 'corners = "%s"\n' "$corners" >"$chrome/ui.toml"

  local data="$WORK/data"
  rm -rf "$data"; mkdir -p "$data/moarchy-$APP"
  if [[ -f $DIR/demo.py ]]; then
    # The shot's own variables reach the fixture too, so that a run which
    # pins the clock pins it in both halves at once.
    env "MOARCHY_${UP}_DIR=$data/moarchy-$APP" "${env[@]}" \
        python3 "$DIR/demo.py" >/dev/null 2>&1
  fi

  local log="$WORK/$name.log"
  env "XDG_DATA_HOME=$data" "MOARCHY_${UP}_DIR=$data/moarchy-$APP" \
      "MOARCHY_${UP}_OFFLINE=1" NO_COLOR=1 "${env[@]}" \
      quickshell --no-color -p "$WORK/shell.qml" >"$log" 2>&1 &
  local pid=$!

  # Waiting for the window rather than sleeping a guessed number of seconds,
  # which is the GTK harness's own lesson: on a slow start a sleep photographs
  # a screen that is not there yet, and nothing says so.
  local up=0
  for _ in $(seq 60); do
    if swaymsg -t get_tree 2>/dev/null | jq -e '..|objects|select(.app_id? == "org.quickshell")' >/dev/null 2>&1; then
      up=1; break
    fi
    sleep 0.25
  done
  if [[ $up -eq 0 ]]; then
    echo "    $name: the window never appeared" >&2
    sed 's/^/        /' "$log" | tail -6
    kill "$pid" 2>/dev/null; status=1; return
  fi
  # The window is mapped; this is the frame after it has drawn.
  sleep "${SETTLE:-1.5}"

  grim "$OUT/$name.png" 2>>"$WORK/sway.log" \
    && printf '%-20s %s\n' "$name" "$OUT/$name.png" \
    || { echo "    $name: grim failed" >&2; status=1; }

  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  { grep -E '^\s*(WARN|ERROR|FATAL)\b' "$log" \
    | grep -vE 'qt\.qpa|MESA|libEGL|zink|wl_display|window masks|qt\.core\.qobject\.connect' \
    | sort -u | sed 's/^/    /'; } || true
}

if [[ -f $DIR/shots.sh ]]; then
  # shellcheck source=/dev/null
  . "$DIR/shots.sh"
else
  shot "$APP"
fi

exit $status
