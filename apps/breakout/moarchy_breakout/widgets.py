"""The field: one drawing area, one multiplication, sixty times a second.

Everything the world knows is measured in widths -- see `breakout.py` -- so this
widget's entire job is to work out one number, the pixels in a width, and
multiply by it. That is why there is no layout arithmetic in here worth the
name: the field is a fixed shape, the shape is `HEIGHT` widths tall, and a
window that is wider than it is tall gets a narrower field rather than a
stretched one, because a stretched Breakout is a different game.

The frame loop is not here. The window owns it, and installs its tick callback
on this widget -- because the world is the window's state, the events a step
produces are the window's business, and a widget that ran the physics would be a
widget that had to be told when to stop.

What is here is the one thing the drawing has to say that the colours do not:
**a brick with another hit left carries an inset line.** Eight rows of eight
hues is what a Breakout wall has always looked like, and hue cannot also carry
how tough a brick is without asking somebody to hold sixteen colours apart.
"""

from __future__ import annotations

import math
from typing import ClassVar

import cairo
import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import GObject, Gtk  # noqa: E402

from . import theme  # noqa: E402
from .breakout import (  # noqa: E402
    BALL,
    BAT_H,
    BAT_W,
    BAT_Y,
    BRICK_H,
    BRICK_W,
    COLUMNS,
    HEIGHT,
    WIDTH,
    World,
    brick_rect,
)

# A brick's gap from its neighbours and how round its corners are, as fractions
# of a brick.
MORTAR = 0.10
BRICK_ROUND = 0.22

# The smallest field worth playing on: 240px across, which puts a brick at 34px
# and the ball at 8. Below that the ball is a dot.
MINIMUM = 240
# ...and the largest. This is a phone game; past 520px across, the ball takes
# long enough to cross the field that the rally stops being one.
MAXIMUM = 520


def _rounded(cr, x: float, y: float, w: float, h: float, radius: float) -> None:
    radius = min(radius, w / 2, h / 2)
    cr.new_sub_path()
    cr.arc(x + w - radius, y + radius, radius, -math.pi / 2, 0)
    cr.arc(x + w - radius, y + h - radius, radius, 0, math.pi / 2)
    cr.arc(x + radius, y + h - radius, radius, math.pi / 2, math.pi)
    cr.arc(x + radius, y + radius, radius, math.pi, 3 * math.pi / 2)
    cr.close_path()


class FieldView(Gtk.DrawingArea):
    """The wall, the bat and the ball, drawn once a frame."""

    __gtype_name__ = "BreakoutFieldView"

    __gsignals__: ClassVar[dict] = {
        # Somewhere on the field was pressed or dragged to, in widths. The bat
        # follows a finger absolutely and from anywhere, so this is a position
        # rather than a direction -- see window.py for why.
        "aimed": (GObject.SignalFlags.RUN_FIRST, None, (float,)),
        "launched": (GObject.SignalFlags.RUN_FIRST, None, ()),
    }

    def __init__(self) -> None:
        super().__init__()
        self._world: World | None = None
        self._start = 0.0
        self.set_hexpand(True)
        self.set_draw_func(self._draw)

        drag = Gtk.GestureDrag()
        drag.connect("drag-begin", self._on_begin)
        drag.connect("drag-update", self._on_update)
        self.add_controller(drag)
        self.set_colours(theme.fallback(dark=True))

    def do_get_request_mode(self) -> Gtk.SizeRequestMode:
        return Gtk.SizeRequestMode.HEIGHT_FOR_WIDTH

    def do_measure(self, orientation, for_size: int) -> tuple:
        if orientation == Gtk.Orientation.HORIZONTAL:
            return MINIMUM, MINIMUM, -1, -1
        across = min(max(for_size, MINIMUM), MAXIMUM)
        tall = int(across * HEIGHT)
        return tall, tall, -1, -1

    # --- what to draw ----------------------------------------------------

    def set_colours(self, palette: theme.Palette) -> None:
        colours = theme.board_colours(palette)
        self._ink = {
            name: theme.rgb(value)
            for name, value in vars(colours).items()
            if isinstance(value, str)
        }
        self._rows = [theme.rgb(value) for value in colours.rows]
        self.queue_draw()

    def show(self, world: World) -> None:
        self._world = world
        self.update_property([Gtk.AccessibleProperty.LABEL], [self.describe()])
        self.queue_draw()

    def describe(self) -> str:
        world = self._world
        if world is None:
            return "Field"
        if world.dead:
            return f"Field, game over, {world.score} points"
        return (
            f"Field, {world.standing} bricks left, {world.lives} lives, "
            f"{world.score} points"
        )

    # --- pointing --------------------------------------------------------

    def _scale(self) -> tuple[float, float, float]:
        """(x offset, y offset, pixels per width) for the current size."""
        width, height = self.get_width(), self.get_height()
        across = min(width, height / HEIGHT)
        return (width - across) / 2, (height - across * HEIGHT) / 2, across

    def _on_begin(self, _gesture, x: float, y: float) -> None:
        ox, _, across = self._scale()
        if across <= 0:
            return
        self._start = x
        self.emit("aimed", (x - ox) / across)
        # A press is also a launch. A tap and the first frame of a drag are the
        # same gesture on a touch screen, and asking for two would mean a person
        # tapping to serve and then reaching for the bat.
        self.emit("launched")

    def _on_update(self, _gesture, dx: float, _dy: float) -> None:
        ox, _, across = self._scale()
        if across <= 0:
            return
        self.emit("aimed", (self._start + dx - ox) / across)

    # --- drawing ---------------------------------------------------------

    def _draw(self, _area, cr, width: int, height: int) -> None:
        world = self._world
        if world is None:
            return
        ox, oy, across = self._scale()
        if across <= 0:
            return

        cr.set_source_rgb(*self._ink["field"])
        _rounded(cr, ox, oy, across, across * HEIGHT, across * 0.03)
        cr.fill()

        cr.save()
        cr.translate(ox, oy)
        cr.scale(across, across)

        gap = BRICK_W * MORTAR
        for cell, left in enumerate(world.bricks):
            if not left:
                continue
            x, y, w, h = brick_rect(cell)
            row = cell // COLUMNS
            cr.set_source_rgb(*self._rows[row % len(self._rows)])
            _rounded(
                cr,
                x + gap / 2,
                y + gap / 4,
                w - gap,
                h - gap / 2,
                BRICK_H * BRICK_ROUND,
            )
            cr.fill()
            if left > 1:
                # The groove that says this one is not done yet. One line per
                # hit still owed, in the field's own colour so it reads as an
                # absence rather than as another thing on the screen.
                cr.set_source_rgb(*self._ink["tough"])
                cr.set_line_width(BRICK_H * 0.10)
                for step in range(min(left - 1, 2)):
                    inset = gap * 0.9 + step * BRICK_H * 0.22
                    _rounded(
                        cr,
                        x + inset,
                        y + inset * 0.55,
                        w - inset * 2,
                        h - inset * 1.1,
                        BRICK_H * BRICK_ROUND,
                    )
                    cr.stroke()

        half = BAT_W / 2
        cr.set_source_rgb(*self._ink["bat"])
        _rounded(cr, world.bat - half, BAT_Y - BAT_H / 2, BAT_W, BAT_H, BAT_H / 2)
        cr.fill()
        cr.set_source_rgb(*self._ink["bat_rim"])
        cr.set_line_width(BAT_H * 0.16)
        cr.move_to(world.bat - half * 0.7, BAT_Y - BAT_H * 0.18)
        cr.line_to(world.bat + half * 0.7, BAT_Y - BAT_H * 0.18)
        cr.stroke()

        cr.set_source_rgb(*self._ink["ball"])
        cr.arc(world.ball_x, world.ball_y, BALL, 0, math.tau)
        cr.fill_preserve()
        cr.set_source_rgb(*self._ink["ball_rim"])
        cr.set_line_width(BALL * 0.16)
        cr.stroke()
        cr.restore()

        if not world.served and not world.dead:
            self._prompt(cr, ox, oy, across, world)

    def _prompt(self, cr, ox: float, oy: float, across: float, world: World) -> None:
        """The line under the bat that says what to do with it.

        Drawn on the field rather than put in a label under it, because this is
        the one moment the game is waiting for the person and the person is
        looking at the field.
        """
        cr.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
        cr.set_font_size(across * 0.038)
        text = "Tap to serve" if world.ready else "Ready…"
        cr.set_source_rgb(*self._ink["dim"])
        extents = cr.text_extents(text)
        cr.move_to(
            ox + across * WIDTH / 2 - extents.width / 2,
            oy + across * (BAT_Y + 0.055),
        )
        cr.show_text(text)


class Lives(Gtk.Box):
    """The lives left, as a row of small circles.

    Three of anything is faster to read as three shapes than as a digit, and
    this is a number somebody glances at in the middle of a rally without taking
    their eye off a moving ball.
    """

    __gtype_name__ = "BreakoutLives"

    def __init__(self, most: int) -> None:
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=5)
        self.set_valign(Gtk.Align.CENTER)
        self._dots = []
        for _ in range(most):
            dot = Gtk.Box()
            dot.add_css_class("life")
            dot.set_valign(Gtk.Align.CENTER)
            self.append(dot)
            self._dots.append(dot)

    def refresh(self, left: int) -> None:
        for index, dot in enumerate(self._dots):
            if index < left:
                dot.remove_css_class("spent")
            else:
                dot.add_css_class("spent")
        self.update_property([Gtk.AccessibleProperty.LABEL], [f"{left} lives left"])
