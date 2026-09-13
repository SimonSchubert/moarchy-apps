"""The window: a board, a score line, and two buttons a thumb can reach.

The whole app is one screen. The only thing pushed onto the navigation view is
the record, and the controls that belong to the game are in a bar along the
bottom rather than in the header -- on a 720px-tall phone the header is the far
end of a stretch and the bottom bar is under the thumb already holding it.

**One tap while there is a piece in your hand, two once there is not.** That is
not a compromise between the two schemes the other apps here use, it is the
difference between the two halves of this game: in the placing phase there is
nothing to pick up, so a tap on an empty point is the whole move; in the moving
phase the piece matters as much as the point, so a tap picks one up, rings where
it may go, and waits. Auto-moving a piece with only one empty neighbour would be
consistent with Solitaire and wrong here -- a misplaced move in Morris costs the
game, and a card put back does not.

Taking a piece is one tap on one of the pieces ringed in red. The rule about
which those are is the one everybody forgets and it decides real games: not a
piece in a mill, unless every one of them is.

The order of events after a tap is Reversi's, and for Reversi's reason:

    tap -> play -> animate -> settled -> think -> play -> animate -> settled

The computer does not start thinking until the board has stopped moving. That is
not politeness, it is CPython: the search is a Python thread and holds the GIL,
so a search running under an animation turns a 210ms slide into a slideshow.
"""

from __future__ import annotations

import os
import random
import threading

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gio, GLib, Gtk  # noqa: E402
from moarchy_ui.icons import icon  # noqa: E402

from . import ai  # noqa: E402
from .mill import (  # noqa: E402
    BLACK,
    NAMES,
    WHITE,
    Game,
    place_move,
    travel,
    unpack,
)
from .newgame import NewGameDialog  # noqa: E402
from .store import DRAWN, LOST, SOLO, WON, Store  # noqa: E402
from .widgets import BoardView, ScoreLine  # noqa: E402

APP_ICON = "org.moarchy.Mill"


class MillWindow(Adw.ApplicationWindow):
    __gtype_name__ = "MillWindow"

    def __init__(self, store: Store, **kwargs) -> None:
        super().__init__(**kwargs)
        self.store = store
        self.game: Game = store.game()
        self.level = ai.level_for(store.level)
        self._picked = -1
        self._drops: tuple[int, ...] = ()
        self._thinking = False
        self._rng = random.Random()
        self._recorded = store.recorded
        # Bumped whenever the board stops being the one a search was started
        # for. A thread that comes back holding a move for a game that has been
        # restarted or taken back must be dropped on the floor.
        self._generation = 0

        self.set_title("Mill")
        self.set_default_size(360, 720)

        self._nav = Adw.NavigationView()
        self._nav.add(self._game_page())
        self.set_content(self._nav)

        for name, handler in (
            ("new", lambda *_: self.ask_new_game()),
            ("undo", lambda *_: self.undo()),
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
        self._title = Adw.WindowTitle(title="Mill", subtitle="")
        header.set_title_widget(self._title)

        menu = Gtk.MenuButton(
            icon_name=icon("open-menu-symbolic", "view-more-symbolic")
        )
        menu.set_tooltip_text("Menu")
        menu.update_property([Gtk.AccessibleProperty.LABEL], ["Menu"])
        model = Gio.Menu()
        model.append("New game…", "win.new")
        model.append("Record", "win.stats")
        model.append("About Mill", "app.about")
        menu.set_menu_model(model)
        header.pack_end(menu)

        self._score = ScoreLine()

        self._board = BoardView()
        self._board.set_margin_start(8)
        self._board.set_margin_end(8)
        self._board.set_margin_top(4)
        self._board.connect("point-activated", self._on_point)
        self._board.connect("settled", self._on_settled)

        self._status = Gtk.Label()
        self._status.add_css_class("status")
        self._status.set_margin_top(2)
        self._status.set_margin_bottom(2)
        self._status.set_ellipsize(3)

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
        return Adw.NavigationPage.new(view, "Mill")

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
        self._undo.set_tooltip_text("Take back your last turn")
        self._undo.connect("clicked", lambda *_: self.undo())
        bar.append(self._undo)

        self._again = Gtk.Button()
        self._again.set_child(
            Adw.ButtonContent(
                icon_name=icon("view-refresh-symbolic", "document-new-symbolic"),
                label="New game",
            )
        )
        self._again.add_css_class("pill")
        self._again.connect("clicked", lambda *_: self.ask_new_game())
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
    def human(self) -> int:
        return self.store.human

    @property
    def names(self) -> dict[int, str]:
        if not self.solo:
            return {WHITE: NAMES[WHITE], BLACK: NAMES[BLACK]}
        other = BLACK if self.human == WHITE else WHITE
        return {self.human: "You", other: self.level.label}

    def _their_turn(self) -> bool:
        return self.solo and self.game.turn != self.human and not self.game.over

    # --- drawing the state -----------------------------------------------

    def refresh(self) -> None:
        position = self.game.position
        mine = not self._their_turn() and not self._thinking and not self.game.over
        takeable = tuple(position.removable()) if mine and position.removing else ()
        self._board.show(
            position,
            picked=self._picked,
            drops=self._drops,
            takeable=takeable,
            last=self._last_point(),
        )
        self._score.refresh(position, self.names, live=not self.game.over)
        self._status.set_text(self._status_text())
        if self.game.over:
            self._status.add_css_class("alert")
        else:
            self._status.remove_css_class("alert")

        self._undo.set_sensitive(
            bool(self.game.moves) and not self.game.over and not self._thinking
        )
        if self.game.over:
            self._again.add_css_class("suggested-action")
        else:
            self._again.remove_css_class("suggested-action")

        if self.solo:
            side = "white" if self.human == WHITE else "black"
            self._title.set_subtitle(f"{self.level.label} · you are {side}")
        else:
            self._title.set_subtitle("Two players")

    def _last_point(self) -> int:
        move = self.game.last_move()
        if move is None:
            return -1
        return unpack(move)[1]

    def _status_text(self) -> str:
        if self.game.over:
            return self._result_text()
        if self._thinking:
            return f"{self.names[self.game.turn]} is thinking…"
        position = self.game.position
        who = self.names[position.turn]
        if self._their_turn():
            return f"{who} to play"
        if position.removing:
            other = self.names[BLACK if position.turn == WHITE else WHITE]
            return f"A mill — take one of {other}'s pieces"
        if position.placing(position.turn):
            left = position.left(position.turn)
            return f"Place a piece — {left} left in hand"
        if position.flying(position.turn):
            return "Three left: move anywhere"
        return "Move a piece along a line"

    def _result_text(self) -> str:
        if self.game.drawn:
            return "A draw — fifty moves with nothing taken"
        winner = self.game.position.winner()
        if winner is None:
            return "A draw"
        left = self.game.position.count(winner)
        if not self.solo:
            return f"{NAMES[winner]} wins with {left} left"
        if winner == self.human:
            return f"You win with {left} left"
        return f"{self.level.label} wins with {left} left"

    # --- playing ---------------------------------------------------------

    def _on_point(self, _board: BoardView, spot: int) -> None:
        if self._thinking or self._board.busy:
            return
        if self.game.over:
            self._toast("That game is finished. Tap New game.")
            return
        if self._their_turn():
            return
        position = self.game.position

        if position.removing:
            if spot in position.removable():
                self._play(place_move(spot))
            # Silent otherwise. A tap on a piece the rules protect is a miss,
            # and the red rings have already said which ones those are.
            return

        if position.placing(position.turn):
            if position.empty >> spot & 1:
                self._play(place_move(spot))
            return

        if self._picked >= 0:
            if spot in self._drops:
                held = self._picked
                self._clear()
                self._play(travel(held, spot))
                return
            if spot == self._picked:
                # Tapping the piece you picked up puts it back down. There is no
                # other way to change your mind.
                self._clear()
                self.refresh()
                return
            self._clear()

        if position.own >> spot & 1:
            drops = position.destinations(spot)
            if drops:
                self._picked = spot
                self._drops = tuple(drops)
        self.refresh()

    def _play(self, move: int) -> None:
        before = self.game.position
        play = self.game.play(move)
        self._clear()
        self.store.remember(self.game, finished=self.game.over)
        self._save()
        self.refresh()
        self._board.animate(before, play, self.game.position)

    def _clear(self) -> None:
        self._picked = -1
        self._drops = ()

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
        something. If that something was the computer's turn, the search has to
        start again by itself -- there is no tap coming.
        """
        if self.game.over:
            # A result owed from a session that was killed between the move
            # being written and the piece finishing its slide.
            self._finish()
        elif self._their_turn():
            self._think()

    def _think(self) -> None:
        if self._thinking:
            return
        self._thinking = True
        self._generation += 1
        generation = self._generation
        position = self.game.position
        level = self.level
        self.refresh()
        threading.Thread(
            target=self._search,
            args=(position, level, generation),
            # Daemon, so that quitting never waits for a search. The result of
            # an abandoned one is worth nothing, and the headless checks run the
            # app with a time limit.
            daemon=True,
        ).start()

    def _search(self, position, level, generation: int) -> None:
        try:
            move = ai.choose(position, level, self._rng)
        except Exception:  # noqa: BLE001 -- see below
            # A search that dies takes the game with it: this thread is the only
            # thing that will ever move for this side, so it answers with a
            # legal move rather than leaving a board nobody can play on.
            legal = position.moves()
            move = legal[0] if legal else -1
        GLib.idle_add(self._thought, move, generation)

    def _thought(self, move: int, generation: int) -> bool:
        if generation != self._generation:
            return GLib.SOURCE_REMOVE  # a different game now
        self._thinking = False
        if move < 0 or not self.game.position.is_legal(move):
            self.refresh()
            return GLib.SOURCE_REMOVE
        self._play(move)
        return GLib.SOURCE_REMOVE

    # --- finishing -------------------------------------------------------

    def _finish(self) -> None:
        """Record the result once, and say what it was."""
        if self._recorded or not self.game.over:
            return
        self._recorded = True
        winner = self.game.position.winner()
        if self.solo:
            if self.game.drawn or winner is None:
                self.store.record(DRAWN)
            elif winner == self.human:
                self.store.record(WON, self.game.position.count(self.human))
            else:
                self.store.record(LOST)
        self.store.remember(self.game, finished=True)
        self._save()
        self.refresh()
        self._toast(self._result_text())

    # --- the rest --------------------------------------------------------

    def undo(self) -> None:
        if self._thinking or self._board.busy or self.game.over:
            return
        self._clear()
        taken = self.game.takeback(self.human) if self.solo else self.game.undo()
        if not taken:
            return
        # Any search still running is for a board that no longer exists.
        self._generation += 1
        self.store.remember(self.game)
        self._save()
        self.refresh()
        # Taking back the computer's opening move leaves it on move again --
        # the only case where an undo does not end on the person's turn.
        self._resume()

    def ask_new_game(self) -> None:
        dialog = NewGameDialog(
            mode=self.store.mode,
            level=self.level.key,
            human=self.human,
            in_progress=bool(self.game.moves) and not self.game.over,
        )
        dialog.connect("chosen", self._on_chosen)
        dialog.present(self)

    def _on_chosen(self, _dialog, mode: str, level: str, human: int) -> None:
        self._generation += 1
        self._thinking = False
        self._clear()
        self.game = self.store.begin(mode=mode, level=level, human=human)
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
        """Start on a particular screen, for the screenshot harness."""
        if os.environ.get("MOARCHY_MILL_PAGE") == "record":
            self.show_record()
        if os.environ.get("MOARCHY_MILL_NEW"):
            GLib.idle_add(self.ask_new_game)
        if os.environ.get("MOARCHY_MILL_PICK"):
            GLib.idle_add(self.pick_something)

    def pick_something(self) -> bool:
        """Pick up the first piece on the board that can move.

        For the screenshot harness, and only for it: the ring round a piece and
        the rings round where it may go are the one thing this app draws that no
        environment variable can otherwise reach, because reaching it means
        tapping a point whose position depends on the game.
        """
        position = self.game.position
        if position.removing or position.placing(position.turn):
            return False
        for spot in range(24):
            if position.own >> spot & 1 and position.destinations(spot):
                self._picked = spot
                self._drops = tuple(position.destinations(spot))
                self.refresh()
                return True
        return False

    def _on_close(self, *_args) -> bool:
        self.store.remember(self.game, finished=self.game.over)
        self._save()
        return False


class RecordPage(Adw.NavigationPage):
    """Games played against the computer, by difficulty.

    Only the computer's games are in here. Two people passing a phone across a
    table are not playing against the app, and a tally that counted those would
    be counting both of them at once.
    """

    __gtype_name__ = "MillRecord"

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
                ("Best win", totals["best"] or "—"),
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
            played = entry["played"]
            if played:
                row.set_subtitle(
                    f"{entry[WON]} won · {entry[LOST]} lost · {entry[DRAWN]} drawn"
                )
            else:
                row.set_subtitle(level.blurb)
            value = Gtk.Label(
                label=f"{round(100 * entry[WON] / played)}%" if played else "—"
            )
            value.add_css_class("dim-label")
            row.add_suffix(value)
            rows.append(row)
        body.append(rows)

        note = Gtk.Label(
            label=(
                "Best win is how many pieces you had left. Winning with eight "
                "and winning with three are the same result and different games."
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
