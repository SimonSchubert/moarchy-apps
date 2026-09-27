#!/bin/bash
# Every check this repository has, in one run.
#
#   scripts/check.sh              -- everything
#   scripts/check.sh habits mail  -- the repo-wide lints, then just those apps
#
# On a Mac the file checks run here and the QML half needs the container:
#
#   docker run --rm -v "$PWD:/src" -w /src moarchy-qml scripts/check.sh
#
#   ruff            -- the Python that is left: demo fixtures, the mail and
#                      food helpers, and these scripts
#   icon-lint       -- no clip paths, which QtSvg ignores and paints
#   pkgbuild-lint   -- every file a PKGBUILD installs exists
#   Python tests    -- an app's tests/test_*.py (the mail and food helpers)
#   app-check.sh    -- per Quickshell app: its manifest, qmllint, qmltestrunner
#                      and a real run that fails on any QML warning
set -uo pipefail
cd "$(dirname "$0")/.."

status=0
run() { printf '\n==> %s\n' "$*"; "$@" || status=1; }

apps=("$@")
if [[ ${#apps[@]} -eq 0 ]]; then
  # The apps on the kit. Couch, Airwaves, Crypto Market and Transit are
  # Quickshell apps that came in with widgets of their own; their repos check them.
  for d in apps/*/; do [[ -L $d/kit ]] && apps+=("$(basename "$d")"); done
fi

if command -v ruff >/dev/null; then
  run ruff check apps scripts
  run ruff format --check apps scripts
else
  echo "ruff not installed -- skipping the Python lint"
fi
run python3 scripts/icon-lint.py
run python3 scripts/pkgbuild-lint.py

for app in "${apps[@]}"; do
  if compgen -G "apps/$app/tests/test_*.py" >/dev/null; then
    run python3 -m unittest discover -s "apps/$app/tests" -p 'test_*.py'
  fi
done

if command -v quickshell >/dev/null; then
  run scripts/app-check.sh "${apps[@]}"
else
  run python3 scripts/app-lint.py "${apps[@]}"
  echo "no quickshell -- run in docker/Dockerfile.qml for the QML half"
fi

exit $status
