"""Choosing a figure: nine rows, each one a puzzle and how it has gone.

A list rather than a combo box, which is the one place this app's settings sheet
differs from every other one here. A combo row is right when the choice is a
setting -- an opponent, a difficulty, a draw count -- because the answer is a
word and the question is short. Here the choice *is the content*: nine different
puzzles, each with a shape, a size and a record behind it, and a drop-down would
hide eight of them behind a word.

Tapping a row starts it. There is no Start button, because there is nothing else
on the sheet to fill in and a second tap to confirm a tap is a second tap.
"""

from __future__ import annotations

from typing import ClassVar

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, GObject, Gtk  # noqa: E402

from .pegs import FIGURES  # noqa: E402


class FigureDialog(Adw.Dialog):
    """Emits `chosen` with a figure key when a row is tapped."""

    __gtype_name__ = "PegSolitaireFigures"

    __gsignals__: ClassVar[dict] = {
        "chosen": (GObject.SignalFlags.RUN_FIRST, None, (str,)),
    }

    def __init__(self, *, current: str, store) -> None:
        super().__init__()
        self.set_title("Figures")
        self.set_content_width(400)

        header = Adw.HeaderBar()
        close = Gtk.Button(label="Close")
        close.connect("clicked", lambda *_: self.close())
        header.pack_start(close)

        page = Adw.PreferencesPage()
        group = Adw.PreferencesGroup()
        group.set_description(
            "Every one of these can be reduced to a single peg. The app solves "
            "them all before it ships."
        )

        for figure in FIGURES:
            entry = store.record_for(figure.key)
            row = Adw.ActionRow(title=figure.label, subtitle=figure.blurb)
            row.set_activatable(True)
            row.connect("activated", self._pick, figure.key)
            row.add_suffix(_result(entry, figure))
            if figure.key == current:
                row.add_prefix(Gtk.Image.new_from_icon_name("object-select-symbolic"))
            group.add(row)

        page.add(group)

        view = Adw.ToolbarView()
        view.add_top_bar(header)
        view.set_content(page)
        self.set_child(view)

    def _pick(self, _row, key: str) -> None:
        self.emit("chosen", key)
        self.close()


def _result(entry: dict, figure) -> Gtk.Widget:
    """The best this figure has been left at, in three characters or fewer."""
    best = entry.get("best", 0)
    if not best:
        text = "—"
    elif best == 1:
        text = "★" if entry.get("perfect") and figure.centre else "1"
    else:
        text = str(best)
    label = Gtk.Label(label=text)
    label.set_valign(Gtk.Align.CENTER)
    label.add_css_class("dim-label" if not best or best > 1 else "crown")
    return label
