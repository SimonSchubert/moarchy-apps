#!/usr/bin/python3
"""Write a game worth photographing into MOARCHY_PEGSOLITAIRE_DIR.

A figure at its starting position says nothing about the app: no jumps made,
no ring round anything, no result. So this is a real game stopped partway, in
the file shape the app reads and the GTK version wrote.

    demo.py          the English board eleven jumps down a line that wins
    demo.py stuck    the Pyramid played to a dead end, with the banner up
                     (or DEMO=stuck, as a shot in dev/shots sets it)

Both jump lists were played, not placed: the first is the first eleven jumps
of the line 0.1.0's solver found for the English board (tst_solver.qml checks
the QML solver finds the same one), and the second is a seeded random game of
the Pyramid that ran out of jumps. A hand-emptied board is very likely one
legal play could not reach, and the app would be photographed telling a lie
about its own rules. The record is invented.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

BOARD = ("english", [41, 63, 9, 18, 70, 59, 72, 82, 92, 9, 87])
STUCK = ("pyramid", [96, 128, 120])

RECORD = {
    "english": {"played": 7, "best": 3, "solved": 0, "perfect": 0},
    "cross": {"played": 4, "best": 1, "solved": 3, "perfect": 0},
    "plus": {"played": 3, "best": 1, "solved": 2, "perfect": 2},
    "pyramid": {"played": 2, "best": 2, "solved": 0, "perfect": 0},
}


def main() -> int:
    target = os.environ.get("MOARCHY_PEGSOLITAIRE_DIR")
    if not target:
        print("set MOARCHY_PEGSOLITAIRE_DIR first -- refusing to touch a real game", file=sys.stderr)
        return 2
    stuck = (len(sys.argv) > 1 and sys.argv[1] == "stuck") or os.environ.get("DEMO") == "stuck"
    figure, moves = STUCK if stuck else BOARD
    game = {
        "schema": 1,
        "game": {"figure": figure, "finished": stuck, "recorded": stuck, "moves": moves},
        "stats": RECORD,
    }
    out = Path(target)
    out.mkdir(parents=True, exist_ok=True)
    (out / "pegsolitaire.json").write_text(json.dumps(game, indent=1) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
