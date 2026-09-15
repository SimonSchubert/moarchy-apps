#!/bin/bash
# Copy the chrome catalog onto the phone, with shared/qs_ui vendored as ui/.
#
#   plugins/org.moarchy.ui.catalog/install-on-device.sh
#
# PHONE defaults to the same target scripts/device.sh uses.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
KIT="$(cd "$ROOT/../../shared/qs_ui" && pwd)"
PHONE="${PHONE:-moarchy@192.168.0.18}"
ID="org.moarchy.ui.catalog"
DEST=".config/omarchy/plugins/$ID"

echo "==> copy $ID to $PHONE:$DEST"
ssh "$PHONE" "mkdir -p $DEST/ui ~/.local/share/applications ~/.local/share/icons/hicolor/scalable/apps"
scp "$ROOT/manifest.json" "$ROOT/Catalog.qml" "$ROOT/icon.svg" "$PHONE:$DEST/"
scp "$KIT/"*.qml "$KIT/"*.js "$KIT/qmldir" "$PHONE:$DEST/ui/"
scp "$ROOT/icon.svg" "$PHONE:.local/share/icons/hicolor/scalable/apps/org.moarchy.UiCatalog.svg"
scp "$ROOT/org.moarchy.UiCatalog.plugin.desktop" \
  "$PHONE:.local/share/applications/org.moarchy.UiCatalog.plugin.desktop"

echo "==> validate and enable"
ssh "$PHONE" bash -s <<'ENDSSH'
set -euo pipefail
ID=org.moarchy.ui.catalog
omarchy plugin validate ~/.config/omarchy/plugins/$ID
omarchy plugin enable $ID 2>/dev/null || omarchy plugin enable $ID --yes 2>/dev/null || true
python3 - <<'PY'
import json
from pathlib import Path
ID = "org.moarchy.ui.catalog"
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
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export SWAYSOCK="${SWAYSOCK:-$(ls "$XDG_RUNTIME_DIR"/sway-ipc.* 2>/dev/null | head -1)}"
export OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
pkill -x quickshell 2>/dev/null || true
for _ in $(seq 20); do pgrep -x quickshell >/dev/null || break; sleep 0.2; done
mkdir -p ~/.local/state/moarchy
QS_DISABLE_FILE_WATCHER=1 QS_NO_RELOAD_POPUP=1 \
  setsid quickshell -n -p "$OMARCHY_PATH/shell" >~/.local/state/moarchy/shell.log 2>&1 &
sleep 2
pgrep -x quickshell >/dev/null && echo "    restarted omarchy-shell" || echo "    shell failed to start, see ~/.local/state/moarchy/shell.log"
ENDSSH
echo "==> done. tap Chrome in the drawer, or: omarchy-shell shell toggle $ID"
