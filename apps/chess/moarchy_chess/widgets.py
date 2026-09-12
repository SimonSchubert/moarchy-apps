"""The board, the men on it, and the line of names above it.

The board is one Gtk.DrawingArea rather than sixty-four widgets, and that is the
central decision in this file, for the reasons Reversi's version records:
sixty-four buttons is sixty-four style contexts to resolve, sixty-four nodes to
lay out and sixty-four render nodes to submit every time anything changes, for a
grid whose shape never changes at all. One drawing area is one node; a tap is
arithmetic on the pointer position. There is no GL on a Mali-400 and none in the
container these screenshots come from, so software is what this is drawn for.

The size arithmetic is the same too: 360px of screen, 8px of margin each side,
leaves 344 for eight squares of 43. Forty-three is under the 44px a thumb is
usually given, and it is the one place in these apps where that floor is crossed
on purpose -- a board is a grid of known shape where a miss is visible and undo
is one tap away, and the alternative is a board that does not fit the screen.

What chess adds over Reversi is that a square is not a state, it is a *step*:
nothing happens until two squares have been tapped, and between them the board
has to say which piece is up and where it may go. So the board carries a
selection and a set of destinations, and the window drives both -- the board
knows what is drawn on it, never what the rules make of a tap.
"""

from __future__ import annotations

import math
from typing import ClassVar

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import GLib, GObject, Gtk  # noqa: E402

from . import pieces, theme  # noqa: E402
from .chess import (  # noqa: E402
    BLACK,
    KING,
    NO_SQUARE,
    SIZE,
    WHITE,
    Made,
    Position,
    file_of,
    name,
    rank_of,
)

# One move, sliding. Long enough to be followed across the board and short
# enough that a person playing quickly is never waiting for it.
SLIDE_MS = 190.0

# A piece that has just been taken shrinks away underneath the one taking it.
FADE_MS = 150.0

# A piece, as a fraction of its square. Under one because the men have to have
# board around them or a rank of them reads as a solid bar.
PIECE = 0.78

# The dot on a square that can be moved to, and the ring around a piece that can
# be taken, both as fractions of a square.
DOT = 0.15
RING = 0.44

# The smallest board worth drawing: 34px squares, under a thumb but still
# unmistakably a board. Nothing this app runs on is narrower.
MINIMUM = 272

# ...and the largest. A board is square, so a window wide enough would ask for
# more height than it has -- this is a phone app opened on a desktop, dragged
# wide. Past seventy-pixel squares a bigger board is not a more readable one.
MAXIMUM = 560


def _rounded(
    cr, x: float, y: float, width: float, height: float, radius: float
) -> None:
    cr.new_sub_path()
    cr.arc(x + width - radius, y + radius, radius, -math.pi / 2, 0)
    cr.arc(x + width - radius, y + height - radius, radius, 0, math.pi / 2)
    cr.arc(x + radius, y + height - radius, radius, math.pi / 2, math.pi)
    cr.arc(x + radius, y + radius, radius, math.pi, 3 * math.pi / 2)
    cr.close_path()


def _ease(share: float) -> float:
    """Out-cubic. A piece leaves at speed and arrives gently, which is what a
    hand does with one and what stops a 190ms slide reading as a jump."""
    return 1 - (1 - share) ** 3


def draw_piece(cr, ink, code: int, x: float, y: float, size: float) -> None:
    """One man, filled and rimmed, inside a square of `size` at (x, y).

    The rim is not decoration. A white piece on the light squares and a black
    one on the dark squares are each a shape of nearly the board's own colour,
    and at 43px the outline is most of what separates them.
    """
    inset = size * (1 - PIECE) / 2
    white = code >> 3 == WHITE
    pieces.path(cr, code & 7, x + inset, y + inset, size * PIECE)
    cr.set_source_rgb(*(ink["white"] if white else ink["black"]))
    cr.fill_preserve()
    cr.set_source_rgb(*(ink["white_rim"] if white else ink["black_rim"]))
    cr.set_line_width(max(1.0, size * 0.028))
    cr.stroke()


class BoardView(Gtk.DrawingArea):
    """Eight by eight, drawn once per frame that needs one."""

    __gtype_name__ = "ChessBoardView"

    __gsignals__: ClassVar[dict] = {
        # A square was tapped. What that means -- picking a piece up, putting it
        # down, changing your mind -- is the window's business.
        "square-activated": (GObject.SignalFlags.RUN_FIRST, None, (int,)),
        # Everything that was moving has stopped. The window waits for this
        # before it lets the computer think -- see window.py, where the reason
        # is the GIL rather than good manners.
        "settled": (GObject.SignalFlags.RUN_FIRST, None, ()),
    }

    def __init__(self) -> None:
        super().__init__()
        self._position: Position = Position.start()
        self._flipped = False
        self._selected = NO_SQUARE
        self._targets: frozenset[int] = frozenset()
        self._last: tuple[int, int] | None = None
        self._check = NO_SQUARE
        self._anim: dict | None = None
        self._tick = 0

        self.set_hexpand(True)
        self.set_draw_func(self._draw)

        click = Gtk.GestureClick()
        click.connect("pressed", self._on_pressed)
        self.add_controller(click)
        self.set_colours(theme.fallback(dark=True))

    def do_get_request_mode(self) -> Gtk.SizeRequestMode:
        return Gtk.SizeRequestMode.HEIGHT_FOR_WIDTH

    def do_measure(self, orientation, for_size: int) -> tuple:
        """As tall as it is wide, which is the only shape a board has.

        Without this the drawing area takes every spare pixel of height it is
        offered, centres a square inside itself and leaves eighty pixels of
        nothing between the board and the line of text under it -- space the
        window could have given to something, and instead gave to a gap.
        """
        if orientation == Gtk.Orientation.HORIZONTAL:
            return MINIMUM, MINIMUM, -1, -1
        size = min(max(for_size, MINIMUM), MAXIMUM)
        return size, size, -1, -1

    # --- what to draw ----------------------------------------------------

    def set_colours(self, palette: theme.Palette) -> None:
        colours = theme.board_colours(palette)
        # Parsed here and not in the draw function. A slide repaints all
        # thirty-two men on every frame of it, and turning the same nine hex
        # strings into floats four thousand times a second is a cost with
        # nothing behind it on a CPU this size.
        self._ink = {key: theme.rgb(value) for key, value in vars(colours).items()}
        self.queue_draw()

    def set_flipped(self, flipped: bool) -> None:
        """Which side is at the bottom. Black, when Black is the person.

        Not a preference: a board seen from the wrong end is a board every
        pattern anybody has ever learned is mirrored on, and the whole of the
        cost of drawing it the other way up is this flag.
        """
        if flipped != self._flipped:
            self._flipped = flipped
            self.queue_draw()

    def show(
        self,
        position: Position,
        *,
        selected: int = NO_SQUARE,
        targets=(),
        last: tuple[int, int] | None = None,
        check: int = NO_SQUARE,
    ) -> None:
        self._position = position
        self._selected = selected
        self._targets = frozenset(targets)
        self._last = last
        self._check = check
        self.update_property([Gtk.AccessibleProperty.LABEL], [self.describe()])
        self.queue_draw()

    def describe(self) -> str:
        squares = self._position.squares
        held = sum(1 for code in squares if code)
        side = "White" if self._position.turn == WHITE else "Black"
        if self._selected != NO_SQUARE:
            code = squares[self._selected]
            if code:
                return (
                    f"Board, {held} pieces, {pieces.NAMES[code & 7]} on "
                    f"{name(self._selected)} selected, {side} to play"
                )
        return f"Board, {held} pieces, {side} to play"

    # --- moving ----------------------------------------------------------

    def animate(self, made: Made, position: Position) -> None:
        """Show a move landing. Emits `settled` when it has.

        `position` is the board *after* the move, and the pieces that are on
        their way are held back from it and drawn between two squares instead --
        which is why this takes the move as well as the board. `Made` is what
        makes that possible: it already knows what went where and what was
        taken, so nothing here has to work it out by comparing two positions.
        """
        self._stop()
        self._position = position
        if not self._motion_wanted():
            # Reduced motion is a setting people turn on because motion makes
            # them ill. The move still lands, it simply lands at once.
            self.queue_draw()
            GLib.idle_add(self._settle)
            return
        travelling = [(made.piece, made.move & 63, (made.move >> 6) & 63)]
        if made.rook_from != NO_SQUARE:
            # The rook goes with the king rather than after it, because that is
            # one move and showing it as two says it was two.
            travelling.append(
                (self._position.squares[made.rook_to], made.rook_from, made.rook_to)
            )
        self._anim = {
            "start": 0,
            "travelling": travelling,
            "arriving": {to for _, _, to in travelling},
            "taken": (made.captured, made.captured_square) if made.captured else None,
        }
        self._tick = self.add_tick_callback(self._frame)

    def _motion_wanted(self) -> bool:
        settings = Gtk.Settings.get_default()
        return settings is None or settings.props.gtk_enable_animations

    def _frame(self, _widget, clock) -> bool:
        anim = self._anim
        if anim is None:
            return GLib.SOURCE_REMOVE
        now = clock.get_frame_time()
        if not anim["start"]:
            anim["start"] = now
        self.queue_draw()
        if (now - anim["start"]) / 1000.0 < SLIDE_MS:
            return GLib.SOURCE_CONTINUE
        self._anim = None
        self._tick = 0
        self._settle()
        return GLib.SOURCE_REMOVE

    def _stop(self) -> None:
        if self._tick:
            self.remove_tick_callback(self._tick)
            self._tick = 0
        self._anim = None

    def _settle(self) -> bool:
        self.emit("settled")
        return GLib.SOURCE_REMOVE

    @property
    def busy(self) -> bool:
        return self._anim is not None

    # --- geometry --------------------------------------------------------

    def _geometry(self, width: int, height: int) -> tuple[float, float, float]:
        cell = min(width, height) / SIZE
        side = cell * SIZE
        return (width - side) / 2, (height - side) / 2, cell

    @staticmethod
    def _is_dark(row: int, column: int) -> bool:
        """Is the square in this screen row and column a dark one?

        Of the screen, not of the board: the labels have to contrast with what
        is actually painted under them, and when the board is turned round for
        Black the same square is in a different place. Asking the rank instead
        was the first version of this, and it drew every rank number in the
        colour of the square it was standing on, which is a label nobody can
        see and nothing that looks like a failure.
        """
        return (row + column) % 2 == 1

    def _place(self, cell: int) -> tuple[int, int]:
        """A square, as the column and row it is drawn in."""
        file, rank = file_of(cell), rank_of(cell)
        if self._flipped:
            return SIZE - 1 - file, rank
        return file, SIZE - 1 - rank

    def _on_pressed(
        self, gesture: Gtk.GestureClick, _n: int, x: float, y: float
    ) -> None:
        ox, oy, cell = self._geometry(self.get_width(), self.get_height())
        if cell <= 0:
            return  # not laid out yet, so there is nothing under the finger
        column, row = int((x - ox) // cell), int((y - oy) // cell)
        if not (0 <= row < SIZE and 0 <= column < SIZE):
            return
        file = SIZE - 1 - column if self._flipped else column
        rank = row if self._flipped else SIZE - 1 - row
        gesture.set_state(Gtk.EventSequenceState.CLAIMED)
        self.emit("square-activated", rank * SIZE + file)

    # --- drawing ---------------------------------------------------------

    def _draw(self, _area, cr, width: int, height: int) -> None:
        ox, oy, cell = self._geometry(width, height)
        side = cell * SIZE
        ink = self._ink

        cr.set_source_rgb(*ink["light"])
        _rounded(cr, ox, oy, side, side, cell * 0.18)
        cr.fill_preserve()
        cr.clip()

        cr.set_source_rgb(*ink["dark"])
        for row in range(SIZE):
            for column in range(SIZE):
                if self._is_dark(row, column):
                    cr.rectangle(ox + column * cell, oy + row * cell, cell, cell)
        cr.fill()

        if self._last is not None:
            red, green, blue = ink["accent"]
            cr.set_source_rgba(red, green, blue, 0.38)
            for square in self._last:
                column, row = self._place(square)
                cr.rectangle(ox + column * cell, oy + row * cell, cell, cell)
            cr.fill()

        if self._selected != NO_SQUARE:
            red, green, blue = ink["accent"]
            cr.set_source_rgba(red, green, blue, 0.48)
            column, row = self._place(self._selected)
            cr.rectangle(ox + column * cell, oy + row * cell, cell, cell)
            cr.fill()

        if self._check != NO_SQUARE:
            # A wash rather than an outline: the king is standing on it, and an
            # outline is the one thing a piece hides.
            column, row = self._place(self._check)
            red, green, blue = ink["check"]
            cr.set_source_rgba(red, green, blue, 0.55)
            cr.rectangle(ox + column * cell, oy + row * cell, cell, cell)
            cr.fill()

        cr.reset_clip()

        anim = self._anim
        held = anim["arriving"] if anim else ()
        for square, code in enumerate(self._position.squares):
            if not code or square in held:
                continue
            column, row = self._place(square)
            draw_piece(cr, ink, code, ox + column * cell, oy + row * cell, cell)

        self._coordinates(cr, ox, oy, cell)
        self._hints(cr, ox, oy, cell)

        if anim is not None:
            self._travelling(cr, anim, ox, oy, cell)

        cr.set_source_rgb(*ink["line"])
        cr.set_line_width(1.0)
        _rounded(cr, ox + 0.5, oy + 0.5, side - 1, side - 1, cell * 0.18)
        cr.stroke()

    def _coordinates(self, cr, ox: float, oy: float, cell: float) -> None:
        """A letter along the bottom and a number up the side.

        Small, in the colour of the square next door, and drawn into the corner
        of the square rather than outside the board -- a margin of labels is
        eight pixels the board does not have at this size. They earn their place
        in chess in a way they would not in Reversi: the file and rank are how
        the game is written down, and how anybody reads a move back.

        Drawn *after* the pieces, which is the part that had to be found out by
        looking: these outlines stand on a plinth that fills the bottom of their
        square, so a label underneath them is a label the back rank has eaten.
        On top it survives, because the colour it is drawn in is a square colour
        and the thing it lands on is a piece colour.
        """
        cr.select_font_face("sans")
        cr.set_font_size(max(7.0, cell * 0.21))
        for index in range(SIZE):
            file = SIZE - 1 - index if self._flipped else index
            rank = index if self._flipped else SIZE - 1 - index
            # A label sits on the square it names, so it takes the colour of the
            # other square -- which is the one guaranteed to contrast with it,
            # and against a piece is a board colour over a piece colour.
            cr.set_source_rgba(*self.label_ink(SIZE - 1, index), 0.7)
            cr.move_to(
                ox + (index + 1) * cell - cell * 0.30,
                oy + SIZE * cell - cell * 0.16,
            )
            cr.show_text(chr(ord("a") + file))
            cr.set_source_rgba(*self.label_ink(index, 0), 0.7)
            cr.move_to(ox + cell * 0.12, oy + index * cell + cell * 0.31)
            cr.show_text(str(rank + 1))

    def label_ink(self, row: int, column: int) -> tuple:
        """The colour a label in this screen square has to be drawn in."""
        return self._ink["light" if self._is_dark(row, column) else "dark"]

    def _hints(self, cr, ox: float, oy: float, cell: float) -> None:
        """Where the piece in hand may go.

        A dot on an empty square, a ring round a piece that can be taken. Both
        rather than one, because "you may move here" and "you may take that" are
        different enough answers that a touch screen should not make somebody
        find out which by trying.
        """
        if not self._targets or self._anim is not None:
            return
        red, green, blue = self._ink["accent"]
        squares = self._position.squares
        for square in self._targets:
            column, row = self._place(square)
            cx, cy = ox + (column + 0.5) * cell, oy + (row + 0.5) * cell
            if squares[square]:
                cr.set_source_rgba(red, green, blue, 0.85)
                cr.set_line_width(cell * 0.07)
                cr.arc(cx, cy, cell * RING, 0, math.tau)
                cr.stroke()
            else:
                cr.set_source_rgba(red, green, blue, 0.60)
                cr.arc(cx, cy, cell * DOT, 0, math.tau)
                cr.fill()

    def _travelling(self, cr, anim: dict, ox: float, oy: float, cell: float) -> None:
        clock = self.get_frame_clock()
        elapsed = 0.0
        if clock is not None and anim["start"]:
            elapsed = (clock.get_frame_time() - anim["start"]) / 1000.0
        share = _ease(min(elapsed / SLIDE_MS, 1.0))

        taken = anim["taken"]
        if taken and elapsed < FADE_MS:
            code, square = taken
            column, row = self._place(square)
            shrink = 1.0 - elapsed / FADE_MS
            size = cell * shrink
            cr.save()
            cr.push_group()
            draw_piece(
                cr,
                self._ink,
                code,
                ox + column * cell + (cell - size) / 2,
                oy + row * cell + (cell - size) / 2,
                size,
            )
            cr.pop_group_to_source()
            cr.paint_with_alpha(shrink)
            cr.restore()

        for code, frm, to in anim["travelling"]:
            from_column, from_row = self._place(frm)
            to_column, to_row = self._place(to)
            draw_piece(
                cr,
                self._ink,
                code,
                ox + (from_column + (to_column - from_column) * share) * cell,
                oy + (from_row + (to_row - from_row) * share) * cell,
                cell,
            )


class PieceIcon(Gtk.DrawingArea):
    """One man, at a fixed size, outside the board.

    The score line and the promotion sheet both need to show a piece, and both
    of them would otherwise need an icon theme to have chess in it, which no
    icon theme does. The board already knows how to draw one.
    """

    __gtype_name__ = "ChessPieceIcon"

    def __init__(self, code: int, size: int = 22) -> None:
        super().__init__()
        self._code = code
        self._size = size
        self.set_content_width(size)
        self.set_content_height(size)
        self.set_valign(Gtk.Align.CENTER)
        self.set_draw_func(self._draw)
        self.set_colours(theme.fallback(dark=True))
        self.update_property(
            [Gtk.AccessibleProperty.LABEL],
            [f"{'White' if code >> 3 == WHITE else 'Black'} {pieces.NAMES[code & 7]}"],
        )

    def set_colours(self, palette: theme.Palette) -> None:
        self._ink = {
            key: theme.rgb(value)
            for key, value in vars(theme.board_colours(palette)).items()
        }
        self.queue_draw()

    def _draw(self, _area, cr, width: int, height: int) -> None:
        size = min(width, height)
        draw_piece(
            cr, self._ink, self._code, (width - size) / 2, (height - size) / 2, size
        )


class CapturedView(Gtk.DrawingArea):
    """The men one side has taken, in a row, overlapping.

    Overlapping because eight pawns at their own width is eighty pixels and the
    screen is three hundred and sixty. They are drawn rather than listed as
    letters for the same reason the board is: a row of tiny pieces is read at a
    glance and `RNBQ` is read by someone who already plays.
    """

    __gtype_name__ = "ChessCaptured"

    HEIGHT = 16

    # A gap between one piece and the next, so that a row of pawns is a row of
    # pawns rather than a smear. Everything else about the spacing comes from
    # the pieces themselves: a queen is half as wide again as a pawn, and
    # advancing by a fixed step puts the wide ones on top of each other while
    # leaving gaps between the narrow ones.
    GAP = 1.5

    def __init__(self, align_end: bool = False) -> None:
        super().__init__()
        self._codes: tuple[int, ...] = ()
        self._align_end = align_end
        self.set_content_height(self.HEIGHT)
        self.set_hexpand(True)
        self.set_valign(Gtk.Align.CENTER)
        self.set_draw_func(self._draw)
        self.set_colours(theme.fallback(dark=True))

    def _advances(self) -> list[float]:
        scale = self.HEIGHT / pieces.HEIGHT
        return [pieces.OUTLINES[code & 7][0] * scale + self.GAP for code in self._codes]

    def set_colours(self, palette: theme.Palette) -> None:
        self._ink = {
            key: theme.rgb(value)
            for key, value in vars(theme.board_colours(palette)).items()
        }
        self.queue_draw()

    def show(self, codes) -> None:
        # Sorted by what they are worth, so the row reads as "a queen and two
        # pawns" rather than as the order the game happened to take them in.
        codes = tuple(sorted(codes, key=lambda code: -(code & 7)))
        if codes != self._codes:
            self._codes = codes
            self.update_property(
                [Gtk.AccessibleProperty.LABEL],
                [
                    ", ".join(pieces.NAMES[code & 7] for code in codes)
                    if codes
                    else "nothing taken"
                ],
            )
            self.queue_draw()

    def _draw(self, _area, cr, width: int, _height: int) -> None:
        if not self._codes:
            return
        advances = self._advances()
        total = sum(advances)
        # Sixteen men will not fit across half a 360px screen at their own
        # widths, so past the point where they stop fitting they overlap -- by
        # exactly as much as it takes and no more.
        squeeze = min(1.0, width / total) if total else 1.0
        at = width - total * squeeze if self._align_end else 0.0
        for code, advance in zip(self._codes, advances):
            # Each piece is drawn at full size inside a square of its own; only
            # the distance to the next one is squeezed.
            draw_piece(
                cr,
                self._ink,
                code,
                at - self.HEIGHT * 0.5 + advance / 2,
                0,
                self.HEIGHT,
            )
            at += advance * squeeze


class Side(Gtk.Box):
    """One player: a king in their colour, their name, and what they have taken."""

    __gtype_name__ = "ChessSide"

    def __init__(self, colour: int, align_end: bool = False) -> None:
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.colour = colour
        self.add_css_class("side")
        self.set_valign(Gtk.Align.CENTER)
        self.set_hexpand(True)

        self._icon = PieceIcon((colour << 3) | KING, 20)
        if not align_end:
            self.append(self._icon)

        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        text.set_valign(Gtk.Align.CENTER)
        text.set_hexpand(True)
        # No ellipsize. Every name this can hold is one of five short, fixed
        # words -- YOU, WHITE, BLACK, MEDIUM, HARD -- and the class on it carries
        # letter-spacing, which Pango adds *after* the last glyph without
        # counting it in the natural width it then ellipsizes against. In Keep's
        # sibling that produced a chip reading MEDIU… in a box with room spare.
        line = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=5)
        self._who = Gtk.Label(xalign=1.0 if align_end else 0.0)
        self._who.add_css_class("who")
        self._edge = Gtk.Label(xalign=0.0)
        self._edge.add_css_class("edge")
        if align_end:
            line.append(self._edge)
            line.append(self._who)
            self._who.set_hexpand(True)
        else:
            line.append(self._who)
            line.append(self._edge)
            self._edge.set_hexpand(True)
            self._edge.set_xalign(0.0)
        text.append(line)

        self._taken = CapturedView(align_end=align_end)
        text.append(self._taken)
        self.append(text)
        if align_end:
            # The two sides are mirrors: the king, the name and the men taken
            # all hang off the outside edge, so the pair reads as two players
            # facing each other rather than as one layout printed twice.
            self.append(self._icon)

    def set_colours(self, palette: theme.Palette) -> None:
        self._icon.set_colours(palette)
        self._taken.set_colours(palette)

    def refresh(self, who: str, taken, edge: int, playing: bool) -> None:
        self._who.set_text(who.upper())
        self._edge.set_text(f"+{edge}" if edge > 0 else "")
        self._taken.show(taken)
        if playing:
            self.add_css_class("playing")
        else:
            self.remove_css_class("playing")
        lead = f", ahead by {edge}" if edge > 0 else ""
        self.update_property(
            [Gtk.AccessibleProperty.LABEL],
            [f"{who}{lead}{', to play' if playing else ''}"],
        )


class ScoreLine(Gtk.Box):
    """Both players, the one at the top of the board on the left."""

    __gtype_name__ = "ChessScoreLine"

    def __init__(self) -> None:
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.set_margin_start(10)
        self.set_margin_end(10)
        self.set_margin_top(4)
        self.set_homogeneous(True)
        self.white = Side(WHITE)
        self.black = Side(BLACK, align_end=True)
        self.append(self.white)
        self.append(self.black)

    def set_colours(self, palette: theme.Palette) -> None:
        self.white.set_colours(palette)
        self.black.set_colours(palette)

    def refresh(self, game, names: dict[int, str], live: bool) -> None:
        taken = game.captured()
        balance = game.balance()
        turn = game.position.turn
        self.white.refresh(
            names[WHITE],
            [code for code in taken if code >> 3 == BLACK],
            max(balance, 0),
            live and turn == WHITE,
        )
        self.black.refresh(
            names[BLACK],
            [code for code in taken if code >> 3 == WHITE],
            max(-balance, 0),
            live and turn == BLACK,
        )
