"""The rules of Reversi, as two 64-bit integers.

A board is 64 squares, and 64 is the one width a Python int is unreasonably good
at: a whole position is two integers -- one bit per square per colour -- and
every legal move on the board is found with a handful of shifts and masks over
both of them, rather than by walking 64 squares times 8 directions times 7
steps in interpreted bytecode.

That is not a micro-optimisation dressed up as an argument. The opponent in this
app is a search, and a search is worth exactly as many positions per second as
the rules can be applied; on the A53 in a PinePhone the obvious
square-by-square implementation manages a few hundred a second and this one
manages tens of thousands. The gap is the difference between a computer that
plays badly and one worth beating, on a machine where a second of thinking is a
second of the battery.

Bit 0 is a1 and the index grows left to right then top to bottom, so square
(row, column) is row * 8 + column. Othello numbers its rows from the top, which
is what `notation` does -- a1 is the top-left corner, not the bottom-left one a
chess player would expect.

Nothing here imports GTK. That is what makes every rule in this file testable on
any machine with a Python, which is where the rules actually get checked.
"""

from __future__ import annotations

from dataclasses import dataclass

SIZE = 8
CELLS = SIZE * SIZE
FULL = (1 << CELLS) - 1

DARK = 0
LIGHT = 1
COLOURS = (DARK, LIGHT)
NAMES = {DARK: "Dark", LIGHT: "Light"}

# A pass is recorded in the move list like any other turn. It has to be: the
# list is the whole saved game, and a replay that silently invented its own
# passes would be a second implementation of the rule, in the loader.
PASS = -1

# Shifting a bitboard moves every disc on it one square at once. The mask is
# what stops a step wrapping round the edge -- a disc on the h file shifted east
# lands on the a file of the next rank, which is east of nothing.
NOT_A_FILE = 0xFEFEFEFEFEFEFEFE  # every square but the first column
NOT_H_FILE = 0x7F7F7F7F7F7F7F7F  # every square but the last

# (shift, mask), one per direction. A positive shift moves down the board.
# Anything moving east cannot land on the a file; anything moving west cannot
# land on the h file; straight up and down cannot wrap at all.
DIRECTIONS = (
    (1, NOT_A_FILE),  # east
    (-1, NOT_H_FILE),  # west
    (8, FULL),  # south
    (-8, FULL),  # north
    (9, NOT_A_FILE),  # south-east
    (-9, NOT_H_FILE),  # north-west
    (7, NOT_H_FILE),  # south-west
    (-7, NOT_A_FILE),  # north-east
)

# The longest line of enemy discs that can sit between the disc played and the
# disc closing the line: eight squares, minus the two at the ends.
MAX_RUN = SIZE - 2

CORNERS = (1 << 0) | (1 << 7) | (1 << 56) | (1 << 63)


def index(row: int, column: int) -> int:
    return row * SIZE + column


def row_column(cell: int) -> tuple[int, int]:
    return divmod(cell, SIZE)


def notation(cell: int) -> str:
    """d3, or `--` for a pass. For the file, the tests and the screen reader."""
    if cell == PASS:
        return "--"
    row, column = row_column(cell)
    return f"{chr(ord('a') + column)}{row + 1}"


def cells(board: int):
    """The square indices set in a bitboard, lowest first."""
    while board:
        low = board & -board
        yield low.bit_length() - 1
        board ^= low


def _slide(board: int, shift: int, mask: int) -> int:
    return ((board << shift) if shift > 0 else (board >> -shift)) & mask


def legal_moves(own: int, opp: int) -> int:
    """Every square the side holding `own` may play, as a bitboard.

    One direction at a time: step off our own discs onto theirs, keep stepping
    while theirs continue, and the empty square after that run is a move. The
    run is grown for the whole board at once, which is why this is six
    iterations of eight directions rather than sixty-four separate walks.
    """
    empty = FULL & ~(own | opp)
    moves = 0
    for shift, mask in DIRECTIONS:
        run = _slide(own, shift, mask) & opp
        for _ in range(MAX_RUN - 1):
            run |= _slide(run, shift, mask) & opp
        moves |= _slide(run, shift, mask) & empty
    return moves


def flips(own: int, opp: int, cell: int) -> int:
    """The discs that playing `cell` turns over, as a bitboard.

    The mirror image of the scan above, walked out from the square played: a run
    of enemy discs flips only if one of ours is sitting at the end of it. A run
    that reaches an empty square or the edge flips nothing, which is the whole
    rule.
    """
    played = 1 << cell
    turned = 0
    for shift, mask in DIRECTIONS:
        run = _slide(played, shift, mask) & opp
        for _ in range(MAX_RUN - 1):
            run |= _slide(run, shift, mask) & opp
        if _slide(run, shift, mask) & own:
            turned |= run
    return turned


@dataclass(frozen=True)
class Position:
    """A board and whose turn it is. Immutable, so a search can hold one.

    Frozen on purpose: the AI walks thousands of positions and an undo replays
    the game from the opening. Both are trivially correct when playing a move
    returns a new position and impossible to get wrong in the same way when it
    mutates one.
    """

    dark: int
    light: int
    turn: int = DARK

    @property
    def own(self) -> int:
        return self.dark if self.turn == DARK else self.light

    @property
    def opp(self) -> int:
        return self.light if self.turn == DARK else self.dark

    def discs(self, colour: int) -> int:
        return self.dark if colour == DARK else self.light

    def moves(self) -> int:
        return legal_moves(self.own, self.opp)

    def legal(self) -> list[int]:
        return list(cells(self.moves()))

    def is_legal(self, cell: int) -> bool:
        return 0 <= cell < CELLS and bool(self.moves() & (1 << cell))

    def play(self, cell: int) -> Position:
        """The position after this move. Raises on an illegal one."""
        if not self.is_legal(cell):
            raise ValueError(f"{notation(cell)} is not a legal move")
        turned = flips(self.own, self.opp, cell)
        own = self.own | turned | (1 << cell)
        opp = self.opp & ~turned
        other = LIGHT if self.turn == DARK else DARK
        if self.turn == DARK:
            return Position(own, opp, other)
        return Position(opp, own, other)

    def flipped_by(self, cell: int) -> list[int]:
        return list(cells(flips(self.own, self.opp, cell)))

    def passed(self) -> Position:
        return Position(self.dark, self.light, LIGHT if self.turn == DARK else DARK)

    def must_pass(self) -> bool:
        """No move for the side to play, but the game is not over."""
        return not self.moves() and bool(legal_moves(self.opp, self.own))

    def is_over(self) -> bool:
        """Neither side can move -- which is not the same as a full board.

        A game can end with empty squares on it, and does often enough that
        counting squares instead of moves is a bug people actually ship.
        """
        return not self.moves() and not legal_moves(self.opp, self.own)

    def count(self, colour: int) -> int:
        return self.discs(colour).bit_count()

    def counts(self) -> tuple[int, int]:
        return self.dark.bit_count(), self.light.bit_count()

    def empties(self) -> int:
        return CELLS - (self.dark | self.light).bit_count()

    def winner(self) -> int | None:
        """The colour ahead, or None for a draw. Only meaningful once over."""
        dark, light = self.counts()
        if dark == light:
            return None
        return DARK if dark > light else LIGHT


# d4 and e5 light, e4 and d5 dark, dark to play. The one opening every set of
# rules agrees on.
OPENING = Position(
    dark=(1 << index(3, 4)) | (1 << index(4, 3)),
    light=(1 << index(3, 3)) | (1 << index(4, 4)),
    turn=DARK,
)


@dataclass(frozen=True)
class Play:
    """What one move did, for the widget that has to animate it."""

    cell: int
    flipped: tuple[int, ...]
    passes: int = 0


class Game:
    """A game as the list of moves that made it.

    The list is the state. The board is derived from it by replaying the
    opening, which costs sixty applications of the rules above -- microseconds --
    and buys three things worth more than that: undo is a pop, the saved file is
    a line of small integers a person can read, and a board that could not have
    arisen from legal play cannot be loaded, because loading *is* playing.
    """

    def __init__(self, moves: list[int] | tuple[int, ...] = ()) -> None:
        self.moves: list[int] = []
        self.position = OPENING
        for cell in moves:
            if not self._apply(cell):
                raise ValueError(f"{notation(cell)} does not belong to this game")

    @classmethod
    def resume(cls, moves) -> Game:
        """As much of a recorded game as will legally play.

        Where a file stops making sense is where the game stops. Nothing else
        can be done with the rest that is not a guess, and a guess here is a
        board somebody never played.
        """
        game = cls()
        for cell in moves:
            if not game._apply(cell):
                break
        return game

    def _apply(self, cell: int) -> bool:
        """Replay one recorded turn exactly as recorded. False if it will not.

        Deliberately without the courtesy pass that `play` adds: a recorded game
        already has its passes written down, and a replay that inserted its own
        would insert them twice.
        """
        if cell == PASS:
            if not self.position.must_pass():
                return False
            self.position = self.position.passed()
        else:
            if not self.position.is_legal(cell):
                return False
            self.position = self.position.play(cell)
        self.moves.append(cell)
        return True

    # --- playing ---------------------------------------------------------

    def play(self, cell: int) -> Play:
        """Play a move, then pass for whoever cannot answer it.

        The pass is applied here rather than left to the caller because a
        position where the side to move has nothing to do is not a state any
        part of the UI should ever see: it would draw a board with no hints on
        it and wait for a tap that cannot come.
        """
        turned = tuple(self.position.flipped_by(cell))
        self.position = self.position.play(cell)
        self.moves.append(cell)
        passes = 0
        while self.position.must_pass():
            self.position = self.position.passed()
            self.moves.append(PASS)
            passes += 1
        return Play(cell, turned, passes)

    @property
    def turn(self) -> int:
        return self.position.turn

    @property
    def over(self) -> bool:
        return self.position.is_over()

    def last_move(self) -> int | None:
        for cell in reversed(self.moves):
            if cell != PASS:
                return cell
        return None

    # --- taking it back --------------------------------------------------

    def undo(self) -> bool:
        """Take back one move, and any passes that followed it."""
        while self.moves and self.moves[-1] == PASS:
            self.moves.pop()
        if not self.moves:
            return False
        self.moves.pop()
        self._replay()
        return True

    def takeback(self, colour: int) -> bool:
        """Rewind until `colour` is on move again, with something undone.

        A phone is a device you play on with one thumb on a bus, and the tap
        that lands one square off is the ordinary case rather than the strange
        one. Undoing a single ply would hand the board back with the computer's
        reply still on it, which is not what anyone means by undo -- so this
        keeps going until it is genuinely your turn again.
        """
        undone = False
        while self.moves:
            if not self.undo():
                break
            undone = True
            if self.position.turn == colour and not self.position.must_pass():
                break
        return undone

    def _replay(self) -> None:
        moves, self.moves, self.position = self.moves, [], OPENING
        for cell in moves:
            self._apply(cell)
