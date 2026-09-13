"""The window: a hash, a score line, and two buttons that take turns being live.

The whole app is one screen. There is no list to navigate and no detail to open,
so the only thing pushed onto the navigation view is the record, and the
controls that belong to the game are in a bar along the bottom rather than in
the header -- on a 720px-tall phone the header is the far end of a stretch and
the bottom bar is under the thumb already holding the device.

The two buttons down there trade places, and that is the piece of this window
worth reading twice. While a game is on, **Undo** is the live one and Play again
is dead; the moment the game ends, Undo goes dead and **Play again** lights up
as the suggested action. There is never a point in a fifteen-second game where
the wrong button is the easy tap, which on a board this small matters more than
it sounds: a misplaced thumb on Play again would throw away a game that undo
cannot get back.

The order of events after a tap is the other one:

    tap -> play -> draw the mark -> settled -> pause -> answer -> draw -> settled

The pause is deliberate and it is the opposite of Reversi's. There the computer
waits because the search is a Python thread holding the GIL and would turn a
flip into a slideshow. Here the whole game is solved before the first tap and a
reply costs a dictionary lookup -- so the wait is not for the computer, it is
for the person. An opponent that answers in nought milliseconds does not read as
a strong player, it reads as a script, and the mark it drew is already on the
board before the eye has left the one you drew.
"""

from __future__ import annotations

import os
import random

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gio, GLib, Gtk  # noqa: E402
from moarchy_ui.icons import icon  # noqa: E402

from . import ai  # noqa: E402
from .newgame import NewGameDialog  # noqa: E402
from .store import DRAWN, LOST, SOLO, WON, Store  # noqa: E402
from .tictactoe import NAMES, Game, other  # noqa: E402
from .widgets import BoardView, ScoreLine  # noqa: E402

APP_ICON = "org.moarchy.TicTacToe"

# How long the computer sits on a move it already has. Long enough to read as a
# turn being taken, short enough that six games still fit between two bus stops.
# Tuned by playing it: at 150ms the reply lands before the eye has moved, and at
# 600ms a game of five moves feels like it is being administered.
THINK_MS = 340

# The names on the two seats when nobody is playing the computer. Short on
# purpose -- they sit under a number on a chip 90px wide.
SEATS = {"a": "One", "b": "Two"}


class TicTacToeWindow(Adw.ApplicationWindow):
    __gtype_name__ = "TicTacToeWindow"

    def __init__(self, store: Store, **kwargs) -> None:
        super().__init__(**kwargs)
        self.store = store
        self.game: Game = store.game()
        self.level = ai.level_for(store.level)
        self._rng = random.Random()
        self._thinking = 0
        # Whether this game's result has already been counted. It comes from
        # the file rather than from "is the board finished", because the move
        # that ends a game is saved the instant it is played and counted a
        # fraction of a second later, when the mark has finished being drawn --
        # so a phone killed between the two comes back to a finished board with
        # a result still owed to it.
        self._recorded = store.recorded
        # Bumped whenever the board stops being the one a reply was asked for.
        # A timeout that fires for a game that has been restarted or taken back
        # must be dropped on the floor, and a counter is the whole mechanism.
        self._generation = 0

        self.set_title("Tic-tac-toe")
        self.set_default_size(360, 720)

        self._nav = Adw.NavigationView()
        self._nav.add(self._game_page())
        self.set_content(self._nav)

        for name, handler in (
            ("new", lambda *_: self.ask_new_game()),
            ("undo", lambda *_: self.undo()),
            ("again", lambda *_: self.rematch()),
            ("stats", lambda *_: self.show_record()),
        ):
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", handler)
            self.add_action(action)

        self.connect("close-request", self._on_close)
        self.refresh()
        self._resume()
        self._open_requested()

    # --- the page --------------------------------------------------------

    def _game_page(self) -> Adw.NavigationPage:
        header = Adw.HeaderBar()
        self._title = Adw.WindowTitle(title="Tic-tac-toe", subtitle="")
        header.set_title_widget(self._title)

        menu = Gtk.MenuButton(
            icon_name=icon("open-menu-symbolic", "view-more-symbolic")
        )
        menu.set_tooltip_text("Menu")
        menu.update_property([Gtk.AccessibleProperty.LABEL], ["Menu"])
        model = Gio.Menu()
        model.append("New game…", "win.new")
        model.append("Record", "win.stats")
        model.append("About Tic-tac-toe", "app.about")
        menu.set_menu_model(model)
        header.pack_end(menu)

        self._score = ScoreLine()

        self._board = BoardView()
        self._board.set_margin_start(12)
        self._board.set_margin_end(12)
        self._board.set_margin_top(4)
        self._board.connect("cell-activated", self._on_cell)
        self._board.connect("settled", self._on_settled)

        self._status = Gtk.Label()
        self._status.add_css_class("status")
        self._status.set_margin_top(2)
        self._status.set_margin_bottom(2)
        self._status.set_ellipsize(3)

        # The score, the board and what it is saying travel together, centred in
        # whatever the buttons leave. Pinning the score to the top and the
        # status to the bottom would read as three things that had drifted
        # apart; one block with the hole around it reads as a margin.
        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        body.set_vexpand(True)
        body.set_valign(Gtk.Align.CENTER)
        body.append(self._score)
        body.append(self._board)
        body.append(self._status)

        self._toasts = Adw.ToastOverlay()
        self._toasts.set_child(body)

        view = Adw.ToolbarView()
        view.add_top_bar(header)
        view.set_content(self._toasts)
        view.add_bottom_bar(self._actions())
        return Adw.NavigationPage.new(view, "Tic-tac-toe")

    def _actions(self) -> Gtk.Widget:
        bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        bar.add_css_class("actionbar")
        bar.set_homogeneous(True)

        self._undo = Gtk.Button()
        self._undo.set_child(
            Adw.ButtonContent(
                icon_name=icon("edit-undo-symbolic", "go-previous-symbolic"),
                label="Undo",
            )
        )
        self._undo.add_css_class("pill")
        self._undo.set_tooltip_text("Take back your last mark")
        self._undo.connect("clicked", lambda *_: self.undo())
        bar.append(self._undo)

        self._again = Gtk.Button()
        self._again.set_child(
            Adw.ButtonContent(
                icon_name=icon("view-refresh-symbolic", "document-new-symbolic"),
                label="Play again",
            )
        )
        self._again.add_css_class("pill")
        self._again.set_tooltip_text("Another game, with the marks swapped")
        self._again.connect("clicked", lambda *_: self.rematch())
        bar.append(self._again)
        return bar

    def set_palette(self, palette) -> None:
        """The theme changed. The widgets repaint themselves from the reloaded
        stylesheet; the board is drawn by hand and has to be told."""
        self._board.set_colours(palette)

    # --- who is who ------------------------------------------------------

    @property
    def solo(self) -> bool:
        return self.store.mode == SOLO

    @property
    def marks(self) -> dict[str, int]:
        """Which mark each seat is holding this game."""
        return {"a": self.store.mark, "b": other(self.store.mark)}

    @property
    def names(self) -> dict[str, str]:
        if not self.solo:
            return dict(SEATS)
        return {"a": "You", "b": self.level.label}

    def _their_turn(self) -> bool:
        return self.solo and self.game.turn != self.store.mark and not self.game.over

    # --- drawing the state -----------------------------------------------

    def refresh(self) -> None:
        position = self.game.position
        self._board.show(position)
        self._score.refresh(
            position, self.marks, self.names, self.store.series, live=not self.game.over
        )
        self._status.set_text(self._status_text())
        if self.game.over:
            self._status.add_css_class("alert")
        else:
            self._status.remove_css_class("alert")

        # The two buttons trade places. Exactly one of them is ever the obvious
        # tap, which on a board where a game lasts fifteen seconds is what stops
        # a thumb from throwing one away.
        self._undo.set_sensitive(
            bool(self.game.moves) and not self.game.over and not self._thinking
        )
        self._again.set_sensitive(self.game.over)
        if self.game.over:
            self._again.add_css_class("suggested-action")
        else:
            self._again.remove_css_class("suggested-action")

        if self.solo:
            mine = NAMES[self.store.mark]
            self._title.set_subtitle(f"{self.level.label} · you are {mine}")
        else:
            self._title.set_subtitle("Two players")

    def _status_text(self) -> str:
        if self.game.over:
            return self._result_text()
        if self.solo:
            if self.game.turn == self.store.mark:
                return "Your move"
            return f"{self.level.label} is playing…"
        return f"{NAMES[self.game.turn]} to play"

    def _result_text(self) -> str:
        winner = self.game.position.winner()
        if winner is None:
            return "A draw — as it should be"
        if not self.solo:
            seat = "a" if winner == self.store.mark else "b"
            return f"{SEATS[seat]} wins as {NAMES[winner]}"
        if winner == self.store.mark:
            return f"You win as {NAMES[winner]}"
        return f"{self.level.label} wins as {NAMES[winner]}"

    # --- playing ---------------------------------------------------------

    def _on_cell(self, _board: BoardView, cell: int) -> None:
        if self._thinking or self._board.busy:
            return
        if self.game.over:
            self._toast("That game is finished. Tap Play again.")
            return
        if self._their_turn():
            return
        if not self.game.position.is_legal(cell):
            # Silent. A tap on a square that is already marked is a miss, and an
            # app that scolds you for a miss on a touch screen scolds you all
            # day long.
            return
        self._play(cell)

    def _play(self, cell: int) -> None:
        play = self.game.play(cell)
        self.store.remember(self.game, finished=self.game.over)
        self._save()
        self.refresh()
        self._board.animate(play)

    def _on_settled(self, *_args) -> None:
        self.refresh()
        if self.game.over:
            self._finish()
        elif self._their_turn():
            self._think()

    # --- the opponent ----------------------------------------------------

    def _resume(self) -> None:
        """Pick the game back up where it was put down.

        A phone app is closed by being killed, usually in the middle of
        something. If that something was the computer's turn, the reply has to
        start again by itself -- there is no tap coming.
        """
        if self.game.over:
            # A game that ended while the app was being killed, or one whose
            # last mark was drawn and never counted. Either way the result is
            # owed, and nothing else is going to ask for it.
            self._finish()
        elif self._their_turn():
            self._think()

    def _think(self) -> None:
        """Wait, then answer. The waiting is the whole of it.

        There is no thread here and no search. `ai.choose` is a lookup in a
        table that was filled before the window opened, so the move is already
        known when this is called; the timeout exists so that the person gets to
        see their own mark land before the answer to it does.
        """
        if self._thinking:
            return
        self._generation += 1
        generation = self._generation
        self._thinking = GLib.timeout_add(THINK_MS, self._answer, generation)
        self.refresh()

    def _answer(self, generation: int) -> bool:
        self._thinking = 0
        if generation != self._generation:
            return GLib.SOURCE_REMOVE  # a different game now
        try:
            cell = ai.choose(self.game.position, self.level, self._rng)
        except Exception:  # noqa: BLE001 -- see below
            # An opponent that dies takes the game with it: this is the only
            # thing that will ever move for this side, so it answers with a
            # legal move rather than leaving a board nobody can play on.
            legal = self.game.position.legal()
            cell = legal[0] if legal else -1
        if cell < 0 or not self.game.position.is_legal(cell):
            self.refresh()
            return GLib.SOURCE_REMOVE
        self._play(cell)
        return GLib.SOURCE_REMOVE

    # --- finishing -------------------------------------------------------

    def _finish(self) -> None:
        """Record the result once, and say what it was."""
        if self._recorded:
            return
        self._recorded = True
        winner = self.game.position.winner()
        if winner is None:
            result = DRAWN
        else:
            result = WON if winner == self.store.mark else LOST
        self.store.record(result)
        self.store.remember(self.game, finished=True)
        self._save()
        self.refresh()
        self._toast(self._result_text())

    # --- the rest --------------------------------------------------------

    def undo(self) -> None:
        if self._thinking or self._board.busy or self.game.over:
            return
        taken = self.game.takeback(self.store.mark) if self.solo else self.game.undo()
        if not taken:
            return
        # Any reply still pending is for a board that no longer exists.
        self._generation += 1
        self.store.remember(self.game)
        self._save()
        self.refresh()
        # Taking back the computer's opening mark leaves it on move again -- the
        # only case where an undo does not end on the person's turn. Without
        # this the board sits there with nobody whose turn it is to tap.
        self._resume()

    def rematch(self) -> None:
        """Another game on the same terms, with the marks swapped."""
        self._generation += 1
        self._thinking = 0
        self.game = self.store.rematch()
        self._recorded = False
        self._save()
        self.refresh()
        self._resume()

    def ask_new_game(self) -> None:
        dialog = NewGameDialog(
            mode=self.store.mode,
            level=self.level.key,
            mark=self.store.mark,
            in_progress=bool(self.game.moves) or any(self.store.series.values()),
        )
        dialog.connect("chosen", self._on_chosen)
        dialog.present(self)

    def _on_chosen(self, _dialog, mode: str, level: str, mark: int) -> None:
        self._generation += 1
        self._thinking = 0
        self.game = self.store.begin(mode=mode, level=level, mark=mark)
        self.level = ai.level_for(level)
        self._recorded = False
        self._save()
        self.refresh()
        self._resume()

    def show_record(self) -> None:
        self._nav.push(RecordPage(self.store))

    def _toast(self, text: str) -> None:
        toast = Adw.Toast.new(text)
        toast.set_timeout(3)
        self._toasts.add_toast(toast)

    def _save(self) -> None:
        try:
            self.store.save()
        except OSError as exc:
            self._toast(f"Could not save: {exc.strerror or exc}")

    def _open_requested(self) -> None:
        """Start on a particular screen, for the screenshot harness.

        A headless X server has no pointer worth clicking with, and a run that
        opens straight into the screen it should photograph needs none. The same
        mechanism Keep, Habits and Reversi use, for the same reason.
        """
        if os.environ.get("MOARCHY_TICTACTOE_PAGE") == "record":
            self.show_record()
        if os.environ.get("MOARCHY_TICTACTOE_NEW"):
            self.ask_new_game()

    def _on_close(self, *_args) -> bool:
        self.store.remember(self.game, finished=self.game.over)
        self._save()
        return False


class RecordPage(Adw.NavigationPage):
    """Games against the computer, by difficulty.

    The headline figure is not wins, and that is the one honest thing this page
    has to do. Against Perfect there are no wins to be had -- the game is drawn
    with correct play from both sides, every time, forever -- so a page that put
    a win percentage at the top would be a page telling somebody they are bad at
    a game they have in fact solved. The figure is the **longest run without
    losing**, which is a thing you can get better at against all three levels.
    """

    __gtype_name__ = "TicTacToeRecord"

    def __init__(self, store: Store) -> None:
        super().__init__()
        self.set_title("Record")

        header = Adw.HeaderBar()

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        body.set_margin_top(16)
        body.set_margin_bottom(24)
        body.set_margin_start(14)
        body.set_margin_end(14)

        totals = store.totals()
        body.append(
            _tally(
                ("Played", totals["played"]),
                ("Won", totals[WON]),
                ("Unbeaten", totals["best"]),
            )
        )

        heading = Gtk.Label(label="BY DIFFICULTY", xalign=0.0)
        heading.add_css_class("section-heading")
        body.append(heading)

        rows = Gtk.ListBox()
        rows.set_selection_mode(Gtk.SelectionMode.NONE)
        rows.add_css_class("boxed-list")
        for level in ai.LEVELS:
            entry = store.record_for(level.key)
            row = Adw.ActionRow(title=level.label)
            if entry["played"]:
                row.set_subtitle(
                    f"{entry[WON]} won · {entry[LOST]} lost · {entry[DRAWN]} drawn"
                )
            else:
                row.set_subtitle("Not played yet")
            value = Gtk.Label(
                label=f"{entry['best']} unbeaten" if entry["played"] else "—"
            )
            value.add_css_class("dim-label")
            row.add_suffix(value)
            rows.append(row)
        body.append(rows)

        note = Gtk.Label(
            label=(
                "Perfect cannot be beaten — with correct play on both sides this "
                "game is always drawn. A run of draws against it is the result."
            ),
            xalign=0.0,
            wrap=True,
        )
        note.add_css_class("status")
        body.append(note)

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_vexpand(True)
        scroller.set_child(body)

        view = Adw.ToolbarView()
        view.add_top_bar(header)
        view.set_content(scroller)
        self.set_child(view)


def _tally(*figures: tuple[str, object]) -> Gtk.Widget:
    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    box.add_css_class("tally")
    box.set_homogeneous(True)
    for label, value in figures:
        column = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        figure = Gtk.Label(label=str(value))
        figure.add_css_class("figure")
        column.append(figure)
        caption = Gtk.Label(label=label.upper())
        caption.add_css_class("figure-label")
        column.append(caption)
        box.append(column)
    return box
