"""A masonry layout: columns of cards, each card as tall as its own contents.

This is the one piece of Keep's look that no stock GTK container gives you.
Gtk.FlowBox lines its children up in rows and makes every child in a row as tall
as the tallest, which turns a two-word note next to a shopping list into a
two-word note with three centimetres of empty card under it. Keep's grid instead
stacks each column independently and drops the next note into whichever column is
currently shortest -- so the cards interlock, and the page has no holes in it.

Doing that needs a layout manager rather than a container, because the height of
a card is not known until it has been measured at the width of a column, and the
width of a column is not known until the window has one. Gtk.LayoutManager is
handed both, at the right moment, twice: once to say how tall the whole grid
wants to be, and once to place the children in the height it was given.
"""

from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")

from gi.repository import Gdk, Gtk  # noqa: E402


class Masonry(Gtk.LayoutManager):
    """Places children into the shortest column, top to bottom."""

    __gtype_name__ = "KeepMasonry"

    def __init__(self, minimum_column: int = 150, spacing: int = 10) -> None:
        super().__init__()
        self.minimum_column = minimum_column
        self.spacing = spacing
        self.limit = 5  # most columns to use, however wide the window gets

    def set_limit(self, limit: int) -> None:
        """1 for Keep's single-column view, 5 for its grid."""
        limit = max(1, limit)
        if limit != self.limit:
            self.limit = limit
            self.layout_changed()

    # --- geometry --------------------------------------------------------

    def columns_for(self, width: int) -> int:
        if width <= 0:
            return 1
        fits = (width + self.spacing) // (self.minimum_column + self.spacing)
        return max(1, min(self.limit, int(fits)))

    def _visible(self, widget: Gtk.Widget) -> list[Gtk.Widget]:
        children, child = [], widget.get_first_child()
        while child is not None:
            if child.should_layout():
                children.append(child)
            child = child.get_next_sibling()
        return children

    def _place(self, widget: Gtk.Widget, width: int) -> tuple[list, int]:
        """Work out where every child goes. Returns (placements, total height).

        The same routine answers both questions GTK asks -- how tall are you,
        and where does each child go -- so a measure and the allocate that
        follows it can never disagree about the number of columns.
        """
        columns = self.columns_for(width)
        gaps = self.spacing * (columns - 1)
        # Integer division leaves up to `columns - 1` pixels over. Handing them
        # out one per column from the left keeps the grid flush with the right
        # margin instead of ending a pixel or two short of it, which is visible
        # against a card's outline.
        base, extra = divmod(max(0, width - gaps), columns)
        widths = [base + (1 if i < extra else 0) for i in range(columns)]
        offsets, x = [], 0
        for w in widths:
            offsets.append(x)
            x += w + self.spacing

        heights = [0] * columns
        placements = []
        for child in self._visible(widget):
            # Shortest column, leftmost on a tie: `index` breaks ties in favour
            # of the earlier column, which is what keeps a fresh grid filling
            # left to right the way reading order expects.
            column = min(range(columns), key=lambda i: (heights[i], i))
            w = widths[column]
            height = child.measure(Gtk.Orientation.VERTICAL, w)[1]
            placements.append((child, offsets[column], heights[column], w, height))
            heights[column] += height + self.spacing

        # The trailing spacing of each column is not part of the grid's height.
        total = max((h - self.spacing for h in heights if h), default=0)
        return placements, max(0, total)

    # --- Gtk.LayoutManager ----------------------------------------------

    def do_get_request_mode(self, _widget) -> Gtk.SizeRequestMode:
        return Gtk.SizeRequestMode.HEIGHT_FOR_WIDTH

    def do_measure(self, widget, orientation, for_size):
        if orientation == Gtk.Orientation.HORIZONTAL:
            # One column is enough to be usable, two is what the phone shows.
            natural = self.minimum_column * min(2, self.limit)
            if self.limit > 1:
                natural += self.spacing
            return self.minimum_column, natural, -1, -1

        width = for_size
        if width <= 0:
            # Height asked for before a width is known. Answer for the width we
            # would have asked for, rather than for one column, so the first
            # measure is not wildly taller than the layout that follows.
            width = self.do_measure(widget, Gtk.Orientation.HORIZONTAL, -1)[1]
        _, height = self._place(widget, width)
        return height, height, -1, -1

    def do_allocate(self, widget, width, height, baseline) -> None:
        placements, _ = self._place(widget, width)
        area = Gdk.Rectangle()
        for child, x, y, w, h in placements:
            area.x, area.y, area.width, area.height = x, y, w, h
            child.size_allocate(area, baseline)


class MasonryBox(Gtk.Widget):
    """A plain container for the layout above.

    Gtk.Box is not usable here: its layout manager is part of what it is, and
    replacing it leaves a widget whose `orientation` property lies about how its
    children are arranged. A bare Gtk.Widget with children parented onto it is
    the honest version, and costs one dispose override.
    """

    __gtype_name__ = "KeepMasonryBox"

    def __init__(self, minimum_column: int = 150, spacing: int = 10) -> None:
        super().__init__()
        self.masonry = Masonry(minimum_column, spacing)
        self.set_layout_manager(self.masonry)

    def add(self, child: Gtk.Widget) -> None:
        child.set_parent(self)

    def clear(self) -> None:
        child = self.get_first_child()
        while child is not None:
            following = child.get_next_sibling()
            child.unparent()
            child = following

    def set_limit(self, limit: int) -> None:
        self.masonry.set_limit(limit)

    def do_dispose(self) -> None:
        # A widget that is finalised with children still parented on it warns,
        # once per child, and leaks them. Nothing unparents them for us: this
        # container has no container semantics of its own.
        self.clear()
        Gtk.Widget.do_dispose(self)
