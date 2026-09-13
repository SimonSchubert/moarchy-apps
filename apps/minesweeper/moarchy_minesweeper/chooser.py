"""Choosing a board: three rows, each one a size and a density.

A list rather than a combo box, for the reason Peg Solitaire's figure sheet is
one: the choice is the content rather than a setting. A row can say that Hard is
twelve by sixteen with forty mines *and* what your best time on it is, which is
the question somebody choosing a level is actually asking.

Tapping a row starts a game on it. There is no Start button, because there is
nothing else on the sheet to fill in.
"""

from __future__ import annotations

from typing import ClassVar

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, GObject, Gtk  # noqa: E402

from .minesweeper import LEVELS  # noqa: E402
from .store import WON, clock  # noqa: E402


class LevelDialog(Adw.Dialog):
    """Emits `chosen` with a level key when a row is tapped."""

    __gtype_name__ = "MinesweeperLevels"

    __gsignals__: ClassVar[dict] = {
        "chosen": (GObject.SignalFlags.RUN_FIRST, None, (str,)),
    }

    def __init__(self, *, current: str, store, in_progress: bool) -> None:
        super().__init__()
        self.set_title("New game")
        self.set_content_width(400)

        header = Adw.HeaderBar()
        close = Gtk.Button(label="Cancel")
        close.connect("clicked", lambda *_: self.close())
        header.pack_start(close)

        page = Adw.PreferencesPage()
        group = Adw.PreferencesGroup()
        if in_progress:
            group.set_description("The game in progress will count as a loss.")

        for level in LEVELS:
            entry = store.record_for(level.key)
            row = Adw.ActionRow(
                title=level.label,
                subtitle=(
                    f"{level.width} × {level.height}, {level.mines} mines"
                    f" · one cell in {round(1 / level.density)}"
                ),
            )
            row.set_activatable(True)
            row.connect("activated", self._pick, level.key)
            best = entry["best"]
            value = Gtk.Label(label=clock(best) if best else "—")
            value.set_valign(Gtk.Align.CENTER)
            value.add_css_class("dim-label")
            value.set_tooltip_text(
                f"{entry[WON]} won of {entry['played']}" if entry["played"] else ""
            )
            row.add_suffix(value)
            if level.key == current:
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
