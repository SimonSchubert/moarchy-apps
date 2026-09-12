#!/usr/bin/python3
"""Write a set of notes to look at.

Screenshots and hand-testing both need an app with something in it, and an
empty grid is the one state that photographs badly. This writes into
MOARCHY_KEEP_DIR, never into the real notes.

  MOARCHY_KEEP_DIR=/tmp/keep ./scripts/demo-notes.py
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from moarchy_keep.notes import LIST, TEXT, Item, Note, Store

NOW = time.time()
MINUTE = 60


def note(kind, title, colour, pinned, age, body="", items=()):
    return Note(
        kind=kind,
        title=title,
        body=body,
        items=[Item(text=t, done=d) for t, d in items],
        colour=colour,
        pinned=pinned,
        created=NOW - age * MINUTE,
        edited=NOW - age * MINUTE,
    )


NOTES = [
    note(
        LIST,
        "Shopping",
        "sand",
        True,
        4,
        items=[
            ("Oat milk", False),
            ("Coffee, the dark one", False),
            ("Tomatoes", False),
            ("Bread", True),
            ("Washing up liquid", True),
        ],
    ),
    note(
        TEXT,
        "PinePhone battery",
        "coral",
        True,
        40,
        body="Idle drain is 4%/h with the modem up and 1.5%/h with it down. "
        "Suspend needs the kernel from linux-pinephone, not the stock one.",
    ),
    note(TEXT, "", "default", False, 55, body="Ring the dentist back before Thursday"),
    note(
        LIST,
        "Trip",
        "mint",
        False,
        90,
        items=[
            ("Charger + USB-C cable", True),
            ("SD card reader", False),
            ("Offline maps for Lisbon", False),
            ("Passport", True),
        ],
    ),
    note(
        TEXT,
        "Sourdough",
        "peach",
        False,
        260,
        body="100g starter, 350g water, 500g flour, 10g salt.\n\n"
        "Autolyse an hour, four folds at 30 minute intervals, "
        "bulk until it has grown by half. Cold retard overnight.",
    ),
    note(
        TEXT,
        "Sway keybinds worth remembering",
        "fog",
        False,
        700,
        body="Super+Space  drawer\nSuper+K       keyboard\n"
        "Super+Shift+Q close\nSuper+1..9    workspace",
    ),
    note(
        LIST,
        "Before the release",
        "dusk",
        False,
        1500,
        items=[
            ("Bump pkgver", False),
            ("Regenerate screenshots", False),
            ("Check it on a cold boot", False),
        ],
    ),
    note(
        TEXT,
        "",
        "sage",
        False,
        2400,
        body="“The best way to predict the future is to invent it.”",
    ),
    note(
        TEXT,
        "Bike service",
        "clay",
        False,
        4000,
        body="Rear brake pads, gear cable, and the headset is notchy.",
    ),
]


def main() -> int:
    store = Store()
    store.notes = NOTES
    store.save()
    print(f"{len(NOTES)} notes -> {store.path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
