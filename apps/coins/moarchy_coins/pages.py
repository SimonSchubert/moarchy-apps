"""A scrolling list of coins, and what to say when there is nothing in it.

Both pages in this app are this widget with a different list handed to it: the
market is the top hundred by capitalisation, the starred page is whichever of
them somebody tapped a star on. Two instances rather than one filtered view,
because the empty state is the part that differs and it is the part that has to
be right -- a starred page that came up saying "no coins" would be reporting a
network problem the app does not have.

The rows are pooled. Every refresh refills the ones that exist and hides the
rest, so the widget tree stops growing after the first hundred and the scroll
position survives a price update -- see `widgets.py` for why that matters more
than it sounds like it does.
"""

from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gtk  # noqa: E402

from .market import Coin  # noqa: E402
from .widgets import CoinRow  # noqa: E402


class CoinList(Gtk.Box):
    """One page: a list of coins, or a reason there are none."""

    __gtype_name__ = "CoinsCoinList"

    def __init__(self, on_star) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self._on_star = on_star
        self._rows: list[CoinRow] = []

        self._list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        self._list.set_valign(Gtk.Align.START)

        self._scroller = Gtk.ScrolledWindow()
        self._scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self._scroller.set_hexpand(True)
        self._scroller.set_vexpand(True)
        self._scroller.set_child(self._list)

        self._blank = Adw.StatusPage()
        self._blank.set_vexpand(True)

        self._stack = Gtk.Stack()
        self._stack.add_named(self._scroller, "list")
        self._stack.add_named(self._blank, "blank")
        self._stack.set_vexpand(True)
        self.append(self._stack)

    def set_blank(self, title: str, body: str, icon_name: str) -> None:
        """What this page says when it has nothing to show.

        Set before every `fill`, because the reason changes: a starred page with
        nothing on it is an invitation, the same page under a search that
        matches nothing is a different sentence, and the market page with no
        prices at all is a network problem.
        """
        self._blank.set_title(title)
        self._blank.set_description(body)
        self._blank.set_icon_name(icon_name)

    def fill(self, coins: list[Coin], currency: str, favourites: list[str]) -> None:
        starred = set(favourites)
        for index, coin in enumerate(coins):
            if index == len(self._rows):
                row = CoinRow(self._on_star)
                self._rows.append(row)
                self._list.append(row)
            self._rows[index].fill(coin, currency, coin.id in starred)
        for row in self._rows[len(coins) :]:
            # Hidden rather than removed: the next refresh almost always wants
            # exactly this many rows back again, and a ListBox that is emptied
            # and refilled once a minute is a hundred widgets built a minute.
            row.set_visible(False)
        self._stack.set_visible_child_name("list" if coins else "blank")

    def top(self) -> None:
        """Back to the first row.

        Called when the list becomes a different list -- a search, rather than a
        refresh. A price update deliberately does not do this: the row somebody
        is reading has to stay under their thumb.
        """
        adjustment = self._scroller.get_vadjustment()
        if adjustment is not None:
            adjustment.set_value(adjustment.get_lower())
