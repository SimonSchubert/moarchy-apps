#!/bin/bash
# Install and photograph one or more apps on the actual phone.
#
#   scripts/device.sh check
#   scripts/device.sh install tictactoe solitaire
#   scripts/device.sh all mill
#   scripts/device.sh remove breakout
#
# Lifted out of apps/keep/scripts/device.sh, which said in its own header to do
# exactly that when a second app needed a device run. Seven did at once. The
# app-specific parts it named -- the package name, the data file, the shots --
# turned out to be derivable: the package is moarchy-<app>, the app id is read
# out of the .desktop file the app already ships, and a device run wants one
# photograph of the thing running rather than the four a screenshot pass takes.
#
# The phone is a shared device with other sessions working on it, so every step
# here is small, announced, and reversible. Nothing is copied into the phone's
# filesystem by hand: packages are installed with pacman, which owns every file
# it places, and `remove` takes all of them away again.
#
#   PHONE   ssh target (default moarchy@moarchy.local)
#
# The account is `moarchy`, not DanctNIX's `alarm`, and its password is locked:
# publickey is the only way in, and sudo is passwordless. Anything that goes
# through polkit instead of sudo asks for a password that does not exist.
#
# Three things in here are scar tissue from other sessions on this device and
# are not optional:
#
#   * Every package is checksummed ON the phone against the local copy before
#     pacman is allowed near it. scp to this device truncates in a way that
#     depends on size -- a large package once arrived at a fraction of its
#     length and aborted a transaction, leaving `pacman -Q` reporting a version
#     whose files were not on disk. App packages are small enough to be safe;
#     the check costs a second and removes the question.
#
#   * pacman runs detached with its output in a file that is read afterwards,
#     rather than over a live ssh channel. A dropped connection mid-transaction
#     is how the above happened.
#
#   * Nothing here uses `-f` with pgrep or pkill. Over ssh both match against
#     full command lines, and the command line of the shell running them
#     contains the pattern -- so `pkill -f` kills its own session, and `pgrep -f
#     "pacman -U.*<name>"` matches itself and waits forever for a transaction
#     that finished in four seconds. This script did the second of those on its
#     first run, in the step immediately below a comment warning about the
#     first. Processes are matched by name with `-x`; apps are closed through
#     the compositor, by app id.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# moarchy.local and not an address: the phone's systemd-resolved answers mDNS
# (+mDNS is on by default and avahi is not installed), so this follows it from
# one lease to the next. The literal that used to be here, 192.168.0.18, had
# stopped being the phone at all -- and the router is no help, because its DNS
# returns every lease the name has ever held, four of them dead, one per query.
PHONE="${PHONE:-moarchy@moarchy.local}"
# One multiplexed connection for the whole run. Several sessions each opening a
# fresh connection per scp is what trips sshd's MaxStartups on this phone, and
# it presents as "Connection reset by peer" rather than as anything about
# limits. The control path is short on purpose: a path under a scratchpad
# directory exceeds the 104-byte sockaddr limit and ssh refuses it.
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10
          -o ControlMaster=auto -o ControlPath=/tmp/.cm-moarchy -o ControlPersist=5m)
OUT="${OUT:-}"

# The environment a Wayland client needs when it is started from an ssh session
# rather than from the session itself, plus the socket swaymsg looks for.
PHONE_ENV='export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-1
           export SWAYSOCK=$(ls $XDG_RUNTIME_DIR/sway-ipc.* 2>/dev/null | head -1)'

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[33m    %s\033[0m\n' "$*"; }
die()  { printf '\033[31m!! %s\033[0m\n' "$*" >&2; exit 1; }
phone() { ssh "${SSH_OPTS[@]}" "$PHONE" "$@"; }

# --- what an app is called ---------------------------------------------------

pkg_of()  { echo "moarchy-$1"; }
appid_of() {
  local file
  file=$(ls "$ROOT/apps/$1/data/"org.moarchy.*.desktop 2>/dev/null | head -1)
  [[ -n $file ]] || return 1
  basename "$file" .desktop
}
newest_pkg() { ls -t "$ROOT/packages/$(pkg_of "$1")"-*.pkg.tar.* 2>/dev/null | head -1; }

# --- steps -------------------------------------------------------------------

step_check() {
  say "the phone"
  phone true 2>/dev/null || die "cannot reach $PHONE (PHONE=moarchy@<ip>; the account is moarchy, not alarm)"
  phone "$PHONE_ENV"'
    echo "  host:      $(uname -m) $(uname -r)"
    echo "  session:   $(pgrep -x sway >/dev/null && echo "sway running" || echo "NO SWAY -- a screenshot would be a still wallpaper")"
    echo "  theme:     $(basename "$(readlink -f ~/.local/state/omarchy/current/theme 2>/dev/null)" 2>/dev/null || echo none)"
    echo "  free:      $(df -h / | awk "NR==2 {print \$4}")"
    echo "  pacman:    $([ -e /var/lib/pacman/db.lck ] && echo "LOCKED -- another transaction is running" || echo free)"
    echo "  installed: $(pacman -Qq 2>/dev/null | grep -c "^moarchy-") moarchy packages"'
}

# Refuses to start while somebody else's transaction is in flight, rather than
# dying halfway through its own.
wait_for_pacman() {
  local waited=0
  while phone 'test -e /var/lib/pacman/db.lck' 2>/dev/null; do
    [[ $waited -eq 0 ]] && warn "another pacman transaction is running -- waiting"
    sleep 5
    waited=$((waited + 5))
    [[ $waited -ge 120 ]] && die "pacman has been locked for two minutes; check who is on the device"
  done
}

step_install() {
  local app="$1" pkg name sum there
  pkg=$(newest_pkg "$app")
  [[ -n $pkg ]] || die "no package for $app -- run scripts/package.sh $app first"
  name=$(basename "$pkg")
  info "$name"

  scp "${SSH_OPTS[@]}" -q "$pkg" "$PHONE:/tmp/" || die "scp failed for $name"
  # Checksummed on the device, not trusted. See the header.
  sum=$(shasum -a 256 "$pkg" | cut -d' ' -f1)
  there=$(phone "sha256sum /tmp/$name | cut -d' ' -f1")
  [[ $sum == "$there" ]] || die "$name arrived corrupt (local $sum, phone $there)"

  wait_for_pacman
  # Deliberately NOT --needed. This harness exists to put the build in front of
  # you onto the phone, and these packages carry no version bump between one
  # build and the next -- so --needed compares 0.1.0-1 against 0.1.0-1, decides
  # there is nothing to do, and leaves yesterday's code installed. It did
  # exactly that here: a one-line fix was built, "installed", photographed and
  # reported green, and the file on the device had not changed. `pacman -Q` says
  # the version, which was never the question.
  #
  # Detached, with the log read afterwards: a dropped ssh in the middle of a
  # transaction is what leaves this device reporting versions whose files are
  # not on disk.
  local before
  before=$(phone "pacman -Qi $(pkg_of "$app") 2>/dev/null | grep '^Install Date'" || echo none)
  phone "setsid nohup sudo pacman -U --noconfirm /tmp/$name > /tmp/pacman-$app.log 2>&1 < /dev/null &" >/dev/null

  # Waited for by asking the question that matters -- has this package been
  # installed *just now* -- rather than by watching for a process. The first cut
  # polled the process table immediately after launching, won the race, decided
  # the transaction was over before pacman had started, and reported six
  # perfectly good installs as failures.
  local waited=0 after
  while true; do
    after=$(phone "pacman -Qi $(pkg_of "$app") 2>/dev/null | grep '^Install Date'" || echo none)
    [[ $after != none && $after != "$before" ]] && break
    sleep 2; waited=$((waited + 2))
    if [[ $waited -ge 120 ]]; then
      phone "tail -20 /tmp/pacman-$app.log" | sed 's/^/    /'
      die "pacman never installed $name"
    fi
  done
  if phone "grep -qiE '^error|failed to commit' /tmp/pacman-$app.log"; then
    phone "grep -iE '^error|failed' /tmp/pacman-$app.log" | sed 's/^/    /'
    warn "pacman reported errors for $name"
    status=1
  fi
  info "$(phone "pacman -Q $(pkg_of "$app")")"

  # The app drawer lists desktop entries, so an app whose .desktop is wrong is
  # an app that cannot be started by tapping, however well it runs from a shell.
  local appid
  appid=$(appid_of "$app") || die "no .desktop in apps/$app/data"
  phone "desktop-file-validate /usr/share/applications/$appid.desktop" \
    && info "desktop entry valid" \
    || warn "desktop entry does not validate"
}

# grim blocks forever on a blanked output and says nothing about it: swayidle
# turns DSI-1 off after a few minutes, a blanked output commits no frames, and
# wlr-screencopy never delivers one. Found by moarchy-apps-f6 after losing half
# an hour to it. One line, before every capture.
wake_screen() {
  phone "$PHONE_ENV"'
    swaymsg "output * dpms on" >/dev/null 2>&1; true'
}

# Is there a window with this app id on the seat right now?
on_screen() {
  phone "$PHONE_ENV"'
    swaymsg -t get_tree 2>/dev/null' | grep -q "\"app_id\": \"$1\""
}

close_app() {
  local appid="$1"
  phone "$PHONE_ENV"'
    swaymsg "[app_id=\"'"$appid"'\"] kill" >/dev/null 2>&1; true'
}

# The app id of the window left on screen by the last shot, so the next one can
# be started before it is closed. See below.
LAST_APPID=""

step_shot() {
  local app="$1" appid bin out
  appid=$(appid_of "$app") || die "no .desktop in apps/$app/data"
  bin=$(pkg_of "$app")
  out="${OUT:-$ROOT/apps/$app/docs/screenshots/device}"

  # Started *before* the previous one is closed, which is the whole trick. Kill
  # the last window first and the shell brings the app drawer forward to be the
  # home screen -- with its search field focused and the on-screen keyboard up
  # -- and the drawer then sits on top of whatever starts next. The first run of
  # this script photographed the drawer seven times for exactly that reason.
  #
  # Through the compositor, not straight from ssh: a GUI started from an ssh
  # session lands outside the seat, and anything that then wants a polkit
  # agent, a portal or an input method finds none.
  phone "$PHONE_ENV"'
    swaymsg exec '"'$bin'"' >/dev/null' || die "could not launch $bin"

  # Waited for rather than slept through, which is the lesson screenshot.sh
  # already learnt on the virtual screen: a fixed sleep is a guess, and the
  # first app launched after an install is the slowest one there will ever be --
  # nothing of GTK is in the page cache yet and it comes off eMMC.
  local waited=0
  until on_screen "$appid"; do
    sleep 1; waited=$((waited + 1))
    [[ $waited -ge ${PATIENCE:-25} ]] && break
  done

  # Now that something else is in front, the previous one can go.
  [[ -n $LAST_APPID && $LAST_APPID != "$appid" ]] && close_app "$LAST_APPID"
  LAST_APPID="$appid"

  # And this is the line that actually beats the drawer, which re-sequencing the
  # launches did not: the app drawer is a layer-shell surface on sway's Top
  # layer, and an ordinary toplevel is drawn *under* that whatever order things
  # started in. A fullscreen toplevel is drawn above it. So the drawer can be
  # open, focused, with the on-screen keyboard up, and the capture is still of
  # the app. Found by moarchy-apps-f6, who lost a session's worth of captures to
  # the same thing before working it out.
  phone "$PHONE_ENV"'
    swaymsg "[app_id=\"'"$appid"'\"] focus" >/dev/null 2>&1
    swaymsg "[app_id=\"'"$appid"'\"] fullscreen enable" >/dev/null 2>&1; true'

  sleep "${SETTLE:-3}"
  if ! on_screen "$appid"; then
    warn "$bin never put a window on the screen"
    # Narrowed to the app's own output. A loose pattern here matched the sudo
    # lines from the package's own install and reported those as the reason.
    # "Unable to create a GL context" is filtered because every GTK4 app on this
    # phone logs it: the image sets no GSK_RENDERER, GTK tries GL on a Mali-400,
    # fails, and falls back to cairo -- which is what it should be doing anyway.
    phone "journalctl --user -n 200 --no-pager 2>/dev/null | grep -iE 'Traceback|$bin' | grep -v 'GL context' | tail -12" | sed 's/^/    /'
    LAST_APPID=""
    return 1
  fi

  wake_screen
  phone "$PHONE_ENV"'; grim /tmp/device-shot.png' || { warn "grim failed"; return 1; }
  mkdir -p "$out"
  scp "${SSH_OPTS[@]}" -q "$PHONE:/tmp/device-shot.png" "$out/$app.png" \
    || { warn "could not fetch the shot"; return 1; }
  printf '    %-14s %s\n' "$app" "$out/$app.png"
}

# Everything step_shot deliberately left on the screen.
close_last() {
  [[ -n $LAST_APPID ]] && close_app "$LAST_APPID"
  LAST_APPID=""
}

step_log() {
  local app="$1"
  phone "journalctl --user -n 200 --no-pager 2>/dev/null | grep -iE 'moarchy-$app|$app.*(Traceback|WARNING|CRITICAL)' | tail -15" \
    | sed 's/^/    /' || info "nothing in the user journal"
}

step_remove() {
  local app="$1" appid
  appid=$(appid_of "$app") || true
  [[ -n ${appid:-} ]] && close_app "$appid"
  wait_for_pacman
  phone "sudo pacman -R --noconfirm $(pkg_of "$app") 2>/dev/null && echo '    removed $(pkg_of "$app")' || echo '    $(pkg_of "$app") was not installed'"
  phone "rm -f /tmp/$(pkg_of "$app")-*.pkg.tar.* /tmp/pacman-$app.log"
}

# --- the front door ----------------------------------------------------------

action="${1:-check}"; shift || true
apps=("$@")
if [[ ${#apps[@]} -eq 0 && $action != check ]]; then
  mapfile -t apps < <(find "$ROOT/apps" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort)
fi

status=0
case "$action" in
  check) step_check ;;
  install)
    step_check
    for app in "${apps[@]}"; do say "install $app"; step_install "$app" || status=1; done ;;
  shots)
    for app in "${apps[@]}"; do say "photograph $app"; step_shot "$app" || status=1; done
    close_last ;;
  log)
    for app in "${apps[@]}"; do say "what $app said"; step_log "$app"; done ;;
  remove)
    for app in "${apps[@]}"; do say "remove $app"; step_remove "$app"; done ;;
  all)
    step_check
    for app in "${apps[@]}"; do
      say "$app"
      step_install "$app" && step_shot "$app" || status=1
    done
    close_last ;;
  *) echo "usage: device.sh {check|install|shots|log|remove|all} [app ...]" >&2; exit 1 ;;
esac
exit $status
