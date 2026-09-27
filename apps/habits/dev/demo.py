#!/usr/bin/python3
"""Fill MOARCHY_HABITS_DIR with habits that have a history.

An empty habit tracker photographs as an empty list. The screenshots need a
grid with marks in it and a streak worth showing -- so this writes a
plausible few months rather than a perfect one: a habit nobody keeps every
day is the normal case, and a heatmap with no gaps in it is the one that
looks fake. Written in the file shape the app reads and the GTK version
wrote; the achievements are left for the app to credit on first read.

Seeded and entirely invented. MOARCHY_HABITS_TODAY pins "today", as the app
reads it too.
"""

from __future__ import annotations

import json
import os
import random
import sys
import time
from datetime import date, timedelta
from pathlib import Path

# (name, question, colour, kind, target, unit, (freq_num, freq_den), how reliably kept)
DEMO = [
    ("Read", "Did you read today?", "green", "boolean", 1, "", (1, 1), 0.86),
    ("Exercise", "", "orange", "boolean", 1, "", (3, 7), 0.52),
    ("Water", "", "cyan", "measurable", 8, "glasses", (1, 1), 0.74),
    ("Practice guitar", "Twenty minutes?", "magenta", "boolean", 1, "", (5, 7), 0.61),
    ("No phone in bed", "", "blue", "boolean", 1, "", (1, 1), 0.68),
]
DAYS = 120


def main() -> int:
    target = os.environ.get("MOARCHY_HABITS_DIR")
    if not target:
        print("set MOARCHY_HABITS_DIR first -- refusing to touch real habits", file=sys.stderr)
        return 2
    stamp = os.environ.get("MOARCHY_HABITS_TODAY")
    now = date.fromisoformat(stamp) if stamp else date.today()
    rng = random.Random(20260912)

    habits = []
    for index, (name, question, colour, kind, goal, unit, freq, keep) in enumerate(DEMO):
        entries: dict[str, float] = {}
        for back in range(DAYS):
            day = now - timedelta(days=back)
            # Recent days are kept a little more often than old ones, so the
            # strength score has somewhere to have come from.
            if rng.random() > keep * (1.0 - back / (DAYS * 3)):
                continue
            if kind == "measurable":
                entries[day.isoformat()] = float(rng.choice([goal, goal, goal, goal - 2, goal - 4]))
            else:
                entries[day.isoformat()] = 1.0
        habits.append({
            "id": f"demo{index:028d}",
            "name": name,
            "question": question,
            "kind": kind,
            "target": float(goal),
            "unit": unit,
            "colour": colour,
            "freq_num": freq[0],
            "freq_den": freq[1],
            "created": time.mktime((now - timedelta(days=DAYS)).timetuple()),
            "archived": False,
            "entries": dict(sorted(entries.items())),
        })

    out = Path(target)
    out.mkdir(parents=True, exist_ok=True)
    payload = {"schema": 2, "habits": habits, "meta": {"achievements": {}}}
    (out / "habits.json").write_text(json.dumps(payload, indent=1) + "\n", encoding="utf-8")
    print(f"wrote {len(habits)} habits to {out / 'habits.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
