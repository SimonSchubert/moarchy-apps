#!/usr/bin/python3
"""Fill a data directory with a game worth photographing.

A figure at its starting position says what the figure is and nothing about the
app: no jumps made, no ring round anything, no result. So this plays a real game
-- with the solver this app ships -- and stops it partway through.

Playing it rather than removing pegs matters for one reason: every screenshot
then shows a board that legal play can actually reach. There are 187 million
positions on the English board and only a fraction of them are reachable, so a
hand-emptied board is very likely one that could not happen, and the app would
be photographed telling a lie about its own rules.

    demo.py          the English board part-played, with jumps left in it
    demo.py stuck    a figure played to a dead end, with the banner up

The record is invented and says so.
"""

from __future__ import annotations

import os
import random
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_pegsolitaire.pegs import CENTRE, Game, figure_for  # noqa: E402
from moarchy_pegsolitaire.solver import solve  # noqa: E402
from moarchy_pegsolitaire.store import Store  # noqa: E402

# How far down the solved line to stop. Far enough that a third of the pegs are
# gone and the cross has holes in it worth looking at; early enough that the
# board still reads as the English board rather than as a handful of pegs.
JUMPS = 11

# (figure, played, best, solved, perfect) -- a plausible record for the page
# that shows one.
RECORD = (
    ("english", 7, 3, 0, 0),
    ("cross", 4, 1, 3, 0),
    ("plus", 3, 1, 2, 2),
    ("pyramid", 2, 2, 0, 0),
)


def main() -> int:
    target = os.environ.get("MOARCHY_PEGSOLITAIRE_DIR")
    if not target:
        print(
            "set MOARCHY_PEGSOLITAIRE_DIR first -- refusing to touch a real game",
            file=sys.stderr,
        )
        return 2

    stage = sys.argv[1] if len(sys.argv) > 1 else "board"
    store = Store(Path(target) / "pegsolitaire.json")

    if stage == "stuck":
        game = _stuck()
    else:
        game = _part_played()

    store.begin(game.figure.key)
    store.remember(game, finished=game.over)
    for key, played, best, solved, perfect in RECORD:
        store.figure = key
        # Written straight rather than through record(), because record() takes
        # one finished game at a time and these are invented histories.
        store.stats[key] = {
            "played": played,
            "best": best,
            "solved": solved,
            "perfect": perfect,
        }
    store.figure = game.figure.key
    store.recorded = game.over
    store.save()

    print(
        f"wrote {len(game.moves)} jumps on the {game.figure.key} figure, "
        f"{game.count} pegs left, to {store.path}"
    )
    return 0


def _part_played() -> Game:
    """The English board, eleven jumps into a line that wins.

    Down a solution rather than down a random walk: a board that is eleven
    jumps from the start and already lost would photograph the app in a state
    its own hint button would call hopeless.
    """
    game = Game("english")
    line = solve(game.position, CENTRE, seconds=30)
    if not line:
        raise SystemExit("the English board would not solve -- check solver.py")
    for move in line[:JUMPS]:
        game.play(move)
    return game


def _stuck() -> Game:
    """A figure played at random until nothing will move.

    Random on purpose. Being stuck is what happens when somebody stops thinking
    about where the last peg has to end up, and a randomly played Pyramid is
    exactly that game.
    """
    rng = random.Random(20260913)
    for _ in range(200):
        game = Game(figure_for("pyramid"))
        while not game.over:
            game.play(rng.choice(game.position.moves()))
        if game.count > 1:
            return game
    raise SystemExit("could not get stuck, which is its own kind of problem")


if __name__ == "__main__":
    raise SystemExit(main())
