"""One row of the list, which is very nearly the whole app.

A coin tracker is a list and a star, so there is one widget here and it is
built by hand rather than from `Adw.ActionRow`. The reason is the right-hand
edge: the price and the day have to sit in a column that lines up down the
whole list, and a libadwaita suffix lines up with whatever is above it instead.

Nothing in this file is drawn. There is no cairo in this app at all -- no graph,
no sparkline, no logo -- so every figure on screen is a `Gtk.Label`, which means
it scales with the phone's font size, ellipsizes when a name is too long, and is
read out by a screen reader. That is the repo's standing rule about text, and it
is also why this package does not depend on python-cairo the way Vitals does.

Rows are made once and refilled. A refresh arrives once a minute with a hundred
coins in it; rebuilding a hundred rows of six widgets each would be six hundred
style lookups a minute on a phone with no GL, and -- the part that is actually
visible -- it would throw away the scroll position every time, which on a list
this long means the row somebody is reading jumps back to the top while they
read it.
"""

from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")

from gi.repository import Gtk, Pango  # noqa: E402
from moarchy_ui.icons import icon  # noqa: E402

from . import theme  # noqa: E402
from .market import Coin, compact, direction, money, percent  # noqa: E402

# The star, and what to settle for. The phone's icon theme is not the
# container's -- see moarchy_ui.icons for the whole story -- so every name here
# is a chain rather than a name, and the last one in each is present everywhere.
STAR_ON = ("starred-symbolic", "bookmark-new-symbolic", "emblem-favorite-symbolic")
STAR_OFF = ("non-starred-symbolic", "star-new-symbolic", "bookmark-new-symbolic")

_resolved: dict[bool, str] = {}


def star_icon(on: bool) -> str:
    """The icon name for a star in one state, looked up once.

    Cached because this is asked twice per row per refresh and the answer is a
    property of the icon theme, which does not change while the app is running.
    """
    if on not in _resolved:
        _resolved[on] = icon(*(STAR_ON if on else STAR_OFF))
    return _resolved[on]


class CoinRow(Gtk.ListBoxRow):
    """A rank, a name, a price, a day, and the one button in the app."""

    __gtype_name__ = "CoinsCoinRow"

    def __init__(self, on_star) -> None:
        super().__init__()
        self._on_star = on_star
        self.coin: Coin | None = None
        self._hue = ""
        # Set while the row is being refilled, so that putting the star into the
        # state the store already holds does not read as somebody tapping it.
        self._filling = False

        # Not activatable and not selectable: the row has exactly one action and
        # it has its own button. A row that highlights under a thumb is a
        # promise that tapping it does something.
        self.set_activatable(False)
        self.set_selectable(False)
        self.add_css_class("coin-row")

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)

        self._badge = Gtk.Label()
        self._badge.add_css_class("badge")
        self._badge.set_valign(Gtk.Align.CENTER)
        box.append(self._badge)

        names = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        names.set_valign(Gtk.Align.CENTER)
        names.set_hexpand(True)
        self._name = Gtk.Label(xalign=0.0)
        self._name.add_css_class("coin-name")
        self._name.set_ellipsize(Pango.EllipsizeMode.END)
        self._note = Gtk.Label(xalign=0.0)
        self._note.add_css_class("coin-note")
        self._note.set_ellipsize(Pango.EllipsizeMode.END)
        names.append(self._name)
        names.append(self._note)
        box.append(names)

        figures = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        figures.set_valign(Gtk.Align.CENTER)
        self._price = Gtk.Label(xalign=1.0)
        self._price.add_css_class("coin-price")
        self._change = Gtk.Label(xalign=1.0)
        self._change.add_css_class("coin-change")
        figures.append(self._price)
        figures.append(self._change)
        box.append(figures)

        self._star = Gtk.ToggleButton(icon_name=star_icon(False))
        self._star.add_css_class("flat")
        self._star.add_css_class("star")
        self._star.set_valign(Gtk.Align.CENTER)
        self._star.set_size_request(theme.TARGET, theme.TARGET)
        self._star.connect("toggled", self._on_toggled)
        box.append(self._star)

        self.set_child(box)

    def fill(self, coin: Coin, currency: str, favourite: bool) -> None:
        """Point this row at a coin. Called for every row on every refresh."""
        self._filling = True
        self.coin = coin

        hue = theme.badge_hue(coin.id)
        if hue != self._hue:
            if self._hue:
                self._badge.remove_css_class(f"badge-{self._hue}")
            self._badge.add_css_class(f"badge-{hue}")
            self._hue = hue
        self._badge.set_label(str(coin.rank))

        self._name.set_label(coin.name)
        self._note.set_label(f"{coin.symbol} · {compact(coin.cap, currency)}")
        self._price.set_label(money(coin.price, currency))

        way = direction(coin.change)
        for name in ("up", "down", "flat"):
            if name == way:
                self._change.add_css_class(name)
            else:
                self._change.remove_css_class(name)
        self._change.set_label(percent(coin.change))

        self._star.set_active(favourite)
        self._star.set_icon_name(star_icon(favourite))
        # The state is in the icon and the colour, and neither is a word. A
        # screen reader gets the whole sentence instead.
        label = f"Unstar {coin.name}" if favourite else f"Star {coin.name}"
        self._star.set_tooltip_text(label)
        self._star.update_property([Gtk.AccessibleProperty.LABEL], [label])
        if favourite:
            self._star.add_css_class("on")
        else:
            self._star.remove_css_class("on")

        self.set_visible(True)
        self._filling = False

    def _on_toggled(self, button: Gtk.ToggleButton) -> None:
        if self._filling or self.coin is None:
            return
        self._on_star(self.coin.id, button.get_active())
