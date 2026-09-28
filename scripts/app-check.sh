#!/bin/bash
# Everything that can be checked about a Quickshell app in apps/ without a
# phone. scripts/check.sh runs it, after the repo-wide lints.
#
#   scripts/app-check.sh              -- every app with a Panel.qml, and the kit
#   scripts/app-check.sh vitals       -- just that one
#
#   app-lint.py    -- what the manifest, PKGBUILD and launcher claim
#   qmllint        -- the app and its kit, read
#   qmltestrunner  -- the .pragma library modules
#   a real run     -- quickshell, offscreen, failing on any QML warning
#
# The last one is the one that matters: `quickshell -p shell.qml` exits 0 with
# a ReferenceError in a tap handler, and the only sign is a line on stderr.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH=/usr/lib/qt6/bin:$PATH

status=0
run() { printf '\n==> %s\n' "$*"; "$@" || status=1; }

names=("$@")
if [[ ${#names[@]} -eq 0 ]]; then
  for d in apps/*/; do [[ -f $d/Panel.qml && -L $d/kit ]] && names+=("$(basename "$d")"); done
fi

run python3 scripts/app-lint.py "${names[@]}"

if ! command -v quickshell >/dev/null; then
  echo "no quickshell -- run in docker/Dockerfile.qml for the UI checks" >&2
  exit 1
fi

run env QT_QPA_PLATFORM=offscreen qmltestrunner -input shared/kit/tests

# The gallery draws every widget in the kit, so a kit change that breaks one
# fails here before it fails in an app that happens to use it.
printf '\n==> the kit gallery\n'
gwork=$(mktemp -d)
cp -RL shared/kit-gallery "$gwork/g"
if ! qmllint -W 0 --unqualified=info "$gwork"/g/*.qml "$gwork"/g/kit/*.qml >"$gwork/lint.log" 2>&1; then
  grep -E '^(Warning|Error)' "$gwork/lint.log"; status=1
fi
env HOME="$gwork/home" MOARCHY_QUIT_AFTER=4 QT_QPA_PLATFORM=offscreen NO_COLOR=1 \
  timeout 30 quickshell --no-color -p "$gwork/g/shell.qml" >"$gwork/run.log" 2>&1
if grep -q 'Configuration Loaded' "$gwork/run.log" && ! grep -E '^\s*(WARN|ERROR|FATAL)\b' "$gwork/run.log" \
    | grep -vqE 'qt\.qpa|MESA|libEGL|zink|wl_display|window masks|qt\.core\.qobject\.connect|PulseAudioService'; then
  echo "clean"
else
  sed 's/^/    /' "$gwork/run.log" | tail -8; status=1
fi
rm -rf "$gwork"

for name in "${names[@]}"; do
  dir="apps/$name"
  [[ -f $dir/Panel.qml ]] || { echo "no such app: $name" >&2; status=1; continue; }
  printf '\n########## %s ##########\n' "$name"

  # A copy with the kit resolved, as the release tarball has it: the thing
  # linted and run is the thing shipped.
  work=$(mktemp -d)
  cp -RL "$dir" "$work/app"
  rm -rf "$work/app/docs"

  # -W 0 makes any warning a failure. --unqualified=info is visible but not
  # fatal, until the delegates carry `pragma ComponentBehavior: Bound`.
  # Only the warnings are printed: the info notes are hundreds of lines and
  # say the same thing about every delegate.
  printf '\n==> qmllint\n'
  if qmllint -W 0 --unqualified=info "$work"/app/*.qml "$work"/app/kit/*.qml >"$work/lint.log" 2>&1; then
    echo "clean"
  else
    grep -E '^(Warning|Error)' "$work/lint.log" | sed "s|$work/app/||"; status=1
  fi

  if [[ -d $dir/tests ]]; then
    run env QT_QPA_PLATFORM=offscreen qmltestrunner -input "$dir/tests"
  fi

  printf '\n==> a real run, offscreen\n'
  up=$(tr '[:lower:]-' '[:upper:]_' <<<"$name")
  data="$work/data"; state="$work/state"
  mkdir -p "$data/moarchy-$name" "$state"
  if [[ -f $dir/dev/demo.py ]]; then
    env "MOARCHY_${up}_DIR=$data/moarchy-$name" "XDG_DATA_HOME=$data" \
        python3 "$dir/dev/demo.py" >/dev/null 2>&1
  fi
  log="$work/run.log"
  env "XDG_DATA_HOME=$data" "XDG_STATE_HOME=$state" "MOARCHY_${up}_DIR=$data/moarchy-$name" \
      MOARCHY_QUIT_AFTER=6 "MOARCHY_${up}_OFFLINE=1" \
      QT_QPA_PLATFORM=offscreen NO_COLOR=1 \
      timeout 40 quickshell --no-color -p "$work/app/shell.qml" >"$log" 2>&1

  # An empty log is not a pass: a config that never loaded has one too.
  if ! grep -q 'Configuration Loaded' "$log"; then
    echo "the config never loaded:"; sed 's/^/    /' "$log" | tail -12; status=1
  fi
  # PulseAudioService: a container has no sound server for an app that plays.
  complaints=$(grep -E '^\s*(WARN|ERROR|FATAL)\b' "$log" \
    | grep -vE 'qt\.qpa|MESA|libEGL|zink|wl_display|window masks|qt\.core\.qobject\.connect|PulseAudioService' \
    | sort -u)
  if [[ -n $complaints ]]; then
    echo "the run complained:"; printf '%s\n' "$complaints" | sed 's/^/    /'; status=1
  else
    echo "clean"
  fi
  rm -rf "$work"
done

exit $status
