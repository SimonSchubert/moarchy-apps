"""One row of the list, which is very nearly the whole app.

A launch tracker is a list and a star, so there is one widget here and it is
built by hand rather than from `Adw.ActionRow`. The reason is the right-hand
edge: the countdown has to sit in a column that lines up down the whole list,
and a libadwaita suffix lines up with whatever is above it instead.

Nothing in this file is drawn. There is no cairo in this app at all -- no
rocket, no map, no patch -- so every figure on screen is a `Gtk.Label`, which
means it scales with the phone's font size, ellipsizes when a name is too
long, and is read out by a screen reader. That is the repo's standing rule
about text, and it is also why this package does not depend on python-cairo
the way Vitals does.

Rows are made once and refilled. A refresh arrives with twenty launches in
it; rebuilding twenty rows of widgets would throw away the scroll position,
which on a list this long means the row somebody is reading jumps back to
the top while they read it. A tick every second only changes the countdown
label, and that is the point of `fill`.
"""

from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")

from gi.repository import Gtk, Pango  # noqa: E402
from moarchy_ui.icons import icon  # noqa: E402

from . import theme  # noqa: E402
from .launches import Launch, disc, headline, hue, tone  # noqa: E402

STAR_ON = ("starred-symbolic", "bookmark-new-symbolic", "emblem-favorite-symbolic")
STAR_OFF = ("non-starred-symbolic", "star-new-symbolic", "bookmark-new-symbolic")

_resolved: dict[bool, str] = {}


def star_icon(on: bool) -> str:
    """The icon name for a star in one state, looked up once."""
    if on not in _resolved:
        _resolved[on] = icon(*(STAR_ON if on else STAR_OFF))
    return _resolved[on]


class LaunchRow(Gtk.ListBoxRow):
    """A status, a name, a countdown, and the one button in the app."""

    __gtype_name__ = "LaunchesLaunchRow"

    def __init__(self, on_star) -> None:
        super().__init__()
        self._on_star = on_star
        self.launch: Launch | None = None
        self._hue = ""
        self._filling = False

        self.set_activatable(True)
        self.set_selectable(False)
        self.add_css_class("launch-row")

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)

        self._badge = Gtk.Label()
        self._badge.add_css_class("badge")
        self._badge.set_valign(Gtk.Align.CENTER)
        box.append(self._badge)

        names = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        names.set_valign(Gtk.Align.CENTER)
        names.set_hexpand(True)
        self._name = Gtk.Label(xalign=0.0)
        self._name.add_css_class("launch-name")
        self._name.set_ellipsize(Pango.EllipsizeMode.END)
        self._note = Gtk.Label(xalign=0.0)
        self._note.add_css_class("launch-note")
        self._note.set_ellipsize(Pango.EllipsizeMode.END)
        self._place = Gtk.Label(xalign=0.0)
        self._place.add_css_class("launch-note")
        self._place.set_ellipsize(Pango.EllipsizeMode.END)
        names.append(self._name)
        names.append(self._note)
        names.append(self._place)
        box.append(names)

        self._when = Gtk.Label(xalign=1.0)
        self._when.add_css_class("launch-when")
        self._when.set_valign(Gtk.Align.CENTER)
        box.append(self._when)

        self._star = Gtk.ToggleButton(icon_name=star_icon(False))
        self._star.add_css_class("flat")
        self._star.add_css_class("star")
        self._star.set_valign(Gtk.Align.CENTER)
        self._star.set_size_request(theme.TARGET, theme.TARGET)
        self._star.connect("toggled", self._on_toggled)
        box.append(self._star)

        self.set_child(box)

    def fill(self, item: Launch, favourite: bool) -> None:
        """Point this row at a launch. Called for every row on every tick."""
        self._filling = True
        self.launch = item

        role = hue(item)
        if role != self._hue:
            if self._hue:
                self._badge.remove_css_class(f"badge-{self._hue}")
            self._badge.add_css_class(f"badge-{role}")
            self._hue = role
        self._badge.set_label(disc(item))

        self._name.set_label(item.name)
        note = " · ".join(part for part in (item.vehicle, item.agency) if part)
        self._note.set_label(note or item.vehicle or item.agency)
        self._place.set_label(item.location or item.pad)
        self._place.set_visible(bool(item.location or item.pad))

        way = tone(item)
        for name in ("soon", "late", "wait", "dim"):
            if name == way:
                self._when.add_css_class(name)
            else:
                self._when.remove_css_class(name)
        self._when.set_label(headline(item))

        self._star.set_active(favourite)
        self._star.set_icon_name(star_icon(favourite))
        label = f"Unstar {item.name}" if favourite else f"Star {item.name}"
        self._star.set_tooltip_text(label)
        self._star.update_property([Gtk.AccessibleProperty.LABEL], [label])
        if favourite:
            self._star.add_css_class("on")
        else:
            self._star.remove_css_class("on")

        self.set_visible(True)
        self._filling = False

    def _on_toggled(self, button: Gtk.ToggleButton) -> None:
        if self._filling or self.launch is None:
            return
        self._on_star(self.launch.id, button.get_active())
