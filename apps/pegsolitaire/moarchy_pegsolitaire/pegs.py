"""The rules of peg solitaire, as one integer and a board to put it on.

A board is a 7x7 grid with the corners cut off, so a whole position is a single
49-bit integer -- one bit per hole -- and a jump is three bits: a peg, a peg next
to it, and a hole after that. The board itself is a second integer, which is
what lets the English cross and the European octagon be the same code with
different data.

Bit 0 is the top-left corner of the 7x7 grid and the index grows left to right
then top to bottom, so hole (row, column) is row * 7 + column. Holes that are
not on the board are simply never set in either integer.

A move is one small integer too: `cell * 4 + direction`, where the four
directions are up, down, left and right in that order. That is what goes in the
file -- a jump is fully described by where it starts and which way it goes, and
recording the landing hole as well would be recording something the rules
already know, which is a second chance to disagree with them.

The figures at the bottom are the app's actual content. Peg solitaire with all
thirty-two pegs is one puzzle; the same board with fourteen pegs in the shape of
an arrow is another, and they cost a string each.

Nothing here imports GTK.
"""

from __future__ import annotations

from dataclasses import dataclass

SIZE = 7
CELLS = SIZE * SIZE

CENTRE = (SIZE // 2) * SIZE + SIZE // 2

UP, DOWN, LEFT, RIGHT = 0, 1, 2, 3
DIRECTIONS = (UP, DOWN, LEFT, RIGHT)
# (row step, column step), in the order above.
STEPS = ((-1, 0), (1, 0), (0, -1), (0, 1))
ARROWS = ("up", "down", "left", "right")


def index(row: int, column: int) -> int:
    return row * SIZE + column


def row_column(cell: int) -> tuple[int, int]:
    return divmod(cell, SIZE)


def cells(board: int):
    """The hole indices set in a mask, lowest first."""
    while board:
        low = board & -board
        yield low.bit_length() - 1
        board ^= low


def parse(art: str) -> tuple[int, int]:
    """A picture of a board, as (holes, pegs).

    `o` is a peg, `.` is an empty hole, and anything else is not part of the
    board. Written as art because that is what these are: a person reading this
    file should be able to see the cross, and a person adding a figure should be
    able to draw one.
    """
    holes = pegs = 0
    rows = [line for line in art.strip("\n").splitlines() if line.strip()]
    for row, line in enumerate(rows[:SIZE]):
        for column, glyph in enumerate(line[:SIZE]):
            if glyph not in ("o", "."):
                continue
            bit = 1 << index(row, column)
            holes |= bit
            if glyph == "o":
                pegs |= bit
    return holes, pegs


def _step_mask(direction: int, distance: int) -> int:
    """Every hole a jump in this direction can start from without leaving the
    grid. Shifting a bitboard wraps rows into each other, and this is what stops
    a peg on the right edge jumping onto the left edge of the next row."""
    down, across = STEPS[direction]
    mask = 0
    for row in range(SIZE):
        for column in range(SIZE):
            if (
                0 <= row + down * distance < SIZE
                and 0 <= column + across * distance < SIZE
            ):
                mask |= 1 << index(row, column)
    return mask


def _shift(direction: int, distance: int) -> int:
    down, across = STEPS[direction]
    return down * SIZE * distance + across * distance


# Precomputed once: for each direction, how far a bitboard moves and which bits
# may move at all. Four shifts and four masks is the whole of the geometry.
JUMPS = tuple(
    (_shift(d, 1), _step_mask(d, 1), _shift(d, 2), _step_mask(d, 2)) for d in DIRECTIONS
)


def _slide(board: int, shift: int) -> int:
    return (board << shift) if shift > 0 else (board >> -shift)


def encode(cell: int, direction: int) -> int:
    return cell * len(DIRECTIONS) + direction


def decode(move: int) -> tuple[int, int]:
    return divmod(move, len(DIRECTIONS))


def notation(move: int) -> str:
    """`d4 up`, for the file, the tests and the screen reader."""
    cell, direction = decode(move)
    row, column = row_column(cell)
    return f"{chr(ord('a') + column)}{row + 1} {ARROWS[direction]}"


@dataclass(frozen=True)
class Position:
    """The pegs, and the board they are on. Immutable, so a search can hold one.

    The board travels with the pegs rather than sitting in a global, because the
    English cross and the European octagon are the same rules on different holes
    and a solver that had to be told which one it was looking at would be a
    solver with a second argument to get wrong.
    """

    holes: int
    pegs: int

    @property
    def empty(self) -> int:
        return self.holes & ~self.pegs

    @property
    def count(self) -> int:
        return self.pegs.bit_count()

    def has_peg(self, cell: int) -> bool:
        return bool(self.pegs >> cell & 1)

    def is_hole(self, cell: int) -> bool:
        return bool(self.holes >> cell & 1)

    def moves(self) -> list[int]:
        """Every legal jump, as encoded integers.

        A whole direction at a time: shift the pegs one step to find pairs, shift
        again to find where the pair could land. Four iterations of three shifts
        rather than thirty-three holes times four directions in bytecode.
        """
        out: list[int] = []
        empty = self.empty
        for direction in DIRECTIONS:
            over, over_mask, land, land_mask = JUMPS[direction]
            movable = self.pegs & over_mask & land_mask
            # A peg with a peg next to it...
            movable &= _slide(self.pegs, -over) if over else self.pegs
            # ...and an empty hole after that.
            movable &= _slide(empty, -land) if land else empty
            out.extend(encode(cell, direction) for cell in cells(movable))
        return sorted(out)

    def jumps_from(self, cell: int) -> list[int]:
        """The moves this particular peg may make. What a tap needs."""
        return [move for move in self.moves() if decode(move)[0] == cell]

    def is_legal(self, move: int) -> bool:
        cell, direction = decode(move)
        if not 0 <= cell < CELLS or direction not in DIRECTIONS:
            return False
        over, over_mask, land, land_mask = JUMPS[direction]
        bit = 1 << cell
        if not (self.pegs & bit & over_mask & land_mask):
            return False
        return bool(self.pegs & _slide(bit, over) and self.empty & _slide(bit, land))

    def landing(self, move: int) -> tuple[int, int]:
        """(the peg jumped over, the hole landed in) for a legal move."""
        cell, direction = decode(move)
        over, _, land, _ = JUMPS[direction]
        return cell + over, cell + land

    def play(self, move: int) -> Position:
        """The position after this jump. Raises on an illegal one."""
        if not self.is_legal(move):
            raise ValueError(f"{notation(move)} is not a legal jump")
        cell, _ = decode(move)
        over, landed = self.landing(move)
        pegs = self.pegs & ~(1 << cell) & ~(1 << over) | (1 << landed)
        return Position(self.holes, pegs)

    @property
    def stuck(self) -> bool:
        return not self.moves()

    @property
    def solved(self) -> bool:
        return self.count == 1

    def perfect(self, target: int) -> bool:
        """One peg, and it is in the middle."""
        return self.count == 1 and bool(self.pegs >> target & 1)


@dataclass(frozen=True)
class Figure:
    """A board, what is standing on it, and whether it can finish in the middle.

    `centre` is a claim about the figure and it is checked rather than asserted:
    `tests/test_solver.py` solves every figure here and fails if any of them
    cannot be reduced to one peg, or if this flag disagrees with whether that
    last peg can be made to land in the middle. A puzzle app that ships a figure
    nobody can finish is a puzzle app that is lying, and there is no way to
    notice by looking at a picture of one.
    """

    key: str
    label: str
    blurb: str
    art: str
    centre: bool

    @property
    def holes(self) -> int:
        return parse(self.art)[0]

    @property
    def pegs(self) -> int:
        return parse(self.art)[1]

    def start(self) -> Position:
        holes, pegs = parse(self.art)
        return Position(holes, pegs)

    @property
    def target(self) -> int:
        """The middle of the board, which is where a solution wants to finish.

        Every figure here is on a seven by seven grid and the middle of it is
        the same hole in all of them, so this is a constant rather than
        something derived. Finishing with one peg is the puzzle; finishing with
        it in the middle is the classic extra condition, and it is kept apart
        from the puzzle in the record for exactly that reason.
        """
        return CENTRE


# The English board: a 7x7 grid with the four 2x2 corners cut off, thirty-three
# holes. The European board rounds the corners off one hole at a time instead,
# giving thirty-seven -- which is the same game and a famously harder one,
# because thirty-six pegs on it cannot be reduced to one at all.
# Every figure here has been solved by the solver in `solver.py` before being
# shipped, and the test suite solves them again on every run. They are listed
# with the whole board first -- it is the one everybody means by peg solitaire
# -- and then by how many pegs they start with, which is near enough to how hard
# they are that nothing better is worth inventing.
FIGURES = (
    Figure(
        key="english",
        label="English board",
        blurb="Thirty-two pegs, the middle empty. The one everybody means.",
        centre=True,
        art="""
  ooo
  ooo
ooooooo
ooo.ooo
ooooooo
  ooo
  ooo
""",
    ),
    Figure(
        key="cross",
        label="Cross",
        blurb="Six pegs. The gentlest way in.",
        centre=False,
        art="""
  ...
  .o.
...o...
..ooo..
...o...
  ...
  ...
""",
    ),
    Figure(
        key="plus",
        label="Plus",
        blurb="Nine pegs, and eight jumps if you find them.",
        centre=True,
        art="""
  ...
  .o.
...o...
.ooooo.
...o...
  .o.
  ...
""",
    ),
    Figure(
        key="pyramid",
        label="Pyramid",
        blurb="Nine pegs stacked three deep, finishing in the middle.",
        centre=True,
        art="""
  ...
  ...
...o...
..ooo..
.ooooo.
  ...
  ...
""",
    ),
    Figure(
        key="hearth",
        label="Hearth",
        blurb="Twelve pegs. It looks easier than it is.",
        centre=False,
        art="""
  ...
  ...
..ooo..
.ooooo.
oo...oo
  ...
  ...
""",
    ),
    Figure(
        key="diamond",
        label="Diamond",
        blurb="Twelve pegs, symmetrical every way you look at it.",
        centre=True,
        art="""
  ...
  .o.
..ooo..
.oo.oo.
..ooo..
  .o.
  ...
""",
    ),
    Figure(
        key="arrow",
        label="Arrow",
        blurb="Thirteen pegs pointing the way out.",
        centre=False,
        art="""
  .o.
  ooo
.ooooo.
...o...
...o...
  .o.
  .o.
""",
    ),
    Figure(
        key="wall",
        label="Wall",
        blurb="Fourteen pegs in two rows, and nothing else on the board.",
        centre=False,
        art="""
  ...
  ...
ooooooo
ooooooo
.......
  ...
  ...
""",
    ),
    Figure(
        key="goblet",
        label="Goblet",
        blurb="Sixteen pegs, fifteen jumps, and it ends in the middle.",
        centre=True,
        art="""
  ...
  ...
ooooooo
.ooooo.
..ooo..
  .o.
  ...
""",
    ),
)
FIGURE_KEYS = tuple(figure.key for figure in FIGURES)
DEFAULT_FIGURE = "english"


def figure_for(key: str) -> Figure:
    for figure in FIGURES:
        if figure.key == key:
            return figure
    return FIGURES[0]


class Game:
    """A figure and the jumps made on it.

    The list is the state. The board is derived by replaying it, which costs one
    application of the rules per jump -- microseconds -- and buys three things:
    undo is a pop, the saved file is a line of small integers a person can read,
    and a board that could not have arisen from legal play cannot be loaded,
    because loading is playing.
    """

    def __init__(self, figure: Figure | str = DEFAULT_FIGURE, moves=()) -> None:
        self.figure = figure if isinstance(figure, Figure) else figure_for(figure)
        self.start = self.figure.start()
        self.position = self.start
        self.moves: list[int] = []
        for move in moves:
            if not self._apply(move):
                raise ValueError(f"{notation(move)} does not belong to this game")

    @classmethod
    def resume(cls, figure, moves) -> Game:
        """As much of a recorded game as will legally play."""
        game = cls(figure)
        for move in moves:
            if not isinstance(move, int) or isinstance(move, bool):
                break
            if not game._apply(move):
                break
        return game

    def _apply(self, move: int) -> bool:
        if not self.position.is_legal(move):
            return False
        self.position = self.position.play(move)
        self.moves.append(move)
        return True

    def play(self, move: int) -> bool:
        return self._apply(move)

    def undo(self) -> bool:
        if not self.moves:
            return False
        self.moves.pop()
        self._replay()
        return True

    def _replay(self) -> None:
        moves, self.moves, self.position = self.moves, [], self.start
        for move in moves:
            self._apply(move)

    @property
    def count(self) -> int:
        return self.position.count

    @property
    def over(self) -> bool:
        return self.position.stuck

    @property
    def solved(self) -> bool:
        return self.position.solved

    @property
    def perfect(self) -> bool:
        """One peg in the middle, on a figure where that is possible at all.

        Kept apart from `solved` because it is not an achievement on every
        figure: the Cross can be reduced to one peg and that peg can never be
        the middle one, so a game that told somebody they had nearly done it
        would be a game setting them a task with no answer.
        """
        return self.figure.centre and self.position.perfect(self.figure.target)

    def last_move(self) -> int | None:
        return self.moves[-1] if self.moves else None
