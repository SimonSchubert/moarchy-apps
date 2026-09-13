#!/usr/bin/python3
"""Fill a data directory with a game worth photographing.

A fresh deal is seven columns of face-down cards and says almost nothing about
the app: no foundations started, nothing picked up, no banner. So this plays a
real one -- with the rules this app ships, choosing the move a person would
obviously choose -- and stops it partway through.

Playing it rather than placing cards matters for one reason: every screenshot
then shows a table that legal play can actually reach. A hand-dealt table
photographs the app telling a lie about its own rules, and in a game everybody's
grandmother knows, everybody who looks at it will see.

    demo.py          a game in progress, four foundations started
    demo.py home     the same deal, nothing face down, the banner up

The record is invented and says so.
"""

from __future__ import annotations

import os
import random
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_solitaire.klondike import (  # noqa: E402
    RED,
    STOCK,
    WASTE,
    Game,
    Move,
    Table,
    is_foundation,
    rank,
    shuffled,
    suit,
)
from moarchy_solitaire.store import LOST, WON, Store  # noqa: E402

# (draw, played, won) -- a plausible record for the page that shows one.
RECORD = ((1, 38, 26), (3, 17, 4))

# How far in to stop. Far enough that the foundations have something on them and
# half the face-down cards are gone; not so far that the table is decided.
TARGET_HOME = 6


def _safe_home(table: Table, card: int) -> bool:
    """Is sending this card home a move you will not want back?

    The rule every book gives: a card is safe once both foundations of the other
    colour have reached one rank below it, because nothing left on the table can
    still need it to build on. Sending everything home the moment it will go is
    the classic way to lose a winnable deal, and a demo that played that way
    would need a lot more seeds.
    """
    others = [index for index in range(4) if (index in RED) != (suit(card) in RED)]
    return rank(card) <= min(table.up[index] for index in others) + 1


def _prefer(game: Game, rng: random.Random) -> Move | None:
    """The move a decent player would make, or None if there is none.

    Not a solver -- a solver good enough to say whether a deal is winnable is a
    much bigger program than this app. It is the order of preference a book
    gives: turn a card over, take the free aces, build from the waste, use an
    empty column for something that uncovers, send home only what is safe, and
    turn the stock over when there is nothing else.
    """
    table = game.table
    moves = [m for m in table.moves() if m.src != STOCK and m.dst != STOCK]
    rng.shuffle(moves)

    uncovers = [
        m
        for m in moves
        if not is_foundation(m.dst) and sum(table.apply(m).down) < sum(table.down)
    ]
    if uncovers:
        return uncovers[0]

    home = [
        m
        for m in moves
        if is_foundation(m.dst)
        and _safe_home(table, table.run_from(m.src, table.cards_in(m.src) - 1)[0])
    ]
    if home:
        return home[0]

    from_waste = [m for m in moves if m.src == WASTE and not is_foundation(m.dst)]
    if from_waste:
        return from_waste[0]

    if table.stock or table.waste:
        if table.stock:
            return Move(STOCK, WASTE, min(table.draw, len(table.stock)))
        return Move(WASTE, STOCK, len(table.waste))

    # Nothing left in the stock: take any move at all rather than stopping,
    # since from here every card is somewhere a person can see.
    return moves[0] if moves else None


def main() -> int:
    target = os.environ.get("MOARCHY_SOLITAIRE_DIR")
    if not target:
        print(
            "set MOARCHY_SOLITAIRE_DIR first -- refusing to touch a real game",
            file=sys.stderr,
        )
        return 2

    stage = sys.argv[1] if len(sys.argv) > 1 else "table"
    store = Store(Path(target) / "solitaire.json")

    # A seed that walks into a table with something on every foundation. Found
    # by trying seeds, which is the honest way: the alternative is arranging
    # fifty-two cards by hand and calling it a deal.
    for seed in range(4000):
        rng = random.Random(seed)
        game = Game(shuffled(rng), 1)
        seen = {game.table}
        for _ in range(600):
            if stage != "home" and game.table.home >= TARGET_HOME:
                break
            if game.table.finishable or game.won:
                break
            move = _prefer(game, rng)
            if move is None:
                break
            game.play(move)
            if game.table in seen:
                # Round in a circle. Another seed will do better than another
                # thousand moves of this one.
                break
            seen.add(game.table)
        if stage == "home" and game.table.finishable:
            break
        if stage != "home" and game.table.home >= TARGET_HOME and any(game.table.down):
            break
    else:
        print("no seed reached a table worth photographing", file=sys.stderr)
        return 1

    store.begin(draw=1, deck=game.deck)
    store.remember(game, finished=game.won)
    for draw, played, won in RECORD:
        store.draw = draw
        for index in range(played):
            store.record(WON, 120 + index * 3) if index < won else store.record(LOST)
    store.draw = 1
    # The invented record left `recorded` set, which is right for a finished
    # game and wrong for this one: the deal on the screen has not been counted
    # and must not be, because it is still being played.
    store.recorded = False
    store.save()

    print(
        f"wrote {game.count} moves, {game.table.home} home, "
        f"{sum(game.table.down)} face down to {store.path}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
