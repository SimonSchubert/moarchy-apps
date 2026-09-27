#!/usr/bin/python3
"""Write a game worth photographing into MOARCHY_CHESS_DIR.

The opening position says nothing about the app: nothing taken, no piece worth
picking up, no check and no history. So this is a real game -- 0.1.0's own
opponent played it, Medium against Easy from a fixed seed, and it stopped
twenty-two plies in with the person (White) to move -- written in the file
shape the app reads and the GTK version wrote. Played rather than arranged,
because somebody who knows the game will see a board legal play cannot reach.

    demo.py         the game in progress, White to move
    demo.py mate    a short game the person has won (the scholar's mate)

or DEMO=mate, as a shot in dev/shots sets it. The record is invented.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

GAME = (
    "b1c3 g7g5 d2d4 g5g4 e2e4 b8c6 d4d5 c6e5 c1f4 e5g6 d1g4 "
    "g6f4 g4f4 e7e5 f4e5 g8e7 e5h8 e7d5 c3d5 b7b6 h8e5 f8e7"
).split()
MATE = "e2e4 e7e5 f1c4 b8c6 d1h5 g8f6 h5f7".split()

STATS = {
    "easy": {"played": 7, "won": 6, "lost": 1, "drawn": 0, "quickest": 19},
    "medium": {"played": 10, "won": 4, "lost": 6, "drawn": 0, "quickest": 28},
    "hard": {"played": 5, "won": 1, "lost": 4, "drawn": 0, "quickest": 41},
}


def main() -> int:
    target = os.environ.get("MOARCHY_CHESS_DIR")
    if not target:
        print("set MOARCHY_CHESS_DIR first -- refusing to touch a real game", file=sys.stderr)
        return 2
    mate = (len(sys.argv) > 1 and sys.argv[1] == "mate") or os.environ.get("DEMO") == "mate"
    payload = {
        "schema": 1,
        "game": {
            "mode": "solo",
            "level": "medium",
            "human": "white",
            # A finished game's result went into the record when it finished.
            "finished": mate,
            "moves": MATE if mate else GAME,
        },
        "stats": STATS,
    }
    out = Path(target)
    out.mkdir(parents=True, exist_ok=True)
    (out / "chess.json").write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
