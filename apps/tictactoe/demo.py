#!/usr/bin/python3
"""Fill a data directory with a game worth photographing.

An empty board is four rules and nothing else, and says nothing about the app.
So this plays a real one -- the opponent this app ships, at a fixed seed -- and
stops it partway through with the person to move.

Playing it rather than placing marks matters for one reason: every screenshot
then shows a position that legal play can actually reach. A hand-placed board
photographs the app telling a lie about its own rules, and in a game this small
everybody who looks at it knows the rules.

    demo.py         a game in progress, the person to move
    demo.py won     the same series, one game later, won and struck through

Two stages rather than one because the strike through three in a row is the one
thing this app draws that a board in progress cannot show, and the screenshot
harness re-seeds between shots rather than the app inventing a finished game.

The series score and the record are invented and say so.
"""

from __future__ import annotations

import os
import random
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_tictactoe import ai  # noqa: E402
from moarchy_tictactoe.store import DRAWN, LOST, SOLO, WON, Store  # noqa: E402
from moarchy_tictactoe.tictactoe import CROSS, Game  # noqa: E402

# Far enough in that both marks are on the board and there is something to read,
# early enough that nothing is decided and every square still matters. Even, so
# that X -- the seat the person is in -- is the one on move: an odd number leaves
# the computer to play, and the app answers it half a second after the window
# opens, which photographs as a board with one more mark than the demo wrote.
PLIES = 4

# The sitting so far: seat A has won two, the computer one, and one was drawn.
# The finished stage counts one more for A, because the result of the game on
# the screen has already gone into the score by the time it is on the screen --
# a won board over a score that has not moved is the app failing to count.
SERIES = {"a": 2, "b": 1, DRAWN: 1}
SERIES_WON = {"a": 3, "b": 1, DRAWN: 1}

# (level, played, won, lost) -- a plausible record for the page that shows one.
# Perfect has no wins in it, because there are none to be had.
RECORD = (("easy", 14, 12, 1), ("fair", 21, 9, 4), ("perfect", 11, 0, 2))


def _game_in_progress(rng: random.Random) -> Game:
    """A few marks down, seat A -- playing X, moving first -- to move again."""
    game = Game()
    level = ai.level_for("fair")
    while len(game.moves) < PLIES and not game.over:
        game.play(ai.choose(game.position, level, rng))
    return game


def _game_won(rng: random.Random) -> Game:
    """A finished game that the person won, for the strike-through.

    Fair against a careless X, replayed until X takes one. It is a real game
    every time -- the seed only decides which one.
    """
    fair = ai.level_for("fair")
    easy = ai.level_for("easy")
    for _ in range(500):
        game = Game()
        while not game.over:
            level = easy if game.turn == CROSS else fair
            game.play(ai.choose(game.position, level, rng))
        if game.position.winner() == CROSS:
            return game
    raise SystemExit("could not find a game X wins -- check ai.choose")


def main() -> int:
    target = os.environ.get("MOARCHY_TICTACTOE_DIR")
    if not target:
        print(
            "set MOARCHY_TICTACTOE_DIR first -- refusing to touch a real game",
            file=sys.stderr,
        )
        return 2

    stage = sys.argv[1] if len(sys.argv) > 1 else "board"
    rng = random.Random(20260913)
    store = Store(Path(target) / "tictactoe.json")

    game = _game_won(rng) if stage == "won" else _game_in_progress(rng)

    # Seat A holds X, which is the seat the person is sitting in and the mark
    # that moves first. A rematch would swap it; this is the first game of the
    # series as far as the file is concerned, with an invented score above it.
    store.begin(mode=SOLO, level="fair", mark=CROSS)
    store.remember(game, finished=game.over)
    series = SERIES_WON if stage == "won" else SERIES
    store.series = dict(series)
    for level, played, won, lost in RECORD:
        store.level = level
        for index in range(played):
            store.record(WON if index < won else LOST if index < won + lost else DRAWN)
    store.level = "fair"
    # The invented record wrote through the series as well, because one call
    # does both -- and it left `recorded` set, which is what a finished board
    # wants: the result on the screen is already in the score above it, so the
    # app must not count it a second time on the way in.
    store.series = dict(series)
    store.save()

    marks = game.position.played()
    winner = game.position.winner()
    result = "in progress" if winner is None and not game.over else "finished"
    print(f"wrote {marks} marks ({result}) to {store.path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
