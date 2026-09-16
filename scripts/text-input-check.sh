#!/bin/bash
# Does the app enable Wayland text input?
#
# This is the property that decides whether the app can be typed into on a
# phone. moarchy-keyboard commits text through zwp_input_method_v2 to whichever
# client has enabled zwp_text_input_v3, so a client that never enables it gets
# no text even with the keyboard up, with nothing in any log to say why.
# (Enabling it no longer raises the keyboard -- moarchy-keyboard's SPEC.md AC 50
# -- so this checks typing, not whether the keyboard appears.)
#
# X11 has no such protocol, so scripts/check.sh cannot see this at all. Here the
# app runs under headless sway -- the compositor the phone runs -- and the
# Wayland protocol trace is read directly. A bare GtkTextView is the control: if
# the control fails too, the harness is broken rather than the app.
#
#   scripts/text-input-check.sh keep
#
# PROBE_ENV is how an app says "open something typable". Keep wants a new text
# note; another app may want nothing at all, in which case the default is
# harmless -- an app with no such variable simply opens on its first screen,
# and an app with no text field anywhere has nothing to check here.
set -uo pipefail
cd "$(dirname "$0")/.."

APP="${1:?usage: text-input-check.sh <app>}"
[[ -d "apps/$APP" ]] || { echo "no such app: $APP" >&2; exit 1; }
UP=$(tr '[:lower:]' '[:upper:]' <<<"$APP")
MODULE=$(basename "$(find "apps/$APP" -maxdepth 1 -name 'moarchy_*' -type d)")
PROBE_ENV="${PROBE_ENV:-MOARCHY_${UP}_NEW=1}"
export PYTHONPATH="$PWD/shared:$PWD/apps/$APP"

command -v sway >/dev/null || { echo "no sway -- run inside docker/Dockerfile.dev" >&2; exit 1; }

WORK=$(mktemp -d)
export XDG_RUNTIME_DIR="$WORK/run"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
export WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman
export XDG_SESSION_TYPE=wayland
# The image pins GDK_BACKEND=x11 for the screenshot harness. Left set, GTK
# would connect to an X server that is not running here, and both the app and
# the control would fail for a reason that has nothing to do with text input.
export GDK_BACKEND=wayland
unset DISPLAY

cat > "$WORK/sway.conf" <<'CONF'
# No decorations, no bar, one window: as close to the phone's single-window
# workspace as a headless compositor gets.
default_border none
CONF

# A copy, because Arch's sway carries cap_sys_nice and a container refuses to
# exec a file with capabilities it cannot grant -- "Operation not permitted",
# with nothing to say that capabilities are what it means. cp does not preserve
# them, so the copy runs.
cp /usr/sbin/sway "$WORK/sway" 2>/dev/null || cp "$(command -v sway)" "$WORK/sway"
chmod +x "$WORK/sway"

"$WORK/sway" -c "$WORK/sway.conf" >"$WORK/sway.log" 2>&1 &
SWAY=$!
trap 'kill $SWAY 2>/dev/null; rm -rf "$WORK"' EXIT

for _ in $(seq 40); do
  [ -n "$(ls "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | head -1)" ] && break
  sleep 0.25
done
export WAYLAND_DISPLAY=$(basename "$(ls "$XDG_RUNTIME_DIR"/wayland-[0-9] 2>/dev/null | head -1)")
[ -n "${WAYLAND_DISPLAY:-}" ] || { echo "sway never came up:"; tail -5 "$WORK/sway.log"; exit 1; }

# The control: a window whose entire content is one text view. Known to enable
# text input on the phone, so a failure here is the harness, not the app.
cat > "$WORK/control.py" <<'PY'
import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, GLib, Gtk


def activate(app):
    window = Adw.ApplicationWindow(application=app, title="Control")
    view = Gtk.TextView()
    window.set_content(view)
    window.present()
    GLib.timeout_add(600, view.grab_focus)
    GLib.timeout_add(3500, app.quit)


app = Adw.Application(application_id="org.moarchy.TextInputControl")
app.connect("activate", activate)
app.run([])
PY

# A headless compositor has no input devices, so its seat advertises no
# keyboard, so no surface is ever given keyboard focus -- and without keyboard
# focus the compositor never sends text_input.enter, however correct the client
# is. wtype attaches a virtual keyboard for as long as it runs, which is enough
# for sway to hand focus to the window and for the exchange to happen.
poke_with_a_keyboard() {
  sleep 3
  wtype "hello" >/dev/null 2>&1 || true
}

probe() { # probe <label> <command...>
  local label="$1"; shift
  local log="$WORK/$label.log"
  poke_with_a_keyboard &
  WAYLAND_DEBUG=1 timeout 25 "$@" >"$log" 2>&1
  wait
  local created=$(grep -c 'get_text_input' "$log")
  local entered=$(grep -cE 'zwp_text_input_v3#[0-9]+\.enter' "$log")
  local enabled=$(grep -cE 'zwp_text_input_v3#[0-9]+\.enable' "$log")
  printf '  %-24s created=%s enter=%s enable=%s  %s\n' \
    "$label" "$created" "$entered" "$enabled" \
    "$([ "$enabled" -gt 0 ] && echo 'CAN BE TYPED INTO' || echo '** NO KEYBOARD **')"
  [ "$enabled" -gt 0 ]
}

echo "==> Wayland text input, under headless sway"
probe "control (bare TextView)" python3 "$WORK/control.py"
control=$?

export "MOARCHY_${UP}_DIR=$WORK/data"
mkdir -p "$WORK/data"
python3 "apps/$APP/demo.py" >/dev/null 2>&1

env "MOARCHY_${UP}_QUIT_AFTER=6" "$PROBE_ENV" \
  probe "moarchy-$APP" python3 -m "$MODULE"
app=$?

if [ $control -ne 0 ]; then
  echo "  the control failed -- the harness is broken, not the app" >&2
  exit 2
fi
exit $app
