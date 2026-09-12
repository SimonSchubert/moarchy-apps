#!/bin/bash
# Do this app's icon names exist on the phone?
#
#   scripts/icon-check.sh habits
#
# An icon name that the theme does not have is not an error. GTK draws the
# missing-image placeholder and says nothing, so the app runs, the screenshot is
# taken, and a grey warning triangle sits in the middle of the empty state until
# somebody looks at the picture.
#
# scripts/check.sh cannot catch it: the container's icon theme is Adwaita and the
# phone's is Yaru-blue, so a name can be present in every test and absent on the
# only machine that matters. Both view-list-bullet-symbolic and
# document-edit-symbolic passed in the container and drew placeholders on the
# device.
#
# This asks the running guest, because the guest is the authority. It needs the
# VM up and the lease taken.
#
# The reliable fix for a name with no home in some theme is to use the app's own
# icon, which its package installs -- it cannot be missing wherever the app is.
set -uo pipefail
cd "$(dirname "$0")/.."

APP="${1:?usage: icon-check.sh <app>}"
[[ -d "apps/$APP" ]] || { echo "no such app: $APP" >&2; exit 1; }
VM="${MOARCHY_VM:-$HOME/Projects/omarchy-mobile}"
[[ -x "$VM/scripts/vm-ssh.sh" ]] || { echo "no VM at $VM -- set MOARCHY_VM" >&2; exit 1; }

names=$(grep -rhoE 'icon_name="[^"]+"|set_icon_name\("[^"]+"\)' "apps/$APP"/moarchy_*/*.py \
        | grep -oE '"[^"]+"' | tr -d '"' | sort -u)
[[ -n $names ]] || { echo "no icon names found in apps/$APP"; exit 0; }

echo "==> icon names in apps/$APP, against the phone's own theme"
"$VM/scripts/vm-ssh.sh" "
export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1
python3 - <<'PY'
import gi
gi.require_version('Gtk', '4.0')
from gi.repository import Gtk, Gdk
Gtk.init()
theme = Gtk.IconTheme.get_for_display(Gdk.Display.get_default())
names = '''$(echo $names)'''.split()
print('    theme:', theme.get_theme_name())
missing = [n for n in names if not theme.has_icon(n)]
for n in names:
    print(('    ok      ' if n not in missing else '    MISSING ') + n)
raise SystemExit(1 if missing else 0)
PY"
