#!/usr/bin/python3
"""Fill a data directory with habits that have a history.

An empty habit tracker photographs as an empty list, which says nothing about
what the app is. The screenshots need a grid with marks in it, and a streak
worth showing -- so this generates a plausible few weeks rather than a perfect
one: a habit nobody keeps every day is the normal case, and a heatmap with no
gaps in it is the one that looks fake.

The pattern is deterministic, seeded, and entirely invented. It is demo data
and says so.
"""

from __future__ import annotations

import os
import random
import sys
from datetime import timedelta
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_habits.habits import MEASURABLE, Store, today  # noqa: E402

# (name, question, colour, kind, target, unit, freq, how reliably it is kept)
DEMO = [
    ("Read", "Did you read today?", "green", None, 1, "", (1, 1), 0.86),
    ("Exercise", "", "orange", None, 1, "", (3, 7), 0.52),
    ("Water", "", "cyan", MEASURABLE, 8, "glasses", (1, 1), 0.74),
    ("Practice guitar", "Twenty minutes?", "magenta", None, 1, "", (5, 7), 0.61),
    ("No phone in bed", "", "blue", None, 1, "", (1, 1), 0.68),
]

DAYS = 120


def main() -> int:
    target = os.environ.get("MOARCHY_HABITS_DIR")
    if not target:
        print(
            "set MOARCHY_HABITS_DIR first -- refusing to touch real habits",
            file=sys.stderr,
        )
        return 2

    rng = random.Random(20260912)
    store = Store(Path(target) / "habits.json")
    now = today()

    for name, question, colour, kind, goal, unit, freq, keep in DEMO:
        habit = store.create(
            name,
            question=question,
            colour=colour,
            kind=kind or "boolean",
            target=float(goal),
            unit=unit,
            freq_num=freq[0],
            freq_den=freq[1],
        )
        for back in range(DAYS):
            day = now - timedelta(days=back)
            # Recent days are kept a little more often than old ones, so the
            # strength score has somewhere to have come from.
            odds = keep * (1.0 - back / (DAYS * 3))
            if rng.random() > odds:
                continue
            if kind == MEASURABLE:
                habit.set_value(day, rng.choice([goal, goal, goal, goal - 2, goal - 4]))
            else:
                habit.set_value(day, 1)

    store.save()
    print(f"wrote {len(store.habits)} habits to {store.path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
