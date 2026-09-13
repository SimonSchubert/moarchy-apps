"""Can this position still be finished, and what is the next jump if it can?

Peg solitaire is the one game in this repository where the hard question is not
"what is a good move" but "have I already lost". A position with twenty pegs on
it and no way to reach one looks exactly like a position with a way -- there is
no material to count and no threat to see -- and a person can spend ten minutes
jumping around a board that was decided eight moves ago. Every other app here
answers a question the player could answer themselves, more slowly; this one
answers a question they cannot.

So the hint is a **search, not a heuristic**, and it gives one of three answers:

    a jump       there is a way from here, and this is the first step of one
    no way       proved: every line from here ends with more than one peg
    no answer    the clock ran out before either of those was established

The third is not a failure, it is the honest shape of the thing. The whole board
from its opening position is a sixty-thousand-node search here and a rather
larger one on a figure that has gone wrong, and the answer that matters on a
phone is one that arrives.

**On a clock, not on a node budget.** The same count is a proof on a laptop and
a shrug on a PinePhone, which is the argument Reversi's search makes about depth
and is the same argument. The clock is checked every few hundred nodes, because
checking it on every one costs more than the node does.

**The dead set is the whole optimisation.** A position that has been shown to
lead nowhere leads nowhere however it was arrived at, and the same position is
reached by a great many orders of the same jumps -- so one set of integers turns
an intractable tree into a manageable graph. It is thrown away between searches
rather than kept: it is keyed on the pegs alone, and a different figure is a
different board.

No GTK here either: the whole solver is testable, and the window runs it on a
thread that knows nothing about any of it.
"""

from __future__ import annotations

import time
from dataclasses import dataclass

from .pegs import Position

# How long a hint is allowed to take. Long enough to settle most positions on a
# phone, short enough that a person who taps Hint does not wonder whether they
# tapped it.
SECONDS = 2.0

# How often the clock is looked at. A node is a few microseconds and
# time.monotonic() is not free, so asking on every node would spend a
# measurable share of the search on knowing what time it is.
CHECK_EVERY = 512

SOLVED = "solved"
IMPOSSIBLE = "impossible"
UNKNOWN = "unknown"


@dataclass(frozen=True)
class Answer:
    """What the search found, and what it is allowed to claim.

    `line` is the whole solution rather than only its first jump, because the
    window keeps it: a person who follows a hint has the next one for nothing,
    which turns the second tap on Hint from a two-second search into a list
    lookup. It is dropped the moment a move is played that is not on it.
    """

    verdict: str
    line: tuple[int, ...] = ()
    nodes: int = 0

    @property
    def move(self) -> int | None:
        return self.line[0] if self.line else None


class _TimeoutError(Exception):
    pass


def search(position: Position, target: int = -1, seconds: float = SECONDS) -> Answer:
    """Look for a line that ends with one peg -- in `target` if it is given."""
    if position.count == 1:
        return Answer(SOLVED if target < 0 or position.has_peg(target) else IMPOSSIBLE)

    holes = position.holes
    dead: set[int] = set()
    line: list[int] = []
    nodes = 0
    deadline = time.monotonic() + seconds

    def walk(pegs: int) -> bool:
        nonlocal nodes
        nodes += 1
        if nodes % CHECK_EVERY == 0 and time.monotonic() > deadline:
            raise _TimeoutError
        if pegs.bit_count() == 1:
            return target < 0 or bool(pegs >> target & 1)
        if pegs in dead:
            return False
        here = Position(holes, pegs)
        for move in here.moves():
            line.append(move)
            if walk(here.play(move).pegs):
                return True
            line.pop()
        # Only now. A position is dead when every jump out of it has been tried
        # and none of them led anywhere -- marking it on the way in would mark
        # every position on the board.
        dead.add(pegs)
        return False

    try:
        found = walk(position.pegs)
    except _TimeoutError:
        return Answer(UNKNOWN, (), nodes)
    if found:
        return Answer(SOLVED, tuple(line), nodes)
    return Answer(IMPOSSIBLE, (), nodes)


def solve(position: Position, target: int = -1, seconds: float = 30.0):
    """The whole line, or None. For the tests and for demo.py.

    The same search with the clock turned up: nothing in the app calls this,
    because nothing in the app may take thirty seconds.
    """
    answer = search(position, target, seconds)
    return list(answer.line) if answer.verdict == SOLVED else None
