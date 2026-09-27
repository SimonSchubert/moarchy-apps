#!/usr/bin/python3
"""Write a board worth photographing into MOARCHY_MINESWEEPER_DIR.

An unopened board is a grid of lids. So this plays one: the first tap in the
middle, then a flag on every mine that touches an opened number, then one
number cleared round -- in the file shape the app reads and the GTK version
wrote, a seed and the taps.

    demo.py        a game in progress, flags down
    demo.py won    every safe cell opened
    demo.py lost   a mine opened, with one flag wrong
    (or DEMO=won / DEMO=lost, as a shot in dev/shots sets it)

The mines are laid the way Minesweeper.js lays them, which is the way the GTK
version did: Python's own random.Random(seed).random(), a Fisher-Yates written
out on top of it, and nothing within one cell of the first tap. The record is
invented.
"""

from __future__ import annotations

import json
import os
import random
import sys
from pathlib import Path

WIDTH, HEIGHT, MINES = 10, 13, 22  # "standard"
SEED = 20260927
OPEN, FLAG, CHORD = 0, 1, 2

mode = (sys.argv[1] if len(sys.argv) > 1 else os.environ.get("DEMO", "")).strip()
out = Path(os.environ.get("MOARCHY_MINESWEEPER_DIR") or "demo")
out.mkdir(parents=True, exist_ok=True)


def around(cell: int) -> list[int]:
    r, c = divmod(cell, WIDTH)
    return [
        (r + dr) * WIDTH + (c + dc)
        for dr in (-1, 0, 1)
        for dc in (-1, 0, 1)
        if (dr or dc) and 0 <= r + dr < HEIGHT and 0 <= c + dc < WIDTH
    ]


def place(first: int) -> set[int]:
    forbidden = {first, *around(first)}
    available = [c for c in range(WIDTH * HEIGHT) if c not in forbidden]
    rng = random.Random(SEED)
    for at in range(len(available) - 1, 0, -1):
        swap = int(rng.random() * (at + 1))
        available[at], available[swap] = available[swap], available[at]
    return set(available[:MINES])


first = (HEIGHT // 2) * WIDTH + WIDTH // 2
mines = place(first)


def count(cell: int) -> int:
    return sum(1 for n in around(cell) if n in mines)


def flood(start: int, opened: set[int], flags: set[int]) -> None:
    stack = [start]
    while stack:
        here = stack.pop()
        if here in opened or here in flags:
            continue
        opened.add(here)
        if count(here) == 0:
            stack.extend(n for n in around(here) if n not in opened)


moves = [first * 3 + OPEN]
opened: set[int] = set()
flags: set[int] = set()
flood(first, opened, flags)

if mode == "won":
    for cell in range(WIDTH * HEIGHT):
        if cell not in mines and cell not in opened:
            moves.append(cell * 3 + OPEN)
            flood(cell, opened, flags)
else:
    # Every mine that an opened number already gives away, flagged.
    for cell in sorted(opened):
        for n in around(cell):
            if n in mines and n not in flags:
                flags.add(n)
                moves.append(n * 3 + FLAG)
    # One number cleared round, the move that makes this game quick.
    for cell in sorted(opened):
        wanted = count(cell)
        near = around(cell)
        shut = [n for n in near if n not in opened and n not in flags]
        if wanted and sum(1 for n in near if n in flags) == wanted and shut:
            moves.append(cell * 3 + CHORD)
            for n in shut:
                flood(n, opened, flags)
            break
    if mode == "lost":
        wrong = next(c for c in range(WIDTH * HEIGHT) if c not in mines and c not in opened and c not in flags)
        moves.append(wrong * 3 + FLAG)
        boom = next(c for c in sorted(mines) if c not in flags)
        moves.append(boom * 3 + OPEN)

finished = mode in ("won", "lost")
data = {
    "schema": 1,
    "game": {
        "level": "standard",
        "seed": SEED,
        "seconds": 83 if mode == "won" else 47,
        "finished": finished,
        "recorded": finished,
        "moves": moves,
    },
    "stats": {
        "gentle": {"played": 14, "won": 11, "best": 38, "streak": 4, "longest": 6},
        "standard": {"played": 23, "won": 12, "best": 97, "streak": 1, "longest": 4},
        "hard": {"played": 6, "won": 1, "best": 412, "streak": 0, "longest": 1},
    },
}
(out / "minesweeper.json").write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")
