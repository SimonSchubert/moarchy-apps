#!/usr/bin/python3
"""Write a game worth photographing into MOARCHY_TICTACTOE_DIR.

An empty board is four rules and nothing else. So this is a game partway
through, with the person to move, a sitting's score and a record -- in the
file shape the app reads and the GTK version wrote.

    demo.py         a game in progress, X (the person) to move
    demo.py won     the same sitting, one game later, won and struck through
                    (or DEMO=won, as a shot in dev/shots sets it)

The moves are a legal game, played out below. The score and the record are
invented.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

won = (len(sys.argv) > 1 and sys.argv[1] == "won") or os.environ.get("DEMO") == "won"
out = Path(os.environ.get("MOARCHY_TICTACTOE_DIR") or "demo")
out.mkdir(parents=True, exist_ok=True)

game = {
    "schema": 1,
    "game": {
        "mode": "solo",
        "level": "fair",
        "mark": "x",
        # X centre, O an edge (the mistake), X a corner, O blocks the
        # diagonal; X to move. Won: X takes the other corner for a fork, O
        # blocks one side of it, X completes the other.
        "moves": [4, 1, 0, 8, 6, 2, 3] if won else [4, 1, 0, 8],
        "finished": won,
        "recorded": won,
    },
    "series": {"a": 3 if won else 2, "b": 1, "drawn": 4},
    "stats": {
        "easy": {"played": 12, "won": 9, "lost": 1, "drawn": 2, "unbeaten": 6, "best": 8},
        "fair": {"played": 20, "won": 7, "lost": 4, "drawn": 9, "unbeaten": 3, "best": 7},
        "perfect": {"played": 10, "won": 0, "lost": 2, "drawn": 8, "unbeaten": 5, "best": 5},
    },
}
(out / "tictactoe.json").write_text(json.dumps(game, indent=1) + "\n", encoding="utf-8")
