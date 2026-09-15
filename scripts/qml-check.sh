#!/bin/bash
# Everything that can be checked about a plugin without a phone.
#
#   scripts/qml-check.sh                       -- every plugin
#   scripts/qml-check.sh org.moarchy.launches  -- just that one
#
#   qmllint        -- the files, read
#   qmltestrunner  -- the .pragma library modules, which are QML-free by design
#   a real run     -- quickshell, offscreen, failing on any QML warning
#
# The last one is the one that matters, and for check.sh's exact reason with a
# different toolkit. `quickshell -p shell.qml` exits 0 with a ReferenceError in
# a tap handler and three TypeErrors in its log: nothing raises, the window is
# up, one button does nothing, and the only sign is a line on stderr. On a
# phone that line goes to a journal nobody reads.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH=/usr/lib/qt6/bin:$PATH

status=0
run() { printf '\n==> %s\n' "$*"; "$@" || status=1; }

ids=("$@")
if [[ ${#ids[@]} -eq 0 ]]; then
  mapfile -t ids < <(find plugins -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort)
fi

run python3 scripts/icon-lint.py
run python3 scripts/manifest-lint.py

if ! command -v quickshell >/dev/null; then
  echo "no quickshell -- run in docker/Dockerfile.qml for the UI checks" >&2
  exit 1
fi

# The kit's own tests, once rather than per plugin: it is one tree and every
# plugin vendors the same copy of it.
run env QT_QPA_PLATFORM=offscreen qmltestrunner -input shared/qs_ui/tests

for id in "${ids[@]}"; do
  dir="plugins/$id"
  [[ -d $dir ]] || { echo "no such plugin: $id" >&2; status=1; continue; }
  printf '\n########## %s ##########\n' "$id"

  # Vendor ui/ exactly as install-on-device.sh does, into a temp tree, so the
  # thing linted and the thing run is the thing shipped -- and so a checkout
  # never grows a plugins/*/ui/ nobody meant to commit.
  work=$(mktemp -d)
  # *.svg as well as the QML: a plugin may ship artwork of its own -- a glyph
  # no icon theme on this phone has -- and Chrome.Icon takes it by path. Left
  # out, the app lints and runs with three empty tab icons and nothing said.
  cp "$dir"/*.qml "$dir"/*.js "$dir"/*.svg "$dir"/manifest.json "$work/" 2>/dev/null
  mkdir -p "$work/ui"
  cp shared/qs_ui/*.qml shared/qs_ui/*.js shared/qs_ui/qmldir "$work/ui/"

  # -W 0 makes any warning a failure. Without it qmllint exits 0 having just
  # printed the reason the app will not start, which is how two shell.qml
  # files shipped with no `import QtQuick` in them and no standalone path.
  #
  # --unqualified=info is visible but not fatal, until the delegates carry
  # `pragma ComponentBehavior: Bound`. Everything else is fatal today.
  run qmllint -W 0 --unqualified=info "$work"/*.qml "$work"/ui/*.qml

  if [[ -d $dir/tests ]]; then
    run env QT_QPA_PLATFORM=offscreen qmltestrunner -input "$dir/tests"
  fi

  if [[ ! -f $dir/shell.qml ]]; then
    echo "no shell.qml -- nothing can run, check or photograph this plugin" >&2
    status=1; rm -rf "$work"; continue
  fi

  printf '\n==> a real run, at 360x720\n'
  app=${id##*.}
  up=$(tr '[:lower:]' '[:upper:]' <<<"$app")
  data="$work/data"
  mkdir -p "$data/moarchy-$app"

  # demo.py is not ported and does not need to be: it writes the JSON the QML
  # app reads. Both env vars are set so the GTK writer and the QML reader agree
  # on one directory, which is also how a port is shown not to have changed the
  # rules -- the same seeded game photographs in both.
  if [[ -f apps/$app/demo.py ]]; then
    env "MOARCHY_${up}_DIR=$data/moarchy-$app" "XDG_DATA_HOME=$data" \
        PYTHONPATH="$PWD/shared:$PWD/apps/$app" \
        python3 "apps/$app/demo.py" >/dev/null 2>&1
  fi

  log="$work/run.log"
  env "XDG_DATA_HOME=$data" "MOARCHY_${up}_DIR=$data/moarchy-$app" \
      "MOARCHY_${up}_QUIT_AFTER=6" "MOARCHY_${up}_OFFLINE=1" \
      QT_QPA_PLATFORM=offscreen NO_COLOR=1 \
      timeout 40 quickshell --no-color -p "$work/shell.qml" >"$log" 2>&1

  # The positive assertion. An empty log is not a pass: a config that never
  # loaded has an empty log too, which is the failure mode that hid the missing
  # QtQuick import.
  if ! grep -q 'Configuration Loaded' "$log"; then
    echo "the config never loaded:"; sed 's/^/    /' "$log" | tail -12; status=1
  fi

  # Every QML runtime diagnostic is one category with one prefix. The
  # subtractions are the container's, not ours: there is no compositor behind
  # the offscreen platform and no DRI node behind Mesa.
  complaints=$(grep -E '^\s*(WARN|ERROR|FATAL)\b' "$log" \
    | grep -vE 'qt\.qpa|MESA|libEGL|zink|wl_display|window masks|qt\.core\.qobject\.connect' \
    | sort -u)
  if [[ -n $complaints ]]; then
    echo "the run complained:"; printf '%s\n' "$complaints" | sed 's/^/    /'; status=1
  else
    echo "clean"
  fi
  rm -rf "$work"
done

exit $status
