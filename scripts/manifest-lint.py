#!/usr/bin/python3
"""Check what a plugin's manifest and installer claim against what is on disk.

`pkgbuild-lint.py` exists because five PKGBUILDs installed files that did not
exist and nothing noticed until a package was built. A plugin makes the same
class of claim in four more places, none of them checked until now:

* `manifest.json`'s `entryPoints` names a file the host will load.
* `install-on-device.sh` names every file it copies, one `scp` argument at a
  time -- so a file added to a plugin and not to that line installs a plugin
  that is missing it, and `omarchy plugin validate` does not say so.
* `shared/qs_ui/qmldir` names every component a plugin can import as `Chrome.X`.
  A component added without a line is importable by relative path and not as
  `Chrome.X`, and nothing says so until an app tries.
* `shell.qml` is what lets anything run, check or photograph the plugin at all.

None of this needs a phone, a compositor or a build. It is all a property of
the files, checked by reading them.
"""

from __future__ import annotations

import json
import re
import shlex
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KIT = ROOT / "shared" / "qs_ui"

REQUIRED = ("id", "name", "version", "author", "license", "description",
            "kinds", "keepLoaded", "entryPoints")

# The shapes a plugin may declare. moarchy-store's own rule: a bar widget has
# nowhere to draw on this phone and a bare service has nothing to open.
KINDS = ("overlay", "panel", "menu", "bar", "service")


def scp_sources(script: Path, plugin: Path) -> list[Path]:
    """Every local path an install-on-device.sh copies.

    Folded the way pkgbuild-lint.py folds a PKGBUILD: continuations joined,
    then each `scp` line read as words, destinations (anything with a remote
    `host:path` colon) dropped, flags dropped, and the two variables the
    scripts actually use expanded.
    """
    text = script.read_text(encoding="utf-8").replace("\\\n", " ")
    out: list[Path] = []
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("scp "):
            continue
        try:
            words = shlex.split(line)
        except ValueError:
            continue
        for word in words[1:]:
            if word.startswith("-"):
                continue
            # "$PHONE:$DEST/" and friends -- the destination, always last.
            if '"$PHONE' in word or word.startswith("$PHONE") or ":" in word.split("/")[0]:
                continue
            path = word.replace("$ROOT", str(plugin)).replace("$KIT", str(KIT))
            if "$" in path:
                continue
            out.append(Path(path))
    return out


def check_plugin(plugin: Path) -> list[str]:
    bad: list[str] = []
    problems_extra: list[str] = []
    name = plugin.name

    manifest_path = plugin / "manifest.json"
    if not manifest_path.exists():
        return [f"{name}: no manifest.json"]
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except ValueError as exc:
        return [f"{name}/manifest.json: not valid JSON -- {exc}"]

    for key in REQUIRED:
        if key not in manifest or manifest[key] in ("", None, [], {}):
            bad.append(f"{name}/manifest.json: missing or empty {key!r}")

    if manifest.get("schemaVersion") != 1:
        bad.append(f"{name}/manifest.json: schemaVersion is "
                   f"{manifest.get('schemaVersion')!r}, not 1")

    if manifest.get("id") != name:
        bad.append(f"{name}/manifest.json: id is {manifest.get('id')!r}, "
                   f"which is not the directory name")

    kinds = manifest.get("kinds") or []
    entries = manifest.get("entryPoints") or {}
    for kind in kinds:
        if kind not in KINDS:
            bad.append(f"{name}/manifest.json: unknown kind {kind!r}")
        if kind not in entries:
            bad.append(f"{name}/manifest.json: kind {kind!r} has no entryPoint")
    for kind, target in entries.items():
        if kind not in kinds:
            bad.append(f"{name}/manifest.json: entryPoint {kind!r} is not in kinds")
        if not (plugin / target).exists():
            bad.append(f"{name}/manifest.json: entryPoint {kind!r} names "
                       f"{target}, which does not exist")

    # What nothing else can check: a plugin with no standalone entry point
    # cannot be run, linted end to end, or photographed by any harness here.
    for required_file in ("shell.qml", "run-local.sh", "install-on-device.sh"):
        if not (plugin / required_file).exists():
            bad.append(f"{name}: no {required_file}")

    shell = plugin / "shell.qml"
    if shell.exists():
        text = shell.read_text(encoding="utf-8")
        # Timer, Connections and Component are QtQuick types, and an
        # unresolved type fails the whole document at load -- which is exactly
        # how both shell.qml files here shipped unable to start.
        if re.search(r"\b(Timer|Connections|Component)\b", text) and \
                not re.search(r"^import QtQuick\s*$", text, re.M):
            bad.append(f"{name}/shell.qml: uses a QtQuick type without "
                       f"`import QtQuick`")

    # The icon the entry asks for must be the icon the installer lays down.
    #
    # A desktop entry names its icon without a path or an extension, and the
    # lookup is case-sensitive: `Icon=org.moarchy.TicTacToe` finds
    # org.moarchy.TicTacToe.svg and does not find org.moarchy.Tictactoe.svg.
    # There is no error when it misses -- the drawer simply draws a blank tile,
    # which is how Noughts and crosses shipped with no icon at all.
    desktop = next(iter(plugin.glob("*.plugin.desktop")), None)
    if desktop is not None:
        text = desktop.read_text(encoding="utf-8")
        wanted = ""
        for line in text.splitlines():
            if line.startswith("Icon="):
                wanted = line.split("=", 1)[1].strip()
        installer_text = ""
        installer_path = plugin / "install-on-device.sh"
        if installer_path.exists():
            installer_text = installer_path.read_text(encoding="utf-8")
        if wanted and installer_text:
            if f"/{wanted}.svg" not in installer_text:
                laid = re.findall(r"hicolor/scalable/apps/([^\"\s]+)\.svg", installer_text)
                problems_extra.append(
                    f"{name}: the desktop entry asks for icon {wanted!r} but "
                    f"install-on-device.sh lays down "
                    f"{laid[0] if laid else 'nothing'!r}")

    installer = plugin / "install-on-device.sh"
    if installer.exists():
        named = scp_sources(installer, plugin)
        for source in named:
            if not any(source.parent.glob(source.name)):
                rel = source.relative_to(ROOT) if ROOT in source.parents else source
                bad.append(f"{name}/install-on-device.sh: copies {rel}, "
                           f"which does not exist")
        # The converse, which pkgbuild-lint.py does not check because a
        # PKGBUILD may legitimately not install a test file. For a plugin the
        # tree is the package, so an orphan is a missing install line.
        named_names = {p.name for p in named}
        # Only a wildcard *inside the plugin's own directory* can excuse the
        # check below. The kit is copied with `$KIT/*.qml`, and treating that as
        # a wildcard over the plugin switched this off entirely -- which is how
        # a plugin shipped without its rules file and still linted clean.
        wildcarded = any("*" in f.name and f.parent == plugin for f in named)
        if not wildcarded:
            for f in sorted(plugin.glob("*.qml")) + sorted(plugin.glob("*.js")):
                if f.name == "shell.qml":
                    continue  # the standalone entry point is not installed
                if f.name not in named_names:
                    bad.append(f"{name}/install-on-device.sh: never copies "
                               f"{f.name}")
    bad += problems_extra
    return bad


def check_kit() -> list[str]:
    """shared/qs_ui/qmldir against the directory it describes."""
    bad: list[str] = []
    qmldir = KIT / "qmldir"
    if not qmldir.exists():
        return ["shared/qs_ui/qmldir: missing"]
    listed = {}
    for line in qmldir.read_text(encoding="utf-8").splitlines():
        parts = line.split()
        if len(parts) == 3:
            listed[parts[0]] = parts[2]
    for component, filename in sorted(listed.items()):
        if not (KIT / filename).exists():
            bad.append(f"shared/qs_ui/qmldir: {component} names {filename}, "
                       f"which does not exist")
    for f in sorted(KIT.glob("*.qml")):
        if f.name not in listed.values():
            bad.append(f"shared/qs_ui/qmldir: no line for {f.name}, so it "
                       f"cannot be imported as Chrome.{f.stem}")
    return bad


def check_vendored_not_tracked() -> list[str]:
    """A committed plugins/*/ui/ would go stale silently.

    .gitignore names it; this is the check that the ignore is working, because
    a file added with `git add -f` stays added.
    """
    try:
        out = subprocess.run(["git", "ls-files", "plugins"], cwd=ROOT,
                             capture_output=True, text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return []
    tracked = [p for p in out.splitlines() if "/ui/" in p]
    return [f"{p}: a vendored copy of the kit is tracked; it will go stale"
            for p in tracked]


def main() -> int:
    plugins = sorted(p for p in (ROOT / "plugins").iterdir() if p.is_dir())
    if not plugins:
        print("no plugins found", file=sys.stderr)
        return 1

    bad: list[str] = []
    bad += check_kit()
    bad += check_vendored_not_tracked()
    for plugin in plugins:
        problems = check_plugin(plugin)
        bad += problems
        print(f"    {plugin.relative_to(ROOT)}: "
              f"{'ok' if not problems else f'{len(problems)} problem(s)'}")

    for problem in bad:
        print(f"    {problem}")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
