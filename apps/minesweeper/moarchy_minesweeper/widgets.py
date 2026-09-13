"""The field, and the two readings above it.

One Gtk.DrawingArea rather than a hundred and ninety-two buttons. That is the
same argument Reversi's board makes and it is stronger here than anywhere else
in this repository, because of what a flood is: one tap on a Hard board can open
a hundred and fifty cells, and a hundred and fifty widgets changing state in one
frame is a hundred and fifty style contexts to re-resolve and a hundred and
fifty render nodes to rebuild. Drawn, it is one repaint of a 344px picture.

**Nothing here animates.** Every other board in this repository moves -- discs
flip, cards fly, a peg hops -- and this one does not, on purpose. A tap in
Minesweeper is a question with an immediate answer, and the answer is very often
half the board; an animation would mean a person waiting to find out whether
they had just lost. The one thing that would be worth animating is the flood,
and the flood is exactly the thing nobody wants slowed down.

The size arithmetic: 360px of screen, 8px of margin each side, leaves 344. Hard
is twelve columns, so a cell is 28px -- under the 44px a thumb is usually given,
and the smallest target in this repository. Three things pay for it. A hold
flags rather than opens, so the dangerous action is never the one a slip makes;
a chord opens a whole number's worth of cells from one tap on a 28px target that
is already open and therefore safe; and the flag button latches, so the common
run of twenty flags is twenty taps with no aiming at all.
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
from .minesweeper import Game, index, row_column  # noqa: E402

# A cell, as fractions of itself.
GAP = 0.06
ROUND = 0.18
DIGIT = 0.66
MINE = 0.24
FLAG_POLE = 0.34

# How long a press has to be to mean "flag" rather than "open". GTK's own
# default is 500ms; this is a little shorter, because the gesture is used dozens
# of times a game rather than once, and half a second twenty times is ten
# seconds of somebody's game spent waiting for a flag.
HOLD_MS = 380

# The smallest and largest a cell may be drawn. The floor is where a number
# stops being a number; the ceiling is a phone app dragged wide on a desktop,
# where a 90px minefield is not a more readable one.
MINIMUM_CELL = 22
MAXIMUM_CELL = 58


def _rounded(cr, x: float, y: float, size: float, radius: float) -> None:
    cr.new_sub_path()
    cr.arc(x + size - radius, y + radius, radius, -math.pi / 2, 0)
    cr.arc(x + size - radius, y + size - radius, radius, 0, math.pi / 2)
    cr.arc(x + radius, y + size - radius, radius, math.pi / 2, math.pi)
    cr.arc(x + radius, y + radius, radius, math.pi, 3 * math.pi / 2)
    cr.close_path()


class FieldView(Gtk.DrawingArea):
    """The minefield, drawn once per frame that needs one."""

    __gtype_name__ = "MinesweeperFieldView"

    __gsignals__: ClassVar[dict] = {
        # A cell was tapped, and a cell was held. What either means is the
        # window's business -- the field knows what is drawn on it, not what
        # the rules or the flag button make of a press.
        "cell-tapped": (GObject.SignalFlags.RUN_FIRST, None, (int,)),
        "cell-held": (GObject.SignalFlags.RUN_FIRST, None, (int,)),
    }

    def __init__(self) -> None:
        super().__init__()
        self._game: Game | None = None
        self._held = False

        self.set_hexpand(True)
        self.set_draw_func(self._draw)

        hold = Gtk.GestureLongPress()
        hold.set_delay_factor(HOLD_MS / 500.0)
        hold.connect("pressed", self._on_held)
        self.add_controller(hold)

        click = Gtk.GestureClick()
        click.connect("released", self._on_released)
        self.add_controller(click)

        self.set_colours(theme.fallback(dark=True))

    # --- size ------------------------------------------------------------

    def do_get_request_mode(self) -> Gtk.SizeRequestMode:
        return Gtk.SizeRequestMode.HEIGHT_FOR_WIDTH

    def do_measure(self, orientation, for_size: int) -> tuple:
        level = self._game.level if self._game else None
        columns = level.width if level else 10
        rows = level.height if level else 13
        if orientation == Gtk.Orientation.HORIZONTAL:
            smallest = columns * MINIMUM_CELL
            return smallest, smallest, -1, -1
        cell = min(max(for_size / columns, MINIMUM_CELL), MAXIMUM_CELL)
        height = int(cell * rows)
        return height, height, -1, -1

    # --- what to draw ----------------------------------------------------

    def set_colours(self, palette: theme.Palette) -> None:
        colours = theme.board_colours(palette)
        self._ink = {
            name: theme.rgb(value)
            for name, value in vars(colours).items()
            if isinstance(value, str)
        }
        self._numbers = [theme.rgb(value) for value in colours.numbers]
        self.queue_draw()

    def show(self, game: Game) -> None:
        first = self._game is None or self._game.level is not game.level
        self._game = game
        if first:
            self.queue_resize()
        self.update_property([Gtk.AccessibleProperty.LABEL], [self.describe()])
        self.queue_draw()

    def describe(self) -> str:
        game = self._game
        if game is None:
            return "Minefield"
        if game.lost:
            return "Minefield, a mine went off"
        if game.won:
            return "Minefield, cleared"
        shut = game.level.cells - len(game.opened)
        return (
            f"Minefield, {shut} cells unopened, {game.remaining} mines unaccounted for"
        )

    # --- pressing --------------------------------------------------------

    def _geometry(self, width: int, height: int) -> tuple[float, float, float]:
        level = self._game.level if self._game else None
        if level is None:
            return 0.0, 0.0, 0.0
        cell = min(width / level.width, height / level.height)
        return (
            (width - cell * level.width) / 2,
            (height - cell * level.height) / 2,
            cell,
        )

    def _cell_at(self, x: float, y: float) -> int:
        game = self._game
        if game is None:
            return -1
        ox, oy, cell = self._geometry(self.get_width(), self.get_height())
        if cell <= 0:
            return -1
        column, row = int((x - ox) // cell), int((y - oy) // cell)
        if 0 <= row < game.level.height and 0 <= column < game.level.width:
            return index(row, column, game.level.width)
        return -1

    def _on_held(self, gesture: Gtk.GestureLongPress, x: float, y: float) -> None:
        cell = self._cell_at(x, y)
        if cell < 0:
            return
        # Marked so that the release which follows every long press does not
        # then arrive as a tap and open the cell that was just flagged. The two
        # gestures are not grouped, because grouping them makes the long press
        # swallow the tap on a *short* press as well on some touch stacks.
        self._held = True
        gesture.set_state(Gtk.EventSequenceState.CLAIMED)
        self.emit("cell-held", cell)

    def _on_released(
        self, gesture: Gtk.GestureClick, _n: int, x: float, y: float
    ) -> None:
        if self._held:
            self._held = False
            return
        cell = self._cell_at(x, y)
        if cell < 0:
            return
        gesture.set_state(Gtk.EventSequenceState.CLAIMED)
        self.emit("cell-tapped", cell)

    # --- drawing ---------------------------------------------------------

    def _draw(self, _area, cr, width: int, height: int) -> None:
        game = self._game
        if game is None:
            return
        ox, oy, cell = self._geometry(width, height)
        if cell <= 0:
            return
        gap = max(cell * GAP, 1.0)
        radius = cell * ROUND
        level = game.level
        over = game.over
        mines = game.hidden_mines() if game.lost else set()
        # A won board flags the mines it never needed you to flag. Counting out
        # the last four squares when the outcome is decided is bookkeeping, and
        # the picture of a finished board should be a finished board.
        certain = game.hidden_mines() if game.won else set()
        wrong = game.wrong_flags() if over else set()

        cr.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
        cr.set_font_size(cell * DIGIT)

        for cell_index in range(level.cells):
            row, column = row_column(cell_index, level.width)
            x = ox + column * cell + gap / 2
            y = oy + row * cell + gap / 2
            size = cell - gap

            if cell_index in game.opened:
                boom = cell_index == game.boom
                cr.set_source_rgb(*self._ink["boom" if boom else "pit"])
                _rounded(cr, x, y, size, radius)
                cr.fill()
                if game.is_mine(cell_index):
                    self._mine(cr, x + size / 2, y + size / 2, size)
                    continue
                number = game.count(cell_index)
                if number:
                    self._digit(cr, x, y, size, number)
                continue

            if cell_index in mines:
                # Every mine still in the ground, once one has gone off. The
                # board is over and the question everybody asks is where the
                # rest of them were.
                cr.set_source_rgb(*self._ink["pit"])
                _rounded(cr, x, y, size, radius)
                cr.fill()
                self._mine(cr, x + size / 2, y + size / 2, size)
                continue

            cr.set_source_rgb(*self._ink["lid"])
            _rounded(cr, x, y, size, radius)
            cr.fill()
            # A lighter edge along the top and the left, which is the whole of
            # what makes a flat rectangle read as something raised.
            cr.set_source_rgb(*self._ink["lid_top"])
            cr.set_line_width(1.0)
            cr.move_to(x + radius, y + 0.5)
            cr.line_to(x + size - radius, y + 0.5)
            cr.move_to(x + 0.5, y + radius)
            cr.line_to(x + 0.5, y + size - radius)
            cr.stroke()

            if cell_index in game.flags or cell_index in certain:
                self._flag(cr, x, y, size, crossed=cell_index in wrong)

    def _digit(self, cr, x: float, y: float, size: float, number: int) -> None:
        cr.set_source_rgb(*self._numbers[min(number, len(self._numbers)) - 1])
        label = str(number)
        extents = cr.text_extents(label)
        cr.move_to(
            x + (size - extents.width) / 2 - extents.x_bearing,
            y + (size - extents.height) / 2 - extents.y_bearing,
        )
        cr.show_text(label)

    def _mine(self, cr, cx: float, cy: float, size: float) -> None:
        radius = size * MINE
        cr.set_source_rgb(*self._ink["mine"])
        cr.set_line_width(max(size * 0.07, 1.2))
        for step in range(4):
            angle = math.pi * step / 4
            cr.move_to(
                cx - math.cos(angle) * radius * 1.7, cy - math.sin(angle) * radius * 1.7
            )
            cr.line_to(
                cx + math.cos(angle) * radius * 1.7, cy + math.sin(angle) * radius * 1.7
            )
        cr.stroke()
        cr.arc(cx, cy, radius, 0, math.tau)
        cr.fill()
        # The one glint on it, which is what makes a black circle read as a
        # thing rather than as a hole in the board.
        cr.set_source_rgb(*self._ink["lid_top"])
        cr.arc(cx - radius * 0.32, cy - radius * 0.34, radius * 0.26, 0, math.tau)
        cr.fill()

    def _flag(self, cr, x: float, y: float, size: float, *, crossed: bool) -> None:
        pole_x = x + size * 0.38
        top = y + size * 0.22
        foot = y + size * 0.78
        cr.set_source_rgb(*self._ink["pole"])
        cr.set_line_width(max(size * 0.075, 1.2))
        cr.move_to(pole_x, top)
        cr.line_to(pole_x, foot)
        cr.move_to(pole_x - size * 0.16, foot)
        cr.line_to(pole_x + size * 0.20, foot)
        cr.stroke()
        cr.set_source_rgb(*self._ink["flag"])
        cr.move_to(pole_x, top)
        cr.line_to(pole_x + size * FLAG_POLE, top + size * 0.13)
        cr.line_to(pole_x, top + size * 0.26)
        cr.close_path()
        cr.fill()
        if not crossed:
            return
        # A flag with no mine under it, shown only once the game is over. It is
        # the most useful thing a lost board has to say: not "there was a mine
        # there", but "you were sure about this one and you were wrong".
        cr.set_source_rgb(*self._ink["wrong"])
        cr.set_line_width(max(size * 0.09, 1.5))
        cr.move_to(x + size * 0.18, y + size * 0.18)
        cr.line_to(x + size * 0.82, y + size * 0.82)
        cr.move_to(x + size * 0.82, y + size * 0.18)
        cr.line_to(x + size * 0.18, y + size * 0.82)
        cr.stroke()


class Reading(Gtk.Box):
    """One of the two numbers above the board: a value and what it is."""

    __gtype_name__ = "MinesweeperReading"

    def __init__(self, label: str) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.set_valign(Gtk.Align.CENTER)
        self._value = Gtk.Label()
        self._value.add_css_class("reading")
        self.append(self._value)
        self._label = Gtk.Label(label=label.upper())
        self._label.add_css_class("reading-label")
        self.append(self._label)
        self._name = label

    def refresh(self, value: str, *, low: bool = False, paused: bool = False) -> None:
        self._value.set_text(value)
        for css, on in (("low", low), ("paused", paused)):
            if on:
                self._value.add_css_class(css)
            else:
                self._value.remove_css_class(css)
        self.update_property([Gtk.AccessibleProperty.LABEL], [f"{self._name}: {value}"])
