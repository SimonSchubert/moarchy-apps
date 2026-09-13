"""The board, and the score line above it.

The board is one Gtk.DrawingArea rather than nine buttons, which matters less
here than it does in Reversi -- nine widgets is not sixty-four -- and is done
anyway for a reason nine buttons could not give: the marks are *drawn*. An X
that arrives as two strokes and an O that arrives as a sweep are the whole of
what this game has instead of a board full of pieces, and a button with a label
in it cannot do either.

It is a hash and not a grid of boxes. Four rules that overshoot their crossings
and no border around the outside, which is what a person actually draws and what
makes the game recognisable from across a room. A bordered three by three is a
chessboard with most of the squares missing.

The size arithmetic: 360px of screen, 12px of margin each side, leaves 336 for
three cells of 112. That is two and a half times the 44px a thumb is usually
given, and it is the one board in this repository with room to spare -- so the
cap is what does the work here rather than the floor, because a phone app opened
on a desktop and dragged wide should not answer with a 900px noughts and
crosses.
"""

from __future__ import annotations

import math
from typing import ClassVar

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import GLib, GObject, Gtk  # noqa: E402

from . import theme  # noqa: E402
from .tictactoe import (  # noqa: E402
    EMPTY,
    MARKS,
    NAMES,
    SIZE,
    X,
    Play,
    Position,
    cells,
    row_column,
)

# One mark being drawn. Fast enough to feel like a reply and slow enough to see
# which stroke went down first, which is the only thing making it a drawing
# rather than an image appearing.
MARK_MS = 190.0

# The line through three in a row, and the pause before it: the third mark has
# to land before the line goes through it, or the line is announcing a win the
# board has not finished showing.
STRIKE_MS = 300.0
STRIKE_WAIT = 90.0

# A mark inside its cell, and how thick the pencil is. Both as fractions of a
# cell, so the board is the same drawing at 240px and at 420.
MARK = 0.27
NIB = 0.105
RULE = 0.048
# How far the rules stop short of the sheet's edge, and how far the strike
# overshoots the marks it goes through.
GUTTER = 0.16
OVERSHOOT = 0.26

# The smallest board worth drawing, and the largest worth having. Below 240 the
# marks stop being strokes; above 420 a bigger noughts and crosses is not a more
# readable one, and the window is a phone window that somebody has dragged wide.
MINIMUM = 240
MAXIMUM = 420


def _ease(t: float) -> float:
    """Out-cubic. A pencil starts fast and stops, and this is that."""
    return 1.0 - (1.0 - t) ** 3


def _rounded(cr, x: float, y: float, size: float, radius: float) -> None:
    cr.new_sub_path()
    cr.arc(x + size - radius, y + radius, radius, -math.pi / 2, 0)
    cr.arc(x + size - radius, y + size - radius, radius, 0, math.pi / 2)
    cr.arc(x + radius, y + size - radius, radius, math.pi / 2, math.pi)
    cr.arc(x + radius, y + radius, radius, math.pi, 3 * math.pi / 2)
    cr.close_path()


class BoardView(Gtk.DrawingArea):
    """Three by three, drawn once per frame that needs one."""

    __gtype_name__ = "TicTacToeBoardView"

    __gsignals__: ClassVar[dict] = {
        # A square was tapped. Legality is the window's business: the board
        # knows what is drawn on it, not what the rules make of a tap.
        "cell-activated": (GObject.SignalFlags.RUN_FIRST, None, (int,)),
        # Everything that was moving has stopped. The window waits for this
        # before it lets the computer answer, so that a reply never lands on
        # top of the mark it is replying to.
        "settled": (GObject.SignalFlags.RUN_FIRST, None, ()),
    }

    def __init__(self) -> None:
        super().__init__()
        self._position: Position = EMPTY
        self._line: tuple[int, ...] = ()
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
        """As tall as it is wide, which is the only shape this board has.

        Without this the drawing area takes every spare pixel of height it is
        offered, centres a square inside itself, and leaves a hole between the
        board and the line of text under it -- space the window could have given
        to something and instead gave to a gap.
        """
        if orientation == Gtk.Orientation.HORIZONTAL:
            return MINIMUM, MINIMUM, -1, -1
        size = min(max(for_size, MINIMUM), MAXIMUM)
        return size, size, -1, -1

    # --- what to draw ----------------------------------------------------

    def set_colours(self, palette: theme.Palette) -> None:
        colours = theme.board_colours(palette)
        # Parsed here and not in the draw function: a mark being drawn repaints
        # the whole board sixty times a second, and turning the same seven hex
        # strings into floats is a cost with nothing behind it on this CPU.
        self._ink = {name: theme.rgb(value) for name, value in vars(colours).items()}
        self.queue_draw()

    def show(self, position: Position) -> None:
        self._position = position
        self._line = position.winning_line()
        self.update_property([Gtk.AccessibleProperty.LABEL], [self.describe()])
        self.queue_draw()

    def describe(self) -> str:
        position = self._position
        winner = position.winner()
        if winner is not None:
            return f"Board, {NAMES[winner]} has won"
        if position.is_full():
            return "Board, drawn"
        return f"Board, {position.played()} marks, {NAMES[position.turn]} to play"

    # --- moving ----------------------------------------------------------

    def animate(self, play: Play) -> None:
        """Show a mark being drawn. Emits `settled` when it has stopped."""
        self._stop()
        self._line = play.line
        if not self._motion_wanted():
            # Reduced motion is a setting people turn on because motion makes
            # them ill. The mark still lands, it simply lands at once.
            self.queue_draw()
            GLib.idle_add(self._settle)
            return
        self._anim = {
            "start": 0,
            "cell": play.cell,
            "strike": bool(play.line),
        }
        self._tick = self.add_tick_callback(self._frame)

    def _motion_wanted(self) -> bool:
        settings = Gtk.Settings.get_default()
        return settings is None or settings.props.gtk_enable_animations

    def _length(self, anim: dict) -> float:
        if anim["strike"]:
            return MARK_MS + STRIKE_WAIT + STRIKE_MS
        return MARK_MS

    def _frame(self, _widget, clock) -> bool:
        anim = self._anim
        if anim is None:
            return GLib.SOURCE_REMOVE
        now = clock.get_frame_time()
        if not anim["start"]:
            anim["start"] = now
        self.queue_draw()
        if (now - anim["start"]) / 1000.0 < self._length(anim):
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

    # --- tapping ---------------------------------------------------------

    def _geometry(self, width: int, height: int) -> tuple[float, float, float]:
        cell = min(width, height) / SIZE
        side = cell * SIZE
        return (width - side) / 2, (height - side) / 2, cell

    def _on_pressed(
        self, gesture: Gtk.GestureClick, _n: int, x: float, y: float
    ) -> None:
        ox, oy, cell = self._geometry(self.get_width(), self.get_height())
        if cell <= 0:
            return  # not laid out yet, so there is nothing under the finger
        column, row = int((x - ox) // cell), int((y - oy) // cell)
        if 0 <= row < SIZE and 0 <= column < SIZE:
            gesture.set_state(Gtk.EventSequenceState.CLAIMED)
            self.emit("cell-activated", row * SIZE + column)

    # --- drawing ---------------------------------------------------------

    def _centre(self, ox: float, oy: float, cell: float, square: int) -> tuple:
        row, column = row_column(square)
        return ox + (column + 0.5) * cell, oy + (row + 0.5) * cell

    def _draw(self, _area, cr, width: int, height: int) -> None:
        ox, oy, cell = self._geometry(width, height)
        side = cell * SIZE

        cr.set_source_rgb(*self._ink["sheet"])
        _rounded(cr, ox, oy, side, cell * 0.14)
        cr.fill()

        # The hash: two rules each way, stopping short of the paper's edge the
        # way a hand does, with round ends because a pencil has one.
        cr.set_source_rgb(*self._ink["rule"])
        cr.set_line_width(cell * RULE)
        cr.set_line_cap(1)  # cairo.LINE_CAP_ROUND, without importing cairo
        gutter = cell * GUTTER
        for step in (1, 2):
            cr.move_to(ox + step * cell, oy + gutter)
            cr.line_to(ox + step * cell, oy + side - gutter)
            cr.move_to(ox + gutter, oy + step * cell)
            cr.line_to(ox + side - gutter, oy + step * cell)
        cr.stroke()

        anim = self._anim
        elapsed = 0.0
        if anim is not None:
            clock = self.get_frame_clock()
            if clock is not None and anim["start"]:
                elapsed = (clock.get_frame_time() - anim["start"]) / 1000.0

        # A finished game dims everything outside the winning line, so that the
        # three squares that decided it are the three the eye lands on. Not to
        # nothing: the rest of the board is still the game that was played.
        striking = bool(self._line) and (anim is None or elapsed >= MARK_MS)
        cr.set_line_width(cell * NIB)
        for mark in MARKS:
            name = "x" if mark == X else "o"
            for square in cells(self._position.marks(mark)):
                faded = striking and square not in self._line
                cr.set_source_rgb(*self._ink[f"faded_{name}" if faded else name])
                share = 1.0
                if anim is not None and square == anim["cell"]:
                    share = _ease(min(elapsed / MARK_MS, 1.0))
                cx, cy = self._centre(ox, oy, cell, square)
                if mark == X:
                    self._cross(cr, cx, cy, cell * MARK, share)
                else:
                    self._ring(cr, cx, cy, cell * MARK, share)

        if self._line:
            share = 1.0
            if anim is not None and anim["strike"]:
                share = _ease(
                    max(min((elapsed - MARK_MS - STRIKE_WAIT) / STRIKE_MS, 1.0), 0.0)
                )
            if share > 0:
                self._strike(cr, ox, oy, cell, share)

    def _cross(self, cr, cx: float, cy: float, reach: float, share: float) -> None:
        """Two strokes, the second starting where the first has finished.

        Drawn in the order a right-handed person draws them -- top-left down to
        bottom-right, then top-right down to bottom-left -- because it is the
        order the eye expects and the reason this reads as somebody marking a
        square rather than as a glyph fading in.
        """
        first = min(share * 2.0, 1.0)
        second = max(share * 2.0 - 1.0, 0.0)
        if first > 0:
            cr.move_to(cx - reach, cy - reach)
            cr.line_to(cx - reach + 2 * reach * first, cy - reach + 2 * reach * first)
            cr.stroke()
        if second > 0:
            cr.move_to(cx + reach, cy - reach)
            cr.line_to(cx + reach - 2 * reach * second, cy - reach + 2 * reach * second)
            cr.stroke()

    def _ring(self, cr, cx: float, cy: float, reach: float, share: float) -> None:
        """One sweep, from the top, clockwise. Which is how a hand draws one."""
        if share <= 0:
            return
        cr.arc(cx, cy, reach, -math.pi / 2, -math.pi / 2 + math.tau * share)
        cr.stroke()

    def _strike(self, cr, ox: float, oy: float, cell: float, share: float) -> None:
        first = self._centre(ox, oy, cell, self._line[0])
        last = self._centre(ox, oy, cell, self._line[-1])
        # Out past the marks at both ends, so the line reads as struck through
        # three of them rather than as joining their middles.
        dx, dy = last[0] - first[0], last[1] - first[1]
        span = math.hypot(dx, dy) or 1.0
        over = cell * OVERSHOOT
        x1, y1 = first[0] - dx / span * over, first[1] - dy / span * over
        x2, y2 = last[0] + dx / span * over, last[1] + dy / span * over
        winner = self._position.winner()
        cr.set_source_rgb(*self._ink["x" if winner == X else "o"])
        cr.set_line_width(cell * NIB * 0.85)
        cr.move_to(x1, y1)
        cr.line_to(x1 + (x2 - x1) * share, y1 + (y2 - y1) * share)
        cr.stroke()


class Chip(Gtk.Box):
    """One seat on the score line: its mark, its games in this series, its name.

    The mark is on the chip rather than only in the status text because it moves
    between the seats -- the rematch swaps who plays X -- and a person coming
    back to the phone after a stop needs to know which one they are without
    reading a sentence about it.
    """

    __gtype_name__ = "TicTacToeChip"

    def __init__(self) -> None:
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.add_css_class("side")
        self.set_valign(Gtk.Align.CENTER)

        self._glyph = Gtk.Label()
        self._glyph.add_css_class("glyph")
        self._glyph.set_valign(Gtk.Align.CENTER)
        self.append(self._glyph)

        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        text.set_valign(Gtk.Align.CENTER)
        self._count = Gtk.Label(xalign=0.0)
        self._count.add_css_class("count")
        text.append(self._count)
        # No ellipsize. Every name this can hold is one of six short fixed words
        # -- YOU, ONE, TWO, EASY, FAIR, PERFECT -- and the class on it carries
        # letter-spacing, which Pango adds after the last glyph without counting
        # it in the natural width it then ellipsizes against. Reversi's chip
        # said MEDIU… in a box with room to spare for exactly that reason.
        self._who = Gtk.Label(xalign=0.0)
        self._who.add_css_class("who")
        text.append(self._who)
        self.append(text)

    def refresh(self, mark: int, count: int, who: str, playing: bool) -> None:
        name = NAMES[mark]
        self._glyph.set_text(name)
        for css in ("x", "o"):
            self._glyph.remove_css_class(css)
        self._glyph.add_css_class(name.lower())
        self._count.set_text(str(count))
        self._who.set_text(who.upper())
        if playing:
            self.add_css_class("playing")
        else:
            self.remove_css_class("playing")
        self.update_property(
            [Gtk.AccessibleProperty.LABEL], [f"{who}, playing {name}: {count} won"]
        )


class ScoreLine(Gtk.Box):
    """Both seats, with the drawn games between them."""

    __gtype_name__ = "TicTacToeScoreLine"

    def __init__(self) -> None:
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.set_margin_start(12)
        self.set_margin_end(12)
        self.set_margin_top(6)

        self.a = Chip()
        self.append(self.a)

        middle = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        middle.set_hexpand(True)
        middle.set_valign(Gtk.Align.CENTER)
        self._drawn = Gtk.Label()
        self._drawn.add_css_class("drawn")
        middle.append(self._drawn)
        self.append(middle)

        self.b = Chip()
        self.append(self.b)

    def refresh(
        self,
        position: Position,
        marks: dict[str, int],
        names: dict[str, str],
        series: dict[str, int],
        live: bool,
    ) -> None:
        for seat, chip in (("a", self.a), ("b", self.b)):
            chip.refresh(
                marks[seat],
                series[seat],
                names[seat],
                live and position.turn == marks[seat],
            )
        drawn = series.get("drawn", 0)
        self._drawn.set_text(f"{drawn} drawn" if drawn else "")
