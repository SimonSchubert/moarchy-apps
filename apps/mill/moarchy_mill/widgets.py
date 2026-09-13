"""The board, and the score line above it.

One Gtk.DrawingArea rather than twenty-four widgets, for Reversi's reason and
one more that is this board's own: **a Morris board is not a grid.** It is three
squares and four spokes, the points are at the corners and the midpoints of
those squares, and the gaps between them are not cells -- they are board with
nothing on it. A grid of widgets would have to be a 7x7 with twenty-five holes
in it, laid out and measured and tappable, to describe a shape that here is
nine lines and twenty-four circles.

Which is also why a tap is answered by **the nearest point**, not by the cell it
landed in. The points are 52px apart at 360px wide, so a finger anywhere within
half that distance is unambiguous -- and the spaces between them mean nothing,
so there is nothing to be wrong about by snapping to the closest.

The size arithmetic: 360px of screen, 8px of margin each side, leaves 344. Take
18px of breathing room off each edge so a piece on the outer ring is not clipped
by its own shadow, and the rings sit at 154, 102 and 51 pixels from the middle --
52 apart, with a 34px piece on each point.
"""

from __future__ import annotations

import math
from typing import ClassVar

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import GLib, GObject, Gtk  # noqa: E402

from . import theme  # noqa: E402
from .mill import (  # noqa: E402
    BLACK,
    NAMES,
    OPENING,
    POINTS,
    WHITE,
    Play,
    Position,
    ring_place,
    spots,
)

# A piece being placed arrives at once -- a tap has to be answered in the frame
# it happens in -- and only grows into place.
PLACE_MS = 150.0
# One piece sliding along a line to the next point.
SLIDE_MS = 210.0
# A piece being taken, and the line drawn through the mill that took it. The
# mill goes first: it is the reason the removal is happening.
MILL_MS = 260.0
TAKE_MS = 240.0

# Where the three rings sit, as fractions of the board's half-width.
RINGS = (1.0, 0.66, 0.33)
# Which way each place lies from the middle, clockwise from the top-left.
OFFSETS = (
    (-1, -1),
    (0, -1),
    (1, -1),
    (1, 0),
    (1, 1),
    (0, 1),
    (-1, 1),
    (-1, 0),
)

# A piece, a point and a ring, as fractions of the gap between two rings.
MAN = 0.66
SPOT = 0.13
RING = 0.86
# How far from a point a tap may land and still mean it.
REACH = 0.62
# The margin between the widest thing drawn and the edge of the widget. The
# widest thing is a piece on the outer ring, whose centre is `half` from the
# middle and which is half a piece wider than that again -- so the rings cannot
# simply be a fraction of the widget, they have to be solved for. Getting this
# wrong is not subtle and was not: the first cut put the outer ring at 89% of
# the half-width and photographed with the left and right columns of pieces
# sliced off by the window.
PAD = 18.0
SPREAD = 1.0 + MAN * (RINGS[0] - RINGS[1]) / 2

# The smallest board worth drawing: rings 40px apart, a 26px piece. Below that
# the inner square stops being a square.
MINIMUM = 260
# ...and the largest. A phone app opened on a desktop and dragged wide should
# not answer with a 900px board.
MAXIMUM = 520


class BoardView(Gtk.DrawingArea):
    """Three squares and four spokes, drawn once per frame that needs one."""

    __gtype_name__ = "MillBoardView"

    __gsignals__: ClassVar[dict] = {
        # A point was tapped. Legality is the window's business: the board knows
        # what is drawn on it, not what the rules make of a tap.
        "point-activated": (GObject.SignalFlags.RUN_FIRST, None, (int,)),
        # Everything that was moving has stopped. The window waits for this
        # before it lets the computer think -- see window.py, where the reason
        # is the GIL rather than good manners.
        "settled": (GObject.SignalFlags.RUN_FIRST, None, ()),
    }

    def __init__(self) -> None:
        super().__init__()
        self._position: Position = OPENING
        self._picked = -1
        self._drops: tuple[int, ...] = ()
        self._takeable: tuple[int, ...] = ()
        self._last = -1
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
        """As tall as it is wide, which is the only shape this board has."""
        if orientation == Gtk.Orientation.HORIZONTAL:
            return MINIMUM, MINIMUM, -1, -1
        size = min(max(for_size, MINIMUM), MAXIMUM)
        return size, size, -1, -1

    # --- what to draw ----------------------------------------------------

    def set_colours(self, palette: theme.Palette) -> None:
        colours = theme.board_colours(palette)
        # Parsed here and not in the draw function: a slide repaints every piece
        # on the board sixty times a second, and turning the same dozen hex
        # strings into floats is a cost with nothing behind it on this CPU.
        self._ink = {name: theme.rgb(value) for name, value in vars(colours).items()}
        self.queue_draw()

    def show(
        self,
        position: Position,
        *,
        picked: int = -1,
        drops: tuple[int, ...] = (),
        takeable: tuple[int, ...] = (),
        last: int = -1,
    ) -> None:
        self._position = position
        self._picked = picked
        self._drops = drops
        self._takeable = takeable
        self._last = last
        self.update_property([Gtk.AccessibleProperty.LABEL], [self.describe()])
        self.queue_draw()

    def describe(self) -> str:
        position = self._position
        white, black = position.count(WHITE), position.count(BLACK)
        if position.removing:
            return f"Board, {NAMES[position.turn]} to take a piece"
        return f"Board, white {white}, black {black}, {NAMES[position.turn]} to play"

    # --- moving ----------------------------------------------------------

    def animate(self, before: Position, play: Play, after: Position) -> None:
        """Show one move happening. Emits `settled` when it has stopped."""
        self._stop()
        self._position = after
        self._picked = -1
        self._drops = ()
        self._takeable = ()
        if not self._motion_wanted():
            # Reduced motion is a setting people turn on because motion makes
            # them ill. The move still lands, it simply lands at once.
            self.queue_draw()
            GLib.idle_add(self._settle)
            return
        self._anim = {
            "start": 0,
            "play": play,
            "colour": play.colour,
            "length": self._length(play),
        }
        self._tick = self.add_tick_callback(self._frame)

    def _length(self, play: Play) -> float:
        if play.removed >= 0:
            return TAKE_MS
        base = SLIDE_MS if play.src >= 0 else PLACE_MS
        return base + (MILL_MS if play.mill else 0.0)

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
        if (now - anim["start"]) / 1000.0 < anim["length"]:
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
        size = min(width, height)
        half = max(size / 2 - PAD, 1.0) / SPREAD
        return width / 2, height / 2, half

    def _at(self, cx: float, cy: float, half: float, spot: int) -> tuple[float, float]:
        ring, place = ring_place(spot)
        dx, dy = OFFSETS[place]
        reach = half * RINGS[ring]
        return cx + dx * reach, cy + dy * reach

    def _gap(self, half: float) -> float:
        """The distance between two rings, which sets every other size here."""
        return half * (RINGS[0] - RINGS[1])

    def piece_radius(self, half: float) -> float:
        """Half a piece. Public because the geometry is worth a test.

        Everything drawn here is inside `half * SPREAD + PAD` of the middle by
        construction, and "by construction" is exactly the kind of claim that
        turns out to be false once somebody changes a constant -- so the test
        suite measures it rather than believing it.
        """
        return self._gap(half) * MAN / 2

    def _on_pressed(
        self, gesture: Gtk.GestureClick, _n: int, x: float, y: float
    ) -> None:
        cx, cy, half = self._geometry(self.get_width(), self.get_height())
        if half <= 0:
            return  # not laid out yet, so there is nothing under the finger
        limit = self._gap(half) * REACH
        best, distance = -1, limit
        for spot in range(POINTS):
            px, py = self._at(cx, cy, half, spot)
            away = math.hypot(x - px, y - py)
            if away < distance:
                best, distance = spot, away
        if best < 0:
            return
        gesture.set_state(Gtk.EventSequenceState.CLAIMED)
        self.emit("point-activated", best)

    # --- drawing ---------------------------------------------------------

    def _draw(self, _area, cr, width: int, height: int) -> None:
        cx, cy, half = self._geometry(width, height)
        gap = self._gap(half)
        position = self._position

        cr.set_source_rgb(*self._ink["wood"])
        _rounded(
            cr,
            cx - half - gap * 0.5,
            cy - half - gap * 0.5,
            (half + gap * 0.5) * 2,
            gap * 0.5,
        )
        cr.fill()

        cr.set_source_rgb(*self._ink["line"])
        cr.set_line_width(max(gap * 0.045, 1.5))
        cr.set_line_cap(1)  # cairo.LINE_CAP_ROUND, without importing cairo
        for share in RINGS:
            reach = half * share
            cr.rectangle(cx - reach, cy - reach, reach * 2, reach * 2)
        cr.stroke()
        # The four spokes, from the outer ring's midpoints to the inner ring's.
        for place in (1, 3, 5, 7):
            first = self._at(cx, cy, half, place)
            last = self._at(cx, cy, half, 16 + place)
            cr.move_to(*first)
            cr.line_to(*last)
        cr.stroke()

        cr.set_source_rgb(*self._ink["spot"])
        for spot in range(POINTS):
            px, py = self._at(cx, cy, half, spot)
            cr.arc(px, py, gap * SPOT, 0, math.tau)
            cr.fill()

        anim = self._anim
        elapsed = 0.0
        if anim is not None:
            clock = self.get_frame_clock()
            if clock is not None and anim["start"]:
                elapsed = (clock.get_frame_time() - anim["start"]) / 1000.0

        play = anim["play"] if anim else None
        radius = self.piece_radius(half)

        for colour in (WHITE, BLACK):
            for spot in spots(position.men(colour)):
                if play is not None and spot == play.dst and play.removed < 0:
                    continue  # in flight or growing, drawn below
                px, py = self._at(cx, cy, half, spot)
                self._man(cr, px, py, radius, colour)

        if play is not None:
            self._moving(cr, cx, cy, half, radius, play, elapsed)

        if anim is None:
            self._rings(cr, cx, cy, half, gap)
        elif play is not None and play.mill:
            self._mill_line(cr, cx, cy, half, gap, play, elapsed)

    def _moving(self, cr, cx, cy, half, radius, play: Play, elapsed: float) -> None:
        if play.removed >= 0:
            # The piece being taken shrinks where it stood. It is the only thing
            # on screen saying which piece a mill cost.
            share = max(1.0 - elapsed / TAKE_MS, 0.0)
            if share > 0:
                px, py = self._at(cx, cy, half, play.removed)
                other = BLACK if play.colour == WHITE else WHITE
                self._man(cr, px, py, radius * share, other)
            return
        tx, ty = self._at(cx, cy, half, play.dst)
        if play.src >= 0:
            share = min(elapsed / SLIDE_MS, 1.0)
            share = 1.0 - (1.0 - share) ** 3
            fx, fy = self._at(cx, cy, half, play.src)
            self._man(
                cr, fx + (tx - fx) * share, fy + (ty - fy) * share, radius, play.colour
            )
            return
        grown = min(elapsed / PLACE_MS, 1.0)
        self._man(cr, tx, ty, radius * (0.5 + 0.5 * grown), play.colour)

    def _man(self, cr, px: float, py: float, radius: float, colour: int) -> None:
        if radius <= 0:
            return
        name = "white" if colour == WHITE else "black"
        # A shadow under the piece, not a gradient on it: one more flat fill,
        # and it is what stops eighteen circles reading as printed on.
        cr.set_source_rgba(0, 0, 0, 0.20)
        cr.arc(px, py + radius * 0.12, radius, 0, math.tau)
        cr.fill()
        cr.set_source_rgb(*self._ink[name])
        cr.arc(px, py, radius, 0, math.tau)
        cr.fill_preserve()
        cr.set_source_rgb(*self._ink[f"{name}_rim"])
        cr.set_line_width(1.2)
        cr.stroke()

    def _rings(self, cr, cx, cy, half, gap) -> None:
        cr.set_line_width(max(gap * 0.07, 2.0))
        radius = gap * RING / 2
        if self._last >= 0 and self._picked < 0 and not self._takeable:
            px, py = self._at(cx, cy, half, self._last)
            cr.set_source_rgb(*self._ink["accent"])
            cr.set_line_width(max(gap * 0.05, 1.5))
            cr.arc(px, py, radius, 0, math.tau)
            cr.stroke()
            cr.set_line_width(max(gap * 0.07, 2.0))
        if self._picked >= 0:
            px, py = self._at(cx, cy, half, self._picked)
            cr.set_source_rgb(*self._ink["pick"])
            cr.arc(px, py, radius, 0, math.tau)
            cr.stroke()
        for spot in self._drops:
            px, py = self._at(cx, cy, half, spot)
            cr.set_source_rgb(*self._ink["drop"])
            cr.arc(px, py, radius, 0, math.tau)
            cr.stroke()
        for spot in self._takeable:
            px, py = self._at(cx, cy, half, spot)
            cr.set_source_rgb(*self._ink["take"])
            cr.arc(px, py, radius, 0, math.tau)
            cr.stroke()

    def _mill_line(self, cr, cx, cy, half, gap, play: Play, elapsed: float) -> None:
        """The line drawn through three in a row as it closes.

        It is the whole reward of the move: a mill is not worth anything on the
        board, it is worth the piece it lets you take, and the line is what says
        so in the moment between the two.
        """
        started = SLIDE_MS if play.src >= 0 else PLACE_MS
        share = max(min((elapsed - started) / MILL_MS, 1.0), 0.0)
        if share <= 0:
            return
        first = self._at(cx, cy, half, play.mill[0])
        last = self._at(cx, cy, half, play.mill[-1])
        cr.set_source_rgb(*self._ink["mill"])
        cr.set_line_width(max(gap * 0.09, 2.5))
        cr.move_to(*first)
        cr.line_to(
            first[0] + (last[0] - first[0]) * share,
            first[1] + (last[1] - first[1]) * share,
        )
        cr.stroke()


def _rounded(cr, x: float, y: float, size: float, radius: float) -> None:
    cr.new_sub_path()
    cr.arc(x + size - radius, y + radius, radius, -math.pi / 2, 0)
    cr.arc(x + size - radius, y + size - radius, radius, 0, math.pi / 2)
    cr.arc(x + radius, y + size - radius, radius, math.pi / 2, math.pi)
    cr.arc(x + radius, y + radius, radius, math.pi, 3 * math.pi / 2)
    cr.close_path()


class Chip(Gtk.Box):
    """One side of the score line: a piece, a count, and who is holding it.

    The count is "on the board plus in the hand" -- `7+2` -- because in the
    first half of this game those are two different things and both of them
    matter. A side with three on the board and six to come is not in trouble;
    a side with three on the board and none to come is about to fly.
    """

    __gtype_name__ = "MillChip"

    def __init__(self, colour: int) -> None:
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.colour = colour
        self.add_css_class("side")
        self.set_valign(Gtk.Align.CENTER)

        disc = Gtk.Box()
        disc.add_css_class("chip")
        disc.add_css_class("white" if colour == WHITE else "black")
        disc.set_valign(Gtk.Align.CENTER)
        self.append(disc)

        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        text.set_valign(Gtk.Align.CENTER)
        self._count = Gtk.Label(xalign=0.0)
        self._count.add_css_class("count")
        text.append(self._count)
        # No ellipsize. Every name this can hold is one of five short fixed
        # words, and the class on it carries letter-spacing, which Pango adds
        # after the last glyph without counting it in the natural width it then
        # ellipsizes against -- which is how Reversi's chip said MEDIU…
        self._who = Gtk.Label(xalign=0.0)
        self._who.add_css_class("who")
        text.append(self._who)
        self.append(text)

    def refresh(self, on_board: int, in_hand: int, who: str, playing: bool) -> None:
        self._count.set_text(f"{on_board}+{in_hand}" if in_hand else str(on_board))
        self._who.set_text(who.upper())
        if playing:
            self.add_css_class("playing")
        else:
            self.remove_css_class("playing")
        held = f", {in_hand} to place" if in_hand else ""
        self.update_property(
            [Gtk.AccessibleProperty.LABEL], [f"{who}: {on_board} on the board{held}"]
        )


class ScoreLine(Gtk.Box):
    """Both chips, with the board's business between them."""

    __gtype_name__ = "MillScoreLine"

    def __init__(self) -> None:
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.set_margin_start(12)
        self.set_margin_end(12)
        self.set_margin_top(6)

        self.white = Chip(WHITE)
        self.append(self.white)

        spacer = Gtk.Box()
        spacer.set_hexpand(True)
        self.append(spacer)

        self.black = Chip(BLACK)
        self.append(self.black)

    def refresh(self, position: Position, names: dict[int, str], live: bool) -> None:
        for colour, chip in ((WHITE, self.white), (BLACK, self.black)):
            chip.refresh(
                position.count(colour),
                position.left(colour),
                names[colour],
                live and position.turn == colour,
            )
