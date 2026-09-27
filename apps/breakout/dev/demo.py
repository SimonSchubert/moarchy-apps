#!/usr/bin/python3
"""Write a game worth photographing into MOARCHY_BREAKOUT_DIR.

A full wall with the ball on the bat says what the app is and nothing about
playing it. So these are walls a real game left: the GTK version's demo played
its own physics at sixty frames a second, with a bat that followed the ball
with a lean that changed, and stopped with part of the wall down. Its walls
were recorded here rather than rubbed out by hand, because a real wall is
eaten from the middle outwards along the ball's lines and an invented one is
easy to spot.

    demo.py          a third of the first wall down
    demo.py late     deep into the second wall, one life gone
    (or DEMO=late, as a shot in dev/shots sets it)

The file is the shape the app reads and the GTK version wrote. The record is
invented.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

BOARD = {
    "level": 0,
    "score": 120,
    "lives": 3,
    "speed": 1.022,
    "bricks": [1, 1, 1, 1, 1, 1, 0,
               1, 1, 1, 1, 1, 0, 0,
               0, 0, 1, 1, 1, 0, 0,
               0, 0, 1, 0, 1, 0, 0,
               0, 0, 0, 0, 1, 0, 0,
               0, 0, 0, 0, 0, 0, 0,
               0, 0, 0, 0, 0, 0, 0,
               0, 0, 0, 0, 0, 0, 0],
}

LATE = {
    "level": 1,
    "score": 335,
    "lives": 2,
    "speed": 1.106,
    "bricks": [0, 0, 2, 2, 2, 0, 0,
               0, 1, 2, 2, 2, 2, 0,
               0, 0, 0, 0, 2, 2, 0,
               0, 0, 0, 0, 0, 0, 0,
               0, 0, 0, 0, 0, 0, 0,
               0, 0, 0, 0, 0, 0, 0,
               0, 0, 0, 0, 0, 0, 0,
               0, 0, 0, 0, 0, 0, 0],
}

STATS = {"played": 23, "best": 2140, "furthest": 4, "cleared": 41}


def main() -> int:
    target = os.environ.get("MOARCHY_BREAKOUT_DIR")
    if not target:
        print("set MOARCHY_BREAKOUT_DIR first -- refusing to touch a real game", file=sys.stderr)
        return 2
    late = (len(sys.argv) > 1 and sys.argv[1] == "late") or os.environ.get("DEMO") == "late"
    out = Path(target)
    out.mkdir(parents=True, exist_ok=True)
    payload = {"schema": 1, "game": LATE if late else BOARD, "stats": STATS}
    (out / "breakout.json").write_text(json.dumps(payload, indent=1) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
