"""The rules of Nine Men's Morris, as two 24-bit integers.

The board is twenty-four points on three concentric squares, so a whole position
is two integers -- one bit per point per colour -- and "has this side made a
mill" is sixteen ands against sixteen constants. That is the same trick Reversi's
board uses and it matters here for the same reason: the opponent is a search,
and a search is worth exactly as many positions a second as the rules can be
applied.

The numbering is a ring and a place on it. Point `ring * 8 + place`, with the
rings running outer, middle, inner and the places running clockwise from the
top-left corner -- so the even places are corners and the odd ones are the
midpoints of the sides. That is worth the sentence it costs, because it makes
both halves of the adjacency fall out of arithmetic instead of a table somebody
has to check by eye: within a ring, a point touches `place ± 1`; between rings,
only the odd places connect, and they connect straight through.

The sixteen mills are the same shape. Four to a ring -- corner, midpoint, corner
-- and four across the rings at each odd place. Twelve plus four.

A turn is not always one move. Closing a mill earns a removal, and the removal
is a move in its own right with the same side still on turn: `removing` says so,
and the move list records it like anything else. Making it implicit would mean
the loader guessing which piece a recorded game had taken.

Nothing here imports GTK.
"""

from __future__ import annotations

from dataclasses import dataclass

RINGS = 3
PLACES = 8
POINTS = RINGS * PLACES

WHITE = 0
BLACK = 1
COLOURS = (WHITE, BLACK)
NAMES = {WHITE: "White", BLACK: "Black"}

# Nine pieces each, which is the name of the game.
PIECES = 9

# Below this a side has lost; at this a side may fly.
DEAD = 2
FLYING = 3


def point(ring: int, place: int) -> int:
    return ring * PLACES + place % PLACES


def ring_place(spot: int) -> tuple[int, int]:
    return divmod(spot, PLACES)


def _build_neighbours() -> tuple[tuple[int, ...], ...]:
    out: list[tuple[int, ...]] = []
    for spot in range(POINTS):
        ring, place = ring_place(spot)
        near = [point(ring, place - 1), point(ring, place + 1)]
        if place % 2 == 1:
            # Only the midpoints of the sides are joined between rings, and
            # they are joined straight through: outer to middle to inner.
            if ring > 0:
                near.append(point(ring - 1, place))
            if ring < RINGS - 1:
                near.append(point(ring + 1, place))
        out.append(tuple(sorted(near)))
    return tuple(out)


NEIGHBOURS = _build_neighbours()


def _build_mills() -> tuple[tuple[int, ...], ...]:
    out: list[tuple[int, ...]] = []
    for ring in range(RINGS):
        for corner in (0, 2, 4, 6):
            out.append(
                (point(ring, corner), point(ring, corner + 1), point(ring, corner + 2))
            )
    for place in (1, 3, 5, 7):
        out.append(tuple(point(ring, place) for ring in range(RINGS)))
    return tuple(out)


MILLS = _build_mills()
MILL_MASKS = tuple(sum(1 << spot for spot in mill) for mill in MILLS)
# Which mills a given point belongs to. Two each -- one in its ring, and either
# one across the rings (the midpoints) or a second in its ring (the corners).
MILLS_AT = tuple(
    tuple(index for index, mill in enumerate(MILLS) if spot in mill)
    for spot in range(POINTS)
)
NEIGHBOUR_MASKS = tuple(
    sum(1 << near for near in NEIGHBOURS[spot]) for spot in range(POINTS)
)

# A move is one integer. A placement or a removal is the point itself; a
# movement is the pair, offset past them so the two cannot be confused. That
# offset is the whole encoding, and it is what goes in the file.
MOVE_BASE = POINTS


def place_move(spot: int) -> int:
    return spot


def travel(src: int, dst: int) -> int:
    return MOVE_BASE + src * POINTS + dst


def is_travel(move: int) -> bool:
    return move >= MOVE_BASE


def unpack(move: int) -> tuple[int, int]:
    """(from, to) for a movement, or (-1, point) for a placement or removal."""
    if move < MOVE_BASE:
        return -1, move
    src, dst = divmod(move - MOVE_BASE, POINTS)
    return src, dst


def notation(move: int) -> str:
    """`c2` or `c2-b2`, for the tests and the screen reader.

    Rings are lettered from the outside in and places are numbered clockwise
    from the top-left corner, which is not the notation a Morris book uses --
    books use a chess-like grid -- and is the notation this board's own
    numbering produces without a lookup table to get wrong.
    """
    src, dst = unpack(move)
    if src < 0:
        return _spot_name(dst)
    return f"{_spot_name(src)}-{_spot_name(dst)}"


def _spot_name(spot: int) -> str:
    ring, place = ring_place(spot)
    return f"{'abc'[ring]}{place + 1}"


def spots(board: int):
    """The point indices set in a bitboard, lowest first."""
    while board:
        low = board & -board
        yield low.bit_length() - 1
        board ^= low


@dataclass(frozen=True)
class Position:
    """Everything about a board: the pieces, the turn, and what is owed.

    Immutable, for the reason every other board in this repository is: the
    search walks thousands of these and an undo replays the game from the start.
    Both are trivially correct when playing a move returns a new position.

    `placed` counts how many pieces each side has ever put down, which is what
    tells the placing phase from the moving one -- and it has to be carried,
    because a board with seven white pieces on it could be one mid-placement or
    one two captures into the endgame, and the rules for the two are different.
    """

    white: int = 0
    black: int = 0
    turn: int = WHITE
    placed: tuple[int, int] = (0, 0)
    # True when the side to move has just closed a mill and owes a removal.
    removing: bool = False

    # --- reading -----------------------------------------------------------

    @property
    def own(self) -> int:
        return self.white if self.turn == WHITE else self.black

    @property
    def opp(self) -> int:
        return self.black if self.turn == WHITE else self.white

    def men(self, colour: int) -> int:
        return self.white if colour == WHITE else self.black

    def count(self, colour: int) -> int:
        return self.men(colour).bit_count()

    def left(self, colour: int) -> int:
        """Pieces still to place. What the tray above the board is showing."""
        return PIECES - self.placed[colour]

    @property
    def empty(self) -> int:
        return ((1 << POINTS) - 1) & ~(self.white | self.black)

    def placing(self, colour: int) -> bool:
        return self.placed[colour] < PIECES

    def flying(self, colour: int) -> bool:
        """Down to three, and allowed to move anywhere.

        Only once the placing phase is over. A side that has three pieces on the
        board because it has placed three is not in trouble, it is in its first
        few turns, and letting it fly then would be a different game.
        """
        return not self.placing(colour) and self.count(colour) == FLYING

    def closes(self, colour: int, spot: int, without: int = -1) -> bool:
        """Would `colour` holding `spot` complete a mill?

        `without` is the point it is moving *off*, which has to be taken out
        first: a piece that slides along its own mill and back closes nothing,
        and a rule that forgot this would let one mill be closed forever.
        """
        men = self.men(colour) | (1 << spot)
        if without >= 0:
            men &= ~(1 << without)
        return any(
            men & MILL_MASKS[index] == MILL_MASKS[index] for index in MILLS_AT[spot]
        )

    def in_mill(self, colour: int, spot: int) -> bool:
        men = self.men(colour)
        return any(
            men & MILL_MASKS[index] == MILL_MASKS[index] for index in MILLS_AT[spot]
        )

    def mills(self, colour: int) -> int:
        men = self.men(colour)
        return sum(1 for mask in MILL_MASKS if men & mask == mask)

    # --- what may be done --------------------------------------------------

    def removable(self) -> list[int]:
        """Which of the other side's pieces may be taken.

        Not one that is in a mill -- unless every one of them is, which is the
        rule everybody forgets and which decides real games: without it a side
        that has walled itself into mills can never be touched.
        """
        other = BLACK if self.turn == WHITE else WHITE
        theirs = list(spots(self.men(other)))
        loose = [spot for spot in theirs if not self.in_mill(other, spot)]
        return loose or theirs

    def moves(self) -> list[int]:
        if self.removing:
            return [place_move(spot) for spot in self.removable()]
        if self.placing(self.turn):
            return [place_move(spot) for spot in spots(self.empty)]
        empty = self.empty
        out: list[int] = []
        if self.flying(self.turn):
            for src in spots(self.own):
                out.extend(travel(src, dst) for dst in spots(empty))
            return out
        for src in spots(self.own):
            out.extend(travel(src, dst) for dst in spots(empty & NEIGHBOUR_MASKS[src]))
        return out

    def is_legal(self, move: int) -> bool:
        return move in self.moves()

    def destinations(self, src: int) -> list[int]:
        """Where this piece may go. What a tap on it lights up."""
        if self.removing or self.placing(self.turn):
            return []
        if not self.own >> src & 1:
            return []
        empty = self.empty
        if self.flying(self.turn):
            return list(spots(empty))
        return list(spots(empty & NEIGHBOUR_MASKS[src]))

    # --- doing it ----------------------------------------------------------

    def play(self, move: int) -> Position:
        """The position after this move. Raises on an illegal one."""
        if not self.is_legal(move):
            raise ValueError(f"{notation(move)} is not a legal move")
        other = BLACK if self.turn == WHITE else WHITE
        src, dst = unpack(move)

        if self.removing:
            men = self.men(other) & ~(1 << dst)
            if self.turn == WHITE:
                white, black = self.white, men
            else:
                white, black = men, self.black
            return Position(white, black, other, self.placed, False)

        own = self.own
        placed = list(self.placed)
        if src < 0:
            own |= 1 << dst
            placed[self.turn] += 1
        else:
            own = (own & ~(1 << src)) | (1 << dst)
        white, black = (own, self.black) if self.turn == WHITE else (self.white, own)
        made = self.closes(self.turn, dst, without=src)
        after = Position(white, black, self.turn, tuple(placed), True)
        if made and after.removable():
            return after
        return Position(white, black, other, tuple(placed), False)

    # --- endings -----------------------------------------------------------

    def lost(self, colour: int) -> bool:
        """Has this side lost? Two pieces, or nowhere to go.

        Both conditions only bite once the placing phase is done. A side with
        one piece on the board in the opening has not lost, and a side that
        cannot move in the opening cannot happen, because placing always can.
        """
        if self.placing(colour):
            return False
        if self.count(colour) < FLYING:
            return True
        if self.turn != colour or self.removing:
            # "Nowhere to go" is only asked of the side on move. Asking it of
            # the other one calls a game over a turn before it is, which shows
            # up as a search that thinks every quiet position is winning.
            return False
        return not self.moves()

    @property
    def over(self) -> bool:
        return self.lost(WHITE) or self.lost(BLACK)

    def winner(self) -> int | None:
        if self.lost(WHITE):
            return BLACK
        if self.lost(BLACK):
            return WHITE
        return None


OPENING = Position()


@dataclass(frozen=True)
class Play:
    """What one move did, for the widget that has to animate it."""

    move: int
    colour: int
    src: int
    dst: int
    removed: int = -1
    mill: tuple[int, ...] = ()


# How many moves may pass in the moving phase with nothing taken before the game
# is called a draw. The standard tournament figure is fifty; two people shuffling
# pieces on a phone reach that in about a minute of tapping, and a game that
# cannot end is worse than one that ends level.
QUIET_LIMIT = 50


class Game:
    """A game as the list of moves that made it.

    The list is the state. The board is derived by replaying it, which costs a
    few hundred applications of the rules -- microseconds -- and buys three
    things: undo is a pop, the saved file is small integers a person can read,
    and a board that could not have arisen from legal play cannot be loaded,
    because loading is playing.
    """

    def __init__(self, moves=()) -> None:
        self.moves: list[int] = []
        self.position = OPENING
        self.quiet = 0
        for move in moves:
            if not self._apply(move):
                raise ValueError(f"{notation(move)} does not belong to this game")

    @classmethod
    def resume(cls, moves) -> Game:
        """As much of a recorded game as will legally play."""
        game = cls()
        for move in moves:
            if not isinstance(move, int) or isinstance(move, bool):
                break
            if not game._apply(move):
                break
        return game

    def _apply(self, move: int) -> bool:
        if not self.position.is_legal(move):
            return False
        before = self.position
        self.position = before.play(move)
        self.moves.append(move)
        if before.removing or before.placing(before.turn):
            self.quiet = 0
        else:
            self.quiet += 1
        return True

    # --- playing -----------------------------------------------------------

    def play(self, move: int) -> Play:
        before = self.position
        colour = before.turn
        src, dst = unpack(move)
        if not self._apply(move):
            raise ValueError(f"{notation(move)} is not a legal move")
        if before.removing:
            return Play(move, colour, -1, -1, removed=dst)
        mill = ()
        if self.position.removing:
            mill = self._mill_at(colour, dst)
        return Play(move, colour, src, dst, mill=mill)

    def _mill_at(self, colour: int, spot: int) -> tuple[int, ...]:
        men = self.position.men(colour)
        for index in MILLS_AT[spot]:
            if men & MILL_MASKS[index] == MILL_MASKS[index]:
                return MILLS[index]
        return ()

    @property
    def turn(self) -> int:
        return self.position.turn

    @property
    def drawn(self) -> bool:
        return not self.position.over and self.quiet >= QUIET_LIMIT

    @property
    def over(self) -> bool:
        return self.position.over or self.drawn

    def last_move(self) -> int | None:
        return self.moves[-1] if self.moves else None

    # --- taking it back ----------------------------------------------------

    def undo(self) -> bool:
        if not self.moves:
            return False
        self.moves.pop()
        self._replay()
        return True

    def takeback(self, colour: int) -> bool:
        """Rewind until `colour` is on move again, with something undone.

        A phone is a device played on with one thumb on a bus, and the tap that
        lands one point off is the ordinary case. Undoing a single ply would
        hand the board back with the computer's reply still on it -- and in this
        game a single ply is sometimes only half a turn, because a mill owes a
        removal.
        """
        undone = False
        while self.moves:
            if not self.undo():
                break
            undone = True
            if self.position.turn == colour and not self.position.removing:
                break
        return undone

    def _replay(self) -> None:
        moves, self.moves = self.moves, []
        self.position, self.quiet = OPENING, 0
        for move in moves:
            self._apply(move)
