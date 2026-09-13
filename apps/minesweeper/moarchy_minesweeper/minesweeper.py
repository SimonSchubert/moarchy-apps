"""The rules of Minesweeper, and where the mines come from.

A field is a width, a height and a set of cells with mines in them. Everything
else -- the numbers, the flood that opens half the board on a lucky tap, whether
the game is won -- is derived from that set and the list of taps made on it.

Two things here are worth reading before the code.

**The mines are not in the saved file.** What is saved is a seed and the tap
that started the game, and the same few lines put the same mines back. That is
partly because it is smaller, and mostly because a file holding the answer is a
file somebody can read: this game is played on a device where the save is a JSON
file in the home directory, and a person who gets stuck at two in the morning
should have to want it rather badly. The shuffle is written out here rather than
taken from `random.sample`, because reproducing a layout a month later means
depending on an algorithm that is promised not to change, and the one thing
CPython does promise not to change is the stream out of `random.random()`.

**The first tap is never a mine, and never a number either.** Every mine is
placed after it, avoiding the cell tapped and all eight around it, so the first
tap always opens a space and floods. A first tap that ends the game is the
oldest complaint about this game and it was fixed decades ago; a first tap that
opens a lone 4 in the middle of a blank board is the same complaint wearing a
hat, and this avoids both for the cost of eight extra exclusions.

Nothing here imports GTK.
"""

from __future__ import annotations

import random
from dataclasses import dataclass

# What a tap did. Three actions, because chording -- tapping a number that has
# all its flags to open everything else around it -- is a move in its own right
# and not a shorthand for several opens: replaying it has to re-derive what it
# opened, since the board it lands on may differ by a flag.
OPEN = 0
FLAG = 1
CHORD = 2
ACTIONS = (OPEN, FLAG, CHORD)


@dataclass(frozen=True)
class Level:
    key: str
    label: str
    width: int
    height: int
    mines: int

    @property
    def cells(self) -> int:
        return self.width * self.height

    @property
    def density(self) -> float:
        return self.mines / self.cells


# Shaped for a phone rather than for a desktop. The classic three are 9x9,
# 16x16 and 30x16, and the last of those is twice as wide as a phone screen --
# so these are taller than they are wide, with the column count chosen so that a
# cell never falls below 28px on a 360px screen. The mine densities are the
# classic ones: about one cell in eight, one in six, one in five.
LEVELS = (
    Level("gentle", "Gentle", 8, 10, 10),
    Level("standard", "Standard", 10, 13, 22),
    Level("hard", "Hard", 12, 16, 40),
)
LEVEL_KEYS = tuple(level.key for level in LEVELS)
DEFAULT_LEVEL = "standard"


def level_for(key: str) -> Level:
    for level in LEVELS:
        if level.key == key:
            return level
    return LEVELS[1]


def row_column(cell: int, width: int) -> tuple[int, int]:
    return divmod(cell, width)


def index(row: int, column: int, width: int) -> int:
    return row * width + column


def around(cell: int, width: int, height: int) -> list[int]:
    """The eight cells touching this one, minus whatever is off the board."""
    row, column = row_column(cell, width)
    out = []
    for dr in (-1, 0, 1):
        for dc in (-1, 0, 1):
            if dr == 0 and dc == 0:
                continue
            r, c = row + dr, column + dc
            if 0 <= r < height and 0 <= c < width:
                out.append(index(r, c, width))
    return out


def _shuffled(items: list[int], rng: random.Random) -> list[int]:
    """Fisher-Yates on top of random(), and nothing else.

    Written out rather than calling `random.shuffle` or `random.sample` for one
    reason: the saved game is a seed, so a layout has to come back the same in
    six months and on another machine. CPython promises that `random.random()`
    keeps producing the same stream; it promises nothing about how sample() or
    shuffle() are implemented on top of it, and both have changed before.
    """
    out = list(items)
    for at in range(len(out) - 1, 0, -1):
        swap = int(rng.random() * (at + 1))
        out[at], out[swap] = out[swap], out[at]
    return out


def place(level: Level, seed: int, first: int) -> frozenset[int]:
    """Where the mines go, once the first tap has said where they may not.

    The first cell and all eight around it are excluded, so the first tap always
    opens a space and floods outward. On a board where the mines would not fit
    in what is left -- which no shipped level comes near -- the exclusion is
    narrowed to the tapped cell alone rather than failing.
    """
    forbidden = {first, *around(first, level.width, level.height)}
    available = [cell for cell in range(level.cells) if cell not in forbidden]
    if len(available) < level.mines:
        available = [cell for cell in range(level.cells) if cell != first]
    rng = random.Random(seed)
    return frozenset(_shuffled(available, rng)[: level.mines])


@dataclass(frozen=True)
class Field:
    """A board and where the mines are. Nothing about what has been tapped."""

    level: Level
    mines: frozenset[int]

    def is_mine(self, cell: int) -> bool:
        return cell in self.mines

    def count(self, cell: int) -> int:
        """How many mines touch this cell. The number that gets drawn on it."""
        width, height = self.level.width, self.level.height
        return sum(1 for near in around(cell, width, height) if near in self.mines)

    def neighbours(self, cell: int) -> list[int]:
        return around(cell, self.level.width, self.level.height)


class Game:
    """A field and the taps made on it.

    The taps are the state. The board is derived by replaying them, which costs
    a few hundred set operations and buys what it buys everywhere else in this
    repository: undo is a pop, the saved file is small integers, and a board
    that could not have arisen from legal play cannot be loaded, because loading
    is playing.

    Undo is deliberately *not* offered to the player here -- see window.py --
    but the replay is what makes the file safe, so it is built the same way.
    """

    def __init__(self, level: Level, seed: int, moves=()) -> None:
        self.level = level
        self.seed = seed
        self.moves: list[int] = []
        self.field: Field | None = None
        self.opened: set[int] = set()
        self.flags: set[int] = set()
        self.boom: int = -1
        for move in moves:
            if not self._apply(move):
                break

    @classmethod
    def resume(cls, level: Level, seed: int, moves) -> Game:
        """As much of a recorded game as will legally play."""
        clean = [m for m in moves if isinstance(m, int) and not isinstance(m, bool)]
        return cls(level, seed, clean)

    # --- moves as integers -------------------------------------------------

    @staticmethod
    def encode(cell: int, action: int) -> int:
        return cell * len(ACTIONS) + action

    @staticmethod
    def decode(move: int) -> tuple[int, int]:
        return divmod(move, len(ACTIONS))

    def _apply(self, move: int) -> bool:
        if move < 0:
            return False
        cell, action = self.decode(move)
        if not 0 <= cell < self.level.cells or action not in ACTIONS:
            return False
        if self.over:
            return False
        changed = (
            self._open(cell)
            if action == OPEN
            else self._flag(cell)
            if action == FLAG
            else self._chord(cell)
        )
        if not changed:
            return False
        self.moves.append(move)
        return True

    # --- playing -----------------------------------------------------------

    def tap(self, cell: int) -> bool:
        return self._apply(self.encode(cell, OPEN))

    def mark(self, cell: int) -> bool:
        return self._apply(self.encode(cell, FLAG))

    def clear_around(self, cell: int) -> bool:
        return self._apply(self.encode(cell, CHORD))

    def _start(self, first: int) -> None:
        self.field = Field(self.level, place(self.level, self.seed, first))

    def _open(self, cell: int) -> bool:
        if cell in self.opened or cell in self.flags:
            # A flagged cell is not opened by a tap, and that is not a
            # convenience: the flag is there precisely to stop the tap that is
            # about to happen by accident.
            return False
        if self.field is None:
            self._start(cell)
        field = self.field
        if field.is_mine(cell):
            self.opened.add(cell)
            self.boom = cell
            return True
        self._flood(cell)
        return True

    def _flood(self, cell: int) -> None:
        """Open this cell, and everything an empty one leads to.

        Iterative rather than recursive. A first tap on a gentle board opens
        forty cells and on a hard one can open a hundred and fifty, and a
        recursion that deep is a stack nobody needs to spend.
        """
        field = self.field
        stack = [cell]
        while stack:
            here = stack.pop()
            if here in self.opened or here in self.flags:
                continue
            self.opened.add(here)
            if field.count(here) == 0:
                stack.extend(
                    near for near in field.neighbours(here) if near not in self.opened
                )

    def _flag(self, cell: int) -> bool:
        if cell in self.opened:
            return False
        if cell in self.flags:
            self.flags.discard(cell)
        else:
            self.flags.add(cell)
        return True

    def _chord(self, cell: int) -> bool:
        """Open everything round a number that already has its flags.

        The move that makes this game playable at speed, and the one that makes
        it playable at all on a 28px cell: once the flags are down, clearing the
        rest of a number is one tap rather than five aimed ones.

        It opens nothing when the flags do not add up. That is not politeness --
        it is the difference between a move and a gamble, and a gamble that ends
        the game is not something a thumb should be able to do by resting on a
        number.
        """
        if self.field is None or cell not in self.opened:
            return False
        field = self.field
        wanted = field.count(cell)
        if wanted == 0:
            return False
        near = field.neighbours(cell)
        if sum(1 for c in near if c in self.flags) != wanted:
            return False
        shut = [c for c in near if c not in self.flags and c not in self.opened]
        if not shut:
            return False
        for target in shut:
            if field.is_mine(target):
                self.opened.add(target)
                self.boom = target
                return True
            self._flood(target)
        return True

    # --- how it is going ---------------------------------------------------

    @property
    def started(self) -> bool:
        return self.field is not None

    @property
    def lost(self) -> bool:
        return self.boom >= 0

    @property
    def won(self) -> bool:
        if self.field is None or self.lost:
            return False
        return len(self.opened) == self.level.cells - self.level.mines

    @property
    def over(self) -> bool:
        return self.lost or self.won

    @property
    def remaining(self) -> int:
        """Mines minus flags. It can go negative, and it is allowed to.

        Clamping it at zero would be hiding the most useful thing it ever says,
        which is that you have put down more flags than there are mines and one
        of them is wrong.
        """
        return self.level.mines - len(self.flags)

    def count(self, cell: int) -> int:
        return 0 if self.field is None else self.field.count(cell)

    def is_mine(self, cell: int) -> bool:
        return self.field is not None and self.field.is_mine(cell)

    def wrong_flags(self) -> set[int]:
        """Flags on cells with no mine under them. Only shown once it is over."""
        if self.field is None:
            return set()
        return {cell for cell in self.flags if not self.field.is_mine(cell)}

    def hidden_mines(self) -> set[int]:
        if self.field is None:
            return set()
        return {cell for cell in self.field.mines if cell not in self.flags}

    def satisfied(self, cell: int) -> bool:
        """Is this number ready to be chorded? What the widget draws a hint on."""
        if self.field is None or cell not in self.opened:
            return False
        wanted = self.field.count(cell)
        if wanted == 0:
            return False
        near = self.field.neighbours(cell)
        if sum(1 for c in near if c in self.flags) != wanted:
            return False
        return any(c not in self.flags and c not in self.opened for c in near)
