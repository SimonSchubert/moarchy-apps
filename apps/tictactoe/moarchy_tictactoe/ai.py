"""The computer player: the whole game, solved, and then told to err.

This is the one file in this repository where the opponent is not a search on a
clock, and the reason is arithmetic. Tic-tac-toe has 5,478 reachable positions.
Reversi has more than that in the first four moves. So there is no depth to
choose, no time to budget and no evaluation function to tune: the game is solved
outright, in about a tenth of a second on an A53, and the table is then good for
the life of the process.

Which leaves the question this game actually poses. A solved opponent cannot be
beaten -- the best anybody gets against correct play is a draw, every time,
forever -- and an app that ships only that is an app nobody opens twice. So the
levels here are not depths. They are descriptions of what the opponent *sees*:

    Easy      takes a win it is handed, and does not look for yours
    Fair      takes a win, blocks a threat, and is otherwise careless
    Perfect   never loses, and plays for the mistake rather than the draw

That last clause is the part worth reading twice. Between two perfect players
this game is always drawn, so among moves that all draw there is nothing to
choose on the scoreboard -- and something real to choose on the board. Every
optimal move is scored by how many replies to it lose, and the one that gives
the opponent the most ways to go wrong is played. It cannot make Perfect win a
game it should draw; it wins the games where somebody taps without looking,
which on a phone, on a bus, is most of them.

The blunders are deliberate and they are the same mechanism at all three levels:
a level names the chance that this turn is played casually rather than
correctly, and what "casually" is allowed to notice. A level that played
correctly with a random move mixed in would be an opponent that is perfect until
it suddenly is not, which reads as a bug. One that always notices a win it can
take and sometimes fails to notice yours reads as somebody not concentrating,
which is what an easy opponent is.

No GTK here either: the whole opponent is testable, and the window runs it on a
thread that knows nothing about any of it.
"""

from __future__ import annotations

import random
from dataclasses import dataclass

from .tictactoe import CELLS, Position, other

# Values are from the point of view of the side to move, and carry the number of
# moves left on the board with them: a win in one is worth more than a win in
# three, and a loss in three is worth more than a loss in one. Without that a
# solved opponent that is already lost plays a move that loses immediately --
# correct, and indistinguishable from not trying.
WIN = 10
DRAW = 0


@dataclass(frozen=True)
class Level:
    key: str
    label: str
    blurb: str
    # The chance that a turn is played casually rather than correctly.
    careless: float
    # ...and what a careless turn still notices. Taking a win that is on the
    # board is what separates an opponent who is not concentrating from one who
    # is not playing.
    takes_wins: bool
    blocks: bool


LEVELS = (
    Level(
        key="easy",
        label="Easy",
        blurb="Takes a win it is given. Will not see yours coming.",
        careless=0.80,
        takes_wins=True,
        blocks=False,
    ),
    Level(
        key="fair",
        label="Fair",
        blurb="Blocks what it can see. Misses about one turn in five.",
        careless=0.22,
        takes_wins=True,
        blocks=True,
    ),
    Level(
        key="perfect",
        label="Perfect",
        blurb="Cannot be beaten. A draw is a result against this one.",
        careless=0.0,
        takes_wins=True,
        blocks=True,
    ),
)
LEVEL_KEYS = tuple(level.key for level in LEVELS)
DEFAULT_LEVEL = "fair"


def level_for(key: str) -> Level:
    for level in LEVELS:
        if level.key == key:
            return level
    return LEVELS[1]


# (x, o, turn) -> value to the side to move. Positions are frozen and hashable,
# so the position itself is the key. The table is a module global rather than
# per-search state because it describes the rules and not a game: it is correct
# for every game this process ever plays, and filling it once is the difference
# between a first move that takes a tenth of a second and every first move
# taking one.
_SOLVED: dict[Position, int] = {}


def value(position: Position) -> int:
    """What this position is worth to the side about to move, played out.

    Exact. There is no horizon and no evaluation: the recursion bottoms out on
    a finished board every time, because the board fills in at most nine plies.
    """
    cached = _SOLVED.get(position)
    if cached is not None:
        return cached

    winner = position.winner()
    if winner is not None:
        # Whoever is to move is the one who did not just make three in a row.
        result = -(WIN + CELLS - position.played())
    elif position.is_full():
        result = DRAW
    else:
        result = max(-value(position.play(cell)) for cell in position.legal())

    _SOLVED[position] = result
    return result


def scored(position: Position) -> dict[int, int]:
    """Every legal move and what it is worth. The whole opponent, really."""
    return {cell: -value(position.play(cell)) for cell in position.legal()}


def _mistakes_allowed(position: Position, cell: int) -> int:
    """How many replies to this move would lose for the player replying.

    The tie-break among equally good moves, and the only thing separating
    Perfect from any other correct player. Between two perfect players this
    game is drawn from the empty board, so a solver with nothing but the result
    to go on has no reason to prefer any drawing move to any other -- and
    against a person on a bus there is every reason to prefer the one with the
    most ways to go wrong in it.
    """
    after = position.play(cell)
    return sum(1 for value_ in scored(after).values() if value_ < DRAW)


def best(position: Position) -> list[int]:
    """The optimal moves, in the order a perfect player would prefer them."""
    values = scored(position)
    if not values:
        return []
    top = max(values.values())
    tied = [cell for cell, score in values.items() if score == top]
    return sorted(tied, key=lambda cell: (-_mistakes_allowed(position, cell), cell))


def careless(position: Position, level: Level, rng: random.Random) -> int:
    """A move played without thinking about it, to the depth the level allows.

    Deliberately not "a random legal move". An opponent that sometimes fails to
    take a win it has been handed does not read as easy, it reads as broken --
    the board says three in a row is there and the app did not take it. Missing
    *your* threat is the thing that reads as not concentrating, and it is the
    only thing Easy is actually allowed to miss.
    """
    if level.takes_wins:
        mine = position.wins_now(position.turn)
        if mine:
            return rng.choice(mine)
    if level.blocks:
        theirs = position.wins_now(other(position.turn))
        if theirs:
            return rng.choice(theirs)
    return rng.choice(position.legal())


def choose(position: Position, level: Level, rng: random.Random | None = None) -> int:
    """The computer's move, or -1 on a board with no moves left in it."""
    legal = position.legal()
    if not legal:
        return -1
    if len(legal) == 1:
        # Nobody waits for a move they had no choice about, and on this board
        # that is the ninth square of every drawn game.
        return legal[0]

    rng = rng or random.Random()
    if level.careless and rng.random() < level.careless:
        return careless(position, level, rng)
    return best(position)[0]


def warm() -> int:
    """Solve the game. Returns the number of positions, for the tests.

    Called off the main loop before the first move is asked for, so that the
    tenth of a second this costs is spent while somebody is looking at an empty
    board rather than while they are waiting for a reply to their first tap.
    """
    value(Position())
    return len(_SOLVED)
