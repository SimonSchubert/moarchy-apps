#!/usr/bin/python3
"""Fill a data directory with a game worth photographing.

An empty board is four discs in the middle and says nothing about the app: no
hints worth seeing, no score to read, nothing turned over. So this plays a real
game -- the same search the app ships, at two different levels, with a fixed
seed -- and stops it partway through with the person to move.

Playing it rather than scattering discs matters for one reason: every screenshot
then shows a position that legal play can actually reach. A hand-placed board
photographs the app telling a lie about its own rules, and someone who knows the
game will see it.

The record is invented and says so.
"""

from __future__ import annotations

import os
import random
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_reversi import ai  # noqa: E402
from moarchy_reversi.reversi import DARK, Game  # noqa: E402
from moarchy_reversi.store import LOST, SOLO, WON, Store  # noqa: E402

# Far enough in that both sides hold corners-worth of board and the counts are
# interesting, early enough that there is plenty left to play.
PLIES = 26

# (level, played, won, lost) -- a plausible record for the page that shows one.
RECORD = (("easy", 6, 5, 1), ("medium", 9, 4, 5), ("hard", 4, 1, 3))


def main() -> int:
    target = os.environ.get("MOARCHY_REVERSI_DIR")
    if not target:
        print(
            "set MOARCHY_REVERSI_DIR first -- refusing to touch a real game",
            file=sys.stderr,
        )
        return 2

    rng = random.Random(20260912)
    store = Store(Path(target) / "reversi.json")
    game = Game()
    # The person plays dark and moves first, so an even number of plies leaves
    # the board waiting for them -- which is the state with hints on it.
    sides = (ai.level_for("medium"), ai.level_for("easy"))
    while len(game.moves) < PLIES and not game.over:
        game.play(ai.choose(game.position, sides[game.turn], rng=rng))
    while game.turn != DARK and not game.over:
        game.play(ai.choose(game.position, sides[game.turn], rng=rng))

    store.begin(mode=SOLO, level="medium", human=DARK)
    store.remember(game, finished=game.over)
    for level, played, won, lost in RECORD:
        store.level = level
        for index in range(played):
            if index < won:
                store.record(WON, 8 + index * 4)
            elif index < won + lost:
                store.record(LOST)
    store.level = "medium"
    store.save()

    dark, light = game.position.counts()
    print(f"wrote {len(game.moves)} moves ({dark}-{light}) to {store.path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
