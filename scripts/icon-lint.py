#!/usr/bin/env python3
"""Are these app icons ones the phone can actually draw?

Two failures, both found the hard way and neither one visible from a test, a
screenshot or a desktop. An icon that is wrong here does not raise: the drawer
draws something else, and somebody has to look at the grid and notice.

1. **It has to be well-formed XML.** Reversi's icon carried a `--` inside its
   own comment, which is not allowed in XML, so librsvg refused the file and
   every drawer showing that icon was showing nothing. It had been that way
   since the icon was written.

2. **It cannot use a clip path.** mobileomarchy's AppDrawer renders with QtSvg,
   which does not clip: `clip-path` is ignored -- so whatever the clip was
   holding in spills over the canvas -- and worse, a `<clipPath>` declared
   outside `<defs>` is *painted*, and an unfilled rect is black. Chess's first
   icon did both, and drew as a black square with a knight on it on any phone
   whose image does not carry omarchy-mobile's repair hook.

   The fix is never a clip. A shape that needs one can carry its own rounded
   corner, or be inset far enough not to need it, or be a `<mask>` -- which
   QtSvg does honour.

Run by scripts/check.sh over every app, because this is a property of a file
rather than of an app, and the second app to get it wrong was the one written
by somebody who had just read the first one's icon and copied its comment.
"""

from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    # plugins/*/icon.svg goes through the same QtSvg drawer as the app icons,
    # so the clipPath rule below applies to it harder, not less -- a plugin's
    # icon is the only artwork it ships. It was unchecked until the QML ports
    # arrived, because this glob named apps/ alone.
    icons = sorted([*ROOT.glob("apps/*/data/*.svg"), *ROOT.glob("plugins/*/icon.svg")])
    if not icons:
        print("no app icons found", file=sys.stderr)
        return 1
    bad = 0
    for icon in icons:
        name = icon.relative_to(ROOT)
        text = icon.read_text(encoding="utf-8")
        try:
            root = ET.fromstring(text)
        except ET.ParseError as exc:
            print(f"    {name}: not well-formed XML -- {exc}")
            bad += 1
            continue
        # Over the parsed tree rather than the text, so that a comment
        # explaining why there is no clip path is not itself a clip path.
        clipped = [
            element
            for element in root.iter()
            if element.tag.endswith("clipPath") or "clip-path" in element.attrib
        ]
        if clipped:
            print(f"    {name}: uses a clip path, which QtSvg ignores and paints")
            bad += 1
            continue
        print(f"    {name}: ok")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
