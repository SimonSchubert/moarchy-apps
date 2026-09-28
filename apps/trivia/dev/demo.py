#!/usr/bin/python3
"""Write a round and a record worth photographing into MOARCHY_TRIVIA_DIR.

The shots run offline, so the round is written here rather than asked for:
ten geography questions, in the file shape the app keeps, with a record
behind them.

    demo.py          question 4 of 10, answered right (DEMO=quiz, the default)
    demo.py wrong    the same question, answered wrong
    demo.py open     the same question, not answered yet
    demo.py done     the round finished, on the score screen
    demo.py home     no round: the categories

The questions are true; the record is invented.
"""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

mode = (sys.argv[1] if len(sys.argv) > 1 else os.environ.get("DEMO") or "quiz").lower()
out = Path(os.environ.get("MOARCHY_TRIVIA_DIR") or "demo")
out.mkdir(parents=True, exist_ok=True)

GEO = 22


def q(text, answers, correct, difficulty="medium", kind="multiple"):
    return {"text": text, "category": GEO, "difficulty": difficulty, "type": kind,
            "answers": answers, "correct": correct}


questions = [
    q("What is the capital of Canada?", ["Toronto", "Ottawa", "Vancouver", "Montreal"], 1, "easy"),
    q("Which river flows through Budapest?", ["Rhine", "Elbe", "Vistula", "Danube"], 3),
    q("Mount Kilimanjaro is in Kenya.", ["True", "False"], 1, "easy", "boolean"),
    q("Which country has more natural lakes than the rest of the world combined?",
      ["Russia", "Finland", "Canada", "United States"], 2),
    q("What is the smallest sovereign country in South America by area?",
      ["Uruguay", "Suriname", "Guyana", "Paraguay"], 1, "hard"),
    q("The Strait of Gibraltar separates Spain from which country?",
      ["Morocco", "Algeria", "Portugal", "Tunisia"], 0),
    q("Which of these capital cities lies furthest north?",
      ["Oslo", "Helsinki", "Reykjavik", "Tórshavn"], 2, "hard"),
    q("Lake Baikal is the deepest lake in the world.", ["True", "False"], 0, "medium", "boolean"),
    q("In which country is most of the Atacama Desert?", ["Peru", "Chile", "Bolivia", "Argentina"], 1),
    q("What is the capital of Australia?", ["Sydney", "Melbourne", "Canberra", "Perth"], 2, "easy"),
]

now_ms = int(time.time() * 1000)
day = 24 * 3600 * 1000

if mode == "done":
    picks = [1, 3, 1, 2, 0, 0, 0, 0, 1, 2]       # 8 of 10: two wrong
    index = 10
elif mode in ("wrong", "open"):
    picks = [1, 3, 1] + ([0] if mode == "wrong" else [])
    index = 3
else:
    picks = [1, 3, 1, 2]
    index = 3

round_ = None if mode == "home" else {
    "category": GEO, "difficulty": "any", "type": "any",
    "questions": questions, "picks": picks, "index": index,
    "started": now_ms - 180_000, "recorded": mode == "done",
}

recent = [
    {"at": now_ms - 1 * day, "category": 23, "difficulty": "medium", "right": 7, "of": 10},
    {"at": now_ms - 2 * day, "category": 22, "difficulty": "any", "right": 10, "of": 10},
    {"at": now_ms - 2 * day, "category": 18, "difficulty": "hard", "right": 6, "of": 10},
    {"at": now_ms - 4 * day, "category": 0, "difficulty": "any", "right": 12, "of": 15},
    {"at": now_ms - 6 * day, "category": 11, "difficulty": "easy", "right": 4, "of": 5},
    {"at": now_ms - 9 * day, "category": 17, "difficulty": "medium", "right": 5, "of": 10},
]
if mode == "done":
    recent.insert(0, {"at": now_ms, "category": GEO, "difficulty": "any", "right": 8, "of": 10})

book = {
    "schema": 1,
    "pick": {"category": GEO, "difficulty": "any", "type": "any", "amount": 10},
    "token": None,
    "round": round_,
    "stats": {
        "rounds": 31, "answered": 312, "right": 214, "sweeps": 4,
        "streak": 1 if mode == "wrong" else 3, "bestStreak": 17,
        "byDifficulty": {
            "easy": {"answered": 120, "right": 101},
            "medium": {"answered": 128, "right": 85},
            "hard": {"answered": 64, "right": 28},
        },
        "byCategory": {
            "22": {"answered": 90, "right": 68, "rounds": 9, "best": 100},
            "23": {"answered": 60, "right": 39, "rounds": 6, "best": 90},
            "17": {"answered": 50, "right": 31, "rounds": 5, "best": 80},
            "18": {"answered": 40, "right": 30, "rounds": 4, "best": 90},
            "11": {"answered": 30, "right": 19, "rounds": 3, "best": 80},
            "12": {"answered": 22, "right": 13, "rounds": 2, "best": 70},
            "9": {"answered": 20, "right": 14, "rounds": 2, "best": 80},
        },
    },
    "recent": recent,
}
(out / "trivia.json").write_text(json.dumps(book, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
