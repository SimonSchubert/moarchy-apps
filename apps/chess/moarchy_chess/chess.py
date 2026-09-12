"""The rules of chess, on a list of sixty-four small integers.

Reversi keeps a position in two Python ints because a 64-square board is exactly
what a Python int is unreasonably good at. Chess cannot do that without six
bitboards a side and a magic-multiply attack generator, which is a thousand
lines to write and to test. So this is the other classic representation: one
flat list of 64 squares, every table it needs precomputed at import, and
*make/unmake on the list itself* rather than a new board per move.

That last part is the decision worth defending, because it is the one that the
obvious implementation gets wrong. Copying an 8x8 board per node costs a list
allocation and 64 writes; a search at depth four visits tens of thousands of
nodes, and on the A53 in a PinePhone that copying alone is the whole time
budget. Playing the move into the board and taking it back out again costs a
dozen writes and one small tuple, and the tuple -- `Made` -- turns out to be
worth having anyway: it is a complete description of what the move did, which
is what the animation needs and what the evaluation in `ai.py` needs to update
its score without looking at the board at all.

Squares run a1 = 0 to h8 = 63, so `square = rank * 8 + file` and flipping a
square to the other side's point of view is `square ^ 56`. Pieces are small
ints: `colour * 8 + kind`, so white is 1..6 and black is 9..14, `piece & 7` is
what it is and `piece >> 3` is whose it is. A move is one int too --
`from | to << 6 | promotion << 12` -- which is what makes a move list cheap to
build, cheap to sort, and trivial to write to a file.

Nothing here imports GTK, which is what makes every rule in this file testable
on any machine with a Python -- and the rules of chess are a great deal easier
to get subtly wrong than the rules of Reversi. En passant, castling out of and
through check, the fifty-move counter and the three draws by material,
repetition and stalemate are all in here, and all in `tests/test_chess.py`.
"""

from __future__ import annotations

import random
from typing import NamedTuple

SIZE = 8
CELLS = SIZE * SIZE

WHITE = 0
BLACK = 1
COLOURS = (WHITE, BLACK)
COLOUR_NAMES = {WHITE: "White", BLACK: "Black"}

EMPTY = 0
PAWN = 1
KNIGHT = 2
BISHOP = 3
ROOK = 4
QUEEN = 5
KING = 6
KINDS = (PAWN, KNIGHT, BISHOP, ROOK, QUEEN, KING)
KIND_NAMES = {
    PAWN: "pawn",
    KNIGHT: "knight",
    BISHOP: "bishop",
    ROOK: "rook",
    QUEEN: "queen",
    KING: "king",
}
LETTERS = {PAWN: "p", KNIGHT: "n", BISHOP: "b", ROOK: "r", QUEEN: "q", KING: "k"}

# What a piece is worth when a person counts, which is not what it is worth when
# the search counts -- `ai.py` has its own table, in hundredths of a pawn, with
# a bishop worth slightly more than a knight. These are the numbers everybody
# learns, and they are here because they are what goes on the screen.
POINTS = {PAWN: 1, KNIGHT: 3, BISHOP: 3, ROOK: 5, QUEEN: 9, KING: 0}
KIND_OF_LETTER = {letter: kind for kind, letter in LETTERS.items()}

# The four castling rights, as bits, so that the whole of "what may still
# castle" is one int to store, to hash and to restore on the way back out of a
# search.
WHITE_KINGSIDE = 1
WHITE_QUEENSIDE = 2
BLACK_KINGSIDE = 4
BLACK_QUEENSIDE = 8
ALL_CASTLING = 15

NO_SQUARE = -1


def piece(colour: int, kind: int) -> int:
    return (colour << 3) | kind


def kind_of(code: int) -> int:
    return code & 7


def colour_of(code: int) -> int:
    return code >> 3


def square(file: int, rank: int) -> int:
    return rank * SIZE + file


def file_of(cell: int) -> int:
    return cell & 7


def rank_of(cell: int) -> int:
    return cell >> 3


def name(cell: int) -> str:
    """e4. The notation a person reads, and the one the saved file is in."""
    return f"{chr(ord('a') + (cell & 7))}{(cell >> 3) + 1}"


def parse_square(text: str) -> int:
    if len(text) != 2:
        raise ValueError(f"not a square: {text!r}")
    file = ord(text[0]) - ord("a")
    rank = ord(text[1]) - ord("1")
    if not (0 <= file < SIZE and 0 <= rank < SIZE):
        raise ValueError(f"not a square: {text!r}")
    return rank * SIZE + file


def move(frm: int, to: int, promotion: int = 0) -> int:
    return frm | (to << 6) | (promotion << 12)


def move_from(code: int) -> int:
    return code & 63


def move_to(code: int) -> int:
    return (code >> 6) & 63


def move_promotion(code: int) -> int:
    return code >> 12


def uci(code: int) -> str:
    """e2e4, or e7e8q. Long algebraic, which is what the file holds.

    A saved game is a list of these rather than a list of packed ints, and that
    is on purpose: `["e2e4", "e7e5"]` is a game anyone can read, diff, mail to
    somebody or repair by hand on a phone with no keyboard attached, and the
    packing saves bytes nobody was short of.
    """
    promotion = code >> 12
    tail = LETTERS[promotion] if promotion else ""
    return f"{name(code & 63)}{name((code >> 6) & 63)}{tail}"


def parse_uci(text: str) -> int:
    """A move as written. Says nothing about whether it is legal here."""
    if len(text) not in (4, 5):
        raise ValueError(f"not a move: {text!r}")
    frm = parse_square(text[0:2])
    to = parse_square(text[2:4])
    promotion = 0
    if len(text) == 5:
        promotion = KIND_OF_LETTER.get(text[4].lower(), 0)
        if promotion not in (KNIGHT, BISHOP, ROOK, QUEEN):
            raise ValueError(f"not a promotion: {text!r}")
    return move(frm, to, promotion)


# --- the tables, built once at import ------------------------------------

# Rook directions first, then bishop directions, as (file, rank) steps. The
# order matters: a sliding attack along ray `i` is a rook's if i < 4 and a
# bishop's otherwise, and a queen's either way, which is the whole of the
# sliding attack test.
_STEPS = ((0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (-1, 1), (1, -1), (-1, -1))
_ROOK_RAYS = (0, 1, 2, 3)
_BISHOP_RAYS = (4, 5, 6, 7)

_KNIGHT_STEPS = ((1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2))


def _walk(cell: int, step: tuple[int, int]) -> tuple[int, ...]:
    file, rank = file_of(cell) + step[0], rank_of(cell) + step[1]
    out = []
    while 0 <= file < SIZE and 0 <= rank < SIZE:
        out.append(square(file, rank))
        file += step[0]
        rank += step[1]
    return tuple(out)


def _step(cell: int, step: tuple[int, int]) -> int:
    file, rank = file_of(cell) + step[0], rank_of(cell) + step[1]
    if 0 <= file < SIZE and 0 <= rank < SIZE:
        return square(file, rank)
    return NO_SQUARE


RAYS = tuple(tuple(_walk(cell, step) for step in _STEPS) for cell in range(CELLS))
KNIGHT_MOVES = tuple(
    tuple(t for t in (_step(cell, s) for s in _KNIGHT_STEPS) if t != NO_SQUARE)
    for cell in range(CELLS)
)
KING_MOVES = tuple(
    tuple(t for t in (_step(cell, s) for s in _STEPS) if t != NO_SQUARE)
    for cell in range(CELLS)
)
# Where a pawn of this colour, standing here, attacks.
PAWN_ATTACKS = tuple(
    tuple(
        tuple(
            t
            for t in (
                _step(cell, (-1, 1 if colour == WHITE else -1)),
                _step(cell, (1, 1 if colour == WHITE else -1)),
            )
            if t != NO_SQUARE
        )
        for cell in range(CELLS)
    )
    for colour in COLOURS
)
# ...and the same relation read backwards: where a pawn of this colour would
# have to stand to attack here. Inverting the table rather than working the
# geometry out again is what stops the two disagreeing.
PAWN_ATTACKERS = tuple(
    tuple(
        tuple(frm for frm in range(CELLS) if cell in PAWN_ATTACKS[colour][frm])
        for cell in range(CELLS)
    )
    for colour in COLOURS
)

# Rights that survive a piece leaving or arriving on a square. AND-ing both ends
# of every move into the rights is the whole rule, including the awkward half of
# it: capturing a rook on its own corner ends that castling too, and a version
# that only looks at the square a piece left gets that wrong.
CASTLE_MASK = [ALL_CASTLING] * CELLS
CASTLE_MASK[square(0, 0)] &= ~WHITE_QUEENSIDE
CASTLE_MASK[square(7, 0)] &= ~WHITE_KINGSIDE
CASTLE_MASK[square(4, 0)] &= ~(WHITE_KINGSIDE | WHITE_QUEENSIDE)
CASTLE_MASK[square(0, 7)] &= ~BLACK_QUEENSIDE
CASTLE_MASK[square(7, 7)] &= ~BLACK_KINGSIDE
CASTLE_MASK[square(4, 7)] &= ~(BLACK_KINGSIDE | BLACK_QUEENSIDE)
CASTLE_MASK = tuple(CASTLE_MASK)

# Zobrist keys, from a fixed seed so that a key means the same thing in every
# run, in the tests and in the file if it ever went there. Hashing the position
# incrementally is what makes repetition detection free: without it, every node
# of the search would walk sixty-four squares to ask a question about a draw.
_RANDOM = random.Random(0x5245564552534905)
_ZOBRIST_PIECE = tuple(
    tuple(_RANDOM.getrandbits(64) for _ in range(CELLS)) for _ in range(15)
)
_ZOBRIST_SIDE = _RANDOM.getrandbits(64)
_ZOBRIST_CASTLING = tuple(_RANDOM.getrandbits(64) for _ in range(16))
_ZOBRIST_EP = tuple(_RANDOM.getrandbits(64) for _ in range(SIZE))


class Made(NamedTuple):
    """What one move did, and everything needed to take it back out again.

    It is the undo record and the description of the move at the same time, and
    that is deliberate. The board no longer holds the answer to "what moved,
    what did it take, was that a castle" once the move has been played, and
    three different parts of this app need to know: `unmake`, the animation in
    `widgets.py`, and the incremental evaluation in `ai.py`. One tuple, filled
    in by the only code that has all of it to hand.
    """

    move: int
    piece: int
    placed: int  # differs from `piece` only on a promotion
    captured: int  # 0 for a quiet move
    captured_square: int  # not the arrival square, for en passant
    rook_from: int  # -1 unless this was a castle
    rook_to: int
    castling: int  # the rights, the clock and the key as they were *before*
    ep: int
    halfmove: int
    key: int


ONGOING = "ongoing"
CHECKMATE = "checkmate"
STALEMATE = "stalemate"
FIFTY_MOVE = "fifty-move"
INSUFFICIENT = "insufficient"
REPETITION = "repetition"
DRAWS = (STALEMATE, FIFTY_MOVE, INSUFFICIENT, REPETITION)

START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"


class Position:
    """A board, whose turn it is, and the four things a board does not say.

    Mutable, and moved through with `make` and `unmake`. Reversi's position is
    frozen because the whole of it is two integers and a copy is free; this one
    is sixty-four list slots plus state, and a search that copied it per node
    would spend most of the phone's time budget on the copying. Where a snapshot
    genuinely is wanted -- handing a position to the search thread, drawing one
    while the game moves on -- `copy()` says so out loud.
    """

    __slots__ = (
        "castling",
        "ep",
        "fullmove",
        "halfmove",
        "key",
        "keys",
        "kings",
        "squares",
        "turn",
    )

    def __init__(
        self,
        squares: list[int],
        turn: int = WHITE,
        castling: int = 0,
        ep: int = NO_SQUARE,
        halfmove: int = 0,
        fullmove: int = 1,
    ) -> None:
        self.squares = squares
        self.turn = turn
        self.castling = castling
        self.ep = ep
        self.halfmove = halfmove
        self.fullmove = fullmove
        self.kings = [NO_SQUARE, NO_SQUARE]
        for cell, code in enumerate(squares):
            if code and code & 7 == KING:
                self.kings[code >> 3] = cell
        self.key = self._hash()
        self.keys = [self.key]

    # --- making one ------------------------------------------------------

    @classmethod
    def start(cls) -> Position:
        return cls.from_fen(START_FEN)

    @classmethod
    def from_fen(cls, text: str) -> Position:
        """A position as Forsyth-Edwards writes it.

        Here for the tests and for `demo.py` rather than for the app, which
        never sees one -- but a rules suite that cannot state a position in one
        line states it in twenty, and the tests that matter most in chess are
        the ones about a particular awkward board.
        """
        parts = text.split()
        if len(parts) < 4:
            raise ValueError(f"not a FEN: {text!r}")
        squares = [EMPTY] * CELLS
        rank = SIZE - 1
        file = 0
        for char in parts[0]:
            if char == "/":
                rank -= 1
                file = 0
            elif char.isdigit():
                file += int(char)
            else:
                kind = KIND_OF_LETTER.get(char.lower())
                if kind is None or not (0 <= file < SIZE and 0 <= rank < SIZE):
                    raise ValueError(f"not a FEN: {text!r}")
                colour = WHITE if char.isupper() else BLACK
                squares[square(file, rank)] = piece(colour, kind)
                file += 1
        castling = 0
        for char, bit in (
            ("K", WHITE_KINGSIDE),
            ("Q", WHITE_QUEENSIDE),
            ("k", BLACK_KINGSIDE),
            ("q", BLACK_QUEENSIDE),
        ):
            if char in parts[2]:
                castling |= bit
        return cls(
            squares,
            turn=BLACK if parts[1] == "b" else WHITE,
            castling=castling,
            ep=parse_square(parts[3]) if parts[3] != "-" else NO_SQUARE,
            halfmove=int(parts[4]) if len(parts) > 4 and parts[4].isdigit() else 0,
            fullmove=int(parts[5]) if len(parts) > 5 and parts[5].isdigit() else 1,
        )

    def fen(self) -> str:
        rows = []
        for rank in range(SIZE - 1, -1, -1):
            row, gap = "", 0
            for file in range(SIZE):
                code = self.squares[square(file, rank)]
                if not code:
                    gap += 1
                    continue
                if gap:
                    row += str(gap)
                    gap = 0
                letter = LETTERS[code & 7]
                row += letter.upper() if code >> 3 == WHITE else letter
            rows.append(row + (str(gap) if gap else ""))
        rights = "".join(
            char
            for char, bit in (
                ("K", WHITE_KINGSIDE),
                ("Q", WHITE_QUEENSIDE),
                ("k", BLACK_KINGSIDE),
                ("q", BLACK_QUEENSIDE),
            )
            if self.castling & bit
        )
        return " ".join(
            (
                "/".join(rows),
                "w" if self.turn == WHITE else "b",
                rights or "-",
                name(self.ep) if self.ep != NO_SQUARE else "-",
                str(self.halfmove),
                str(self.fullmove),
            )
        )

    def copy(self) -> Position:
        other = Position.__new__(Position)
        other.squares = list(self.squares)
        other.turn = self.turn
        other.castling = self.castling
        other.ep = self.ep
        other.halfmove = self.halfmove
        other.fullmove = self.fullmove
        other.kings = list(self.kings)
        other.key = self.key
        other.keys = list(self.keys)
        return other

    def _hash(self) -> int:
        key = 0
        for cell, code in enumerate(self.squares):
            if code:
                key ^= _ZOBRIST_PIECE[code][cell]
        if self.turn == BLACK:
            key ^= _ZOBRIST_SIDE
        key ^= _ZOBRIST_CASTLING[self.castling]
        if self.ep != NO_SQUARE:
            key ^= _ZOBRIST_EP[file_of(self.ep)]
        return key

    # --- playing ---------------------------------------------------------

    def make(self, code: int) -> Made:
        """Play a move into this board. The move must be pseudo-legal.

        Legality -- as opposed to pseudo-legality -- is the one thing this does
        not check, because the cheapest way to know it is to play the move and
        look at the king, which is what `moves()` and the search both do.
        """
        squares = self.squares
        frm = code & 63
        to = (code >> 6) & 63
        promotion = code >> 12
        mover = squares[frm]
        kind = mover & 7
        us = mover >> 3
        key = self.key ^ _ZOBRIST_SIDE ^ _ZOBRIST_CASTLING[self.castling]
        if self.ep != NO_SQUARE:
            key ^= _ZOBRIST_EP[file_of(self.ep)]

        captured = squares[to]
        captured_square = to
        if kind == PAWN and to == self.ep and not captured:
            # The only capture in chess that does not happen on the square the
            # capturing piece lands on.
            captured_square = to - SIZE if us == WHITE else to + SIZE
            captured = squares[captured_square]
        if captured:
            squares[captured_square] = EMPTY
            key ^= _ZOBRIST_PIECE[captured][captured_square]

        placed = piece(us, promotion) if promotion else mover
        squares[frm] = EMPTY
        squares[to] = placed
        key ^= _ZOBRIST_PIECE[mover][frm] ^ _ZOBRIST_PIECE[placed][to]

        rook_from = rook_to = NO_SQUARE
        if kind == KING:
            self.kings[us] = to
            if to - frm == 2 or frm - to == 2:
                rook_from, rook_to = (
                    (frm + 3, frm + 1) if to > frm else (frm - 4, frm - 1)
                )
                rook = squares[rook_from]
                squares[rook_from] = EMPTY
                squares[rook_to] = rook
                key ^= _ZOBRIST_PIECE[rook][rook_from] ^ _ZOBRIST_PIECE[rook][rook_to]

        made = Made(
            move=code,
            piece=mover,
            placed=placed,
            captured=captured,
            captured_square=captured_square if captured else NO_SQUARE,
            rook_from=rook_from,
            rook_to=rook_to,
            castling=self.castling,
            ep=self.ep,
            halfmove=self.halfmove,
            key=self.key,
        )

        self.castling &= CASTLE_MASK[frm] & CASTLE_MASK[to]
        self.ep = (
            (frm + to) >> 1
            if kind == PAWN and (to - frm == 16 or frm - to == 16)
            else NO_SQUARE
        )
        self.halfmove = 0 if kind == PAWN or captured else self.halfmove + 1
        if us == BLACK:
            self.fullmove += 1
        self.turn = us ^ 1
        key ^= _ZOBRIST_CASTLING[self.castling]
        if self.ep != NO_SQUARE:
            key ^= _ZOBRIST_EP[file_of(self.ep)]
        self.key = key
        self.keys.append(key)
        return made

    def unmake(self, made: Made) -> None:
        squares = self.squares
        frm = made.move & 63
        to = (made.move >> 6) & 63
        us = made.piece >> 3

        squares[to] = EMPTY
        squares[frm] = made.piece
        if made.captured:
            squares[made.captured_square] = made.captured
        if made.rook_from != NO_SQUARE:
            squares[made.rook_from] = squares[made.rook_to]
            squares[made.rook_to] = EMPTY
        if made.piece & 7 == KING:
            self.kings[us] = frm

        self.castling = made.castling
        self.ep = made.ep
        self.halfmove = made.halfmove
        if us == BLACK:
            self.fullmove -= 1
        self.turn = us
        self.key = made.key
        self.keys.pop()

    # --- what is attacking what ------------------------------------------

    def attacked(self, cell: int, by: int) -> bool:
        """Is this square attacked by that colour?

        Asked from the square rather than about it: rather than walking every
        enemy piece and asking where it goes, this walks outwards from the one
        square in question and asks what is standing there. Sixty-four pieces
        become about thirty square reads, and this is called once per move
        generated, which makes it the hottest thing in the file.
        """
        squares = self.squares
        base = by << 3
        for frm in PAWN_ATTACKERS[by][cell]:
            if squares[frm] == base | PAWN:
                return True
        for frm in KNIGHT_MOVES[cell]:
            if squares[frm] == base | KNIGHT:
                return True
        for frm in KING_MOVES[cell]:
            if squares[frm] == base | KING:
                return True
        rays = RAYS[cell]
        for index in _ROOK_RAYS:
            for frm in rays[index]:
                found = squares[frm]
                if found:
                    if found == base | ROOK or found == base | QUEEN:
                        return True
                    break
        for index in _BISHOP_RAYS:
            for frm in rays[index]:
                found = squares[frm]
                if found:
                    if found == base | BISHOP or found == base | QUEEN:
                        return True
                    break
        return False

    def in_check(self, colour: int | None = None) -> bool:
        colour = self.turn if colour is None else colour
        king = self.kings[colour]
        return king != NO_SQUARE and self.attacked(king, colour ^ 1)

    # --- generating moves ------------------------------------------------

    def pseudo_moves(self, *, tactical: bool = False) -> list[int]:
        """Every move the pieces allow, before the king is considered.

        `tactical` narrows it to captures and queen promotions, which is what
        the quiescence search in `ai.py` wants and by far the cheapest way to
        give it that -- generating everything and filtering costs the generation
        of everything.
        """
        out: list[int] = []
        squares = self.squares
        us = self.turn
        for frm in range(CELLS):
            code = squares[frm]
            if not code or code >> 3 != us:
                continue
            kind = code & 7
            if kind == PAWN:
                self._pawn_moves(frm, us, out, tactical)
            elif kind == KNIGHT:
                self._step_moves(frm, us, KNIGHT_MOVES[frm], out, tactical)
            elif kind == KING:
                self._step_moves(frm, us, KING_MOVES[frm], out, tactical)
                if not tactical:
                    self._castles(frm, us, out)
            else:
                rays = RAYS[frm]
                if kind != BISHOP:
                    self._slide(frm, us, rays, _ROOK_RAYS, out, tactical)
                if kind != ROOK:
                    self._slide(frm, us, rays, _BISHOP_RAYS, out, tactical)
        return out

    def _step_moves(self, frm, us, targets, out, tactical) -> None:
        squares = self.squares
        for to in targets:
            found = squares[to]
            if found:
                if found >> 3 != us:
                    out.append(frm | to << 6)
            elif not tactical:
                out.append(frm | to << 6)

    def _slide(self, frm, us, rays, indices, out, tactical) -> None:
        squares = self.squares
        for index in indices:
            for to in rays[index]:
                found = squares[to]
                if found:
                    if found >> 3 != us:
                        out.append(frm | to << 6)
                    break
                if not tactical:
                    out.append(frm | to << 6)

    def _pawn_moves(self, frm, us, out, tactical) -> None:
        squares = self.squares
        ahead = frm + SIZE if us == WHITE else frm - SIZE
        last = SIZE - 1 if us == WHITE else 0
        if rank_of(ahead) == last:
            # A promotion is four different moves, and a search that offered
            # only the queen would miss the underpromotions that are the point
            # of a handful of famous endings.
            promotions = (QUEEN,) if tactical else (QUEEN, ROOK, BISHOP, KNIGHT)
        else:
            promotions = (0,)
        if not squares[ahead] and (not tactical or promotions[0]):
            for promotion in promotions:
                out.append(frm | ahead << 6 | promotion << 12)
        if (
            not tactical
            and not squares[ahead]
            and rank_of(frm) == (1 if us == WHITE else 6)
        ):
            double = ahead + SIZE if us == WHITE else ahead - SIZE
            if not squares[double]:
                out.append(frm | double << 6)
        for to in PAWN_ATTACKS[us][frm]:
            found = squares[to]
            if (found and found >> 3 != us) or (not found and to == self.ep):
                for promotion in promotions:
                    out.append(frm | to << 6 | promotion << 12)

    def _castles(self, frm, us, out) -> None:
        home = 0 if us == WHITE else 7
        if frm != square(4, home):
            return
        rights = self.castling >> (0 if us == WHITE else 2)
        if not rights & 3:
            return
        squares = self.squares
        them = us ^ 1
        rook = piece(us, ROOK)
        # The king may not start in check, pass through an attacked square, or
        # land on one. The third is left to the legality filter, which checks
        # every move; the first two have to be asked here, because after the
        # move there is nothing left to say the king went through anything.
        if (
            rights & 1
            and not (squares[frm + 1] or squares[frm + 2])
            and squares[frm + 3] == rook
            and not self.attacked(frm, them)
            and not self.attacked(frm + 1, them)
        ):
            out.append(frm | (frm + 2) << 6)
        if (
            rights & 2
            and not (squares[frm - 1] or squares[frm - 2] or squares[frm - 3])
            and squares[frm - 4] == rook
            and not self.attacked(frm, them)
            and not self.attacked(frm - 1, them)
        ):
            out.append(frm | (frm - 2) << 6)

    def moves(self) -> list[int]:
        """The legal moves. Every one of them playable, right now, here."""
        us = self.turn
        out = []
        for code in self.pseudo_moves():
            made = self.make(code)
            if not self.attacked(self.kings[us], self.turn):
                out.append(code)
            self.unmake(made)
        return out

    def moves_from(self, cell: int) -> list[int]:
        return [code for code in self.moves() if code & 63 == cell]

    def is_legal(self, code: int) -> bool:
        return code in self.moves()

    # --- endings ---------------------------------------------------------

    def repetitions(self) -> int:
        """How many times this exact position has stood on the board.

        Only back as far as the last capture or pawn move: nothing before that
        can repeat, because no sequence of moves puts a captured piece back.
        Two at a time, because a position with the other side to move is a
        different position.
        """
        keys = self.keys
        count = 1
        index = len(keys) - 3
        floor = max(len(keys) - 1 - self.halfmove, 0)
        while index >= floor:
            if keys[index] == self.key:
                count += 1
            index -= 2
        return count

    def insufficient_material(self) -> bool:
        """Neither side could deliver mate with what is left.

        The FIDE-and-everybody-else subset: bare kings, king and one minor, and
        the two bishops that never meet because they are on the same colour.
        King and two knights is deliberately not in here -- mate is possible, it
        just cannot be forced, and a game called a draw while a mate is on the
        board is a bug wearing a rule's clothes.
        """
        minors = [0, 0]
        bishops = [NO_SQUARE, NO_SQUARE]
        for cell, code in enumerate(self.squares):
            if not code:
                continue
            kind = code & 7
            if kind in (PAWN, ROOK, QUEEN):
                return False
            if kind == KING:
                continue
            minors[code >> 3] += 1
            if kind == BISHOP:
                bishops[code >> 3] = cell
        if minors[WHITE] > 1 or minors[BLACK] > 1:
            return False
        if minors[WHITE] + minors[BLACK] <= 1:
            return True
        white, black = bishops
        if white == NO_SQUARE or black == NO_SQUARE:
            return False  # a knight each, which can mate with help
        return (file_of(white) + rank_of(white)) % 2 == (
            file_of(black) + rank_of(black)
        ) % 2

    def outcome(self) -> tuple[str, int | None]:
        """How the game stands: a state, and who won if anybody did.

        The order is the order the rules are applied in. Mate first, because a
        position that is checkmate is checkmate even on the hundredth move
        without a capture -- the fifty-move rule does not save a mated king, and
        an engine that checks the clock first announces the wrong result.
        """
        if not self.moves():
            if self.in_check():
                return CHECKMATE, self.turn ^ 1
            return STALEMATE, None
        if self.halfmove >= 100:
            return FIFTY_MOVE, None
        if self.insufficient_material():
            return INSUFFICIENT, None
        if self.repetitions() >= 3:
            return REPETITION, None
        return ONGOING, None


class Game:
    """A game as the list of moves that made it.

    The same shape as Reversi's: the move list is the state, the board is what
    playing it produces, and a file that has been truncated or edited by hand
    cannot describe a board legal play could not reach, because loading it *is*
    playing it. Chess needs one thing Reversi did not -- the moves are taken
    back out of the position rather than replayed from the opening -- because a
    position carries a repetition history that a replay would have to rebuild
    anyway, and `unmake` already exists and is exact.
    """

    def __init__(self, moves=(), position: Position | None = None) -> None:
        self.position = position.copy() if position else Position.start()
        self.start = self.position.copy()
        self.moves: list[int] = []
        self._made: list[Made] = []
        for code in moves:
            if not self._apply(code):
                raise ValueError(f"{uci(code)} does not belong to this game")

    @classmethod
    def resume(cls, moves, position: Position | None = None) -> Game:
        """As much of a recorded game as will legally play.

        Where a file stops making sense is where the game stops. Nothing else
        can be done with the rest that is not a guess, and a guess here is a
        board somebody never played.
        """
        game = cls(position=position)
        for code in moves:
            if not game._apply(code):
                break
        return game

    def _apply(self, code: int) -> bool:
        if code not in self.position.moves():
            return False
        self._made.append(self.position.make(code))
        self.moves.append(code)
        return True

    # --- playing ---------------------------------------------------------

    def play(self, code: int) -> Made:
        if code not in self.position.moves():
            raise ValueError(f"{uci(code)} is not a legal move")
        made = self.position.make(code)
        self._made.append(made)
        self.moves.append(code)
        return made

    @property
    def turn(self) -> int:
        return self.position.turn

    def legal(self) -> list[int]:
        return self.position.moves()

    def last_move(self) -> int | None:
        return self.moves[-1] if self.moves else None

    def outcome(self) -> tuple[str, int | None]:
        return self.position.outcome()

    @property
    def over(self) -> bool:
        return self.position.outcome()[0] != ONGOING

    def uci(self) -> list[str]:
        return [uci(code) for code in self.moves]

    def captured(self) -> list[int]:
        """Everything taken so far, in the order it went.

        Read off the moves rather than by comparing the board with the opening,
        because those two answers differ the moment a pawn promotes -- a board
        with two white queens on it has not captured a black one.
        """
        return [made.captured for made in self._made if made.captured]

    def balance(self) -> int:
        """Material on the board, in points, from White's side.

        From the board and not from the captures, which is the other half of the
        same argument: a promotion is worth eight points and takes nothing.
        """
        total = 0
        for code in self.position.squares:
            if code:
                total += POINTS[code & 7] * (1 if code >> 3 == WHITE else -1)
        return total

    # --- taking it back --------------------------------------------------

    def undo(self) -> bool:
        if not self._made:
            return False
        self.position.unmake(self._made.pop())
        self.moves.pop()
        return True

    def takeback(self, colour: int) -> bool:
        """Rewind until `colour` is on move again, with something undone.

        A phone is a device you play on with one thumb on a bus, and the tap
        that lands one square off is the ordinary case rather than the strange
        one. Undoing a single ply would hand the board back with the computer's
        reply still on it, which is not what anybody means by undo.
        """
        undone = False
        while self.moves:
            if not self.undo():
                break
            undone = True
            if self.position.turn == colour:
                break
        return undone
