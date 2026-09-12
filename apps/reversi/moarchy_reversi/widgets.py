"""The board, and the score line above it.

The board is one Gtk.DrawingArea rather than sixty-four widgets, and that is the
central decision in this file. Sixty-four buttons is sixty-four style contexts
to resolve, sixty-four nodes to lay out and sixty-four render nodes to submit
every time anything changes -- for a grid whose shape never changes at all. One
drawing area is one node: a tap is arithmetic on the pointer position, and a
flip repaints a 344px square in cairo, which is the renderer this runs under
anyway. There is no GL on a Mali-400 and none in the container these
screenshots come from; both fall back to software, so software is what this is
drawn for.

The size arithmetic: 360px of screen, 8px of margin each side, leaves 344 for
eight squares of 43. Forty-three is under the 44px a thumb is usually given, and
it is the one place in these apps where that floor is crossed on purpose -- a
board is a grid of known shape where a miss is visible and undo is one tap away,
and the alternative is a board that does not fit the screen it was drawn for.
"""

from __future__ import annotations

import math
from typing import ClassVar

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import GLib, GObject, Gtk  # noqa: E402

from . import theme  # noqa: E402
from .reversi import (  # noqa: E402
    DARK,
    LIGHT,
    NAMES,
    OPENING,
    SIZE,
    Play,
    Position,
    cells,
    row_column,
)

# The disc that was just played arrives at once -- a tap has to be answered in
# the frame it happens in -- and only grows into place.
PLACE_MS = 140.0

# One flip, edge on at the halfway point.
FLIP_MS = 240.0

# ...and each ring of squares out from the disc played starts a little after the
# one inside it, so a long line turns over as a wave rather than as a block.
# This is the whole reward of the move and it costs nothing but arithmetic.
RIPPLE_MS = 26.0

# A disc, as a fraction of its square.
DISC = 0.40
HINT = 0.13

# The smallest board worth drawing: 34px squares, under a thumb but still
# unmistakably a board. Nothing this app runs on is narrower.
MINIMUM = 272

# ...and the largest. A board is square, so a window wide enough would ask for
# more height than it has -- this is a phone app opened on a desktop, dragged
# wide. Past seventy-pixel squares a bigger board is not a more readable one, so
# the cap costs nothing and keeps the request inside the window.
MAXIMUM = 560


def _rounded(cr, x: float, y: float, size: float, radius: float) -> None:
    cr.new_sub_path()
    cr.arc(x + size - radius, y + radius, radius, -math.pi / 2, 0)
    cr.arc(x + size - radius, y + size - radius, radius, 0, math.pi / 2)
    cr.arc(x + radius, y + size - radius, radius, math.pi / 2, math.pi)
    cr.arc(x + radius, y + radius, radius, math.pi, 3 * math.pi / 2)
    cr.close_path()


class BoardView(Gtk.DrawingArea):
    """Eight by eight, drawn once per frame that needs one."""

    __gtype_name__ = "ReversiBoardView"

    __gsignals__: ClassVar[dict] = {
        # A square was tapped. Legality is the window's business: the board
        # knows what is drawn on it, not what the rules make of a tap.
        "cell-activated": (GObject.SignalFlags.RUN_FIRST, None, (int,)),
        # Everything that was moving has stopped. The window waits for this
        # before it lets the computer think -- see window.py, where the reason
        # is the GIL rather than good manners.
        "settled": (GObject.SignalFlags.RUN_FIRST, None, ()),
    }

    def __init__(self) -> None:
        super().__init__()
        self._position: Position = OPENING
        self._hints = 0
        self._last: int | None = None
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
        # Parsed here and not in the draw function. A flip repaints all
        # sixty-four discs on every frame of it, and turning the same seven hex
        # strings into floats four thousand times a second is a cost with
        # nothing behind it on a CPU this size.
        self._ink = {name: theme.rgb(value) for name, value in vars(colours).items()}
        self.queue_draw()

    def _ink_for(self, colour: int, *, rim: bool = False) -> tuple:
        name = "dark" if colour == DARK else "light"
        return self._ink[f"{name}_rim" if rim else name]

    def show(
        self, position: Position, *, hints: bool = False, last: int | None = None
    ) -> None:
        self._position = position
        self._hints = position.moves() if hints else 0
        self._last = last
        self.update_property([Gtk.AccessibleProperty.LABEL], [self.describe()])
        self.queue_draw()

    def describe(self) -> str:
        dark, light = self._position.counts()
        return (
            f"Board, dark {dark}, light {light}, {NAMES[self._position.turn]} to play"
        )

    # --- moving ----------------------------------------------------------

    def animate(self, play: Play) -> None:
        """Show a move landing. Emits `settled` when the last disc has turned."""
        self._stop()
        if not play.flipped or not self._motion_wanted():
            # Reduced motion is a setting people turn on because motion makes
            # them ill. The move still lands, it simply lands at once.
            self.queue_draw()
            GLib.idle_add(self._settle)
            return
        row, column = row_column(play.cell)
        self._anim = {
            "start": 0,
            "placed": play.cell,
            # Chebyshev distance: the rings of a square, which is how the eight
            # directions of this game are actually shaped.
            "flips": {
                cell: max(abs(r - row), abs(c - column)) * RIPPLE_MS
                for cell, (r, c) in ((f, row_column(f)) for f in play.flipped)
            },
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
        elapsed = (now - anim["start"]) / 1000.0
        self.queue_draw()
        if elapsed < max(anim["flips"].values(), default=0.0) + FLIP_MS:
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

    def _draw(self, _area, cr, width: int, height: int) -> None:
        ox, oy, cell = self._geometry(width, height)
        side = cell * SIZE

        cr.set_source_rgb(*self._ink["felt"])
        _rounded(cr, ox, oy, side, cell * 0.22)
        cr.fill()

        cr.set_source_rgb(*self._ink["line"])
        cr.set_line_width(1.0)
        for step in range(1, SIZE):
            cr.move_to(ox + step * cell, oy)
            cr.line_to(ox + step * cell, oy + side)
            cr.move_to(ox, oy + step * cell)
            cr.line_to(ox + side, oy + step * cell)
        cr.stroke()

        # The four dots every physical Othello board has, at the corners of the
        # inner square. They are not decoration: they are how a player says
        # "two in from the edge" without counting.
        for row in (2, 6):
            for column in (2, 6):
                cr.arc(ox + column * cell, oy + row * cell, cell * 0.055, 0, math.tau)
                cr.fill()

        anim = self._anim
        elapsed = 0.0
        if anim is not None:
            clock = self.get_frame_clock()
            if clock is not None and anim["start"]:
                elapsed = (clock.get_frame_time() - anim["start"]) / 1000.0

        position = self._position
        for colour in (DARK, LIGHT):
            for square in cells(position.discs(colour)):
                row, column = row_column(square)
                cx, cy = ox + (column + 0.5) * cell, oy + (row + 0.5) * cell
                shown, squash = colour, 1.0
                if anim is not None:
                    if square in anim["flips"]:
                        shown, squash = self._flip(anim, square, elapsed, colour)
                    elif square == anim["placed"]:
                        grown = min(elapsed / PLACE_MS, 1.0)
                        squash = 0.55 + 0.45 * grown
                self._disc(cr, cx, cy, cell * DISC, shown, squash)

        if self._hints and anim is None:
            red, green, blue = self._ink_for(position.turn)
            cr.set_source_rgba(red, green, blue, 0.45)
            for square in cells(self._hints):
                row, column = row_column(square)
                cr.arc(
                    ox + (column + 0.5) * cell,
                    oy + (row + 0.5) * cell,
                    cell * HINT,
                    0,
                    math.tau,
                )
                cr.fill()

        if self._last is not None:
            row, column = row_column(self._last)
            cr.set_source_rgb(*self._ink["accent"])
            cr.set_line_width(2.0)
            inset = cell * 0.10
            _rounded(
                cr,
                ox + column * cell + inset,
                oy + row * cell + inset,
                cell - 2 * inset,
                cell * 0.16,
            )
            cr.stroke()

    def _flip(self, anim: dict, square: int, elapsed: float, final: int) -> tuple:
        """Which colour a turning disc shows, and how wide it is.

        Edge on at the halfway point, which is where it changes sides -- the
        same thing a hand does with a real disc, and the reason the colour swap
        does not need announcing.
        """
        share = (elapsed - anim["flips"][square]) / FLIP_MS
        if share <= 0:
            return (LIGHT if final == DARK else DARK), 1.0
        if share >= 1:
            return final, 1.0
        shown = final if share >= 0.5 else (LIGHT if final == DARK else DARK)
        return shown, max(abs(math.cos(math.pi * share)), 0.06)

    def _disc(
        self, cr, cx: float, cy: float, radius: float, colour: int, squash: float
    ) -> None:
        cr.save()
        cr.translate(cx, cy)
        cr.scale(squash, 1.0)
        # A shadow under the disc, not a gradient on it: one more flat fill per
        # disc, and it is what stops sixty-four circles reading as printed on.
        cr.set_source_rgba(0, 0, 0, 0.18)
        cr.arc(0, radius * 0.10, radius, 0, math.tau)
        cr.fill()
        cr.set_source_rgb(*self._ink_for(colour))
        cr.arc(0, 0, radius, 0, math.tau)
        cr.fill_preserve()
        cr.set_source_rgb(*self._ink_for(colour, rim=True))
        cr.set_line_width(1.2)
        cr.stroke()
        cr.restore()


class Chip(Gtk.Box):
    """One side of the score line: a disc, a count, and who is holding it."""

    __gtype_name__ = "ReversiChip"

    def __init__(self, colour: int) -> None:
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.colour = colour
        self.add_css_class("side")
        self.set_valign(Gtk.Align.CENTER)

        disc = Gtk.Box()
        disc.add_css_class("chip")
        disc.add_css_class("dark" if colour == DARK else "light")
        disc.set_valign(Gtk.Align.CENTER)
        self.append(disc)

        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        text.set_valign(Gtk.Align.CENTER)
        self._count = Gtk.Label(xalign=0.0)
        self._count.add_css_class("count")
        text.append(self._count)
        # No ellipsize. Every name this can hold is one of six short, fixed
        # words -- YOU, DARK, LIGHT, EASY, MEDIUM, HARD -- and the class on it
        # carries letter-spacing, which Pango adds *after* the last glyph
        # without counting it in the natural width it then ellipsizes against.
        # The result was a chip that said MEDIU… in a box with room to spare.
        self._who = Gtk.Label(xalign=0.0)
        self._who.add_css_class("who")
        text.append(self._who)
        self.append(text)

    def refresh(self, count: int, who: str, playing: bool) -> None:
        self._count.set_text(str(count))
        self._who.set_text(who.upper())
        if playing:
            self.add_css_class("playing")
        else:
            self.remove_css_class("playing")
        self.update_property([Gtk.AccessibleProperty.LABEL], [f"{who}: {count} discs"])


class ScoreLine(Gtk.Box):
    """Both chips, with the board's business between them."""

    __gtype_name__ = "ReversiScoreLine"

    def __init__(self) -> None:
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.set_margin_start(12)
        self.set_margin_end(12)
        self.set_margin_top(6)

        self.dark = Chip(DARK)
        self.append(self.dark)

        spacer = Gtk.Box()
        spacer.set_hexpand(True)
        self.append(spacer)

        self.light = Chip(LIGHT)
        self.append(self.light)

    def refresh(self, position: Position, names: dict[int, str], live: bool) -> None:
        dark, light = position.counts()
        self.dark.refresh(dark, names[DARK], live and position.turn == DARK)
        self.light.refresh(light, names[LIGHT], live and position.turn == LIGHT)
