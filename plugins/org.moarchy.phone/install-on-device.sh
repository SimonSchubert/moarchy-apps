#!/bin/bash
# Copy Phone onto the phone, with shared/qs_ui vendored as ui/.
#
#   plugins/org.moarchy.phone/install-on-device.sh
#
# PHONE is the same target scripts/device.sh takes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
KIT="$(cd "$ROOT/../../shared/qs_ui" && pwd)"
# omarchy@<address>, or the name `./mobile phone list` prints in the mobile
# repo: an Omarchy Mobile phone announces nothing over mDNS, so there is no
# name that finds it by itself.
PHONE="${PHONE:?set PHONE=omarchy@<phone address>}"
ID="org.moarchy.phone"
DEST=".config/omarchy/plugins/$ID"

echo "==> copy $ID to $PHONE:$DEST"
ssh "$PHONE" "mkdir -p $DEST/ui ~/.local/share/applications ~/.local/share/icons/hicolor/scalable/apps"
scp "$ROOT/manifest.json" "$ROOT/Phone.qml" "$ROOT/DialKey.qml" "$ROOT/CallButton.qml" \
    "$ROOT/Calls.js" "$ROOT/Modem.js" "$ROOT/Numbers.js" "$ROOT/Store.js" "$ROOT/icon.svg" "$PHONE:$DEST/"
scp "$KIT/"*.qml "$KIT/"*.js "$KIT/qmldir" "$PHONE:$DEST/ui/"
scp "$ROOT/icon.svg" "$PHONE:.local/share/icons/hicolor/scalable/apps/org.moarchy.Phone.svg"
scp "$ROOT/org.moarchy.Phone.plugin.desktop" \
  "$PHONE:.local/share/applications/org.moarchy.Phone.plugin.desktop"

echo "==> validate and enable"
ssh "$PHONE" bash -s <<'ENDSSH'
set -euo pipefail
ID=org.moarchy.phone
omarchy plugin validate ~/.config/omarchy/plugins/$ID
omarchy plugin enable $ID 2>/dev/null || omarchy plugin enable $ID --yes 2>/dev/null || true
python3 - <<'PY'
import json
from pathlib import Path
ID = "org.moarchy.phone"
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
data["version"] = data.get("version") or defaults.get("version") or 1
plugins = data.get("plugins")
if not isinstance(plugins, list) or not plugins:
    plugins = list(defaults.get("plugins") or [])
def pid(entry):
    return entry.get("id") if isinstance(entry, dict) else entry
ids = [pid(e) for e in plugins]
if ID not in ids:
    plugins.append({"id": ID})
    print("    added", ID, "to shell.json")
else:
    print("   ", ID, "already in shell.json")
data["plugins"] = plugins
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(json.dumps(data, indent=2) + "\n")
PY
update-desktop-database ~/.local/share/applications >/dev/null 2>&1 || true
# gnome-calls' own daemon would ring as well, and answer from its own window.
# Masked rather than disabled, because a distro package may link it into
# default.target.wants where `disable` cannot reach it.
if systemctl --user cat calls-daemon.service >/dev/null 2>&1; then
  systemctl --user stop calls-daemon.service 2>/dev/null || true
  systemctl --user mask calls-daemon.service >/dev/null 2>&1 \
    && echo "    masked calls-daemon (undo: systemctl --user unmask calls-daemon.service)"
fi
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
# omarchy-restart-shell starts the new shell through Hyprland, so it is the
# compositor's child and in the seat. One started from here would live in this
# ssh session, and polkit gives a remote session nothing.
omarchy-restart-shell >/dev/null 2>&1 || true
sleep 4
pgrep -x quickshell >/dev/null && echo "    restarted omarchy-shell" || echo "    shell failed to start, see journalctl --user"
ENDSSH
echo "==> done. tap Phone in the drawer, or: omarchy-shell shell toggle $ID"
