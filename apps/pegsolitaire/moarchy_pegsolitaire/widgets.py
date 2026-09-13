"""The board, drawn as one cross-shaped plank with holes in it.

One Gtk.DrawingArea rather than thirty-three buttons, for Reversi's reason and
one more of its own: the board is not a grid. It is a cross, and the four
missing corners are not empty cells but places where there is no board -- which
a grid of widgets would have to express as invisible children that are still
laid out, still measured and still there to be tapped by accident.

Drawn as two overlapping rounded rectangles, a tall one and a wide one, filled
with the same colour. The union of those is a cross whose *outer* corners are
rounded and whose inner ones are square, which is what a wooden solitaire board
looks like and is one path each rather than a twelve-segment outline nobody
could adjust afterwards.

The size arithmetic: 360px of screen, 10px of margin each side, leaves 340 for
seven cells of 48. A peg is 29px across and the hole under it is 19, which
sounds small and is not: the tap target is the whole 48px cell, and there is no
row of other pegs above the one being aimed at -- the nearest is a finger's
width away in every direction.
"""

from __future__ import annotations

import math
from typing import ClassVar

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import GLib, GObject, Gtk  # noqa: E402

from . import theme  # noqa: E402
from .pegs import SIZE, Position, cells, index, row_column  # noqa: E402

# One peg hopping over another. Slower than a disc flipping in Reversi, because
# it travels two cells rather than turning over in place, and an arc that is
# over before the eye finds it is a peg that teleported.
HOP_MS = 240.0

# A peg, a hole and the rings, as fractions of a cell.
PEG = 0.30
HOLE = 0.20
RING = 0.40
# How high the hop goes, again as a fraction of a cell. It is what makes the
# move read as "over" rather than "through".
LIFT = 0.42

# The board's edge inside its cells, and how round its outer corners are.
PLANK = 0.06
CORNER = 0.34

# The smallest board worth drawing: 34px cells. Below that a peg is a dot.
MINIMUM = 238
# ...and the largest. A phone app opened on a desktop and dragged wide should
# not answer with a 900px board; past 70px cells a bigger one is not clearer.
MAXIMUM = 490


def _rounded(cr, x: float, y: float, w: float, h: float, radius: float) -> None:
    radius = min(radius, w / 2, h / 2)
    cr.new_sub_path()
    cr.arc(x + w - radius, y + radius, radius, -math.pi / 2, 0)
    cr.arc(x + w - radius, y + h - radius, radius, 0, math.pi / 2)
    cr.arc(x + radius, y + h - radius, radius, math.pi / 2, math.pi)
    cr.arc(x + radius, y + radius, radius, math.pi, 3 * math.pi / 2)
    cr.close_path()


class BoardView(Gtk.DrawingArea):
    """Seven by seven with the corners cut off, drawn once per frame."""

    __gtype_name__ = "PegSolitaireBoardView"

    __gsignals__: ClassVar[dict] = {
        # A hole was tapped. Legality is the window's business: the board knows
        # what is drawn on it, not what the rules make of a tap.
        "hole-activated": (GObject.SignalFlags.RUN_FIRST, None, (int,)),
        # Everything that was moving has stopped.
        "settled": (GObject.SignalFlags.RUN_FIRST, None, ()),
    }

    def __init__(self) -> None:
        super().__init__()
        self._position: Position | None = None
        self._picked: int = -1
        self._drops: tuple[int, ...] = ()
        self._hint: tuple[int, int] = (-1, -1)
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
        offered, centres a square inside itself and leaves a hole between the
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
        self._ink = {n: theme.rgb(value) for n, value in vars(colours).items()}
        self.queue_draw()

    def show(
        self,
        position: Position,
        *,
        picked: int = -1,
        drops: tuple[int, ...] = (),
        hint: tuple[int, int] = (-1, -1),
    ) -> None:
        self._position = position
        self._picked = picked
        self._drops = drops
        self._hint = hint
        self.update_property([Gtk.AccessibleProperty.LABEL], [self.describe()])
        self.queue_draw()

    def describe(self) -> str:
        position = self._position
        if position is None:
            return "Board"
        left = position.count
        if left == 1:
            return "Board, one peg left"
        if position.stuck:
            return f"Board, stuck with {left} pegs"
        return f"Board, {left} pegs, {len(position.moves())} jumps available"

    # --- moving ----------------------------------------------------------

    def animate(self, position: Position, move: int, after: Position) -> None:
        """Show one peg hopping. Emits `settled` when it has landed."""
        self._stop()
        cell = move // 4
        over, landed = position.landing(move)
        self._position = after
        self._picked = -1
        self._drops = ()
        self._hint = (-1, -1)
        if not self._motion_wanted():
            # Reduced motion is a setting people turn on because motion makes
            # them ill. The jump still happens, it simply happens at once.
            self.queue_draw()
            GLib.idle_add(self._settle)
            return
        self._anim = {"start": 0, "from": cell, "over": over, "to": landed}
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
        if (now - anim["start"]) / 1000.0 < HOP_MS:
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

    def _centre(self, ox: float, oy: float, cell: float, hole: int) -> tuple:
        row, column = row_column(hole)
        return ox + (column + 0.5) * cell, oy + (row + 0.5) * cell

    def _on_pressed(
        self, gesture: Gtk.GestureClick, _n: int, x: float, y: float
    ) -> None:
        position = self._position
        if position is None:
            return
        ox, oy, cell = self._geometry(self.get_width(), self.get_height())
        if cell <= 0:
            return  # not laid out yet, so there is nothing under the finger
        column, row = int((x - ox) // cell), int((y - oy) // cell)
        if not (0 <= row < SIZE and 0 <= column < SIZE):
            return
        hole = index(row, column)
        if not position.is_hole(hole):
            # One of the four cut corners. There is no board there, and a tap
            # on it must not clear a selection somebody is in the middle of.
            return
        gesture.set_state(Gtk.EventSequenceState.CLAIMED)
        self.emit("hole-activated", hole)

    # --- drawing ---------------------------------------------------------

    def _draw(self, _area, cr, width: int, height: int) -> None:
        position = self._position
        if position is None:
            return
        ox, oy, cell = self._geometry(width, height)
        self._plank(cr, ox, oy, cell)

        anim = self._anim
        share = 1.0
        if anim is not None:
            clock = self.get_frame_clock()
            if clock is not None and anim["start"]:
                share = min(
                    (clock.get_frame_time() - anim["start"]) / 1000.0 / HOP_MS, 1.0
                )
            else:
                share = 0.0

        for hole in cells(position.holes):
            cx, cy = self._centre(ox, oy, cell, hole)
            cr.set_source_rgb(*self._ink["hole"])
            cr.arc(cx, cy, cell * HOLE, 0, math.tau)
            cr.fill()
            # A lip on the low side, which is all it takes to make a flat dark
            # circle read as a hole rather than as a black counter.
            cr.set_source_rgb(*self._ink["hole_rim"])
            cr.set_line_width(1.2)
            cr.arc(cx, cy + 0.8, cell * HOLE, math.pi * 0.15, math.pi * 0.85)
            cr.stroke()

        for hole in cells(position.pegs):
            if anim is not None and hole == anim["to"]:
                continue  # still in the air
            cx, cy = self._centre(ox, oy, cell, hole)
            self._peg(cr, cx, cy, cell * PEG, 1.0)

        if anim is not None:
            over_x, over_y = self._centre(ox, oy, cell, anim["over"])
            # The peg jumped over goes out as the one jumping passes it, rather
            # than vanishing on the tap. It is the only thing on screen saying
            # which peg was taken.
            taken = max(1.0 - share * 1.8, 0.0)
            if taken > 0:
                self._peg(cr, over_x, over_y, cell * PEG * taken, taken)
            fx, fy = self._centre(ox, oy, cell, anim["from"])
            tx, ty = self._centre(ox, oy, cell, anim["to"])
            lift = math.sin(math.pi * share) * cell * LIFT
            self._peg(
                cr,
                fx + (tx - fx) * share,
                fy + (ty - fy) * share - lift,
                cell * PEG,
                1.0,
            )

        if anim is None:
            self._rings(cr, ox, oy, cell)

    def _plank(self, cr, ox: float, oy: float, cell: float) -> None:
        """The cross, as a tall rectangle and a wide one filled together."""
        pad = cell * PLANK
        radius = cell * CORNER
        cr.set_source_rgb(*self._ink["wood"])
        _rounded(
            cr,
            ox + 2 * cell + pad,
            oy + pad,
            3 * cell - 2 * pad,
            7 * cell - 2 * pad,
            radius,
        )
        cr.fill()
        _rounded(
            cr,
            ox + pad,
            oy + 2 * cell + pad,
            7 * cell - 2 * pad,
            3 * cell - 2 * pad,
            radius,
        )
        cr.fill()

    def _peg(self, cr, cx: float, cy: float, radius: float, alpha: float) -> None:
        if radius <= 0:
            return
        # A shadow under the peg, not a gradient on it: one more flat fill, and
        # it is what stops thirty-two circles reading as printed on.
        cr.set_source_rgba(0, 0, 0, 0.22 * alpha)
        cr.arc(cx, cy + radius * 0.14, radius, 0, math.tau)
        cr.fill()
        cr.set_source_rgb(*self._ink["peg"])
        cr.arc(cx, cy, radius, 0, math.tau)
        cr.fill_preserve()
        cr.set_source_rgb(*self._ink["peg_rim"])
        cr.set_line_width(1.2)
        cr.stroke()
        cr.set_source_rgb(*self._ink["peg_top"])
        cr.arc(cx - radius * 0.26, cy - radius * 0.30, radius * 0.34, 0, math.tau)
        cr.fill()

    def _rings(self, cr, ox: float, oy: float, cell: float) -> None:
        cr.set_line_width(max(cell * 0.085, 2.5))
        if self._picked >= 0:
            cx, cy = self._centre(ox, oy, cell, self._picked)
            cr.set_source_rgb(*self._ink["pick"])
            cr.arc(cx, cy, cell * RING, 0, math.tau)
            cr.stroke()
        for hole in self._drops:
            cx, cy = self._centre(ox, oy, cell, hole)
            cr.set_source_rgb(*self._ink["drop"])
            cr.arc(cx, cy, cell * RING, 0, math.tau)
            cr.stroke()

        peg, landed = self._hint
        if peg < 0:
            return
        # The hint is drawn as an arrow rather than as two more rings, because
        # two rings is what a selection looks like and a person who asked for
        # help should not have to work out which of the two things on the board
        # is the answer.
        fx, fy = self._centre(ox, oy, cell, peg)
        tx, ty = self._centre(ox, oy, cell, landed)
        cr.set_source_rgb(*self._ink["pick"])
        cr.arc(fx, fy, cell * RING, 0, math.tau)
        cr.stroke()
        angle = math.atan2(ty - fy, tx - fx)
        start = cell * RING + 2
        stop = math.hypot(tx - fx, ty - fy) - cell * (HOLE + 0.12)
        cr.move_to(fx + math.cos(angle) * start, fy + math.sin(angle) * start)
        cr.line_to(fx + math.cos(angle) * stop, fy + math.sin(angle) * stop)
        cr.stroke()
        head = cell * 0.22
        tip_x, tip_y = (
            fx + math.cos(angle) * (stop + head),
            fy + math.sin(angle) * (stop + head),
        )
        cr.move_to(tip_x, tip_y)
        cr.line_to(
            tip_x - math.cos(angle - 0.5) * head, tip_y - math.sin(angle - 0.5) * head
        )
        cr.line_to(
            tip_x - math.cos(angle + 0.5) * head, tip_y - math.sin(angle + 0.5) * head
        )
        cr.close_path()
        cr.fill()
