#!/usr/bin/python3
"""Write a day worth photographing into MOARCHY_FIVELETTERS_DIR.

An untouched board is thirty empty squares and says nothing about the app. So
this writes a day four guesses in, against the word the app will set for the
day the harness pins (MOARCHY_FIVELETTERS_TODAY, 2026-09-12 by default) -- in
the file shape the app reads and the GTK version wrote. The app works the
colours out itself, so the tiles in the picture say what the rules say.

    demo.py          four guesses in, the day still open
    demo.py solved   the same day, got on the fifth
    demo.py lost     six guesses and no word
    (or DEMO=solved / DEMO=lost, as a shot in dev/shots sets it)

The record is invented: somebody who plays every morning and is quite good.
"""

from __future__ import annotations

import json
import os
import re
import sys
from datetime import date
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
LISTS = (HERE / "Lists.js").read_text(encoding="utf-8")


def words(name: str) -> list[str]:
    body = re.search(rf"var {name} = `(.*?)`", LISTS, re.S).group(1)
    return [w for w in body.split() if w]


ANSWERS = words("ANSWERS")
GUESSES = set(words("GUESSES")) | set(ANSWERS)

stamp = os.environ.get("MOARCHY_FIVELETTERS_TODAY") or "2026-09-12"
day = date.fromisoformat(stamp)
# Words.js's arithmetic, and words.py's before it.
secret = ANSWERS[(day.toordinal() * 1103515245 + 12345) % len(ANSWERS)]

kind = (sys.argv[1] if len(sys.argv) > 1 else "") or os.environ.get("DEMO", "")
openers = [w for w in ("CRANE", "SLOTH", "PUDGY", "BEFIT", "WHOMP", "GAMUT", "VIXEN", "JOKER",
                       "DUCKY", "BLIMP", "FJORD", "GLYPH")
           if w != secret and w in GUESSES]
guesses = openers[:6] if kind == "lost" else openers[:4]
if kind == "solved":
    guesses.append(secret)

spread = [1, 9, 31, 44, 22, 7]
game = {
    "schema": 1,
    "mode": "daily",
    "daily": {"day": stamp, "guesses": guesses},
    "practice": {"seed": 4242, "guesses": []},
    "stats": {
        "played": 121 + (1 if kind in ("solved", "lost") else 0),
        "won": sum(spread) + (1 if kind == "solved" else 0),
        "streak": 13 if kind == "solved" else 0 if kind == "lost" else 12,
        "best": 34,
        "spread": [s + (1 if kind == "solved" and i == 4 else 0) for i, s in enumerate(spread)],
        "last": stamp if kind in ("solved", "lost") else "2026-09-11",
    },
}

out = Path(os.environ.get("MOARCHY_FIVELETTERS_DIR") or "demo")
out.mkdir(parents=True, exist_ok=True)
(out / "fiveletters.json").write_text(json.dumps(game, indent=1) + "\n", encoding="utf-8")
