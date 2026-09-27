#!/usr/bin/python3
"""Check what a Quickshell app in apps/ claims about itself against the disk.

manifest-lint.py is this for the plugins in plugins/. An app here makes its
claims in five places, and every one of them has been wrong once somewhere:

* `manifest.json` names Panel.qml as the panel the shell loads.
* `kit` is the shared kit, linked in -- a copy would drift from the others.
* `bin/<package>` asks the shell for the plugin id before starting its own.
* the .desktop file runs that launcher.
* the PKGBUILD installs the kit beside the app, or the package cannot start.

And one rule about the views: a colour written into one is a view that ignores
the theme. Hex colours belong in Panel.qml's Tokens (as a theme's fallbacks)
and in the kit, nowhere else.

    scripts/app-lint.py            -- every app with a kit
    scripts/app-lint.py vitals     -- just that one
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REQUIRED = ("schemaVersion", "id", "name", "version", "author", "license",
            "description", "homepage", "icon", "kinds", "keepLoaded", "entryPoints")
HEX = re.compile(r'"#[0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?"')
# Files whose hex colours are the theme's fallbacks, not a view's.
HEX_OK = {"Panel.qml", "Mark.qml"}


def pkgname(app: Path) -> str:
    pkgbuild = app / "PKGBUILD"
    if pkgbuild.exists():
        m = re.search(r"^pkgname=(\S+)", pkgbuild.read_text(), re.M)
        if m:
            return m.group(1).strip("'\"")
    return f"moarchy-{app.name}"


def check(app: Path) -> list[str]:
    bad: list[str] = []
    name = app.name

    try:
        manifest = json.loads((app / "manifest.json").read_text())
    except (OSError, ValueError) as exc:
        return [f"{name}: manifest.json: {exc}"]
    for key in REQUIRED:
        if key not in manifest:
            bad.append(f"{name}: manifest.json has no {key}")
    if manifest.get("kinds") != ["panel"]:
        bad.append(f"{name}: kinds is {manifest.get('kinds')}, not [\"panel\"]")
    if manifest.get("entryPoints", {}).get("panel") != "Panel.qml":
        bad.append(f"{name}: entryPoints.panel is not Panel.qml")
    if manifest.get("keepLoaded") is not True:
        bad.append(f"{name}: keepLoaded is not true")
    icon = manifest.get("icon")
    if icon and not (app / icon).exists():
        bad.append(f"{name}: manifest icon {icon} does not exist")
    pid = manifest.get("id", "")

    kit = app / "kit"
    if not kit.is_symlink() or os.readlink(kit) != "../../shared/kit":
        bad.append(f"{name}: kit is not a link to ../../shared/kit")

    for f in ("Panel.qml", "shell.qml", "LICENSE", "README.md"):
        if not (app / f).exists():
            bad.append(f"{name}: no {f}")
    if (app / "shell.qml").exists() and "standalone: true" not in (app / "shell.qml").read_text():
        bad.append(f"{name}: shell.qml does not run Panel standalone")

    pkg = pkgname(app)
    launcher = app / "bin" / pkg
    if not launcher.exists():
        bad.append(f"{name}: no bin/{pkg}")
    else:
        text = launcher.read_text()
        if f"ID={pid}" not in text or "shell summon" not in text:
            bad.append(f"{name}: bin/{pkg} does not summon {pid} first")
        if not os.access(launcher, os.X_OK):
            bad.append(f"{name}: bin/{pkg} is not executable")

    desktops = list(app.glob("*.desktop"))
    if not desktops:
        bad.append(f"{name}: no .desktop file")
    for d in desktops:
        if f"Exec={pkg}" not in d.read_text():
            bad.append(f"{name}: {d.name} does not run {pkg}")

    pkgbuild = app / "PKGBUILD"
    if pkgbuild.exists():
        text = pkgbuild.read_text()
        if "kit" not in text.split("package()", 1)[-1]:
            bad.append(f"{name}: PKGBUILD does not install kit/")
    else:
        bad.append(f"{name}: no PKGBUILD")

    for qml in sorted(app.glob("*.qml")):
        if qml.name in HEX_OK:
            continue
        for n, line in enumerate(qml.read_text().splitlines(), 1):
            if HEX.search(line) and not line.strip().startswith("//"):
                bad.append(f"{name}: {qml.name}:{n}: a colour in a view: {line.strip()}")
    return bad


def main(argv: list[str]) -> int:
    if argv:
        apps = [ROOT / "apps" / a for a in argv]
    else:
        apps = sorted(p for p in (ROOT / "apps").iterdir() if (p / "kit").is_symlink())
    bad: list[str] = []
    for app in apps:
        bad += check(app)
    for line in bad:
        print(line)
    print(f"{len(apps)} app(s), {len(bad)} problem(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
