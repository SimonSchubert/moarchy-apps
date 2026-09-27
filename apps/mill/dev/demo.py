#!/usr/bin/python3
"""Write a game worth photographing into MOARCHY_MILL_DIR.

An empty Morris board is three squares and nothing else. So this writes a real
game, in the file shape the app reads and 0.1.0 wrote -- one 0.1.0's own
opponent played against itself at a fixed seed, recorded here as its move list
so that the fixture needs nothing but Python to write it.

A played game rather than scattered pieces, because every screenshot then
shows a position legal play can reach: a side with six pieces and none in hand
has had three taken, and a board that does not add up says so.

    demo.py           the middle game, everything placed, you to move
    demo.py take      a mill just closed, the pieces you may take ringed
    demo.py won       a finished game: you won with three left

DEMO=take or DEMO=won does the same, as a shot in dev/shots sets it. The record
is invented.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

# 0.1.0's demo.py, run: Medium as white against Easy, seed 20260913.
BOARD = [6, 0, 4, 5, 13, 16, 19, 2, 1, 22, 23, 20, 21, 9, 11, 10, 3, 10, 8,
         298, 231, 275, 5, 250, 341, 2, 391]
TAKE = [6, 0, 4, 5, 13, 16, 19, 2, 1, 22, 23, 20, 21, 9, 11, 10, 3]
# Hard as white against Easy, seed 1: white wins with three left.
WON = [0, 3, 2, 1, 6, 7, 5, 4, 13, 21, 12, 14, 10, 11, 19, 15, 23, 8, 2, 273,
       50, 12, 25, 300, 498, 323, 473, 11, 550, 450, 573, 473, 21, 107, 357,
       291, 5, 173, 373, 550, 350, 5, 448, 7, 125, 425, 3, 75, 448, 3, 157,
       425, 13, 376, 573, 422, 23, 541, 404, 341, 519, 5, 59, 217, 440, 61,
       298, 13]

# (level, played, won, lost, best) -- a plausible record for the page.
RECORD = (("easy", 8, 7, 1, 7), ("medium", 14, 6, 7, 6), ("hard", 5, 1, 4, 4))


def main() -> int:
    target = os.environ.get("MOARCHY_MILL_DIR")
    if not target:
        print("set MOARCHY_MILL_DIR first -- refusing to touch a real game", file=sys.stderr)
        return 2
    stage = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("DEMO", "board")
    moves = {"take": TAKE, "won": WON}.get(stage, BOARD)
    finished = stage == "won"

    stats = {}
    for level, played, won, lost, best in RECORD:
        stats[level] = {
            "played": played, "won": won, "lost": lost,
            "drawn": played - won - lost, "best": best,
        }
    data = {
        "schema": 1,
        "game": {
            "mode": "solo",
            "level": "medium",
            "human": "white",
            "finished": finished,
            "recorded": finished,
            "moves": moves,
        },
        "stats": stats,
    }
    out = Path(target)
    out.mkdir(parents=True, exist_ok=True)
    (out / "mill.json").write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
