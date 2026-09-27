#!/usr/bin/python3
"""Write a game worth photographing into MOARCHY_REVERSI_DIR.

An empty board is four discs in the middle and says nothing about the app. So
this is a real game: the moves 0.1.0's own opponent played at a fixed seed,
medium against easy, stopped after 26 plies with the person (dark) to move,
so the board has hints on it. The record is invented.

    demo.py         the game in progress
    demo.py over    a finished one, hard against easy to the end, passes and
                    all, dark winning 43-20 (or DEMO=over, as dev/shots sets it)

A game that was played rather than discs scattered: a board a person who
knows the rules can look at without seeing a lie.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

PLAYING = [19, 34, 45, 20, 26, 11, 12, 37, 18, 17, 25, 21, 29, 4, 5, 3, 2, 38,
           41, 32, 10, 30, 44, 53, 46, 42]
OVER = [19, 34, 41, 33, 44, 37, 26, 18, 17, 12, 11, 8, 38, 20, 29, 45, 4, 39,
        46, 5, 9, 55, 47, 43, 13, 3, 2, 0, 6, 21, 42, 52, 63, 31, 23, 40, 30,
        22, 53, 14, 51, 50, 57, 60, 7, 58, 15, 56, 61, 62, 54, -1, 32, 25, 24,
        16, 48, 49, 59, -1, 10]

over = (len(sys.argv) > 1 and sys.argv[1] == "over") or os.environ.get("DEMO") == "over"
out = Path(os.environ.get("MOARCHY_REVERSI_DIR") or "demo")
out.mkdir(parents=True, exist_ok=True)

game = {
    "schema": 1,
    "game": {
        "mode": "solo",
        "level": "hard" if over else "medium",
        "human": "dark",
        "finished": over,
        "moves": OVER if over else PLAYING,
    },
    "stats": {
        "easy": {"played": 6, "won": 5, "lost": 1, "drawn": 0, "best": 24},
        "medium": {"played": 9, "won": 4, "lost": 5, "drawn": 0, "best": 20},
        "hard": {"played": 4, "won": 1, "lost": 3, "drawn": 0, "best": 8},
    },
}
(out / "reversi.json").write_text(json.dumps(game, indent=1) + "\n", encoding="utf-8")
