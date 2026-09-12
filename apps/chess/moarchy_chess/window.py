"""The window: a board, two names, and two buttons a thumb can reach.

The whole app is one screen. There is no list to navigate and no detail to open,
so the only thing pushed onto the navigation view is the record of games played
-- and the controls that belong to the game are in a bar along the bottom rather
than in the header, because on a 720px-tall phone the header is the far end of a
stretch and the bottom bar is under the thumb already holding the device.

The order of events after a tap is the one thing in here worth reading twice:

    tap -> pick up -> tap -> play -> animate -> settled -> think -> play -> ...

The computer does not start thinking until the piece has stopped moving. That is
not politeness, it is CPython: the search is a Python thread and holds the GIL,
so a search running under an animation turns a 190ms slide into a slideshow.
Waiting costs a fifth of a second that the person is spending watching the slide
anyway, and it is the difference between an app that feels smooth on a phone and
one that stutters every move.

The other thing worth reading twice is that a move here takes *two* taps, which
Reversi's board never had to think about. Between them the app is holding a
piece: the square it came from is marked, every square it may go to is dotted,
and a tap anywhere else either picks up a different piece or puts this one down.
Nothing is dragged. Dragging on a 43px square with a thumb over it is a gesture
that ends where the finger was, not where the eye was.
"""

from __future__ import annotations

import os
import threading

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gio, GLib, Gtk  # noqa: E402
from moarchy_ui.icons import icon  # noqa: E402

from . import ai  # noqa: E402
from .chess import (  # noqa: E402
    BLACK,
    CHECKMATE,
    COLOUR_NAMES,
    FIFTY_MOVE,
    INSUFFICIENT,
    NO_SQUARE,
    REPETITION,
    STALEMATE,
    WHITE,
    Game,
    move_from,
    move_promotion,
    move_to,
    parse_square,
)
from .newgame import NewGameDialog  # noqa: E402
from .promote import PromotionDialog  # noqa: E402
from .store import DRAWN, LOST, SOLO, WON, Store  # noqa: E402
from .widgets import BoardView, ScoreLine  # noqa: E402

APP_ICON = "org.moarchy.Chess"


class ChessWindow(Adw.ApplicationWindow):
    __gtype_name__ = "ChessWindow"

    def __init__(self, store: Store, **kwargs) -> None:
        super().__init__(**kwargs)
        self.store = store
        self.game: Game = store.game()
        self.level = ai.level_for(store.level)
        self.palette = None
        self._thinking = False
        self._selected = NO_SQUARE
        # A finished game that was loaded from the file went into the record
        # when it finished. Without this the result would be counted again
        # every time the app is opened on a board with no moves left in it.
        self._recorded = store.finished
        # Bumped whenever the board stops being the one a search was started
        # for. A thread that comes back holding a move for a game that has been
        # restarted or taken back must be dropped on the floor, and a counter is
        # the whole of the mechanism.
        self._generation = 0

        self.set_title("Chess")
        self.set_default_size(360, 720)

        self._nav = Adw.NavigationView()
        self._nav.add(self._game_page())
        self.set_content(self._nav)

        for action, handler in (
            ("new", lambda *_: self.ask_new_game()),
            ("undo", lambda *_: self.undo()),
            ("stats", lambda *_: self.show_record()),
        ):
            entry = Gio.SimpleAction.new(action, None)
            entry.connect("activate", handler)
            self.add_action(entry)

        self.connect("close-request", self._on_close)
        self.refresh()
        self._resume()
        self._open_requested()

    # --- the page --------------------------------------------------------

    def _game_page(self) -> Adw.NavigationPage:
        header = Adw.HeaderBar()
        self._title = Adw.WindowTitle(title="Chess", subtitle="")
        header.set_title_widget(self._title)

        menu = Gtk.MenuButton(
            icon_name=icon("open-menu-symbolic", "view-more-symbolic")
        )
        menu.set_tooltip_text("Menu")
        menu.update_property([Gtk.AccessibleProperty.LABEL], ["Menu"])
        model = Gio.Menu()
        model.append("New game…", "win.new")
        model.append("Record", "win.stats")
        model.append("About Chess", "app.about")
        menu.set_menu_model(model)
        header.pack_end(menu)

        self._score = ScoreLine()

        self._board = BoardView()
        self._board.set_margin_start(8)
        self._board.set_margin_end(8)
        self._board.set_margin_top(4)
        self._board.connect("square-activated", self._on_square)
        self._board.connect("settled", self._on_settled)

        self._status = Gtk.Label()
        self._status.add_css_class("status")
        self._status.set_margin_top(2)
        self._status.set_margin_bottom(2)
        self._status.set_ellipsize(3)

        # The names, the board and what it is saying travel together, centred in
        # whatever the buttons leave. On a 720px screen a 344px board leaves a
        # couple of hundred pixels over, and the choice is where to put the
        # hole: splitting it above and below one block reads as a margin, while
        # pinning the names to the top and the status to the bottom read as
        # three things that had drifted apart.
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
        return Adw.NavigationPage.new(view, "Chess")

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
        self._undo.set_tooltip_text("Take back your last move")
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
        self.palette = palette
        self._board.set_colours(palette)
        self._score.set_colours(palette)

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
            return dict(COLOUR_NAMES)
        other = BLACK if self.human == WHITE else WHITE
        return {self.human: "You", other: self.level.label}

    def _their_turn(self) -> bool:
        return self.solo and self.game.turn != self.human and not self.game.over

    def _mine(self) -> bool:
        """Is the side to move one this person may pick a piece up for?"""
        return not self._their_turn() and not self._thinking and not self.game.over

    # --- drawing the state -----------------------------------------------

    def refresh(self) -> None:
        position = self.game.position
        last = self.game.last_move()
        check = NO_SQUARE
        if position.in_check():
            check = position.kings[position.turn]
        # Hints belong to a person about to tap. They are wrong while the
        # computer is on move and misleading mid-slide, when they would mark the
        # squares of a position that is still arriving.
        targets = ()
        if self._selected != NO_SQUARE and self._mine():
            targets = {move_to(code) for code in position.moves_from(self._selected)}
        self._board.set_flipped(self.solo and self.human == BLACK)
        self._board.show(
            position,
            selected=self._selected,
            targets=targets,
            last=(move_from(last), move_to(last)) if last is not None else None,
            check=check,
        )
        self._score.refresh(self.game, self.names, live=not self.game.over)
        self._status.set_text(self._status_text())
        for style in ("alert", "check"):
            self._status.remove_css_class(style)
        if self.game.over:
            self._status.add_css_class("alert")
        elif check != NO_SQUARE:
            self._status.add_css_class("check")

        # Undo stops at the end of the game. The result has gone into the
        # record by then, and a board that can be rewound past a recorded
        # result is a board that can record a second one.
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

    def _status_text(self) -> str:
        if self.game.over:
            return self._result_text()
        if self._thinking:
            return f"{self.names[self.game.turn]} is thinking…"
        check = "Check — " if self.game.position.in_check() else ""
        if self.solo and self.game.turn == self.human:
            return f"{check}your move"
        # By the display name, not the colour: the header has just told somebody
        # they are white, and answering a move with "Black to play" makes them
        # work out that this means the computer.
        return f"{check}{self.names[self.game.turn]} to play"

    def _result_text(self) -> str:
        kind, winner = self.game.outcome()
        if kind == CHECKMATE:
            if not self.solo:
                return f"Checkmate — {COLOUR_NAMES[winner]} wins"
            if winner == self.human:
                return "Checkmate — you win"
            return f"Checkmate — {self.level.label} wins"
        if kind == STALEMATE:
            return "Stalemate — a draw"
        if kind == FIFTY_MOVE:
            return "A draw — fifty moves with nothing taken"
        if kind == INSUFFICIENT:
            return "A draw — not enough left to mate with"
        if kind == REPETITION:
            return "A draw — the same position three times"
        return ""

    # --- picking a piece up ----------------------------------------------

    def _on_square(self, _board: BoardView, cell: int) -> None:
        if self._thinking or self._board.busy:
            return
        if self.game.over:
            self._toast("That game is finished. Tap New game.")
            return
        if not self._mine():
            return

        position = self.game.position
        if self._selected != NO_SQUARE:
            moves = [
                code
                for code in position.moves_from(self._selected)
                if move_to(code) == cell
            ]
            if moves:
                self._choose(moves)
                return
        code = position.squares[cell]
        if code and code >> 3 == position.turn and position.moves_from(cell):
            # Tapping the piece already up puts it down, which is the gesture
            # for "no, not that one" that needs no second place to tap.
            self._selected = NO_SQUARE if cell == self._selected else cell
        else:
            # Silent. A tap on an empty square is a miss, and an app that scolds
            # you for a miss on a touch screen is an app that scolds you
            # constantly.
            self._selected = NO_SQUARE
        self.refresh()

    def _choose(self, moves: list[int]) -> None:
        """Play the move, asking which piece first if there is a choice.

        More than one move between the same two squares means exactly one thing:
        a pawn on the last rank. Nothing else in chess is ambiguous about where
        a piece came from and where it went.
        """
        if len(moves) == 1:
            self._play(moves[0])
            return
        dialog = PromotionDialog(self.game.turn, self.palette)
        dialog.connect(
            "chosen",
            lambda _dialog, kind: self._play(
                next((code for code in moves if move_promotion(code) == kind), moves[0])
            ),
        )
        dialog.present(self)

    # --- playing ---------------------------------------------------------

    def _play(self, code: int) -> None:
        made = self.game.play(code)
        self._selected = NO_SQUARE
        self.store.remember(self.game, finished=self.game.over)
        self._save()
        self.refresh()
        self._board.animate(made, self.game.position)

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
        if self._their_turn():
            self._think()

    def _think(self) -> None:
        if self._thinking:
            return
        self._thinking = True
        self._generation += 1
        generation = self._generation
        # Copied here, on the main thread, rather than left to the search. The
        # search does copy -- it has to, because it plays moves into what it is
        # given -- but a copy taken on the other thread is a copy taken while
        # this one may be writing.
        position = self.game.position.copy()
        level = self.level
        self.refresh()
        thread = threading.Thread(
            target=self._search,
            args=(position, level, generation),
            # Daemon, so that quitting never waits for a search. The result of
            # an abandoned one is worth nothing, and the headless checks run the
            # app with a time limit.
            daemon=True,
        )
        thread.start()

    def _search(self, position, level, generation: int) -> None:
        try:
            code = ai.choose(position, level)
        except Exception:  # noqa: BLE001 -- see below
            # A search that dies takes the game with it: this thread is the only
            # thing that will ever move for this side, so it answers with a
            # legal move rather than leaving a board nobody can play on.
            legal = position.moves()
            code = legal[0] if legal else None
        GLib.idle_add(self._thought, code if code is not None else 0, generation)

    def _thought(self, code: int, generation: int) -> bool:
        if generation != self._generation:
            return GLib.SOURCE_REMOVE  # a different game now
        self._thinking = False
        if not code or code not in self.game.position.moves():
            self.refresh()
            return GLib.SOURCE_REMOVE
        self._play(code)
        return GLib.SOURCE_REMOVE

    # --- finishing -------------------------------------------------------

    def _finish(self) -> None:
        """Record the result once, and say what it was."""
        if self._recorded:
            return
        self._recorded = True
        _kind, winner = self.game.outcome()
        if self.solo:
            result = (
                DRAWN if winner is None else (WON if winner == self.human else LOST)
            )
            self.store.record(result, (len(self.game.moves) + 1) // 2)
        self.store.remember(self.game, finished=True)
        self._save()
        self._toast(self._result_text())

    # --- the rest --------------------------------------------------------

    def undo(self) -> None:
        if self._thinking or self._board.busy or self.game.over:
            return
        taken = self.game.takeback(self.human) if self.solo else self.game.undo()
        if not taken:
            return
        # Any search still running is for a board that no longer exists.
        self._generation += 1
        self._selected = NO_SQUARE
        self.store.remember(self.game)
        self._save()
        self.refresh()
        # Taking back the computer's opening move leaves it on move again --
        # the only case where an undo does not end on the person's turn. Without
        # this the board sits there with nobody whose turn it is to tap.
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
        self._selected = NO_SQUARE
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
        """Start on a particular screen, for the screenshot harness.

        A headless X server has no pointer worth clicking with, and a run that
        opens straight into the screen it should photograph needs none. The same
        mechanism Keep, Habits and Reversi use, for the same reason.
        """
        if os.environ.get("MOARCHY_CHESS_PAGE") == "record":
            self.show_record()
        if os.environ.get("MOARCHY_CHESS_NEW"):
            self.ask_new_game()
        held = os.environ.get("MOARCHY_CHESS_SELECT")
        if held and self._mine():
            self._hold(held)

    def _hold(self, wanted: str) -> None:
        """Pick a piece up without a tap, for the screenshot harness.

        `auto` means whichever piece has the most to say -- the one with the
        longest list of legal moves -- so the picture of a held piece keeps
        working when `demo.py` plays a different game.
        """
        position = self.game.position
        if wanted == "auto":
            counts = [
                (len(position.moves_from(cell)), cell)
                for cell in range(len(position.squares))
                if position.squares[cell]
            ]
            best, cell = max(counts, default=(0, NO_SQUARE))
            if not best:
                return
        else:
            try:
                cell = parse_square(wanted)
            except ValueError:
                return
            if not position.moves_from(cell):
                return
        self._selected = cell
        self.refresh()

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

    __gtype_name__ = "ChessRecord"

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
                # The number alone, in moves. "19 moves" reads better and is
                # sixty pixels wider than the column it sits in, which on a
                # 360px screen pushes the whole page off the side of it.
                ("Quickest win", totals["quickest"] or "—"),
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
                row.set_subtitle("Not played yet")
            value = Gtk.Label(
                label=f"{round(100 * entry[WON] / played)}%" if played else "—"
            )
            value.add_css_class("dim-label")
            row.add_suffix(value)
            rows.append(row)
        body.append(rows)

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
