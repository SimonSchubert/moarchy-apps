"""Starting a deal: how many cards a tap on the stock turns over.

One question, asked on a bottom sheet -- which is what Adw.Dialog is on a phone.
It is not in a settings page because it is not a setting: it belongs to a deal,
it is chosen when one starts, and a game already under way cannot answer it
differently halfway through without becoming a different game.

The sheet says in advance that the deal in progress will count as a loss.
That is where a warning belongs -- after the decision it only makes people tap
twice -- and it is the honest half of keeping a win percentage at all: a tally
that quietly forgot every game somebody walked away from would be a tally of
the games that were going well.
"""

from __future__ import annotations

from typing import ClassVar

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, GObject, Gtk  # noqa: E402

from .klondike import DRAWS  # noqa: E402

DEALS = ("One card", "Three cards")
BLURBS = (
    "Every card in the stock is reachable. Most deals can be won.",
    "The game as it is printed on the box. Rather fewer can.",
)


class NewGameDialog(Adw.Dialog):
    """Emits `chosen` with the draw count when Deal is tapped."""

    __gtype_name__ = "SolitaireNewGame"

    __gsignals__: ClassVar[dict] = {
        "chosen": (GObject.SignalFlags.RUN_FIRST, None, (int,)),
    }

    def __init__(self, *, draw: int, in_progress: bool) -> None:
        super().__init__()
        self.set_title("New deal")
        self.set_content_width(400)

        header = Adw.HeaderBar()
        cancel = Gtk.Button(label="Cancel")
        cancel.connect("clicked", lambda *_: self.close())
        header.pack_start(cancel)

        start = Gtk.Button(label="Deal")
        start.add_css_class("suggested-action")
        start.connect("clicked", self._on_start)
        header.pack_end(start)

        page = Adw.PreferencesPage()
        group = Adw.PreferencesGroup()
        if in_progress:
            group.set_description("The deal in progress will count as a loss.")

        self._draw = Adw.ComboRow(title="Turn over")
        self._draw.set_model(Gtk.StringList.new(DEALS))
        self._draw.set_selected(DRAWS.index(draw) if draw in DRAWS else 0)
        self._draw.connect("notify::selected", lambda *_: self._describe())
        group.add(self._draw)

        page.add(group)

        view = Adw.ToolbarView()
        view.add_top_bar(header)
        view.set_content(page)
        self.set_child(view)

        self._describe()

    def _describe(self) -> None:
        self._draw.set_subtitle(BLURBS[min(self._draw.get_selected(), len(BLURBS) - 1)])

    def _on_start(self, *_args) -> None:
        self.emit("chosen", DRAWS[min(self._draw.get_selected(), len(DRAWS) - 1)])
        self.close()
