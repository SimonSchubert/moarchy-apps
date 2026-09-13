"""The rules of tic-tac-toe, as two nine-bit integers.

A board is nine squares and a mark is either there or it is not, so a whole
position is two integers -- one bit per square per mark -- and "has this side
won" is eight ands against eight constants. That is the same trick Reversi's
board uses and it is worth less here, because nothing in this game is big
enough to be slow. It is kept because it makes the *rules* small: a win is a
mask, a legal move is an empty bit, and there is no square-by-square walk
anywhere in the file for somebody to get the bounds wrong in.

Bit 0 is the top-left corner and the index grows left to right then top to
bottom, so square (row, column) is row * 3 + column. That matches how the board
is drawn and how a person reads one.

There is no pass. Every turn in this game has a move until the board is full or
the game is already won, which is the one simplification tic-tac-toe genuinely
buys over the other board games in this repository -- Reversi has to record its
passes in the move list, and this does not.

Nothing here imports GTK. The rules and the opponent are covered by tests on any
machine with a Python, which is where rules actually get checked.
"""

from __future__ import annotations

from dataclasses import dataclass

SIZE = 3
CELLS = SIZE * SIZE
FULL = (1 << CELLS) - 1

# Named for the shapes rather than for the letters, which is worth the extra
# characters twice over: `O` on its own is a variable name half the linters in
# the world will not have -- it is the one letter that is also a digit -- and
# "noughts and crosses" is what this game is called everywhere the app is not
# abbreviating itself in a window title.
CROSS = 0
NOUGHT = 1
MARKS = (CROSS, NOUGHT)
NAMES = {CROSS: "X", NOUGHT: "O"}


def other(mark: int) -> int:
    return NOUGHT if mark == CROSS else CROSS


def index(row: int, column: int) -> int:
    return row * SIZE + column


def row_column(cell: int) -> tuple[int, int]:
    return divmod(cell, SIZE)


def cells(board: int):
    """The square indices set in a bitboard, lowest first."""
    while board:
        low = board & -board
        yield low.bit_length() - 1
        board ^= low


def _line(*squares: int) -> tuple[int, tuple[int, ...]]:
    mask = 0
    for square in squares:
        mask |= 1 << square
    return mask, squares


# The eight ways to win, each as the mask that tests it and the three squares
# that draw it. The squares travel with the mask rather than being recovered
# from it afterwards, because the line is struck through on screen and a stroke
# needs its two ends in order -- which `cells()` would give back sorted, turning
# every diagonal into whichever direction the bit order happens to be.
LINES = (
    _line(0, 1, 2),
    _line(3, 4, 5),
    _line(6, 7, 8),
    _line(0, 3, 6),
    _line(1, 4, 7),
    _line(2, 5, 8),
    _line(0, 4, 8),
    _line(2, 4, 6),
)

CENTRE = 4
CORNERS = (0, 2, 6, 8)
EDGES = (1, 3, 5, 7)


def won_line(marks: int) -> tuple[int, ...] | None:
    """The three squares this side has in a row, if it has three in a row."""
    for mask, squares in LINES:
        if marks & mask == mask:
            return squares
    return None


@dataclass(frozen=True)
class Position:
    """A board and whose turn it is. Immutable, so a search can hold one.

    Frozen on purpose, for the two reasons it is frozen in Reversi: the search
    walks every position this game has and an undo replays from an empty board.
    Both are trivially correct when playing a move returns a new position, and
    the second is what makes the saved file a move list rather than a picture of
    a board.
    """

    x: int = 0
    o: int = 0
    turn: int = CROSS

    @property
    def own(self) -> int:
        return self.x if self.turn == CROSS else self.o

    @property
    def opp(self) -> int:
        return self.o if self.turn == CROSS else self.x

    def marks(self, mark: int) -> int:
        return self.x if mark == CROSS else self.o

    def occupied(self) -> int:
        return self.x | self.o

    def moves(self) -> int:
        """Every empty square, as a bitboard -- unless the game is already won.

        A won board has no legal moves on it even though it has empty squares,
        and saying so here is what stops the rest of the app from having to ask
        two questions where one will do.
        """
        if self.winner() is not None:
            return 0
        return FULL & ~self.occupied()

    def legal(self) -> list[int]:
        return list(cells(self.moves()))

    def is_legal(self, cell: int) -> bool:
        return 0 <= cell < CELLS and bool(self.moves() & (1 << cell))

    def play(self, cell: int) -> Position:
        """The position after this move. Raises on an illegal one."""
        if not self.is_legal(cell):
            raise ValueError(f"square {cell} is not a legal move")
        placed = self.own | (1 << cell)
        other = NOUGHT if self.turn == CROSS else CROSS
        if self.turn == CROSS:
            return Position(placed, self.o, other)
        return Position(self.x, placed, other)

    def winner(self) -> int | None:
        """The mark with three in a row, or None.

        Both sides are tested rather than only the one that just moved: this is
        asked of positions that arrive from a file as well as from a move, and a
        file is not a promise about which side made the last mark.
        """
        for mark in MARKS:
            if won_line(self.marks(mark)) is not None:
                return mark
        return None

    def winning_line(self) -> tuple[int, ...]:
        winner = self.winner()
        return () if winner is None else (won_line(self.marks(winner)) or ())

    def is_full(self) -> bool:
        return self.occupied() == FULL

    def is_over(self) -> bool:
        return self.winner() is not None or self.is_full()

    def played(self) -> int:
        return self.occupied().bit_count()

    def wins_now(self, mark: int) -> list[int]:
        """The empty squares that would give `mark` three in a row at once.

        Used by the easier levels, which are defined by what they *do* see
        rather than by how deep they look -- see ai.py.
        """
        marks = self.marks(mark)
        empty = FULL & ~self.occupied()
        return [cell for cell in cells(empty) if won_line(marks | (1 << cell))]


EMPTY = Position()


@dataclass(frozen=True)
class Play:
    """What one move did, for the widget that has to animate it."""

    cell: int
    mark: int
    line: tuple[int, ...] = ()


class Game:
    """A game as the list of moves that made it.

    The list is the state. The board is derived by replaying it, which costs
    nine applications of the rules above and buys three things worth more:
    undo is a pop, the saved file is a line of digits a person can read, and a
    board that could not have arisen from legal play cannot be loaded, because
    loading is playing.
    """

    def __init__(self, moves: list[int] | tuple[int, ...] = ()) -> None:
        self.moves: list[int] = []
        self.position = EMPTY
        for cell in moves:
            if not self._apply(cell):
                raise ValueError(f"square {cell} does not belong to this game")

    @classmethod
    def resume(cls, moves) -> Game:
        """As much of a recorded game as will legally play.

        Where a file stops making sense is where the game stops. Anything else
        that could be done with the rest is a guess, and a guess here is a board
        nobody played.
        """
        game = cls()
        for cell in moves:
            if not game._apply(cell):
                break
        return game

    def _apply(self, cell: int) -> bool:
        if not self.position.is_legal(cell):
            return False
        self.position = self.position.play(cell)
        self.moves.append(cell)
        return True

    # --- playing ---------------------------------------------------------

    def play(self, cell: int) -> Play:
        mark = self.position.turn
        self.position = self.position.play(cell)
        self.moves.append(cell)
        return Play(cell, mark, self.position.winning_line())

    @property
    def turn(self) -> int:
        return self.position.turn

    @property
    def over(self) -> bool:
        return self.position.is_over()

    def last_move(self) -> int | None:
        return self.moves[-1] if self.moves else None

    # --- taking it back --------------------------------------------------

    def undo(self) -> bool:
        if not self.moves:
            return False
        self.moves.pop()
        self._replay()
        return True

    def takeback(self, mark: int) -> bool:
        """Rewind until `mark` is on move again, with something undone.

        A phone is a device played on with one thumb on a bus, and the tap that
        lands one square off is the ordinary case rather than the strange one.
        Undoing a single ply would hand the board back with the computer's reply
        still on it, which is not what anybody means by undo.
        """
        undone = False
        while self.moves:
            if not self.undo():
                break
            undone = True
            if self.position.turn == mark:
                break
        return undone

    def _replay(self) -> None:
        moves, self.moves, self.position = self.moves, [], EMPTY
        for cell in moves:
            self._apply(cell)
