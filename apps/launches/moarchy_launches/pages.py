"""A scrolling list of launches, a detail page, and what to say when empty.

Both tabs in this app are the list widget with a different list handed to it:
upcoming is NET order, starred is the order somebody tapped a star. Two
instances rather than one filtered view, because the empty state is the part
that differs and it is the part that has to be right -- a starred page that
came up saying "no launches" would be reporting a network problem the app
does not have.

The rows are pooled. Every tick refills the ones that exist and hides the
rest, so the widget tree stops growing after the first twenty and the scroll
position survives a countdown update.
"""

from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gtk, Pango  # noqa: E402

from .launches import DASH, Launch, disc, headline, hue, tone, window  # noqa: E402
from .widgets import LaunchRow  # noqa: E402


class LaunchList(Gtk.Box):
    """One page: a list of launches, or a reason there are none."""

    __gtype_name__ = "LaunchesLaunchList"

    def __init__(self, on_star, on_open) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self._on_star = on_star
        self._on_open = on_open
        self._rows: list[LaunchRow] = []

        self._list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        self._list.set_valign(Gtk.Align.START)
        self._list.connect("row-activated", self._activated)

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
        """What this page says when it has nothing to show."""
        self._blank.set_title(title)
        self._blank.set_description(body)
        self._blank.set_icon_name(icon_name)

    def fill(self, items: list[Launch], favourites: list[str]) -> None:
        starred = set(favourites)
        for index, item in enumerate(items):
            if index == len(self._rows):
                row = LaunchRow(self._on_star)
                self._rows.append(row)
                self._list.append(row)
            self._rows[index].fill(item, item.id in starred)
        for row in self._rows[len(items) :]:
            row.set_visible(False)
        self._stack.set_visible_child_name("list" if items else "blank")

    def top(self) -> None:
        """Back to the first row. A search, rather than a tick."""
        adjustment = self._scroller.get_vadjustment()
        if adjustment is not None:
            adjustment.set_value(adjustment.get_lower())

    def _activated(self, _list: Gtk.ListBox, row: Gtk.ListBoxRow) -> None:
        if isinstance(row, LaunchRow) and row.launch is not None:
            self._on_open(row.launch.id)


class DetailView(Gtk.Box):
    """One launch, filled in place when the countdown ticks."""

    __gtype_name__ = "LaunchesDetailView"

    def __init__(self) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.add_css_class("detail")
        self.launch: Launch | None = None

        head = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        self._badge = Gtk.Label()
        self._badge.add_css_class("badge")
        self._badge.set_valign(Gtk.Align.CENTER)
        head.append(self._badge)
        titles = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self._name = Gtk.Label(xalign=0.0, wrap=True)
        self._name.add_css_class("detail-name")
        self._name.set_wrap_mode(Pango.WrapMode.WORD_CHAR)
        self._note = Gtk.Label(xalign=0.0, wrap=True)
        self._note.add_css_class("launch-note")
        titles.append(self._name)
        titles.append(self._note)
        head.append(titles)
        self.append(head)

        self._when = Gtk.Label(xalign=0.0)
        self._when.add_css_class("detail-when")
        self.append(self._when)

        self._facts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.append(self._facts)

        self._body = Gtk.Label(xalign=0.0, wrap=True)
        self._body.add_css_class("detail-body")
        self._body.set_wrap_mode(Pango.WrapMode.WORD_CHAR)
        self.append(self._body)

        self._hue = ""

    def fill(self, item: Launch) -> None:
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
        self._note.set_label(note)
        self._note.set_visible(bool(note))

        way = tone(item)
        for name in ("soon", "late", "wait", "dim"):
            if name == way:
                self._when.add_css_class(name)
            else:
                self._when.remove_css_class(name)
        self._when.set_label(headline(item))

        while (child := self._facts.get_first_child()) is not None:
            self._facts.remove(child)
        facts = [
            ("Status", item.status or DASH),
            ("Vehicle", item.vehicle),
            ("Agency", item.agency),
            ("Pad", item.pad),
            ("Location", item.location),
            (
                "Orbit",
                " · ".join(part for part in (item.orbit, item.mission_type) if part),
            ),
            ("Window", window(item)),
        ]
        if item.probability is not None:
            facts.append(("Probability", f"{item.probability}%"))
        if item.weather:
            facts.append(("Weather", item.weather))
        if item.hold:
            facts.append(("Hold", item.hold))
        for label, value in facts:
            if not value:
                continue
            row = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            row.add_css_class("fact-row")
            caption = Gtk.Label(label=label, xalign=0.0)
            caption.add_css_class("fact-label")
            body = Gtk.Label(label=value, xalign=0.0, wrap=True)
            body.add_css_class("fact-value")
            body.set_wrap_mode(Pango.WrapMode.WORD_CHAR)
            row.append(caption)
            row.append(body)
            self._facts.append(row)

        if item.description:
            self._body.set_label(item.description)
            self._body.set_visible(True)
        else:
            self._body.set_visible(False)
