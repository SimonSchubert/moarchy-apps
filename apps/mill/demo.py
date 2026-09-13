#!/usr/bin/python3
"""Fill a data directory with a game worth photographing.

An empty Morris board is three squares and nothing else, and says nothing about
the app: no pieces, no mills, no rings. So this plays a real one -- the search
this app ships, at two different levels, with a fixed seed -- and stops it
partway through with the person to move.

Playing it rather than scattering pieces matters for one reason: every
screenshot then shows a position that legal play can actually reach. A
hand-placed board photographs the app telling a lie about its own rules, and in
this game the lie would be visible -- a side with six pieces and none in hand
has had three taken, and a board that does not add up says so.

    demo.py         the middle game, pieces all placed, you to move
    demo.py take    a mill just closed, with the pieces you may take ringed

The record is invented and says so.
"""

from __future__ import annotations

import os
import random
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_mill import ai  # noqa: E402
from moarchy_mill.mill import WHITE, Game  # noqa: E402
from moarchy_mill.store import LOST, SOLO, WON, Store  # noqa: E402

# (level, played, won, lost) -- a plausible record for the page that shows one.
RECORD = (("easy", 8, 7, 1), ("medium", 14, 6, 7), ("hard", 5, 1, 4))

# Far enough that everything is placed and pieces have been taken; early enough
# that both sides still have a game.
TARGET = 26


def _play_to(stage: str) -> Game:
    """A real game, stopped where the screenshot wants it.

    Both sides are played by the search, at levels a shade apart, so that the
    position is one two competent players could have reached rather than one a
    random walk produced. The clocks are turned right down: this runs in a
    container during a screenshot pass, and a demo that thinks for two seconds a
    move takes a minute to set up one picture.
    """
    rng = random.Random(20260913)
    quick = [
        ai.Level(lv.key, lv.label, lv.blurb, 0.05, 4, lv.slack) for lv in ai.LEVELS
    ]
    sides = {WHITE: quick[1], 1: quick[0]}
    game = Game()
    while not game.over:
        position = game.position
        if stage == "take":
            if position.removing and position.turn == WHITE:
                return game
        elif (
            len(game.moves) >= TARGET
            and position.turn == WHITE
            and not position.removing
            and not any(position.placing(colour) for colour in (0, 1))
        ):
            return game
        game.play(ai.choose(position, sides[position.turn], rng))
    return game


def main() -> int:
    target = os.environ.get("MOARCHY_MILL_DIR")
    if not target:
        print(
            "set MOARCHY_MILL_DIR first -- refusing to touch a real game",
            file=sys.stderr,
        )
        return 2

    stage = sys.argv[1] if len(sys.argv) > 1 else "board"
    store = Store(Path(target) / "mill.json")
    game = _play_to(stage)

    store.begin(mode=SOLO, level="medium", human=WHITE)
    store.remember(game, finished=game.over)
    for level, played, won, lost in RECORD:
        store.level = level
        for index in range(played):
            if index < won:
                store.record(WON, 4 + index % 4)
            elif index < won + lost:
                store.record(LOST)
    store.level = "medium"
    store.recorded = game.over
    store.save()

    position = game.position
    print(
        f"wrote {len(game.moves)} moves (white {position.count(0)}, "
        f"black {position.count(1)}) to {store.path}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
