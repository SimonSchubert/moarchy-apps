#!/bin/bash
# Install and photograph moarchy-keep on the actual phone.
#
# Still Keep's own rather than shared. Every other harness in this repo was
# generalised when Keep moved into it, but this one talks to hardware that
# cannot be stood up in a container, so generalising it would mean rewriting
# the one script nothing here can test. Lift it into scripts/ when a second
# app actually needs a device run -- the app-specific parts are the package
# name, the data file, and the two shots at the bottom.
#
#   ./scripts/package.sh                    # build it first
#   ./scripts/device.sh install
#   ./scripts/device.sh shots
#   ./scripts/device.sh remove              # puts the phone back
#
# The phone is a shared device with other sessions working on it, so every step
# here is small, announced, and reversible. Nothing is copied into the phone's
# filesystem by hand: the package is installed with pacman, which owns every
# file it places, and `remove` takes all of them away again.
#
#   PHONE   ssh target (default moarchy@moarchy.local)
#
# The account is `moarchy`, not DanctNIX's `alarm`, and its password is locked:
# publickey is the only way in, and sudo is passwordless. Anything that goes
# through polkit instead of sudo asks for a password that does not exist -- this
# app needs neither, which is one reason it installs cleanly here.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # apps/keep
ROOT="$(cd "$REPO/../.." && pwd)"                          # the repo
export PYTHONPATH="$ROOT/shared:$REPO"
# moarchy.local and not an address: the phone's systemd-resolved answers mDNS
# (+mDNS is on by default and avahi is not installed), so this follows it from
# one lease to the next. The literal that used to be here, 192.168.0.18, had
# stopped being the phone at all -- and the router is no help, because its DNS
# returns every lease the name has ever held, four of them dead, one per query.
PHONE="${PHONE:-moarchy@moarchy.local}"
# One multiplexed connection for the whole run. Four sessions each opening a
# fresh connection per scp is what trips sshd's MaxStartups on this phone, and
# it presents as "Connection reset by peer" rather than as anything about
# limits. The control path is short on purpose: a path under a scratchpad
# directory exceeds the 104-byte sockaddr limit and ssh refuses it.
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10
          -o ControlMaster=auto -o ControlPath=/tmp/.cm-keep -o ControlPersist=5m)
OUT="${OUT:-$REPO/docs/screenshots/device}"

# The environment a Wayland client needs when it is started from an ssh session
# rather than from the session itself.
PHONE_ENV='export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-1'

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf '\033[31m!! %s\033[0m\n' "$*" >&2; exit 1; }
phone() { ssh "${SSH_OPTS[@]}" "$PHONE" "$@"; }

step_check() {
  say "the phone"
  phone true 2>/dev/null || die "cannot reach $PHONE (PHONE=moarchy@<ip>; the account is moarchy, not alarm)"
  phone "$PHONE_ENV"'
    echo "  host:     $(uname -m) $(uname -r)"
    echo "  session:  $(pgrep -x sway >/dev/null && echo "sway running" || echo "NO SWAY -- a screenshot would be a still wallpaper")"
    echo "  theme:    $(basename "$(readlink -f ~/.local/state/omarchy/current/theme 2>/dev/null)" 2>/dev/null || echo none)"
    echo "  keyboard: $(pgrep -f moarchy-keyboard >/dev/null && echo running || echo -)"
    echo "  keep:     $(pacman -Q moarchy-keep 2>/dev/null || echo "not installed")"'
}

# The usable height of a workspace. The on-screen keyboard sets an exclusive
# zone when it rises, so the compositor should shrink this rather than draw the
# keys over the note -- which is the difference between "the app must leave room
# at the bottom" and "the app must do nothing at all". Measured, not assumed.
workspace_rect() {
  phone "$PHONE_ENV"'
    export SWAYSOCK=$(ls $XDG_RUNTIME_DIR/sway-ipc.* 2>/dev/null | head -1)
    swaymsg -t get_workspaces 2>/dev/null |
      python3 -c "import json,sys
ws = json.load(sys.stdin)
for w in ws:
    if w.get(\"focused\"):
        r = w[\"rect\"]
        print(f\"{r['\''width'\'']}x{r['\''height'\'']} at {r['\''x'\'']},{r['\''y'\'']}\")"' 2>/dev/null
}

step_install() {
  say "install"
  local pkg
  pkg=$(ls -t "$ROOT"/packages/moarchy-keep-*.pkg.tar.* 2>/dev/null | head -1)
  [[ -n $pkg ]] || die "no package -- run ./scripts/package.sh first"
  info "$(basename "$pkg")"
  scp "${SSH_OPTS[@]}" -q "$pkg" "$PHONE:/tmp/" || die "scp failed"
  phone "sudo pacman -U --needed --noconfirm /tmp/$(basename "$pkg")" || die "pacman failed"
  # The app drawer lists desktop entries, so an app whose .desktop is wrong is
  # an app that cannot be started by tapping, however well it runs from a shell.
  phone 'gtk-launch --help >/dev/null 2>&1 && desktop-file-validate /usr/share/applications/org.moarchy.Keep.desktop && echo "    desktop entry valid"'
}

step_seed() {
  say "seed a few notes to photograph"
  # Never over someone's real notes: if the file is there, it is theirs.
  if phone 'test -s ~/.local/share/moarchy-keep/notes.json' 2>/dev/null; then
    info "notes.json already exists -- leaving it alone"
    return 0
  fi
  local tmp="$REPO/.device-seed"
  rm -rf "$tmp"; mkdir -p "$tmp"
  MOARCHY_KEEP_DIR="$tmp" python3 "$REPO/demo.py" >/dev/null || die "could not build the demo notes"
  phone 'mkdir -p ~/.local/share/moarchy-keep'
  scp "${SSH_OPTS[@]}" -q "$tmp/notes.json" "$PHONE:.local/share/moarchy-keep/notes.json" || die "scp failed"
  rm -rf "$tmp"
  info "seeded (device.sh remove takes them away again)"
}

# shot <name> [VAR=value ...] -- launch, wait, grim, fetch, quit.
shot() {
  local name="$1"; shift
  local env_prefix=""
  [[ $# -gt 0 ]] && env_prefix="env $* "
  # Closed through the compositor, by app_id. pkill is unusable over ssh here:
  # -f matches against full command lines, and the command line of the very
  # shell running the pkill contains the pattern, so it kills its own session
  # and takes the rest of the step with it. The bracket trick does not help --
  # the launch line in the same script still spells the name out.
  phone "$PHONE_ENV"'
    export SWAYSOCK=$(ls $XDG_RUNTIME_DIR/sway-ipc.* 2>/dev/null | head -1)
    swaymsg "[app_id=\"org.moarchy.Keep\"] kill" >/dev/null 2>&1; sleep 1'
  # Through the compositor, not straight from ssh: a GUI started from an ssh
  # session lands outside the seat, and anything that then wants a polkit
  # agent, a portal or an input method finds none.
  phone "$PHONE_ENV"'
    export SWAYSOCK=$(ls $XDG_RUNTIME_DIR/sway-ipc.* 2>/dev/null | head -1)
    swaymsg exec '"'"''"$env_prefix"'moarchy-keep'"'"' >/dev/null' || die "could not launch"
  sleep "${SETTLE:-6}"
  phone "$PHONE_ENV"'; grim /tmp/keep-shot.png' || die "grim failed"
  mkdir -p "$OUT"
  scp "${SSH_OPTS[@]}" -q "$PHONE:/tmp/keep-shot.png" "$OUT/$name.png" || die "could not fetch the shot"
  printf '    %-14s %s\n' "$name" "$OUT/$name.png"
}

step_shots() {
  say "photograph it on the phone"
  info "workspace with nothing up:  $(workspace_rect)"
  shot device-grid
  info "workspace with the grid up: $(workspace_rect)"
  shot device-note-list MOARCHY_KEEP_OPEN=Shopping
  # A new note focuses its body, which is what raises the on-screen keyboard --
  # the only way to see what it covers without a finger to tap with, and the
  # one measurement worth taking: if the keyboard's exclusive zone works, the
  # workspace gets shorter and the note is resized rather than covered.
  shot device-keyboard MOARCHY_KEEP_NEW=text
  info "workspace with the keyboard: $(workspace_rect)"
  close_app
}

step_log() {
  say "what it said"
  # A GTK warning on the phone goes to the compositor's journal, which is the
  # one place nobody looks.
  phone 'journalctl --user -n 40 --no-pager 2>/dev/null | grep -iE "keep|gtk|python" | tail -20 || echo "    nothing in the user journal"'
}

close_app() {
  phone "$PHONE_ENV"'
    export SWAYSOCK=$(ls $XDG_RUNTIME_DIR/sway-ipc.* 2>/dev/null | head -1)
    swaymsg "[app_id=\"org.moarchy.Keep\"] kill" >/dev/null 2>&1; true'
}

step_remove() {
  say "put the phone back"
  close_app
  phone '
    sudo pacman -R --noconfirm moarchy-keep 2>/dev/null && echo "    package removed"
    rm -f /tmp/moarchy-keep-*.pkg.tar.* /tmp/keep-shot.png
    if [ -f ~/.local/share/moarchy-keep/notes.json ]; then
      echo "    left ~/.local/share/moarchy-keep -- remove it by hand if those notes were seeded"
    fi'
}

case "${1:-all}" in
  check)   step_check ;;
  install) step_check; step_install ;;
  seed)    step_seed ;;
  shots)   step_shots ;;
  log)     step_log ;;
  remove)  step_remove ;;
  all)     step_check && step_install && step_seed && step_shots && step_log ;;
  *) echo "steps: check install seed shots log remove" >&2; exit 1 ;;
esac
