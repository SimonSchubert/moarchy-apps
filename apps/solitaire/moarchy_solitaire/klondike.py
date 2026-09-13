"""The rules of Klondike, as five tuples and a list of moves.

A card is an integer from 0 to 51: `card // 4` is its rank, ace as 0 and king as
12, and `card % 4` is its suit in the order clubs, diamonds, hearts, spades --
so the two red suits are the two in the middle and `suit in RED` is a range
check rather than a lookup. Nothing here is a class with a face on it. Fifty-two
small integers is a whole deck a person can read in a JSON file, and a deck a
person can read is a deck a bug can be looked at in.

A whole table is five tuples, and the one worth explaining is `down`: the number
of face-down cards at the *bottom* of each tableau column. Face-down cards in
Klondike are always at the bottom and always contiguous -- nothing is ever
turned back over -- so a count says everything a per-card flag would, in seven
integers instead of twenty-eight, and it makes "did that move turn a card up"
arithmetic rather than a search.

The invariant the whole file leans on: **the face-up part of a column is always
a legal run.** A column starts with one card face up, and cards only ever land
on it as a descending alternating sequence, so every suffix of the face-up part
is movable and no run has to be validated when it is picked up -- only when it
is put down. Turning a card up cannot break it either: one card is a run.

A game is a deck and a list of moves. The table is derived by replaying them,
which costs a few hundred tuple operations -- microseconds -- and buys the three
things Reversi's move list buys: undo is a pop, the file is small integers a
person can read, and a table that legal play could not reach cannot be loaded,
because loading is playing.

Nothing here imports GTK.
"""

from __future__ import annotations

import random
from dataclasses import dataclass

SUITS = 4
RANKS = 13
DECK = SUITS * RANKS

CLUB, DIAMOND, HEART, SPADE = 0, 1, 2, 3
RED = (DIAMOND, HEART)
SUIT_NAMES = ("clubs", "diamonds", "hearts", "spades")
RANK_NAMES = ("A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K")

ACE = 0
KING = RANKS - 1

COLUMNS = 7

# Where a card can be. The numbering is what goes in the file, so it is fixed:
# 0 is the stock, 1 the waste, 2 to 5 the four foundations in suit order, and 6
# to 12 the seven tableau columns left to right.
STOCK = 0
WASTE = 1
FOUNDATION = 2
TABLEAU = FOUNDATION + SUITS
PILES = TABLEAU + COLUMNS

# How many cards a tap on the stock turns over. Three is the game as it is
# printed on the box; one is the game people actually play on a bus.
DRAWS = (1, 3)
DEFAULT_DRAW = 1


def rank(card: int) -> int:
    return card // SUITS


def suit(card: int) -> int:
    return card % SUITS


def is_red(card: int) -> bool:
    return suit(card) in RED


def name(card: int) -> str:
    return f"{RANK_NAMES[rank(card)]} of {SUIT_NAMES[suit(card)]}"


def foundation_of(card: int) -> int:
    return FOUNDATION + suit(card)


def is_foundation(pile: int) -> bool:
    return FOUNDATION <= pile < TABLEAU


def is_tableau(pile: int) -> bool:
    return TABLEAU <= pile < PILES


def shuffled(rng: random.Random | None = None) -> tuple[int, ...]:
    deck = list(range(DECK))
    (rng or random.Random()).shuffle(deck)
    return tuple(deck)


@dataclass(frozen=True)
class Move:
    """One thing a person did. Three small integers, and that is the file.

    `count` is how many cards travelled: one for almost everything, more for a
    run moved between columns, and however many the stock had for a deal. It is
    recorded rather than recomputed because the move list is replayed, and a
    deal that worked out its own count would silently change meaning if the
    draw setting on the file ever disagreed with the one the game was played at.
    """

    src: int
    dst: int
    count: int = 1

    def as_list(self) -> list[int]:
        return [self.src, self.dst, self.count]

    @classmethod
    def of(cls, raw) -> Move | None:
        """One move out of whatever a JSON file actually had in it."""
        if not isinstance(raw, (list, tuple)) or len(raw) != 3:
            return None
        if any(isinstance(v, bool) or not isinstance(v, int) for v in raw):
            return None
        return cls(raw[0], raw[1], raw[2])


@dataclass(frozen=True)
class Table:
    """Every card, where it is, and which way up. Immutable, so undo is a list.

    Frozen for the reason Reversi's Position is: replaying a game from the deal
    is how undo works, and a state that is rebuilt rather than reversed cannot
    be half-reversed by a move whose undo was written wrong.
    """

    stock: tuple[int, ...]
    waste: tuple[int, ...]
    # How many cards of each suit have gone home. The foundations are built in
    # rank order by definition, so a count is the whole pile: suit s holds the
    # ace up to `up[s] - 1`.
    up: tuple[int, ...]
    piles: tuple[tuple[int, ...], ...]
    down: tuple[int, ...]
    draw: int = DEFAULT_DRAW

    # --- reading -----------------------------------------------------------

    def column(self, pile: int) -> tuple[int, ...]:
        return self.piles[pile - TABLEAU]

    def hidden(self, pile: int) -> int:
        return self.down[pile - TABLEAU]

    def face_up(self, pile: int) -> tuple[int, ...]:
        return self.column(pile)[self.hidden(pile) :]

    def top(self, pile: int) -> int | None:
        """The card that can be taken off this pile, or None if there is none."""
        if pile == STOCK:
            return self.stock[-1] if self.stock else None
        if pile == WASTE:
            return self.waste[-1] if self.waste else None
        if is_foundation(pile):
            count = self.up[pile - FOUNDATION]
            return (count - 1) * SUITS + (pile - FOUNDATION) if count else None
        column = self.column(pile)
        return column[-1] if column else None

    def cards_in(self, pile: int) -> int:
        if pile == STOCK:
            return len(self.stock)
        if pile == WASTE:
            return len(self.waste)
        if is_foundation(pile):
            return self.up[pile - FOUNDATION]
        return len(self.column(pile))

    @property
    def won(self) -> bool:
        return all(count == RANKS for count in self.up)

    @property
    def home(self) -> int:
        return sum(self.up)

    @property
    def finishable(self) -> bool:
        """Is there nothing left to find out -- and does playing it out win?

        Every tableau card being face up is the condition people quote, and on
        a table that legal play produced it is sufficient: the columns are all
        legal runs, so the lowest card still needed is never buried under
        anything, and the stock can always be turned over again.

        It is checked by *doing* it rather than by trusting that argument. The
        cheap half rules out almost every table in a couple of comparisons; the
        other half runs the same greedy pass the button runs and asks whether it
        actually wins. A banner offering to finish a game that then does not
        finish is worse than no banner.
        """
        if self.won or any(self.down) or self.home >= DECK:
            return False
        table = self
        for move in homeward(self):
            table = table.apply(move)
        return table.won

    # --- what may be done --------------------------------------------------

    def accepts(self, pile: int, card: int) -> bool:
        """May this card land here? Asked of the bottom card of a run."""
        if is_foundation(pile):
            index = pile - FOUNDATION
            return suit(card) == index and rank(card) == self.up[index]
        if not is_tableau(pile):
            return False
        column = self.column(pile)
        if not column:
            return rank(card) == KING
        under = column[-1]
        return rank(under) == rank(card) + 1 and is_red(under) != is_red(card)

    def run_from(self, pile: int, position: int) -> tuple[int, ...]:
        """The cards a tap at this position picks up, if any.

        Only a tableau has positions -- everywhere else there is one card to
        take and it is the top one. A face-down card picks up nothing: it is not
        a card yet, it is the back of one.
        """
        if not is_tableau(pile):
            top = self.top(pile)
            return () if top is None else (top,)
        column = self.column(pile)
        if not 0 <= position < len(column) or position < self.hidden(pile):
            return ()
        return column[position:]

    def destinations(self, pile: int, position: int) -> list[int]:
        """Everywhere the run picked up here could legally be put down.

        Two collapses, and both are about what a person means rather than what
        the rules permit.

        An **ace never goes to a tableau column**. The rules allow it -- a black
        ace does sit on a red two -- and nobody has ever wanted it, so counting
        it would turn every ace into a question with an obviously wrong second
        answer.

        **Empty columns count once.** Three empty columns are three legal
        destinations for a king and one decision, and offering the same decision
        three times is how a one-tap move becomes a two-tap one for no reason.

        And a **whole column does not move to an empty one**. The rules permit
        it -- a king alone in a column is a king, and an empty column takes a
        king -- and it uncovers nothing, changes nothing and leaves the table in
        the same position with one more move on the counter. Allowing it also
        makes a lost game undetectable: `stuck` asks whether any move exists
        that is not turning the stock over, and a king that can always shuffle
        sideways answers yes forever.
        """
        run = self.run_from(pile, position)
        if not run:
            return []
        card = run[0]
        out: list[int] = []
        if len(run) == 1 and self.accepts(foundation_of(card), card):
            out.append(foundation_of(card))
        if len(run) == 1 and rank(card) == ACE:
            return out
        whole = is_tableau(pile) and position == 0
        empty = -1
        for column in range(TABLEAU, PILES):
            if column == pile or not self.accepts(column, card):
                continue
            if self.column(column):
                out.append(column)
            elif empty < 0 and not whole:
                empty = column
        if empty >= 0:
            out.append(empty)
        return out

    def moves(self) -> list[Move]:
        """Every legal move. For the tests and for "is this game stuck"."""
        out: list[Move] = []
        if self.stock:
            out.append(Move(STOCK, WASTE, min(self.draw, len(self.stock))))
        elif self.waste:
            out.append(Move(WASTE, STOCK, len(self.waste)))
        for pile in (WASTE, *range(FOUNDATION, PILES)):
            if pile == WASTE or is_foundation(pile):
                positions = [max(self.cards_in(pile) - 1, 0)]
            else:
                positions = list(range(self.hidden(pile), len(self.column(pile))))
            for position in positions:
                run = self.run_from(pile, position)
                if not run:
                    continue
                for dst in self.destinations(pile, position):
                    out.append(Move(pile, dst, len(run)))
        return out

    def is_legal(self, move: Move) -> bool:
        if move.src == STOCK:
            return (
                move.dst == WASTE
                and 0 < move.count <= len(self.stock)
                and move.count <= self.draw
            )
        if move.dst == STOCK:
            return (
                move.src == WASTE
                and not self.stock
                and move.count == len(self.waste)
                and move.count > 0
            )
        if move.count < 1 or move.src == move.dst:
            return False
        held = self.cards_in(move.src)
        if move.count > held:
            return False
        if not is_tableau(move.src) and move.count != 1:
            return False
        position = held - move.count
        run = self.run_from(move.src, position)
        if len(run) != move.count:
            return False
        if is_foundation(move.dst) and move.count != 1:
            return False
        return self.accepts(move.dst, run[0])

    # --- doing it ----------------------------------------------------------

    def apply(self, move: Move) -> Table:
        """The table after this move. Raises on an illegal one."""
        if not self.is_legal(move):
            raise ValueError(f"{move} is not a legal move")
        if move.src == STOCK:
            # Dealt one at a time onto the waste, so the last one turned over is
            # the one on top -- which is the same order a hand does it in and
            # the reason a three-card deal shows three different cards.
            taken = self.stock[len(self.stock) - move.count :]
            return self._with(
                stock=self.stock[: len(self.stock) - move.count],
                waste=self.waste + taken,
            )
        if move.dst == STOCK:
            # Turned face down as one block, which reverses it: the card that
            # was on top of the waste is the one that will come off the stock
            # last. Getting this backwards makes a game that is trivially
            # winnable and takes a while to notice.
            return self._with(stock=tuple(reversed(self.waste)), waste=())

        held = self.cards_in(move.src)
        run = self.run_from(move.src, held - move.count)
        table = self._take(move.src, move.count)
        return table._put(move.dst, run)

    def _with(self, **changes) -> Table:
        fields = {
            "stock": self.stock,
            "waste": self.waste,
            "up": self.up,
            "piles": self.piles,
            "down": self.down,
            "draw": self.draw,
        }
        fields.update(changes)
        return Table(**fields)

    def _take(self, pile: int, count: int) -> Table:
        if pile == WASTE:
            return self._with(waste=self.waste[:-count])
        if is_foundation(pile):
            index = pile - FOUNDATION
            up = list(self.up)
            up[index] -= count
            return self._with(up=tuple(up))
        index = pile - TABLEAU
        piles = list(self.piles)
        piles[index] = piles[index][:-count]
        down = list(self.down)
        # The card under the one that left turns over. This is the whole of the
        # rule, and it is why `down` is a count rather than a flag per card.
        if down[index] and len(piles[index]) == down[index]:
            down[index] -= 1
        return self._with(piles=tuple(piles), down=tuple(down))

    def _put(self, pile: int, run: tuple[int, ...]) -> Table:
        if is_foundation(pile):
            up = list(self.up)
            up[pile - FOUNDATION] += len(run)
            return self._with(up=tuple(up))
        index = pile - TABLEAU
        piles = list(self.piles)
        piles[index] = piles[index] + run
        return self._with(piles=tuple(piles))


def deal(deck: tuple[int, ...], draw: int = DEFAULT_DRAW) -> Table:
    """Seven columns of one to seven cards, the rest face down in the stock."""
    if len(deck) != DECK or len(set(deck)) != DECK:
        raise ValueError("that is not a deck")
    piles: list[tuple[int, ...]] = []
    at = 0
    for column in range(COLUMNS):
        piles.append(tuple(deck[at : at + column + 1]))
        at += column + 1
    return Table(
        stock=tuple(deck[at:]),
        waste=(),
        up=(0,) * SUITS,
        piles=tuple(piles),
        down=tuple(range(COLUMNS)),
        draw=draw if draw in DRAWS else DEFAULT_DRAW,
    )


def homeward(table: Table) -> list[Move]:
    """The moves that finish a table nothing is hidden in.

    Greedy and exact: send home whatever will go, turn the stock over when
    nothing will, and stop when the table is won or when a whole pass round the
    stock has changed nothing. On a table with every card face up the first
    branch always wins, which is what `finishable` is claiming.
    """
    moves: list[Move] = []
    stuck = 0
    while not table.won and stuck <= DECK * 2:
        for pile in (WASTE, *range(TABLEAU, PILES)):
            card = table.top(pile)
            if card is not None and table.accepts(foundation_of(card), card):
                move = Move(pile, foundation_of(card), 1)
                moves.append(move)
                table = table.apply(move)
                stuck = 0
                break
        else:
            if table.stock:
                move = Move(STOCK, WASTE, min(table.draw, len(table.stock)))
            elif table.waste:
                move = Move(WASTE, STOCK, len(table.waste))
            else:
                break
            moves.append(move)
            table = table.apply(move)
            stuck += 1
    return moves


def stuck(table: Table) -> bool:
    """Is there nothing left but turning the stock over, round and round?

    Klondike has no rule that ends a lost game. The stock can always be turned
    over again, so `moves()` is almost never empty and a person can sit there
    cycling a pack forever -- which is what losing at patience actually looks
    like, and it is a terrible thing for an app to make somebody discover for
    themselves twenty taps at a time.

    So this turns the stock over for them, as many times as it takes to come
    back round, and asks at each step whether any move exists that is not
    itself turning the stock over. The first iteration answers in the ordinary
    case, because in the ordinary case there is something to play right now.
    """
    steps = 0
    while steps <= DECK * 2:
        for move in table.moves():
            if move.src != STOCK and move.dst != STOCK:
                return False
        if table.stock:
            table = table.apply(Move(STOCK, WASTE, min(table.draw, len(table.stock))))
        elif table.waste:
            table = table.apply(Move(WASTE, STOCK, len(table.waste)))
        else:
            return True
        steps += 1
    return True


class Game:
    """A deal and the moves played on it."""

    def __init__(
        self,
        deck: tuple[int, ...] | None = None,
        draw: int = DEFAULT_DRAW,
        moves=(),
    ) -> None:
        self.deck = tuple(deck) if deck else shuffled()
        self.draw = draw if draw in DRAWS else DEFAULT_DRAW
        self.moves: list[Move] = []
        self.table = deal(self.deck, self.draw)
        self.start = self.table
        for move in moves:
            if not self._apply(move):
                raise ValueError(f"{move} does not belong to this game")

    @classmethod
    def resume(cls, deck, draw: int, moves) -> Game:
        """As much of a recorded game as will legally play.

        Where a file stops making sense is where the game stops. Anything else
        that could be done with the rest is a guess, and a guess here is a table
        nobody dealt.
        """
        try:
            game = cls(deck, draw)
        except ValueError:
            game = cls(None, draw)
            return game
        for raw in moves:
            move = raw if isinstance(raw, Move) else Move.of(raw)
            if move is None or not game._apply(move):
                break
        return game

    def _apply(self, move: Move) -> bool:
        if not self.table.is_legal(move):
            return False
        self.table = self.table.apply(move)
        self.moves.append(move)
        return True

    # --- playing -----------------------------------------------------------

    def play(self, move: Move) -> bool:
        return self._apply(move)

    def undo(self) -> bool:
        if not self.moves:
            return False
        self.moves.pop()
        self._replay()
        return True

    def _replay(self) -> None:
        moves, self.moves, self.table = self.moves, [], self.start
        for move in moves:
            self._apply(move)

    @property
    def won(self) -> bool:
        return self.table.won

    @property
    def count(self) -> int:
        """Moves made. Deals count: turning the stock over is a decision."""
        return len(self.moves)

    @property
    def stuck(self) -> bool:
        return not self.won and stuck(self.table)
