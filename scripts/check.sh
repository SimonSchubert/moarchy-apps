#!/bin/bash
# Everything that can be checked without a phone, for one app or all of them.
#
#   scripts/check.sh            -- every app
#   scripts/check.sh habits     -- just that one
#
#   ruff        -- style and dead code, over the app and the shared code
#   unittest    -- the storage layer, which is deliberately GTK-free
#   a real run  -- the app, on a virtual screen, failing on any GTK warning
#
# That last one is the one that matters. A GTK layout error is not an
# exception: the app starts, the window appears, and one widget is the wrong
# size or missing entirely, with a single line on stderr as the only sign. On a
# phone that line goes to a journal nobody reads.
set -uo pipefail
cd "$(dirname "$0")/.."

status=0
run() { printf '\n==> %s\n' "$*"; "$@" || status=1; }

apps=("$@")
if [[ ${#apps[@]} -eq 0 ]]; then
  mapfile -t apps < <(find apps -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort)
fi

if command -v ruff >/dev/null; then
  run ruff check shared apps scripts
  run ruff format --check shared apps scripts
else
  echo "ruff not installed -- skipping lint"
fi

run python3 scripts/icon-lint.py
run python3 scripts/pkgbuild-lint.py

for app in "${apps[@]}"; do
  dir="apps/$app"
  [[ -d $dir ]] || { echo "no such app: $app" >&2; status=1; continue; }
  printf '\n########## %s ##########\n' "$app"

  # shared first on the path, so an app importing moarchy_ui gets this tree's
  # copy and not one left installed on the machine from a package.
  export PYTHONPATH="$PWD/shared:$PWD/$dir"

  if ! command -v Xvfb >/dev/null; then
    echo "no Xvfb -- run in docker/Dockerfile.dev for the UI checks"
    run bash -c "cd '$dir' && python3 -m unittest discover -s tests -v"
    continue
  fi

  DIR=$(mktemp -d)
  export DISPLAY=:98
  Xvfb :98 -screen 0 360x720x24 -nolisten tcp >/dev/null 2>&1 &
  XVFB=$!

  run bash -c "cd '$dir' && dbus-run-session -- python3 -m unittest discover -s tests -v"

  printf '\n==> a real run, at 360x720\n'
  module=$(basename "$(find "$dir" -maxdepth 1 -name 'moarchy_*' -type d)")
  env "$(tr '[:lower:]' '[:upper:]' <<<"MOARCHY_${app}_DIR")=$DIR" python3 "$dir/demo.py" >/dev/null 2>&1

  log="$DIR/run.log"
  env "$(tr '[:lower:]' '[:upper:]' <<<"MOARCHY_${app}_DIR")=$DIR" \
      "$(tr '[:lower:]' '[:upper:]' <<<"MOARCHY_${app}_QUIT_AFTER")=4" \
      dbus-run-session -- python3 -m "$module" >"$log" 2>&1

  # The portal and a11y warnings belong to the container, not to us: there is
  # no desktop session behind this X server for either to connect to.
  complaints=$(grep -E 'WARNING|CRITICAL|ERROR|Traceback' "$log" | grep -vE 'portal|a11y|dbus-daemon|fuse' | sort -u)
  if [[ -n $complaints ]]; then
    echo "the run complained:"
    printf '%s\n' "$complaints" | sed 's/^/    /'
    status=1
  else
    echo "clean"
  fi

  kill $XVFB 2>/dev/null
  rm -rf "$DIR"
done

exit $status
