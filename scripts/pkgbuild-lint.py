#!/usr/bin/env python3
"""Does every file a PKGBUILD installs actually exist?

This exists because five of them did not, and nothing noticed.

`scripts/check.sh` runs ruff, the tests and a real app at 360x720, and passes
with flying colours on an app whose PKGBUILD installs
`data/org.moarchy.PegPegSolitaire.desktop` -- a name produced by a sed that
matched twice, for a file that has never existed. The package simply fails to
build, months later, on the machine that builds packages. Five apps here were in
exactly that state at once, because each had been derived from the last.

So this is the packaging equivalent of `icon-lint.py`: a property of a file,
checked by looking, rather than a property of a program, checked by running it.
It resolves each install source the way `scripts/package.sh` assembles the build
directory -- the app's own tree first, then `shared/`, then the repository root
for the two files (LICENSE, ruff.toml) that live there -- and says so when a
path leads nowhere.

It does not try to be makepkg. It reads the `install -D` lines, and that is
enough: every file any app here ships goes in through one of them, and the
failure it catches is always a name, never a rule.

Two apps here package somebody else's code and build it from a git checkout
makepkg makes at build time. Nothing they install is in this repository, so
there is nothing here to check and this says so rather than inventing eleven
failures for files that are not meant to exist yet.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# `install -Dm644 a b c -t dir/` and `install -Dm755 src dest`, with line
# continuations already folded. The sources are everything between the mode and
# either `-t` or the last argument.
INSTALL = re.compile(r"^\s*install\s+-D\w*\s+(.*)$")

# Variables a PKGBUILD uses in paths that are not ours to resolve. A line
# mentioning one of these is a destination, not a source.
DESTINATION = ("$pkgdir", "${pkgdir}")

# An app whose source is a git checkout is an app whose files arrive at build
# time from somebody else's repository.
UPSTREAM = re.compile(r"^source=.*git\+", re.MULTILINE)


def sources(line: str) -> list[str]:
    """The files an install line reads, as written."""
    words = line.split()
    out: list[str] = []
    for word in words:
        if word.startswith("-") or word in ("install", "\\"):
            continue
        if any(mark in word for mark in DESTINATION):
            continue
        out.append(word.strip('"'))
    # `install a b c -t dir` lists sources then a target; `install src dest`
    # lists one of each. Either way the destination has already been dropped
    # above, because every destination in this repository is under $pkgdir.
    return out


def resolve(app: Path, path: str) -> bool:
    """Is there a file here, once the build directory has been assembled?

    `package.sh` copies the app's own tree, `shared/moarchy_ui`, and LICENSE
    from the repository root into one directory and builds there, so a source
    can legitimately come from any of the three.
    """
    for base in (app, ROOT / "shared", ROOT):
        if any(base.glob(path)):
            return True
    return False


def fold(text: str) -> list[str]:
    """The file with its line continuations joined up."""
    return re.sub(r"\\\n\s*", " ", text).splitlines()


def main() -> int:
    builds = sorted(ROOT.glob("apps/*/PKGBUILD"))
    if not builds:
        print("no PKGBUILDs found", file=sys.stderr)
        return 1
    bad = 0
    for build in builds:
        app = build.parent
        name = build.relative_to(ROOT)
        text = build.read_text(encoding="utf-8")
        if UPSTREAM.search(text):
            print(f"    {name}: builds from an upstream checkout -- skipped")
            continue
        missing: list[str] = []
        for line in fold(text):
            found = INSTALL.match(line)
            if not found:
                continue
            if "/dev/stdin" in line:
                continue  # a heredoc, written by the build rather than read
            for source in sources(found.group(1)):
                if "$" in source:
                    continue  # resolved by makepkg, not by this repository
                if not resolve(app, source):
                    missing.append(source)
        if missing:
            for source in missing:
                print(f"    {name}: installs {source}, which is not there")
            bad += 1
        else:
            print(f"    {name}: ok")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
