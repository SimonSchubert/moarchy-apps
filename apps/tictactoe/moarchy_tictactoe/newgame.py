"""Starting a series: who you are playing, how hard, and which mark you open on.

Three questions, asked once, on a bottom sheet -- which is what Adw.Dialog is on
a phone. They are not in a settings page because they are not settings: they
belong to a series, they are chosen when one starts, and a sitting already under
way cannot answer them differently halfway through.

The difficulty and mark rows disappear entirely when the opponent is another
person. A row that is visible but insensitive is a question the app is still
asking and refusing to hear the answer to.

"Open as" rather than "You play", because it is only true of the first game.
The marks swap on every rematch -- X moves first, first is worth something
against anybody short of perfect, and two people with a pencil take turns going
first for exactly that reason.
"""

from __future__ import annotations

from typing import ClassVar

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, GObject, Gtk  # noqa: E402

from .ai import LEVELS  # noqa: E402
from .store import HOTSEAT, SOLO  # noqa: E402
from .tictactoe import CROSS, NOUGHT  # noqa: E402

OPPONENTS = ("The computer", "Another person")
# Short, because an Adw.ComboRow ellipsizes its value before its title and
# "X — goe…" is a row that has stopped answering the question it asked.
MARKS = ("X — first", "O — second")


class NewGameDialog(Adw.Dialog):
    """Emits `chosen` with (mode, level key, mark) when Start is tapped."""

    __gtype_name__ = "TicTacToeNewGame"

    __gsignals__: ClassVar[dict] = {
        "chosen": (GObject.SignalFlags.RUN_FIRST, None, (str, str, int)),
    }

    def __init__(self, *, mode: str, level: str, mark: int, in_progress: bool) -> None:
        super().__init__()
        self.set_title("New game")
        self.set_content_width(400)

        header = Adw.HeaderBar()
        cancel = Gtk.Button(label="Cancel")
        cancel.connect("clicked", lambda *_: self.close())
        header.pack_start(cancel)

        start = Gtk.Button(label="Start")
        start.add_css_class("suggested-action")
        start.connect("clicked", self._on_start)
        header.pack_end(start)

        page = Adw.PreferencesPage()
        group = Adw.PreferencesGroup()
        # Said once, here, rather than as a confirmation after Start: a warning
        # that arrives after the decision makes people tap twice, not think.
        if in_progress:
            group.set_description("The game and the series score will be given up.")

        self._opponent = Adw.ComboRow(title="Against")
        self._opponent.set_model(Gtk.StringList.new(OPPONENTS))
        self._opponent.set_selected(1 if mode == HOTSEAT else 0)
        self._opponent.connect("notify::selected", lambda *_: self._sync())
        group.add(self._opponent)

        self._level = Adw.ComboRow(title="Difficulty")
        self._level.set_model(Gtk.StringList.new([lv.label for lv in LEVELS]))
        self._level.set_selected(
            next((i for i, lv in enumerate(LEVELS) if lv.key == level), 1)
        )
        self._level.connect("notify::selected", lambda *_: self._describe())
        group.add(self._level)

        self._mark = Adw.ComboRow(title="Open as")
        self._mark.set_model(Gtk.StringList.new(MARKS))
        self._mark.set_selected(1 if mark == NOUGHT else 0)
        self._mark.set_subtitle("The marks swap on every rematch")
        group.add(self._mark)

        page.add(group)

        view = Adw.ToolbarView()
        view.add_top_bar(header)
        view.set_content(page)
        self.set_child(view)

        self._describe()
        self._sync()

    def _describe(self) -> None:
        level = LEVELS[min(self._level.get_selected(), len(LEVELS) - 1)]
        self._level.set_subtitle(level.blurb)

    def _sync(self) -> None:
        solo = self._opponent.get_selected() == 0
        self._level.set_visible(solo)
        self._mark.set_title("Open as" if solo else "Player one opens as")

    def _on_start(self, *_args) -> None:
        solo = self._opponent.get_selected() == 0
        level = LEVELS[min(self._level.get_selected(), len(LEVELS) - 1)]
        mark = NOUGHT if self._mark.get_selected() == 1 else CROSS
        self.emit("chosen", SOLO if solo else HOTSEAT, level.key, mark)
        self.close()
