#!/usr/bin/python3
"""Fill a data directory with a game worth photographing.

The opening position says nothing about the app: nothing taken, no piece worth
picking up, no check and no history. So this plays a real game -- the same
search the app ships, at two different levels, with a fixed seed -- and stops it
partway through with the person to move.

Playing it rather than arranging pieces matters for one reason: every screenshot
then shows a position that legal play can actually reach. A hand-placed board
photographs the app telling a lie about its own rules, and somebody who knows
the game will see it. It matters more in chess than it did in Reversi, because
far more people will look at the picture and know.

The record is invented and says so.
"""

from __future__ import annotations

import os
import random
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_chess import ai  # noqa: E402
from moarchy_chess.chess import WHITE, Game  # noqa: E402
from moarchy_chess.store import LOST, SOLO, WON, Store  # noqa: E402

# Far enough in that pieces have been taken and the board has a shape, early
# enough that there is a whole game left to play.
PLIES = 22

# (level, played, won, lost) -- a plausible record for the page that shows one.
RECORD = (("easy", 7, 6, 1), ("medium", 11, 4, 6), ("hard", 5, 1, 4))
QUICKEST = {"easy": 19, "medium": 28, "hard": 41}


def main() -> int:
    target = os.environ.get("MOARCHY_CHESS_DIR")
    if not target:
        print(
            "set MOARCHY_CHESS_DIR first -- refusing to touch a real game",
            file=sys.stderr,
        )
        return 2

    rng = random.Random(20260912)
    store = Store(Path(target) / "chess.json")
    game = Game()
    # The person plays White and moves first, so an even number of plies leaves
    # the board waiting for them -- which is the state a piece can be picked up
    # in.
    sides = (ai.level_for("medium"), ai.level_for("easy"))
    while len(game.moves) < PLIES and not game.over:
        game.play(ai.choose(game.position, sides[game.turn], rng=rng))
    while game.turn != WHITE and not game.over:
        game.play(ai.choose(game.position, sides[game.turn], rng=rng))

    store.begin(mode=SOLO, level="medium", human=WHITE)
    store.remember(game, finished=game.over)
    for level, played, won, lost in RECORD:
        store.level = level
        for index in range(played):
            if index < won:
                store.record(WON, QUICKEST[level] + index * 3)
            elif index < won + lost:
                store.record(LOST)
    store.level = "medium"
    store.save()

    print(f"wrote {len(game.moves)} moves to {store.path}")
    print(f"  {' '.join(game.uci())}")
    print(f"  {game.position.fen()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
