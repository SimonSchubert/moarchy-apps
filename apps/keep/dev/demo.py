#!/usr/bin/python3
"""Write a set of notes to look at, into MOARCHY_KEEP_DIR.

Screenshots and hand-testing both need an app with something in it, and an
empty grid is the one state that photographs badly. This writes the file the
app reads -- the shape the GTK version wrote -- and never the real notes.

    MOARCHY_KEEP_DIR=$(mktemp -d) python3 apps/keep/dev/demo.py
"""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

NOW = time.time()
MINUTE = 60


def note(n, kind, title, colour, pinned, age, body="", items=()):
    data = {
        "id": f"demo{n:08x}",
        "kind": kind,
        "title": title,
        "colour": colour,
        "pinned": pinned,
        "created": round(NOW - age * MINUTE, 3),
        "edited": round(NOW - age * MINUTE, 3),
    }
    if kind == "list":
        data["items"] = [{"text": t, "done": d} for t, d in items]
    else:
        data["body"] = body
    return data


NOTES = [
    note(1, "list", "Shopping", "sand", True, 4, items=[
        ("Oat milk", False), ("Coffee, the dark one", False), ("Tomatoes", False),
        ("Bread", True), ("Washing up liquid", True),
    ]),
    note(2, "text", "PinePhone battery", "coral", True, 40,
         body="Idle drain is 4%/h with the modem up and 1.5%/h with it down. "
         "Suspend needs the kernel from linux-pinephone, not the stock one."),
    note(3, "text", "", "default", False, 55, body="Ring the dentist back before Thursday"),
    note(4, "list", "Trip", "mint", False, 90, items=[
        ("Charger + USB-C cable", True), ("SD card reader", False),
        ("Offline maps for Lisbon", False), ("Passport", True),
    ]),
    note(5, "text", "Sourdough", "peach", False, 260,
         body="100g starter, 350g water, 500g flour, 10g salt.\n\n"
         "Autolyse an hour, four folds at 30 minute intervals, "
         "bulk until it has grown by half. Cold retard overnight."),
    note(6, "text", "Hyprland keybinds worth remembering", "fog", False, 700,
         body="Super+Space  launcher\nSuper+K       keyboard\n"
         "Super+W       close\nSuper+1..9    workspace"),
    note(7, "list", "Before the release", "dusk", False, 1500, items=[
        ("Bump pkgver", False), ("Regenerate screenshots", False),
        ("Check it on a cold boot", False),
    ]),
    note(8, "text", "", "sage", False, 2400,
         body="“The best way to predict the future is to invent it.”"),
    note(9, "text", "Bike service", "clay", False, 4000,
         body="Rear brake pads, gear cable, and the headset is notchy."),
]


def main() -> int:
    target = os.environ.get("MOARCHY_KEEP_DIR")
    if not target:
        print("set MOARCHY_KEEP_DIR: this writes a fixture, not your notes", file=sys.stderr)
        return 1
    out = Path(target)
    out.mkdir(parents=True, exist_ok=True)
    payload = {"schema": 1, "view": "grid", "notes": NOTES}
    (out / "notes.json").write_text(json.dumps(payload, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"{len(NOTES)} notes -> {out / 'notes.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
