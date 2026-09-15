#!/bin/bash
# The chrome catalog on this machine, as a plain Quickshell process.
#
#   plugins/org.moarchy.ui.catalog/run-local.sh
#
# Vendors shared/qs_ui as ui/ the way the installer does, then runs the
# standalone entry point. This is the fastest way to see a kit change without
# a phone in front of you.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
KIT="$(cd "$ROOT/../../shared/qs_ui" && pwd)"

rm -rf "$ROOT/ui"
mkdir -p "$ROOT/ui"
cp "$KIT/"*.qml "$KIT/"*.js "$KIT/qmldir" "$ROOT/ui/"

exec quickshell -p "$ROOT/shell.qml" "$@"
