"""The computer player: alpha-beta over the bitboards, on a clock.

Two things shape this file, and both of them are the phone.

The first is that the machine is slow and the search is interpreted, so the
depth reached is not something to write down in advance. Every level names a
number of *seconds* and a depth it will not exceed, and the search deepens one
ply at a time until one of the two runs out -- so the same "Hard" is a six-ply
opponent on a laptop and a four-ply one on a PinePhone, and neither of them
leaves somebody holding a phone that has stopped answering. A fixed depth would
have to be set for the slowest device and would then be the strength everywhere.

The second is that nobody waits for a move they had no choice about. A position
with one legal move is answered instantly, without a search, because thinking
about it is theatre that costs a second of somebody's battery.

No GTK here either: the whole opponent is testable, and the window runs it on a
thread that knows nothing about any of it.
"""

from __future__ import annotations

import random
import time
from dataclasses import dataclass

from .reversi import CELLS, PASS, Position, cells, flips, legal_moves

# What each square is worth to hold. The corners cannot be flipped by anything,
# ever, which is the only truly permanent fact on the board; the squares that
# give a corner away are worth less than nothing. The middle is worth almost
# nothing either way, and saying so is what stops the search from grabbing discs
# early -- the classic beginner's mistake this table exists to avoid making.
WEIGHTS = (
    100, -20, 10,  5,  5, 10, -20, 100,
    -20, -50, -2, -2, -2, -2, -50, -20,
     10,  -2, -1, -1, -1, -1,  -2,  10,
      5,  -2, -1, -1, -1, -1,  -2,   5,
      5,  -2, -1, -1, -1, -1,  -2,   5,
     10,  -2, -1, -1, -1, -1,  -2,  10,
    -20, -50, -2, -2, -2, -2, -50, -20,
    100, -20, 10,  5,  5, 10, -20, 100,
)  # fmt: skip

# Scoring a side means summing the weights of the squares it holds, and doing
# that a bit at a time is eight thousand Python operations a second the search
# does not get to spend elsewhere. A rank is one byte, a byte has 256 values, so
# every rank's contribution is a table lookup: eight shifts and eight lookups
# for a whole side.
_RANK_VALUES = tuple(
    tuple(
        sum(WEIGHTS[rank * 8 + column] for column in range(8) if byte >> column & 1)
        for byte in range(256)
    )
    for rank in range(8)
)

# Having somewhere to go is worth more than having discs: a side with no moves
# hands its turn back, and a side with one move plays whatever it is given. At
# eight points a move this is comparable with holding a good edge square and
# well below a corner, which is the ordering that matters.
MOBILITY = 8

# Near the end the count is the thing being played for rather than a proxy for
# it, and the positional table stops describing the same game.
COUNTING_FROM = 10
DISC = 12

# From this many empty squares on, the depth cap gives way for the levels that
# ask for it and the search plays the game out exactly -- if the clock allows,
# which is the point of the clock. Twelve is about what a phone finishes in a
# couple of seconds with this pruning, and knowing the last dozen moves rather
# than guessing at them is the difference between a computer that wins the
# endgame and one that hopes.
#
# Only Hard asks. An easy opponent that plays the final dozen moves perfectly is
# an easy opponent right up until the part of the game that decides it, which is
# a worse experience than a hard one -- it feels like being cheated rather than
# beaten.
EXACT_FROM = 12

# A decided game beats any arrangement of discs, and the margin rides along so
# that winning by forty is preferred to winning by two.
WIN = 100_000

# The clock is read once every this many nodes. Reading it at every node is
# measurable in Python; a thousand nodes is a millisecond or two of overrun.
CHECK_MASK = 1023

# Squares tried first when searching. Alpha-beta prunes in proportion to how
# early the best move is tried, and the best move is a corner far more often
# than chance, so the static table is also the move order.
SEARCH_ORDER = sorted(range(CELLS), key=WEIGHTS.__getitem__, reverse=True)
_RANK = [SEARCH_ORDER.index(cell) for cell in range(CELLS)]


@dataclass(frozen=True)
class Level:
    """One entry in the difficulty list.

    `slack` is how many points of evaluation the level is willing to throw away:
    at zero it plays the best move it found, and above zero it picks at random
    among the moves that came within that much of it. That is a better shape for
    an easy opponent than a shallower search alone, which is not *weaker* so
    much as differently blind -- it still takes every corner going, and losing
    to something that never errs is not the experience anyone wants from Easy.
    """

    key: str
    label: str
    blurb: str
    depth: int
    seconds: float
    slack: int
    # Play the last dozen squares out to the end rather than evaluating them.
    exact: bool = False


LEVELS: tuple[Level, ...] = (
    Level("easy", "Easy", "Plays quickly, and not always well", 1, 0.15, 45),
    Level("medium", "Medium", "Looks a few moves ahead", 3, 0.7, 8),
    Level(
        "hard",
        "Hard",
        "Thinks for a second and plays the endgame out",
        depth=8,
        seconds=2.0,
        slack=0,
        exact=True,
    ),
)
LEVEL_KEYS = tuple(level.key for level in LEVELS)
DEFAULT_LEVEL = "medium"


def level_for(key: str) -> Level:
    return next((lv for lv in LEVELS if lv.key == key), LEVELS[1])


@dataclass(frozen=True)
class Thought:
    """A move, and what it cost to find it."""

    cell: int
    depth: int
    nodes: int


class _OutOfTimeError(Exception):
    """Raised out of the search when the clock runs out.

    An exception rather than a sentinel score: a depth that did not finish is
    not a worse answer, it is not an answer at all, and its half-filled results
    must not be compared with the ones from the depth below.
    """


def _positional(board: int) -> int:
    return (
        _RANK_VALUES[0][board & 0xFF]
        + _RANK_VALUES[1][board >> 8 & 0xFF]
        + _RANK_VALUES[2][board >> 16 & 0xFF]
        + _RANK_VALUES[3][board >> 24 & 0xFF]
        + _RANK_VALUES[4][board >> 32 & 0xFF]
        + _RANK_VALUES[5][board >> 40 & 0xFF]
        + _RANK_VALUES[6][board >> 48 & 0xFF]
        + _RANK_VALUES[7][board >> 56 & 0xFF]
    )


def terminal(own: int, opp: int) -> int:
    """What a finished game is worth: decided, with the margin riding along."""
    margin = own.bit_count() - opp.bit_count()
    if margin > 0:
        return WIN + margin
    if margin < 0:
        return -WIN + margin
    return 0


def evaluate(own: int, opp: int, moves: int | None = None) -> int:
    """What this position is worth to the side to move."""
    mine = (legal_moves(own, opp) if moves is None else moves).bit_count()
    theirs = legal_moves(opp, own).bit_count()
    if CELLS - (own | opp).bit_count() <= COUNTING_FROM:
        return (own.bit_count() - opp.bit_count()) * DISC + (mine - theirs) * 2
    return _positional(own) - _positional(opp) + MOBILITY * (mine - theirs)


def _apply(own: int, opp: int, cell: int) -> tuple[int, int]:
    turned = flips(own, opp, cell)
    return own | turned | (1 << cell), opp & ~turned


def _search(own, opp, depth, alpha, beta, deadline, clock, counter) -> int:
    counter[0] += 1
    if not counter[0] & CHECK_MASK and clock() > deadline:
        raise _OutOfTimeError
    moves = legal_moves(own, opp)
    if not moves:
        if not legal_moves(opp, own):
            return terminal(own, opp)
        # A pass costs no depth. It is not a move -- charging it one would make
        # the search shallowest exactly where the position is most forcing.
        return -_search(opp, own, depth, -beta, -alpha, deadline, clock, counter)
    if depth <= 0:
        return evaluate(own, opp, moves)
    best = -WIN * 2
    for cell in sorted(cells(moves), key=_RANK.__getitem__):
        mine, theirs = _apply(own, opp, cell)
        score = -_search(
            theirs, mine, depth - 1, -beta, -alpha, deadline, clock, counter
        )
        if score > best:
            best = score
            if best > alpha:
                alpha = best
                if alpha >= beta:
                    break  # the opponent would never let us get here
    return best


def _root(position, order, depth, deadline, clock, counter, prune) -> list:
    """Score every move from here, best first on return.

    `prune` is off for the levels that pick among near-best moves: alpha-beta
    returns bounds rather than values for the moves it refutes, and choosing
    "within eight points of the best" out of a list of bounds would be choosing
    out of numbers that do not mean what they say. A level that plays the best
    move it found does not care, and gets the pruning.
    """
    alpha, scored = -WIN * 2, []
    for cell in order:
        child = position.play(cell)
        window = alpha if prune else -WIN * 2
        score = -_search(
            child.own,
            child.opp,
            depth - 1,
            -(WIN * 2),
            -window,
            deadline,
            clock,
            counter,
        )
        scored.append((cell, score))
        alpha = max(alpha, score)
    scored.sort(key=lambda pair: -pair[1])
    return scored


def think(
    position: Position,
    level: Level,
    *,
    rng: random.Random | None = None,
    clock=time.monotonic,
) -> Thought:
    """Pick a move for the side to play, inside the level's budget."""
    legal = position.legal()
    if not legal:
        return Thought(PASS, 0, 0)
    if len(legal) == 1:
        # Nothing to think about, and a pause here reads as a computer
        # pretending to consider a move it has no choice about.
        return Thought(legal[0], 0, 0)

    empties = position.empties()
    exact = level.exact and empties <= EXACT_FROM
    cap = max(level.depth, empties) if exact else level.depth
    deadline = clock() + level.seconds
    counter = [0]
    order = sorted(legal, key=_RANK.__getitem__)
    scored = [(cell, 0) for cell in order]
    reached = 0

    for depth in range(1, cap + 1):
        try:
            scored = _root(
                position, order, depth, deadline, clock, counter, not level.slack
            )
        except _OutOfTimeError:
            break
        order = [cell for cell, _ in scored]
        reached = depth
        if abs(scored[0][1]) >= WIN:
            break  # the game is decided from here; deeper says the same thing

    top = scored[0][1]
    pool = [cell for cell, score in scored if top - score <= level.slack]
    return Thought((rng or random).choice(pool), reached, counter[0])


def choose(position: Position, level: Level, **kwargs) -> int:
    return think(position, level, **kwargs).cell
