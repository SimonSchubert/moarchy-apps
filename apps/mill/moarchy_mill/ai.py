"""The computer player: alpha-beta over the bitboards, on a clock.

The same two things shape this file that shape Reversi's search, and one more
that is Morris's own.

**The depth is not decided in advance.** Every level names a number of seconds
and a ceiling, and the search deepens one ply at a time until one of the two
runs out -- so the same "Hard" is a six-ply opponent on a laptop and a four-ply
one on a PinePhone, and neither leaves somebody holding a phone that has stopped
answering. A fixed depth would have to be set for the slowest device and would
then be the strength everywhere.

**Nobody waits for a move they had no choice about.** A position with one legal
move is answered instantly, because thinking about it is theatre that costs a
second of somebody's battery.

And the one that is this game's: **a turn is not always one ply.** Closing a mill
earns a removal, and the removal is made by the same side -- so a child position
can have the same player to move as its parent, and negamax's "flip the sign"
is wrong exactly there. Every recursion here asks whose turn the child is before
deciding whether to negate. Getting that wrong produces a search that plays
brilliantly until it makes a mill and then throws a piece away, which is a very
hard bug to see and an easy one to write.

No GTK here either: the whole opponent is testable, and the window runs it on a
thread that knows nothing about any of it.
"""

from __future__ import annotations

import random
import time
from dataclasses import dataclass

from .mill import (
    BLACK,
    MILL_MASKS,
    NEIGHBOUR_MASKS,
    POINTS,
    WHITE,
    Position,
    spots,
    unpack,
)

# What a piece is worth, and what everything else is worth against it. A piece
# is the currency of this game -- a side that is two down is usually lost -- so
# everything else is priced as a fraction of one.
MAN = 100
# A closed mill is worth a third of a piece: it is not material, it is the
# machine that takes material.
MILL = 32
# Two of a line with the third empty. Cheap, because most of them never close.
NEARLY = 11
# Being able to move at all. In the endgame this is most of the game: a side
# with three pieces and two squares to put them on is lost with material level.
MOBILITY = 3
# An enemy piece with nowhere to go. The other half of the same idea.
BLOCKED = 5

WIN = 100_000


@dataclass(frozen=True)
class Level:
    key: str
    label: str
    blurb: str
    seconds: float
    depth: int
    # The chance that a turn is played from the list of *decent* moves rather
    # than the best one. See `choose`.
    slack: float


LEVELS = (
    Level(
        key="easy",
        label="Easy",
        blurb="Looks one move ahead, and often not that far.",
        seconds=0.20,
        depth=2,
        slack=0.55,
    ),
    Level(
        key="medium",
        label="Medium",
        blurb="A second of thought. Will see a mill coming.",
        seconds=0.9,
        depth=6,
        slack=0.12,
    ),
    Level(
        key="hard",
        label="Hard",
        blurb="Two seconds, as deep as they go. Take the mills.",
        seconds=2.2,
        depth=12,
        slack=0.0,
    ),
)
LEVEL_KEYS = tuple(level.key for level in LEVELS)
DEFAULT_LEVEL = "medium"


def level_for(key: str) -> Level:
    for level in LEVELS:
        if level.key == key:
            return level
    return LEVELS[1]


class _TimeoutError(Exception):
    pass


def evaluate(position: Position, colour: int) -> int:
    """What this position is worth to `colour`, in hundredths of a piece.

    Deliberately flat: material, mills, half-mills, and how much either side can
    move. Morris evaluations in the literature run to a dozen weighted terms
    including double mills and three-piece configurations; those are worth
    having on a machine that can afford them, and on an A53 every term is
    another few thousand positions a second not searched.
    """
    other = BLACK if colour == WHITE else WHITE
    if position.lost(colour):
        return -WIN
    if position.lost(other):
        return WIN

    mine, theirs = position.men(colour), position.men(other)
    score = (mine.bit_count() - theirs.bit_count()) * MAN
    score += (_mills(mine) - _mills(theirs)) * MILL
    score += (_nearly(mine, theirs) - _nearly(theirs, mine)) * NEARLY
    # Mobility is only a thing once there is somewhere to move from. In the
    # placing phase every empty point is available to both sides and counting it
    # is counting the same number twice.
    if not position.placing(colour) and not position.placing(other):
        score += (_room(mine, theirs) - _room(theirs, mine)) * MOBILITY
        score += _stuck(theirs, mine) * BLOCKED
    return score


def _mills(men: int) -> int:
    return sum(1 for mask in MILL_MASKS if men & mask == mask)


def _nearly(men: int, others: int) -> int:
    """Lines holding two of mine and nothing of theirs."""
    count = 0
    for mask in MILL_MASKS:
        if others & mask:
            continue
        if (men & mask).bit_count() == 2:
            count += 1
    return count


def _room(men: int, others: int) -> int:
    empty = ((1 << POINTS) - 1) & ~(men | others)
    return sum((NEIGHBOUR_MASKS[spot] & empty).bit_count() for spot in spots(men))


def _stuck(men: int, others: int) -> int:
    empty = ((1 << POINTS) - 1) & ~(men | others)
    return sum(1 for spot in spots(men) if not NEIGHBOUR_MASKS[spot] & empty)


def _ordered(position: Position) -> list[int]:
    """Moves, with the ones that close a mill first.

    One cheap test per move, and it is most of what move ordering buys here: a
    move that closes a mill is very often the best move, and alpha-beta cuts
    what it can only when the best move is tried early.
    """
    moves = position.moves()
    if position.removing:
        return moves
    turn = position.turn

    def key(move: int) -> int:
        src, dst = unpack(move)
        return 0 if position.closes(turn, dst, without=src) else 1

    return sorted(moves, key=key)


def _leaf(position: Position, depth: int) -> int:
    """A finished or exhausted position, from the point of view of the mover.

    The depth is added to a decided game so that a win found sooner is worth
    more than the same win four plies later, and a loss later is worth more than
    the same loss now. Without it a lost search plays the move that loses
    immediately -- correct, and indistinguishable from not trying.
    """
    value = evaluate(position, position.turn)
    if value >= WIN:
        return value + depth
    if value <= -WIN:
        return value - depth
    return value


def _search(
    position: Position, depth: int, alpha: int, beta: int, deadline: float
) -> int:
    """Negamax, except where a turn does not change hands.

    Every value in here is from the point of view of **the side to move in the
    position it describes**, which is the ordinary negamax convention -- and the
    reason it needs saying is that this game breaks the ordinary consequence of
    it. Closing a mill earns a removal made by the same side, so a child can
    have the same player on move as its parent; there the value is already in
    the right frame and the window does not turn over. Flipping the sign at
    those nodes produces a search that plays well until it makes a mill and then
    gives a piece away, which is easy to write and hard to see.
    """
    if time.monotonic() > deadline:
        raise _TimeoutError
    if position.over or depth <= 0:
        return _leaf(position, depth)
    moves = _ordered(position)
    if not moves:
        return _leaf(position, depth)

    best = -WIN * 2
    for move in moves:
        child = position.play(move)
        if child.turn == position.turn:
            score = _search(child, depth - 1, alpha, beta, deadline)
        else:
            score = -_search(child, depth - 1, -beta, -alpha, deadline)
        best = max(best, score)
        alpha = max(alpha, best)
        if alpha >= beta:
            break
    return best


def choose(position: Position, level: Level, rng: random.Random | None = None) -> int:
    """The computer's move, or -1 on a board with nothing to play.

    Iterative deepening: one ply at a time until the clock or the ceiling runs
    out, keeping the best move from the last depth that *finished*. A depth
    abandoned halfway has looked at some moves and not others, and the best of
    those is not a result, it is a bias.
    """
    moves = _ordered(position)
    if not moves:
        return -1
    if len(moves) == 1:
        return moves[0]

    rng = rng or random.Random()
    deadline = time.monotonic() + level.seconds
    best = moves[0]
    scored: list[tuple[int, int]] = [(0, move) for move in moves]

    for depth in range(1, level.depth + 1):
        try:
            here: list[tuple[int, int]] = []
            alpha = -WIN * 2
            for move in moves:
                child = position.play(move)
                if child.turn == position.turn:
                    score = _search(child, depth - 1, alpha, WIN * 2, deadline)
                else:
                    score = -_search(child, depth - 1, -WIN * 2, -alpha, deadline)
                here.append((score, move))
                alpha = max(alpha, score)
        except _TimeoutError:
            break
        scored = here
        # Best first next time round, which is most of what iterative deepening
        # is for: the previous depth is the move ordering for the next one.
        moves = [move for _, move in sorted(here, key=lambda pair: -pair[0])]
        best = moves[0]
        if max(score for score, _ in here) >= WIN:
            break

    if level.slack and rng.random() < level.slack:
        return _casual(scored, rng)
    return best


def _casual(scored: list[tuple[int, int]], rng: random.Random) -> int:
    """A move chosen from the decent ones rather than the best one.

    Not a random legal move. An opponent that gives a piece away for nothing
    does not read as easy, it reads as broken -- and in this game the difference
    is stark, because handing over a piece is most of the way to handing over
    the game. So the pool is every move within a piece of the best, which is an
    opponent that misses things rather than one that is not playing.
    """
    if not scored:
        return -1
    top = max(score for score, _ in scored)
    pool = [move for score, move in scored if score >= top - MAN]
    return rng.choice(pool or [scored[0][1]])
