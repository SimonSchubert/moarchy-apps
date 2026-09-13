#!/usr/bin/python3
"""Fill a data directory with a game worth photographing.

A fresh board is a rectangle of identical grey squares and says nothing about
the app: no numbers, no flags, no flood. So this plays a real one -- with the
rules this app ships, opening only cells it can prove are safe -- and stops it
partway through.

Playing it rather than opening cells at random matters for one reason: every
screenshot then shows a board that legal play can actually reach, with the
numbers that the mines under it actually produce. A hand-drawn field is the app
telling a lie about its own arithmetic, and anybody who counts will see it.

    demo.py          a board half opened, with flags on it
    demo.py lost     the same board with a mine gone off and a flag wrong
    demo.py won      the same board cleared

The record is invented and says so.
"""

from __future__ import annotations

import os
import random
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_minesweeper.minesweeper import Game, index, level_for  # noqa: E402
from moarchy_minesweeper.store import Store  # noqa: E402

LEVEL = "standard"
SEED = 20260913
# Where the first tap goes. Middle-ish, so the flood opens the centre of the
# board and leaves work round the edges -- which is the shape of a real game.
FIRST = (6, 4)

# How much of the board to clear before stopping, and how many of the mines it
# has worked out to flag. Both short of the end: a finished board has nothing
# left to look at.
SHARE = 0.62
FLAGS = 7

# How long the invented game has been going, in seconds, and the record behind
# it. Times that look like somebody playing rather than somebody testing.
SECONDS = 97
RECORD = (("gentle", 22, 19, 41), ("standard", 31, 18, 143), ("hard", 9, 2, 402))


def _safe_game(stage: str) -> Game:
    """Open cells that are provably safe, then stop.

    Not a solver: it opens what the demo knows is safe because the demo can see
    the mines, which is cheating in a way that shows up nowhere -- the board in
    the picture is one a good player could have reached, and nothing about it
    says how it was reached.
    """
    level = level_for(LEVEL)
    game = Game(level, SEED)
    game.tap(index(FIRST[0], FIRST[1], level.width))
    rng = random.Random(SEED)

    wanted = int((level.cells - level.mines) * SHARE)
    safe = [c for c in range(level.cells) if not game.is_mine(c)]
    rng.shuffle(safe)
    for cell in safe:
        if len(game.opened) >= wanted:
            break
        # Only next to something already open, so the picture is one connected
        # worked-out region rather than a scatter of lucky taps.
        if any(n in game.opened for n in game.field.neighbours(cell)):
            game.tap(cell)

    known = [c for c in sorted(game.field.mines) if _touches_open(game, c)]
    for cell in known[:FLAGS]:
        game.mark(cell)

    if stage == "lost":
        # A flag in the wrong place first, so the finished board has something
        # to say beyond "a mine went off".
        for cell in range(level.cells):
            if (
                cell not in game.opened
                and cell not in game.flags
                and not game.is_mine(cell)
            ):
                game.mark(cell)
                break
        game.tap(next(c for c in sorted(game.field.mines) if c not in game.flags))
    elif stage == "won":
        for cell in range(level.cells):
            if not game.is_mine(cell) and cell not in game.opened:
                game.tap(cell)
    return game


def _touches_open(game: Game, cell: int) -> bool:
    return any(near in game.opened for near in game.field.neighbours(cell))


def main() -> int:
    target = os.environ.get("MOARCHY_MINESWEEPER_DIR")
    if not target:
        print(
            "set MOARCHY_MINESWEEPER_DIR first -- refusing to touch a real game",
            file=sys.stderr,
        )
        return 2

    stage = sys.argv[1] if len(sys.argv) > 1 else "board"
    store = Store(Path(target) / "minesweeper.json")
    game = _safe_game(stage)

    store.begin(LEVEL, seed=SEED)
    store.remember(game, finished=game.over)
    store.seconds = SECONDS
    for key, played, won, best in RECORD:
        store.stats[key] = {
            "played": played,
            "won": won,
            "best": best,
            "streak": 2,
            "longest": 5,
        }
    store.recorded = game.over
    store.save()

    print(
        f"wrote {len(game.moves)} taps, {len(game.opened)} cells open, "
        f"{len(game.flags)} flags to {store.path}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
