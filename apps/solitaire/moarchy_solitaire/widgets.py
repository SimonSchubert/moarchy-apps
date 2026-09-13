"""The table: one drawing area, fifty-two cards, and where a tap lands.

Everything is drawn. Fifty-two widgets in seven overlapping stacks is not a
layout GTK has, and building one out of overlays would be fifty-two style
contexts to resolve and fifty-two render nodes to submit for a picture whose
shape is arithmetic. One drawing area is one node: a tap is a rectangle test and
a move is a repaint of a 360px-wide picture in cairo, which is the renderer this
runs under anyway -- there is no GL on a Mali-400 and none in the container
these screenshots come from.

The size arithmetic is the whole layout. 360px of screen, 5px of margin each
side and 4px between columns leaves seven cards of 46px, and a card is 46 by 67.
That is well under the 44px a thumb is usually given, and it is why **a tap is
tested against a column rather than against a card**: the hit area of every
tableau pile is the full 50px stride including the gap, so there is no dead
ground between two columns and a thumb landing on the join gets the nearer one.

What is visible of a covered card is a 20px strip at its top, so the index --
the rank and its pip -- lives in that strip and nowhere else. A card's second
index, the one printed upside down in the far corner of a real card, is left off
entirely: it would be under the card in front of it every time.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import ClassVar

import cairo
import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import GLib, GObject, Gtk  # noqa: E402

from . import theme  # noqa: E402
from .klondike import (  # noqa: E402
    COLUMNS,
    DIAMOND,
    FOUNDATION,
    HEART,
    RANK_NAMES,
    SPADE,
    STOCK,
    SUITS,
    TABLEAU,
    WASTE,
    Move,
    Table,
    is_foundation,
    is_red,
    is_tableau,
    name,
    rank,
    suit,
)

# A card, as a ratio. Poker cards are 2.5 by 3.5; this is a little squarer,
# because the width is fixed by seven columns on a 360px screen and the height
# is what pays for the extra tableau rows.
ASPECT = 1.45

MARGIN = 5.0
GAP = 4.0
# Between the top row and the tableau. Enough that the two are separate things.
SPLIT = 12.0

# How much of a covered card shows. The face-up figure is the one that has to
# hold an index; the face-down one only has to say "there is another card here".
#
# Fixed rather than fitted to the tallest column. Spreading the cards out to
# fill the screen would be a better use of a 720px phone right up until a column
# grew or shrank, at which point every card on the table would move -- and a
# table that rearranges itself under a thumb is a table nobody can aim at. 0.42
# of a card is what makes a column of six face-down and thirteen face-up cards,
# which is the tallest a Klondike column gets, land exactly on the bottom of a
# 360x720 screen.
UP_SHARE = 0.42
DOWN_SHARE = 0.14
# ...and how far either may be squeezed when a column grows past the screen.
# Below this a column stops being readable as cards at all, and the app would
# rather run off the bottom, where a scroll is at least a thing people know.
SQUEEZE = 0.45

# How far the three cards of a draw-three deal are fanned across the waste. They
# spread into the empty slot between the waste and the first foundation, which
# is the only reason that slot is empty.
FAN = 0.34

# One move gliding from where it was to where it is going.
FLIGHT_MS = 170.0

# The smallest table worth drawing. Below this a card is under 34px and the rank
# in the corner stops being a letter.
MINIMUM = 290


@dataclass(frozen=True)
class Layout:
    """Where everything is, worked out once per frame from the widget size."""

    card_w: float
    card_h: float
    stride: float
    left: float
    top: float
    tableau_y: float
    up_step: float
    down_step: float

    def slot_x(self, index: int) -> float:
        return self.left + index * self.stride


def _column_of(pile: int) -> int:
    """Which of the seven slots across the screen a pile sits in.

    The stock and the waste take the first two, the four foundations take the
    last four, and the slot between them is left empty on purpose: it is where a
    three-card deal fans out to.
    """
    if pile == STOCK:
        return 0
    if pile == WASTE:
        return 1
    if is_foundation(pile):
        return 3 + (pile - FOUNDATION)
    return pile - TABLEAU


def layout_for(width: float, height: float, table: Table) -> Layout:
    width = max(width, MINIMUM)
    card_w = (width - 2 * MARGIN - (COLUMNS - 1) * GAP) / COLUMNS
    card_h = card_w * ASPECT
    stride = card_w + GAP
    left = (width - (COLUMNS * card_w + (COLUMNS - 1) * GAP)) / 2
    tableau_y = MARGIN + card_h + SPLIT

    up_step = card_h * UP_SHARE
    down_step = card_h * DOWN_SHARE
    # The tallest column decides the squeeze for all seven, so that a card is
    # the same size everywhere on the table. Seven different overlaps would be
    # seven different-looking columns of the same fifty-two cards.
    tallest = 0.0
    for index in range(COLUMNS):
        hidden = table.down[index]
        shown = max(len(table.piles[index]) - hidden, 0)
        tallest = max(tallest, hidden * down_step + max(shown - 1, 0) * up_step)
    room = height - tableau_y - card_h - MARGIN
    if tallest > room > 0:
        shrink = max(room / tallest, SQUEEZE)
        up_step *= shrink
        down_step *= shrink
    return Layout(
        card_w=card_w,
        card_h=card_h,
        stride=stride,
        left=left,
        top=MARGIN,
        tableau_y=tableau_y,
        up_step=up_step,
        down_step=down_step,
    )


def card_at(layout: Layout, table: Table, pile: int, position: int) -> tuple:
    """The rectangle a given card in a given pile occupies."""
    x = layout.slot_x(_column_of(pile))
    if is_tableau(pile):
        hidden = table.hidden(pile)
        if position < hidden:
            offset = position * layout.down_step
        else:
            offset = hidden * layout.down_step + (position - hidden) * layout.up_step
        return x, layout.tableau_y + offset, layout.card_w, layout.card_h
    if pile == WASTE:
        # Only the last few are drawn, fanned to the right. `position` is an
        # index into the whole waste, so it is turned into a place in the fan.
        shown = min(len(table.waste), table.draw)
        place = position - (len(table.waste) - shown)
        offset = max(place, 0) * layout.card_w * FAN
        return x + offset, layout.top, layout.card_w, layout.card_h
    return x, layout.top, layout.card_w, layout.card_h


def _rounded(cr, x: float, y: float, w: float, h: float, radius: float) -> None:
    cr.new_sub_path()
    cr.arc(x + w - radius, y + radius, radius, -math.pi / 2, 0)
    cr.arc(x + w - radius, y + h - radius, radius, 0, math.pi / 2)
    cr.arc(x + radius, y + h - radius, radius, math.pi / 2, math.pi)
    cr.arc(x + radius, y + radius, radius, math.pi, 3 * math.pi / 2)
    cr.close_path()


def _pip(cr, cx: float, cy: float, size: float, which: int) -> None:
    """One suit symbol, as a path. Four shapes, no font, no SVG, no dependency.

    A pip drawn from a font would be a font question -- the phone's icon theme
    is not the desktop's and neither is its font stack, and a card whose suit
    renders as a box is a card nobody can play. Four paths is thirty lines and
    it is the same drawing at 8px and at 30.
    """
    if which == DIAMOND:
        cr.move_to(cx, cy - size)
        cr.line_to(cx + size * 0.74, cy)
        cr.line_to(cx, cy + size)
        cr.line_to(cx - size * 0.74, cy)
        cr.close_path()
        cr.fill()
        return
    if which == HEART:
        cr.move_to(cx, cy + size)
        cr.curve_to(
            cx - size * 1.30,
            cy - size * 0.20,
            cx - size * 0.55,
            cy - size * 1.25,
            cx,
            cy - size * 0.35,
        )
        cr.curve_to(
            cx + size * 0.55,
            cy - size * 1.25,
            cx + size * 1.30,
            cy - size * 0.20,
            cx,
            cy + size,
        )
        cr.close_path()
        cr.fill()
        return
    if which == SPADE:
        cr.move_to(cx, cy - size)
        cr.curve_to(
            cx + size * 1.30,
            cy + size * 0.20,
            cx + size * 0.55,
            cy + size * 1.05,
            cx,
            cy + size * 0.30,
        )
        cr.curve_to(
            cx - size * 0.55,
            cy + size * 1.05,
            cx - size * 1.30,
            cy + size * 0.20,
            cx,
            cy - size,
        )
        cr.close_path()
        cr.fill()
    else:
        lobe = size * 0.46
        cr.arc(cx, cy - size * 0.42, lobe, 0, math.tau)
        cr.fill()
        cr.arc(cx - size * 0.58, cy + size * 0.34, lobe, 0, math.tau)
        cr.fill()
        cr.arc(cx + size * 0.58, cy + size * 0.34, lobe, 0, math.tau)
        cr.fill()
    # The stem both black suits have, and the one thing that stops a club being
    # three dots and a spade being an upside-down heart at 8px.
    cr.move_to(cx - size * 0.40, cy + size)
    cr.curve_to(
        cx - size * 0.12,
        cy + size * 0.55,
        cx + size * 0.12,
        cy + size * 0.55,
        cx + size * 0.40,
        cy + size,
    )
    cr.close_path()
    cr.fill()


class TableView(Gtk.DrawingArea):
    """The whole game, drawn once per frame that needs one."""

    __gtype_name__ = "SolitaireTableView"

    __gsignals__: ClassVar[dict] = {
        # Somewhere was tapped: a pile, and which card in it. Legality is the
        # window's business -- the table knows what is drawn on it, not what the
        # rules make of a tap.
        "pile-tapped": (GObject.SignalFlags.RUN_FIRST, None, (int, int)),
        # Everything that was moving has stopped.
        "settled": (GObject.SignalFlags.RUN_FIRST, None, ()),
    }

    def __init__(self) -> None:
        super().__init__()
        self._table: Table | None = None
        self._selected: tuple[int, int] | None = None
        self._drops: tuple[int, ...] = ()
        self._flight: dict | None = None
        self._tick = 0

        self.set_hexpand(True)
        self.set_vexpand(True)
        self.set_draw_func(self._draw)

        click = Gtk.GestureClick()
        click.connect("pressed", self._on_pressed)
        self.add_controller(click)
        self.set_colours(theme.fallback(dark=True))

    def do_measure(self, orientation, _for_size: int) -> tuple:
        if orientation == Gtk.Orientation.HORIZONTAL:
            return MINIMUM, MINIMUM, -1, -1
        # Tall enough for the top row and a column of thirteen at the squeeze
        # floor. Anything taller is room the window can give to the picture.
        card_h = (MINIMUM / COLUMNS) * ASPECT
        need = MARGIN + card_h + SPLIT + card_h + 12 * card_h * UP_SHARE * SQUEEZE
        return int(need), int(need), -1, -1

    # --- what to draw ----------------------------------------------------

    def set_colours(self, palette: theme.Palette) -> None:
        colours = theme.board_colours(palette)
        # Parsed here and not in the draw function: a move repaints every card
        # on the table, and turning the same twelve hex strings into floats on
        # every frame is a cost with nothing behind it on this CPU.
        self._ink = {n: theme.rgb(value) for n, value in vars(colours).items()}
        self.queue_draw()

    def show(
        self,
        table: Table,
        *,
        selected: tuple[int, int] | None = None,
        drops: tuple[int, ...] = (),
    ) -> None:
        self._table = table
        self._selected = selected
        self._drops = drops
        self.update_property([Gtk.AccessibleProperty.LABEL], [self.describe()])
        self.queue_draw()

    def describe(self) -> str:
        table = self._table
        if table is None:
            return "Table"
        if table.won:
            return "Table, every card home"
        hidden = sum(table.down)
        return (
            f"Table, {table.home} cards home, {hidden} face down, "
            f"{len(table.stock)} in the stock"
        )

    # --- moving ----------------------------------------------------------

    def animate(self, before: Table, move: Move, after: Table) -> None:
        """Show one move travelling. Emits `settled` when it has landed."""
        self._stop()
        self._table = after
        self._selected = None
        self._drops = ()
        if not self._motion_wanted() or move.dst == STOCK:
            # Reduced motion is a setting people turn on because motion makes
            # them ill -- and a whole waste turning face down is not a card
            # travelling anywhere, it is the pile changing sides.
            self.queue_draw()
            GLib.idle_add(self._settle)
            return

        width, height = self.get_width(), self.get_height()
        if width <= 0 or height <= 0:
            self.queue_draw()
            GLib.idle_add(self._settle)
            return
        was = layout_for(width, height, before)
        now = layout_for(width, height, after)
        held = before.cards_in(move.src)
        run = before.run_from(move.src, held - move.count)
        landed = after.cards_in(move.dst)
        legs = []
        for index, card in enumerate(run):
            fx, fy, _, _ = card_at(was, before, move.src, held - move.count + index)
            tx, ty, _, _ = card_at(now, after, move.dst, landed - len(run) + index)
            legs.append((card, fx, fy, tx, ty))
        self._flight = {
            "start": 0,
            "legs": legs,
            "dst": move.dst,
            "count": len(run),
            # A deal comes off the stock face down and arrives face up, so the
            # cards in the air are the only ones on the table that are neither.
            "from_stock": move.src == STOCK,
        }
        self._tick = self.add_tick_callback(self._frame)

    def _motion_wanted(self) -> bool:
        settings = Gtk.Settings.get_default()
        return settings is None or settings.props.gtk_enable_animations

    def _frame(self, _widget, clock) -> bool:
        flight = self._flight
        if flight is None:
            return GLib.SOURCE_REMOVE
        now = clock.get_frame_time()
        if not flight["start"]:
            flight["start"] = now
        self.queue_draw()
        if (now - flight["start"]) / 1000.0 < FLIGHT_MS:
            return GLib.SOURCE_CONTINUE
        self._flight = None
        self._tick = 0
        self._settle()
        return GLib.SOURCE_REMOVE

    def _stop(self) -> None:
        if self._tick:
            self.remove_tick_callback(self._tick)
            self._tick = 0
        self._flight = None

    def _settle(self) -> bool:
        self.emit("settled")
        return GLib.SOURCE_REMOVE

    @property
    def busy(self) -> bool:
        return self._flight is not None

    # --- tapping ---------------------------------------------------------

    def _on_pressed(
        self, gesture: Gtk.GestureClick, _n: int, x: float, y: float
    ) -> None:
        table = self._table
        if table is None:
            return
        found = self.pile_at(x, y)
        if found is None:
            return
        gesture.set_state(Gtk.EventSequenceState.CLAIMED)
        self.emit("pile-tapped", found[0], found[1])

    def pile_at(self, x: float, y: float) -> tuple[int, int] | None:
        """Which pile and which card is under this point.

        Deliberately generous sideways and strict downwards. The stride is the
        hit area, so there is no dead gap between two columns; the top of a card
        is where it is, because a column is a stack of strips and guessing at
        those would mean picking up the wrong run.
        """
        table = self._table
        if table is None:
            return None
        layout = layout_for(self.get_width(), self.get_height(), table)
        index = int((x - layout.left + GAP / 2) // layout.stride)
        if not 0 <= index < COLUMNS:
            return None

        if y < layout.tableau_y - SPLIT / 2:
            for pile in (STOCK, WASTE, *range(FOUNDATION, TABLEAU)):
                if _column_of(pile) == index:
                    return pile, max(table.cards_in(pile) - 1, 0)
            if index == 2 and table.waste:
                # The empty slot the waste fans into. A tap there means the
                # card lying in it, which is the top of the waste.
                return WASTE, len(table.waste) - 1
            return None

        pile = TABLEAU + index
        column = table.column(pile)
        if not column:
            return pile, 0
        for position in range(len(column) - 1, -1, -1):
            _, cy, _, ch = card_at(layout, table, pile, position)
            if y >= cy:
                return (pile, position) if y <= cy + ch else None
        return pile, 0

    # --- drawing ---------------------------------------------------------

    def _draw(self, _area, cr, width: int, height: int) -> None:
        cr.set_source_rgb(*self._ink["baize"])
        cr.paint()
        table = self._table
        if table is None:
            return
        layout = layout_for(width, height, table)
        flight = self._flight
        skip_pile, skip_count = (flight["dst"], flight["count"]) if flight else (-1, 0)

        cr.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)

        # --- the top row
        self._slot(cr, layout, STOCK, table)
        if table.stock:
            x, y, w, h = card_at(layout, table, STOCK, len(table.stock) - 1)
            self._back(cr, x, y, w, h)
        elif table.waste:
            self._recycle(cr, layout)

        self._slot(cr, layout, WASTE, table)
        shown = min(len(table.waste), table.draw)
        drawn = shown - (skip_count if skip_pile == WASTE else 0)
        for place in range(max(drawn, 0)):
            position = len(table.waste) - shown + place
            x, y, w, h = card_at(layout, table, WASTE, position)
            self._face(cr, x, y, w, h, table.waste[position], full=place == shown - 1)

        for index in range(SUITS):
            pile = FOUNDATION + index
            self._slot(cr, layout, pile, table)
            count = table.up[index] - (skip_count if skip_pile == pile else 0)
            if count > 0:
                card = (count - 1) * SUITS + index
                x, y, w, h = card_at(layout, table, pile, count - 1)
                self._face(cr, x, y, w, h, card, full=True)

        # --- the seven columns
        for index in range(COLUMNS):
            pile = TABLEAU + index
            column = table.column(pile)
            hidden = table.hidden(pile)
            if not column:
                self._slot(cr, layout, pile, table)
                continue
            last = len(column) - (skip_count if skip_pile == pile else 0)
            for position in range(max(last, 0)):
                x, y, w, h = card_at(layout, table, pile, position)
                if position < hidden:
                    self._back(cr, x, y, w, h)
                else:
                    self._face(
                        cr, x, y, w, h, column[position], full=position == last - 1
                    )

        self._highlight(cr, layout, table)

        if flight is not None:
            clock = self.get_frame_clock()
            share = 1.0
            if clock is not None and flight["start"]:
                share = min(
                    (clock.get_frame_time() - flight["start"]) / 1000.0 / FLIGHT_MS, 1.0
                )
            # Out-cubic: a card thrown across a table arrives slowing down.
            share = 1.0 - (1.0 - share) ** 3
            for card, fx, fy, tx, ty in flight["legs"]:
                x = fx + (tx - fx) * share
                y = fy + (ty - fy) * share
                if flight["from_stock"] and share < 0.5:
                    self._back(cr, x, y, layout.card_w, layout.card_h)
                else:
                    self._face(cr, x, y, layout.card_w, layout.card_h, card, full=True)

    # --- the pieces of it ------------------------------------------------

    def _slot(self, cr, layout: Layout, pile: int, table: Table) -> None:
        x, y, w, h = card_at(layout, table, pile, 0)
        cr.set_source_rgb(*self._ink["slot"])
        _rounded(cr, x, y, w, h, w * 0.12)
        cr.fill()
        if is_foundation(pile):
            # The suit that belongs here, faintly. A foundation with nothing on
            # it is otherwise four identical holes, and the first ace of the
            # game has to be put somewhere by somebody who has not memorised
            # the order the suits are in.
            cr.set_source_rgb(*self._ink["slot_ink"])
            _pip(cr, x + w / 2, y + h / 2, h * 0.20, pile - FOUNDATION)

    def _recycle(self, cr, layout: Layout) -> None:
        """The arrow on an empty stock. Three quarters of a circle and a head.

        Not an icon from the theme: this is inside a drawing area, the icon
        would have to be rendered to a texture and scaled, and the phone's icon
        theme is not the desktop's -- which is the failure `moarchy_ui.icons`
        exists for and cannot help with here.
        """
        x = layout.slot_x(_column_of(STOCK))
        cx, cy = x + layout.card_w / 2, layout.top + layout.card_h / 2
        radius = layout.card_h * 0.20
        cr.set_source_rgb(*self._ink["slot_ink"])
        cr.set_line_width(max(layout.card_h * 0.045, 1.5))
        cr.arc(cx, cy, radius, math.pi * 0.65, math.pi * 2.15)
        cr.stroke()
        head = radius * 0.55
        tip_x, tip_y = (
            cx + radius * math.cos(math.pi * 0.65),
            cy + radius * math.sin(math.pi * 0.65),
        )
        cr.move_to(tip_x - head * 0.2, tip_y - head)
        cr.line_to(tip_x + head, tip_y + head * 0.15)
        cr.line_to(tip_x - head * 0.9, tip_y + head * 0.5)
        cr.close_path()
        cr.fill()

    def _back(self, cr, x: float, y: float, w: float, h: float) -> None:
        cr.set_source_rgb(*self._ink["back"])
        _rounded(cr, x, y, w, h, w * 0.12)
        cr.fill()
        cr.set_source_rgb(*self._ink["back_line"])
        cr.set_line_width(1.0)
        _rounded(cr, x + 0.5, y + 0.5, w - 1, h - 1, w * 0.12)
        cr.stroke()
        # A lattice rather than a picture. It is four strokes, it is the same at
        # any size, and it is the one thing that makes a stack of backs read as
        # a stack rather than as a coloured rectangle.
        cr.save()
        _rounded(cr, x + 3, y + 3, w - 6, h - 6, w * 0.09)
        cr.clip()
        cr.set_line_width(1.0)
        step = w * 0.30
        offset = -h
        while offset < w + h:
            cr.move_to(x + offset, y)
            cr.line_to(x + offset + h, y + h)
            offset += step
        cr.stroke()
        cr.restore()

    def _face(
        self, cr, x: float, y: float, w: float, h: float, card: int, *, full: bool
    ) -> None:
        cr.set_source_rgb(*self._ink["face"])
        _rounded(cr, x, y, w, h, w * 0.12)
        cr.fill()
        cr.set_source_rgb(*self._ink["edge"])
        cr.set_line_width(1.0)
        _rounded(cr, x + 0.5, y + 0.5, w - 1, h - 1, w * 0.12)
        cr.stroke()

        cr.set_source_rgb(*self._ink["blood" if is_red(card) else "ink"])
        label = RANK_NAMES[rank(card)]
        size = h * 0.27
        cr.set_font_size(size)
        extents = cr.text_extents(label)
        cr.move_to(x + w * 0.11, y + h * 0.055 + extents.height)
        cr.show_text(label)
        _pip(cr, x + w * 0.74, y + h * 0.145, h * 0.085, suit(card))
        if full:
            # The card nothing is covering gets the big pip in the middle. It is
            # the one card in the pile a tap can pick up, and at this size a
            # 30px symbol is a far faster way to say which card that is than a
            # 12px one in the corner.
            _pip(cr, x + w * 0.5, y + h * 0.66, h * 0.20, suit(card))

    def _highlight(self, cr, layout: Layout, table: Table) -> None:
        if self._selected is not None:
            pile, position = self._selected
            run = table.run_from(pile, position)
            if run:
                x, y, w, _ = card_at(layout, table, pile, position)
                last = card_at(layout, table, pile, position + len(run) - 1)
                bottom = last[1] + last[3]
                cr.set_source_rgb(*self._ink["pick"])
                cr.set_line_width(2.5)
                _rounded(cr, x + 1, y + 1, w - 2, bottom - y - 2, w * 0.12)
                cr.stroke()

        if not self._drops:
            return
        cr.set_source_rgb(*self._ink["drop"])
        cr.set_line_width(2.5)
        cr.set_dash([5.0, 4.0])
        for pile in self._drops:
            count = table.cards_in(pile)
            x, y, w, h = card_at(layout, table, pile, max(count - 1, 0))
            _rounded(cr, x + 1, y + 1, w - 2, h - 2, w * 0.12)
            cr.stroke()
        cr.set_dash([])


def describe_move(table: Table, move: Move) -> str:
    """One move in words, for a toast and for the tests."""
    if move.src == STOCK:
        return f"Turned over {move.count}"
    if move.dst == STOCK:
        return "Turned the waste back over"
    card = table.run_from(move.src, table.cards_in(move.src) - move.count)[0]
    where = "home" if is_foundation(move.dst) else "across"
    return f"{name(card)} {where}"
