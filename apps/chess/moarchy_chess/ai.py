"""The computer player: alpha-beta with a quiescence search, on a clock.

The shape of the search is ported from Braincup's `NormalChessAi` -- the same
piece-square tables, the same MVV/LVA ordering, the same captures-only search
past the horizon, the same deliberate beginner's blunder that makes Easy easy.
What is different is everything about *when it stops*, and that difference is
the phone.

Braincup names a depth per difficulty, which is the right answer on a machine
you can measure. Here the machine is a PinePhone or a laptop or whatever ran
`scripts/check.sh`, and they are two orders of magnitude apart -- so a level
names a number of **seconds** and a depth it will not exceed, and the search
deepens one ply at a time until one of the two runs out. The same "Hard" is a
five-ply opponent on a laptop and a three-ply one on a phone, and neither of
them leaves somebody holding a device that has stopped answering. This is
Reversi's argument, and it is the same argument, because it is the same phone.

The other half of making this fast enough to be worth playing is that nothing
here builds a board. The search plays moves into the one position it was given
and takes them back out (`chess.Position.make`/`unmake`), and carries the
evaluation along as an integer it adjusts by the move it just played rather
than recomputing over sixty-four squares at every leaf. `Made` -- the undo
record -- is what makes that possible: it says what moved, what it took and
where the rook went, which is exactly the four numbers the score changes by.

No GTK here either: the whole opponent is testable, and the window runs it on a
thread that knows nothing about any of it.
"""

from __future__ import annotations

import random
import time
from dataclasses import dataclass

from .chess import (
    BISHOP,
    BLACK,
    CELLS,
    KINDS,
    KING,
    KNIGHT,
    NO_SQUARE,
    PAWN,
    QUEEN,
    ROOK,
    WHITE,
    Position,
    file_of,
    piece,
    rank_of,
)

# What a piece is worth, in hundredths of a pawn. The bishop is twenty points
# over the knight so that the search will part with a knight for a bishop and
# not the other way round, which is the one piece-value opinion that shows up
# in games this shallow.
VALUES = {PAWN: 100, KNIGHT: 300, BISHOP: 320, ROOK: 500, QUEEN: 900, KING: 0}

# Piece-square tables, white's point of view, index 0 = a1. Deliberately small
# next to the piece values: they are there to choose between moves that are
# materially equal, not to talk the search out of winning a pawn.
PAWN_PST = (
      0,   0,   0,   0,   0,   0,   0,   0,
      5,  10,  10, -20, -20,  10,  10,   5,
      5,  -5, -10,   0,   0, -10,  -5,   5,
      0,   0,   0,  20,  20,   0,   0,   0,
      5,   5,  10,  25,  25,  10,   5,   5,
     10,  10,  20,  30,  30,  20,  10,  10,
     50,  50,  50,  50,  50,  50,  50,  50,
      0,   0,   0,   0,   0,   0,   0,   0,
)  # fmt: skip
KNIGHT_PST = (
    -50, -40, -30, -30, -30, -30, -40, -50,
    -40, -20,   0,   5,   5,   0, -20, -40,
    -30,   5,  10,  15,  15,  10,   5, -30,
    -30,   0,  15,  20,  20,  15,   0, -30,
    -30,   5,  15,  20,  20,  15,   5, -30,
    -30,   0,  10,  15,  15,  10,   0, -30,
    -40, -20,   0,   0,   0,   0, -20, -40,
    -50, -40, -30, -30, -30, -30, -40, -50,
)  # fmt: skip
BISHOP_PST = (
    -20, -10, -10, -10, -10, -10, -10, -20,
    -10,   5,   0,   0,   0,   0,   5, -10,
    -10,  10,  10,  10,  10,  10,  10, -10,
    -10,   0,  10,  10,  10,  10,   0, -10,
    -10,   5,   5,  10,  10,   5,   5, -10,
    -10,   0,   5,  10,  10,   5,   0, -10,
    -10,   0,   0,   0,   0,   0,   0, -10,
    -20, -10, -10, -10, -10, -10, -10, -20,
)  # fmt: skip
ROOK_PST = (
      0,   0,   0,   5,   5,   0,   0,   0,
     -5,   0,   0,   0,   0,   0,   0,  -5,
     -5,   0,   0,   0,   0,   0,   0,  -5,
     -5,   0,   0,   0,   0,   0,   0,  -5,
     -5,   0,   0,   0,   0,   0,   0,  -5,
     -5,   0,   0,   0,   0,   0,   0,  -5,
      5,  10,  10,  10,  10,  10,  10,   5,
      0,   0,   0,   0,   0,   0,   0,   0,
)  # fmt: skip
QUEEN_PST = (
    -20, -10, -10,  -5,  -5, -10, -10, -20,
    -10,   0,   0,   0,   0,   0,   0, -10,
    -10,   5,   5,   5,   5,   5,   0, -10,
      0,   0,   5,   5,   5,   5,   0,  -5,
     -5,   0,   5,   5,   5,   5,   0,  -5,
    -10,   0,   5,   5,   5,   5,   0, -10,
    -10,   0,   0,   0,   0,   0,   0, -10,
    -20, -10, -10,  -5,  -5, -10, -10, -20,
)  # fmt: skip
# The king wants the corner it castled into while there are pieces to fear, so
# this is the middlegame table. What it wants once the board has emptied is the
# opposite, and that is not a table -- see MATING below.
KING_PST = (
     20,  30,  10,   0,   0,  10,  30,  20,
     20,  20,   0,   0,   0,   0,  20,  20,
    -10, -20, -20, -20, -20, -20, -20, -10,
    -20, -30, -30, -40, -40, -30, -30, -20,
    -30, -40, -40, -50, -50, -40, -40, -30,
    -30, -40, -40, -50, -50, -40, -40, -30,
    -30, -40, -40, -50, -50, -40, -40, -30,
    -30, -40, -40, -50, -50, -40, -40, -30,
)  # fmt: skip

TABLES = {
    PAWN: PAWN_PST,
    KNIGHT: KNIGHT_PST,
    BISHOP: BISHOP_PST,
    ROOK: ROOK_PST,
    QUEEN: QUEEN_PST,
    KING: KING_PST,
}

# One table for "what is a piece of this colour on this square worth to White",
# material and position together and already signed. That is what lets the
# search keep its evaluation as a running total: a move changes it by the value
# of two or three squares, and the other sixty-one are not looked at.
VALUE_AT: list[list[int]] = [[0] * CELLS for _ in range(15)]
for _kind in KINDS:
    for _cell in range(CELLS):
        _worth = VALUES[_kind] + TABLES[_kind][_cell]
        VALUE_AT[piece(WHITE, _kind)][_cell] = _worth
        VALUE_AT[piece(BLACK, _kind)][_cell ^ 56] = -_worth

# How far a square is from the middle of the board, counted along the ranks and
# the files together: nought in the four centre squares and six in the corners.
# Only used in the ending below, where it is the whole of the mating technique --
# and the reason it is this measure rather than the distance to the nearest edge
# is that the corners come out highest, which is where a bare king is actually
# mated.
CENTRE_DISTANCE = tuple(
    abs(2 * file_of(cell) - 7) // 2 + abs(2 * rank_of(cell) - 7) // 2
    for cell in range(CELLS)
)

# Below this many pieces on the board, the middlegame king table is not merely
# useless but actively wrong: it is telling the winning side to keep its king in
# the corner, and a king in the corner cannot drive a bare king to the edge. So
# under this count the evaluation stops being about safety and starts being
# about mating -- push their king to the rim, bring ours up to it. Without this
# a won rook ending is shuffled into the fifty-move rule, which is the most
# visible thing a weak engine does.
MATING = 6
EDGE_WEIGHT = 12
APPROACH_WEIGHT = 4

# A mate found at ply 1 has to be worth more than the same mate at ply 5, or the
# search has no reason to play the move that gets there sooner -- and an engine
# that announces mate in two and then does not play it looks broken.
MATE = 100_000
INFINITY = 1_000_000

# The clock is read once every this many nodes. Reading it at every node is
# measurable in Python; a thousand nodes is a millisecond or two of overrun.
CHECK_MASK = 1023

# How far the captures-only search may keep going once it is answering checks.
# Without a cap a position where both sides can check forever is a position the
# search never comes back from.
QUIET_PLIES = 8


@dataclass(frozen=True)
class Level:
    """One entry in the difficulty list.

    `blunder` is the odds, per move, of playing a legal move picked at random
    instead of the one the search chose. It is Braincup's, and it is there
    because the obvious way to make an opponent easy -- search less deeply --
    does not make it *weaker* so much as differently blind: a one-ply engine
    still takes every free piece and never leaves one hanging, which is not how
    a beginner plays and not what anybody wants out of Easy.

    `quiescence` is the other half. With it off the search evaluates whatever
    position it lands on at the horizon, so it does not see the recapture and
    trades away pieces it should not -- which is exactly the mistake the person
    playing Easy is still learning not to make.
    """

    key: str
    label: str
    blurb: str
    depth: int
    seconds: float
    quiescence: bool = True
    blunder: float = 0.0


LEVELS: tuple[Level, ...] = (
    Level(
        "easy",
        "Easy",
        "Misses recaptures, and sometimes just plays",
        depth=2,
        seconds=0.4,
        quiescence=False,
        blunder=0.22,
    ),
    Level("medium", "Medium", "Looks three moves ahead and counts", 3, 1.2),
    Level("hard", "Hard", "Thinks for a couple of seconds", 5, 2.5),
)
LEVEL_KEYS = tuple(level.key for level in LEVELS)
DEFAULT_LEVEL = "medium"


def level_for(key: str) -> Level:
    return next((lv for lv in LEVELS if lv.key == key), LEVELS[1])


@dataclass(frozen=True)
class Thought:
    """A move, and what it cost to find it."""

    move: int
    depth: int
    nodes: int
    score: int = 0


class _OutOfTimeError(Exception):
    """Raised out of the search when the clock runs out.

    An exception rather than a sentinel score: a depth that did not finish is
    not a worse answer, it is not an answer at all, and its half-filled results
    must not be compared with the ones from the depth below.
    """


def advantage(position: Position) -> int:
    """Material and position, from White's point of view, counted in full.

    The search never calls this more than once per move it is asked for: after
    that it adjusts the number by hand. It is here to start that number off, and
    because a running total that nothing ever checks is a running total that
    drifts -- `tests/test_ai.py` plays games and compares the two.
    """
    return sum(
        VALUE_AT[code][cell] for cell, code in enumerate(position.squares) if code
    )


def pieces_on(position: Position) -> int:
    return sum(1 for code in position.squares if code)


def _delta(made, position: Position) -> int:
    """How much the move just played changed White's score by."""
    frm = made.move & 63
    to = (made.move >> 6) & 63
    change = VALUE_AT[made.placed][to] - VALUE_AT[made.piece][frm]
    if made.captured:
        change -= VALUE_AT[made.captured][made.captured_square]
    if made.rook_from != NO_SQUARE:
        rook = piece(made.piece >> 3, ROOK)
        change += VALUE_AT[rook][made.rook_to] - VALUE_AT[rook][made.rook_from]
    return change


def _ending(position: Position, score: int) -> int:
    """The correction that turns a won ending into a mate.

    Two things, and the first is the one that is easy to leave out. The king
    table has to be *taken back off*: it pays a king thirty points to sit in the
    corner it castled into, and thirty points is more than any amount of walking
    towards the work is worth, so an ending that merely adds an incentive is an
    ending where the winning king never leaves home. Ask a version without this
    to mate with a rook and it shuffles until the fifty-move rule, which is the
    most visible thing a weak engine does.

    What goes on instead is king-and-rook technique stated as two numbers: the
    side that is ahead is paid for driving the other king towards a corner, and
    for walking its own king up to it.
    """
    white, black = position.kings
    if white == NO_SQUARE or black == NO_SQUARE:
        return 0
    correction = KING_PST[black ^ 56] - KING_PST[white]
    material = score + correction
    apart = abs(file_of(white) - file_of(black)) + abs(rank_of(white) - rank_of(black))
    if material > 0:
        correction += EDGE_WEIGHT * CENTRE_DISTANCE[black] + APPROACH_WEIGHT * (
            14 - apart
        )
    elif material < 0:
        correction -= EDGE_WEIGHT * CENTRE_DISTANCE[white] + APPROACH_WEIGHT * (
            14 - apart
        )
    return correction


def evaluate(position: Position, score: int, pieces: int) -> int:
    """What the position is worth to the side to move."""
    if pieces <= MATING:
        score += _ending(position, score)
    return score if position.turn == WHITE else -score


def _ordered(position: Position, moves: list[int]) -> list[int]:
    """Captures first, richest victim by cheapest attacker, then the rest.

    Alpha-beta prunes in proportion to how early the best move is tried, and the
    best move is a capture far more often than chance. MVV/LVA is the cheapest
    ordering that knows that.
    """
    if len(moves) < 2:
        return moves
    squares = position.squares

    def score(code: int) -> int:
        victim = squares[(code >> 6) & 63]
        promotion = code >> 12
        if not victim and not promotion:
            return -1
        value = 10 * VALUES[victim & 7] if victim else 0
        if promotion:
            value += VALUES[promotion]
        return value - VALUES[squares[code & 63] & 7]

    return sorted(moves, key=score, reverse=True)


def _drawn(position: Position, pieces: int) -> bool:
    """A draw the search should stop at and score as nothing.

    Repetition is counted as *twice* rather than three times inside the search,
    which is the usual convention: a position repeated once is already a line
    the opponent can force to a draw, and waiting for the third occurrence means
    the search will happily walk into one believing it still has a game.
    """
    if position.halfmove >= 100:
        return True
    if pieces <= 4 and position.insufficient_material():
        return True
    return position.repetitions() >= 2


def _quiescence(position, alpha, beta, score, pieces, ply, state) -> int:
    """Keep following captures past the horizon until the board is quiet.

    Without this the search happily trades into a position that is about to lose
    material, because the evaluation at the horizon cannot see the recapture
    standing on the very next square. It is the difference between an engine
    that hangs pieces and one that does not, and it is why Easy turns it off.
    """
    state[0] += 1
    if not state[0] & CHECK_MASK and state[2]() > state[1]:
        raise _OutOfTimeError

    check = position.in_check()
    if not check:
        stand = evaluate(position, score, pieces)
        if stand >= beta:
            return beta
        alpha = max(alpha, stand)
    elif ply >= QUIET_PLIES:
        return evaluate(position, score, pieces)

    # In check there is no standing pat: every move has to be looked at, because
    # the position may be mate and a captures-only list would score it as merely
    # uncomfortable.
    moves = position.pseudo_moves(tactical=not check)
    us = position.turn
    played = 0
    for code in _ordered(position, moves):
        made = position.make(code)
        if position.attacked(position.kings[us], position.turn):
            position.unmake(made)
            continue
        played += 1
        value = -_quiescence(
            position,
            -beta,
            -alpha,
            score + _delta(made, position),
            pieces - 1 if made.captured else pieces,
            ply + 1,
            state,
        )
        position.unmake(made)
        if value >= beta:
            return beta
        alpha = max(alpha, value)
    if check and not played:
        return -(MATE - ply)
    return alpha


def _search(position, depth, alpha, beta, score, pieces, ply, state, level) -> int:
    state[0] += 1
    if not state[0] & CHECK_MASK and state[2]() > state[1]:
        raise _OutOfTimeError
    if ply and _drawn(position, pieces):
        return 0
    if depth <= 0:
        if level.quiescence:
            return _quiescence(position, alpha, beta, score, pieces, ply, state)
        return evaluate(position, score, pieces)

    us = position.turn
    best = -INFINITY
    played = 0
    for code in _ordered(position, position.pseudo_moves()):
        made = position.make(code)
        if position.attacked(position.kings[us], position.turn):
            position.unmake(made)
            continue
        played += 1
        value = -_search(
            position,
            depth - 1,
            -beta,
            -alpha,
            score + _delta(made, position),
            pieces - 1 if made.captured else pieces,
            ply + 1,
            state,
            level,
        )
        position.unmake(made)
        if value > best:
            best = value
            if best > alpha:
                alpha = best
                if alpha >= beta:
                    break  # the opponent would never let us get here
    if not played:
        # Mate is worth less the further away it is, so that the search prefers
        # the move that gets there sooner. Stalemate is nothing at all, and
        # telling the two apart is the whole of the check.
        return -(MATE - ply) if position.in_check() else 0
    return best


def _root(position, moves, depth, score, pieces, state, level) -> list[tuple[int, int]]:
    """Score every legal move from here, best first on return."""
    alpha = -INFINITY
    scored = []
    for code in moves:
        made = position.make(code)
        value = -_search(
            position,
            depth - 1,
            -INFINITY,
            -alpha,
            score + _delta(made, position),
            pieces - 1 if made.captured else pieces,
            1,
            state,
            level,
        )
        position.unmake(made)
        scored.append((code, value))
        alpha = max(alpha, value)
    scored.sort(key=lambda pair: -pair[1])
    return scored


def think(
    position: Position,
    level: Level,
    *,
    rng: random.Random | None = None,
    clock=time.monotonic,
) -> Thought | None:
    """Pick a move for the side to play, inside the level's budget.

    Works on a copy throughout, and that is not tidiness. The search plays moves
    into the position and takes them back out, so a search abandoned part way --
    which is what running out of time *is* here -- unwinds through an exception
    with half a dozen moves still on the board. Copying once, here, is what
    makes "the clock ran out" a thing that can happen to a search without
    happening to the game.
    """
    position = position.copy()
    legal = position.moves()
    if not legal:
        return None
    if len(legal) == 1:
        # Nothing to think about, and a pause here reads as a computer
        # pretending to consider a move it has no choice about.
        return Thought(legal[0], 0, 0)

    chance = rng or random
    if level.blunder and not position.in_check() and chance.random() < level.blunder:
        # Not while in check: the random move might be the only one that saves
        # the king, and picking a different one there does not look casual, it
        # looks broken.
        return Thought(chance.choice(legal), 0, 0)

    score = advantage(position)
    pieces = pieces_on(position)
    state = [0, clock() + level.seconds, clock]
    order = _ordered(position, legal)
    scored = [(code, 0) for code in order]
    reached = 0

    for depth in range(1, level.depth + 1):
        try:
            found = _root(position, order, depth, score, pieces, state, level)
        except _OutOfTimeError:
            break
        scored = found
        # The best move from the depth just finished is tried first at the next
        # one, which is most of what makes iterative deepening cheaper than
        # simply searching to the final depth.
        order = [code for code, _ in scored]
        reached = depth
        if abs(scored[0][1]) >= MATE - 100:
            break  # a mate is a mate; deeper says the same thing more slowly

    return Thought(scored[0][0], reached, state[0], scored[0][1])


def choose(position: Position, level: Level, **kwargs) -> int | None:
    thought = think(position, level, **kwargs)
    return thought.move if thought else None
