#!/bin/bash
# Put apps into the Omarchy shell on the phone, as plugins the shell keeps
# loaded, from the working tree.
#
#   PHONE=omarchy@<address> scripts/install-plugin.sh tictactoe habits
#   PHONE=omarchy@<address> scripts/install-plugin.sh --remove tictactoe
#   PHONE=omarchy@127.0.0.1 PHONE_PORT=2222 scripts/install-plugin.sh keep   # the VM
#
# scripts/device.sh installs an app's package, which runs it as its own
# Quickshell process when the shell does not have it. This is the other half:
# the app in ~/.config/omarchy/plugins/<id>, which is the only place Omarchy
# Mobile loads a third-party plugin from, enabled in shell.json, so that
# `omarchy-shell shell summon <id>` answers ok and the package's launcher opens
# it in the shell. The two can be installed together; neither needs the other.
#
# The kit link is resolved on the way (tar -h), as release.sh resolves it, so
# what lands on the phone is the app and the exact kit it was checked against.
# The app writes its own app-menu entry the first time the shell loads it
# (kit/LauncherEntry.qml), unless its package already installed one.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# An Omarchy Mobile phone announces nothing over mDNS; `./mobile phone list` in
# the mobile repo finds its address.
PHONE="${PHONE:?set PHONE=omarchy@<phone address>}"
# The emulator's ssh is forwarded to a port on this machine:
#   PHONE=omarchy@127.0.0.1 PHONE_PORT=2222 scripts/install-plugin.sh ...
# PHONE_SSH_OPTS for anything else ssh needs -- a VM whose host key changes
# with every image: PHONE_SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
ssh() { command ssh -p "${PHONE_PORT:-22}" ${PHONE_SSH_OPTS:-} "$@"; }

remove=0
[[ ${1:-} == --remove ]] && { remove=1; shift; }
[[ $# -gt 0 ]] || { echo "usage: install-plugin.sh [--remove] <app>..." >&2; exit 1; }

ids=()
for app in "$@"; do
  dir="$ROOT/apps/$app"
  [[ -f $dir/Panel.qml ]] || { echo "not a kit app: $app" >&2; exit 1; }
  id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$dir/manifest.json")
  ids+=("$id")
  dest=".config/omarchy/plugins/$id"
  if [[ $remove -eq 1 ]]; then
    echo "==> remove $id"
    ssh "$PHONE" "rm -rf '$dest' ~/.local/share/applications/omarchy-plugin-$id.desktop"
    continue
  fi
  echo "==> copy $app to $PHONE:$dest"
  # Everything the app runs from, and nothing it was checked or photographed
  # with. One tar over one connection: scp of many small files is what trips
  # this phone's MaxStartups.
  # COPYFILE_DISABLE and --no-xattrs: a Mac's tar otherwise writes its own
  # metadata in, and GNU tar on the phone complains about every file.
  COPYFILE_DISABLE=1 tar -C "$dir" -chf - --no-xattrs --exclude=./docs --exclude=./dev --exclude=./tests \
      --exclude=./PKGBUILD --exclude=./.SRCINFO --exclude='__pycache__' --exclude=./kit/tests . \
    | ssh "$PHONE" "rm -rf '$dest' && mkdir -p '$dest' && tar -C '$dest' -xf -"
done

echo "==> shell.json, and a restart"
# The ids quoted for the far side's shell, which splits the command again.
ssh "$PHONE" "REMOVE=$remove IDS='${ids[*]}' bash -s" <<'ENDSSH'
set -euo pipefail
for id in $IDS; do
  if [ "$REMOVE" = 0 ]; then
    # The entry Mobile's plugin-apps service lists in the drawer. Without one
    # it writes a bare entry with a generic icon; with $id.desktop in the
    # plugin it uses that. So: the app's own entry, pointed at the shell and
    # at the plugin's icon -- and hidden when the app's package is installed
    # too, whose entry already opens it in the shell, or the drawer lists it
    # twice.
    d=~/.config/omarchy/plugins/$id
    src=$(ls "$d"/*.desktop 2>/dev/null | grep -v -e '\.open\.desktop$' -e '\.compose\.desktop$' -e "/$id\.desktop\$" | head -1)
    if [ -n "$src" ]; then
      { sed -e "s|^Exec=.*|Exec=omarchy-shell shell summon $id|" -e "s|^Icon=.*|Icon=$d/icon.svg|" \
            -e '/^NoDisplay=/d' -e '/^MimeType=/d' "$src"
        [ -f "/usr/share/applications/$(basename "$src")" ] && echo "NoDisplay=true"
      } > "$d/$id.desktop"
    fi
    omarchy plugin validate ~/.config/omarchy/plugins/$id
    omarchy plugin enable $id 2>/dev/null || omarchy plugin enable $id --yes 2>/dev/null || true
  fi
done
python3 - <<'PY'
import json, os
from pathlib import Path
ids = os.environ["IDS"].split()
remove = os.environ["REMOVE"] == "1"
defaults = json.loads(Path("/usr/share/omarchy/config/omarchy/shell.json").read_text())
p = Path.home() / ".config/omarchy/shell.json"
data = dict(defaults)
if p.exists():
    try:
        user = json.loads(p.read_text())
        if isinstance(user, dict):
            data.update(user)
    except ValueError:
        pass
# shell.json is not merged with the defaults: a file without "version" or
# "plugins" is a shell with nothing in it.
data["version"] = data.get("version") or defaults.get("version") or 1
plugins = data.get("plugins")
if not isinstance(plugins, list) or not plugins:
    plugins = list(defaults.get("plugins") or [])
pid = lambda e: e.get("id") if isinstance(e, dict) else e
for i in ids:
    have = [pid(e) for e in plugins]
    if remove and i in have:
        plugins = [e for e in plugins if pid(e) != i]
        print("    removed", i)
    elif not remove and i not in have:
        plugins.append({"id": i})
        print("    added", i)
data["plugins"] = plugins
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(json.dumps(data, indent=2) + "\n")
PY
# Made before the restart, not left to the plugin-apps service: that writes
# omarchy-plugin-<id>.desktop a few seconds after the shell is up, and
# Quickshell's DesktopEntries only watches application folders that existed
# when it started. On a phone with no user entries yet the folder is born
# after the scan, and the app never reaches the drawer until the next restart.
mkdir -p ~/.local/share/applications
update-desktop-database ~/.local/share/applications >/dev/null 2>&1 || true
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
# Through Hyprland, so the new shell is the compositor's child and in the seat;
# one started from this ssh session would get nothing from polkit.
omarchy-restart-shell >/dev/null 2>&1 || true
sleep 4
pgrep -x quickshell >/dev/null && echo "    shell restarted" || echo "    shell did not come back: journalctl --user"
ENDSSH
[[ $remove -eq 1 ]] || echo "==> done: omarchy-shell shell summon ${ids[0]}"
