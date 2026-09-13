"""The window: a board, a count, and a hint that is a proof rather than a guess.

The whole app is one screen. The only thing pushed onto the navigation view is
the record, and the two controls the game needs are in a bar along the bottom
rather than in the header -- on a 720px-tall phone the header is the far end of
a stretch and the bottom bar is under the thumb already holding the device.

**A tap jumps the peg when there is one jump it can make, and asks when there is
more than one.** The same rule Solitaire uses, for the same reason: most pegs on
most boards have exactly one thing they can do, and a two-tap protocol for every
one of those is a tap spent on ceremony.

The part worth reading twice is **Hint**, which is the only feature in this
repository that answers a question the player genuinely cannot. Peg solitaire
has no material to count and no threat to see: a board with twenty pegs and no
way to reach one looks exactly like a board with a way, and somebody can spend
ten minutes on a position that was decided eight jumps ago. So the hint runs the
solver, on a thread, on a two-second clock, and gives one of three answers -- a
jump, a proof that there is none, or an honest "no answer in two seconds".

When it does find a line it keeps the whole thing. Following a hint therefore
makes the next one free, and playing anything else throws it away, which is the
only bookkeeping in here.
"""

from __future__ import annotations

import os
import threading

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gio, GLib, Gtk  # noqa: E402
from moarchy_ui.icons import icon  # noqa: E402

from . import solver  # noqa: E402
from .chooser import FigureDialog  # noqa: E402
from .pegs import FIGURES, Game, decode  # noqa: E402
from .store import Store  # noqa: E402
from .widgets import BoardView  # noqa: E402

APP_ICON = "org.moarchy.PegSolitaire"


class PegSolitaireWindow(Adw.ApplicationWindow):
    __gtype_name__ = "PegSolitaireWindow"

    def __init__(self, store: Store, **kwargs) -> None:
        super().__init__(**kwargs)
        self.store = store
        self.game: Game = store.game()
        self._picked = -1
        self._drops: tuple[int, ...] = ()
        self._hint: tuple[int, int] = (-1, -1)
        # The rest of a line the solver found. Following it costs nothing;
        # leaving it throws it away.
        self._line: list[int] = []
        self._thinking = False
        self._generation = 0
        self._recorded = store.recorded

        self.set_title("Peg Solitaire")
        self.set_default_size(360, 720)

        self._nav = Adw.NavigationView()
        self._nav.add(self._game_page())
        self.set_content(self._nav)

        for name, handler in (
            ("figures", lambda *_: self.ask_figure()),
            ("again", lambda *_: self.start_again()),
            ("undo", lambda *_: self.undo()),
            ("hint", lambda *_: self.hint()),
            ("stats", lambda *_: self.show_record()),
        ):
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", handler)
            self.add_action(action)

        self.connect("close-request", self._on_close)
        self.refresh()
        self._open_requested()

    # --- the page --------------------------------------------------------

    def _game_page(self) -> Adw.NavigationPage:
        header = Adw.HeaderBar()
        self._title = Adw.WindowTitle(title="Peg Solitaire", subtitle="")
        header.set_title_widget(self._title)

        menu = Gtk.MenuButton(
            icon_name=icon("open-menu-symbolic", "view-more-symbolic")
        )
        menu.set_tooltip_text("Menu")
        menu.update_property([Gtk.AccessibleProperty.LABEL], ["Menu"])
        model = Gio.Menu()
        model.append("Figures…", "win.figures")
        model.append("Start this one again", "win.again")
        model.append("Record", "win.stats")
        model.append("About Peg Solitaire", "app.about")
        menu.set_menu_model(model)
        header.pack_end(menu)

        self._banner = Adw.Banner()
        self._banner.set_revealed(False)
        self._banner.connect("button-clicked", lambda *_: self.start_again())

        self._count = Gtk.Label()
        self._count.add_css_class("counter")
        self._count.set_margin_top(6)

        self._board = BoardView()
        self._board.set_margin_start(10)
        self._board.set_margin_end(10)
        self._board.set_margin_top(4)
        self._board.connect("hole-activated", self._on_hole)
        self._board.connect("settled", self._on_settled)

        self._status = Gtk.Label()
        self._status.add_css_class("status")
        self._status.set_margin_top(2)
        self._status.set_margin_bottom(2)
        self._status.set_ellipsize(3)

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        body.set_vexpand(True)
        body.set_valign(Gtk.Align.CENTER)
        body.append(self._count)
        body.append(self._board)
        body.append(self._status)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        outer.append(self._banner)
        outer.append(body)

        self._toasts = Adw.ToastOverlay()
        self._toasts.set_child(outer)

        view = Adw.ToolbarView()
        view.add_top_bar(header)
        view.set_content(self._toasts)
        view.add_bottom_bar(self._actions())
        return Adw.NavigationPage.new(view, "Peg Solitaire")

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
        self._undo.set_tooltip_text("Take back the last jump")
        self._undo.connect("clicked", lambda *_: self.undo())
        bar.append(self._undo)

        self._help = Gtk.Button()
        self._help.set_child(
            Adw.ButtonContent(
                icon_name=icon(
                    "dialog-question-symbolic",
                    "help-about-symbolic",
                    "dialog-information-symbolic",
                ),
                label="Hint",
            )
        )
        self._help.add_css_class("pill")
        self._help.set_tooltip_text("Is there a way to finish from here?")
        self._help.connect("clicked", lambda *_: self.hint())
        bar.append(self._help)
        return bar

    def set_palette(self, palette) -> None:
        """The theme changed. The widgets repaint themselves from the reloaded
        stylesheet; the board is drawn by hand and has to be told."""
        self._board.set_colours(palette)

    # --- drawing the state -----------------------------------------------

    def refresh(self) -> None:
        position = self.game.position
        self._board.show(
            position, picked=self._picked, drops=self._drops, hint=self._hint
        )
        left = position.count
        self._count.set_text(f"{left} peg" if left == 1 else f"{left} pegs")
        self._title.set_subtitle(self.game.figure.label)
        self._status.set_text(self._status_text())
        if self.game.over:
            self._status.add_css_class("alert")
        else:
            self._status.remove_css_class("alert")
        self._undo.set_sensitive(bool(self.game.moves) and not self._thinking)
        self._help.set_sensitive(not self.game.over and not self._thinking)
        self._show_banner()

    def _status_text(self) -> str:
        if self._thinking:
            return "Looking for a way through…"
        if self.game.over:
            # Not the result: the banner is already saying that, an inch above
            # the board, and a sentence repeated twice on one screen reads as
            # the app having lost track of what it had said.
            jumps = len(self.game.moves)
            best = self.store.record_for(self.game.figure.key)["best"]
            made = f"{jumps} jump{'' if jumps == 1 else 's'}"
            return f"{made} · best here {best}" if best else made
        jumps = len(self.game.position.moves())
        goal = "one peg, in the middle" if self.game.figure.centre else "one peg"
        return f"{jumps} jump{'' if jumps == 1 else 's'} · finish on {goal}"

    def _result_text(self) -> str:
        if self.game.perfect:
            return "One peg, in the middle. That is the whole puzzle."
        if self.game.solved:
            if self.game.figure.centre:
                return "One peg — but not the one in the middle."
            return "One peg. That is as far as this figure goes."
        return f"Stuck with {self.game.count} pegs."

    def _show_banner(self) -> None:
        if not self.game.over:
            self._banner.set_revealed(False)
            return
        self._banner.set_title(self._result_text())
        self._banner.set_button_label("Start again")
        self._banner.set_revealed(True)

    # --- playing ---------------------------------------------------------

    def _on_hole(self, _board: BoardView, hole: int) -> None:
        if self._board.busy or self._thinking:
            return
        if self.game.over:
            self._toast("Nothing else will move. Tap Start again.")
            return
        position = self.game.position

        if self._picked >= 0:
            if hole in self._drops:
                for move in position.jumps_from(self._picked):
                    if position.landing(move)[1] == hole:
                        self._clear()
                        self._play(move)
                        return
            if hole == self._picked:
                # Tapping the peg you picked up puts it back down. There is no
                # other way to change your mind.
                self._clear()
                self.refresh()
                return
            self._clear()

        jumps = position.jumps_from(hole)
        if not jumps:
            # Silent. A tap on a peg that cannot move, or on an empty hole, is
            # a miss -- and an app that scolds you for a miss on a touch screen
            # scolds you all day long.
            self.refresh()
            return
        if len(jumps) == 1:
            self._play(jumps[0])
            return
        self._picked = hole
        self._drops = tuple(position.landing(move)[1] for move in jumps)
        self.refresh()

    def _play(self, move: int) -> None:
        before = self.game.position
        if not self.game.play(move):
            self.refresh()
            return
        # Following the hint keeps the rest of it; anything else throws it away.
        if self._line and self._line[0] == move:
            self._line.pop(0)
        else:
            self._line = []
        self._hint = (-1, -1)
        self.store.remember(self.game, finished=self.game.over)
        self._save()
        self.refresh()
        self._board.animate(before, move, self.game.position)

    def _on_settled(self, *_args) -> None:
        self.refresh()
        if self.game.over:
            self._finish()

    def _clear(self) -> None:
        self._picked = -1
        self._drops = ()

    # --- the hint --------------------------------------------------------

    def hint(self) -> None:
        """Ask the solver whether this position can still be finished."""
        if self._thinking or self._board.busy or self.game.over:
            return
        self._clear()
        if self._line and self.game.position.is_legal(self._line[0]):
            # Already known: the person is following a line the solver found,
            # and looking for it again would be two seconds spent proving
            # something that is written down.
            self._show_hint(self._line[0])
            return

        self._thinking = True
        self._generation += 1
        generation = self._generation
        position = self.game.position
        target = self.game.figure.target if self.game.figure.centre else -1
        self.refresh()
        threading.Thread(
            target=self._search,
            args=(position, target, generation),
            # Daemon, so that quitting never waits for a search. The result of
            # an abandoned one is worth nothing, and the headless checks run the
            # app with a time limit.
            daemon=True,
        ).start()

    def _search(self, position, target: int, generation: int) -> None:
        try:
            answer = solver.search(position, target)
        except Exception:  # noqa: BLE001
            # A hint that dies must not take the game with it: the board is
            # still playable, and the honest report is that there is no answer.
            answer = solver.Answer(solver.UNKNOWN)
        GLib.idle_add(self._thought, answer, generation)

    def _thought(self, answer, generation: int) -> bool:
        if generation != self._generation:
            return GLib.SOURCE_REMOVE  # a different board now
        self._thinking = False
        if answer.verdict == solver.SOLVED and answer.move is not None:
            self._line = list(answer.line)
            self._show_hint(answer.move)
            return GLib.SOURCE_REMOVE
        self._line = []
        if answer.verdict == solver.IMPOSSIBLE:
            left = self.game.position.count
            self._toast(
                f"No way to finish from here — {left} pegs is as low as it goes."
            )
        else:
            self._toast("No answer inside two seconds. Try a jump and ask again.")
        self.refresh()
        return GLib.SOURCE_REMOVE

    def _show_hint(self, move: int) -> None:
        cell, _ = decode(move)
        self._hint = (cell, self.game.position.landing(move)[1])
        self.refresh()

    # --- finishing -------------------------------------------------------

    def _finish(self) -> None:
        """Record the result once, and say what it was."""
        if self._recorded or not self.game.over:
            return
        self._recorded = True
        self.store.record(self.game.count, perfect=self.game.perfect)
        self.store.remember(self.game, finished=True)
        self._save()
        self.refresh()
        self._toast(self._result_text())

    # --- the rest --------------------------------------------------------

    def undo(self) -> None:
        if self._board.busy or self._thinking:
            return
        self._clear()
        self._hint = (-1, -1)
        if not self.game.undo():
            return
        # The line the solver found was for a board that no longer exists, and
        # so is any search still running for it.
        self._line = []
        self._generation += 1
        self.store.remember(self.game, finished=self.game.over)
        self._save()
        self.refresh()

    def start_again(self) -> None:
        """The same figure, from the top. Nothing is recorded for giving up.

        Backing out of a figure and trying a different third jump is how this
        game is played rather than a defeat, so only a board that would not move
        again goes into the record -- which is what makes the record a measure
        of finishing rather than of persevering.
        """
        self._reset(self.store.again())

    def ask_figure(self) -> None:
        dialog = FigureDialog(current=self.game.figure.key, store=self.store)
        dialog.connect("chosen", self._on_chosen)
        dialog.present(self)

    def _on_chosen(self, _dialog, key: str) -> None:
        self._reset(self.store.begin(key))

    def _reset(self, game: Game) -> None:
        self._generation += 1
        self._thinking = False
        self._clear()
        self._hint = (-1, -1)
        self._line = []
        self.game = game
        self._recorded = False
        self._save()
        self.refresh()

    def show_record(self) -> None:
        self._nav.push(RecordPage(self.store))

    def _toast(self, text: str) -> None:
        toast = Adw.Toast.new(text)
        toast.set_timeout(4)
        self._toasts.add_toast(toast)

    def _save(self) -> None:
        try:
            self.store.save()
        except OSError as exc:
            self._toast(f"Could not save: {exc.strerror or exc}")

    def _open_requested(self) -> None:
        """Start on a particular screen, for the screenshot harness."""
        if os.environ.get("MOARCHY_PEGSOLITAIRE_PAGE") == "record":
            self.show_record()
        if os.environ.get("MOARCHY_PEGSOLITAIRE_FIGURES"):
            GLib.idle_add(self.ask_figure)
        if os.environ.get("MOARCHY_PEGSOLITAIRE_HINT"):
            GLib.idle_add(self.hint)

    def _on_close(self, *_args) -> bool:
        self.store.remember(self.game, finished=self.game.over)
        self._save()
        return False


class RecordPage(Adw.NavigationPage):
    """Every figure and the fewest pegs it has been left at.

    Fewest pegs rather than wins, because peg solitaire is a puzzle and not a
    contest: the thing somebody actually gets better at is finishing with three
    instead of five, and a win column would be a column of zeroes for a week and
    then a single one.
    """

    __gtype_name__ = "PegSolitaireRecord"

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
                ("Figures", f"{totals['best']}/{len(FIGURES)}"),
                ("In the middle", totals["perfect"]),
            )
        )

        heading = Gtk.Label(label="FEWEST PEGS LEFT", xalign=0.0)
        heading.add_css_class("section-heading")
        body.append(heading)

        rows = Gtk.ListBox()
        rows.set_selection_mode(Gtk.SelectionMode.NONE)
        rows.add_css_class("boxed-list")
        for figure in FIGURES:
            entry = store.record_for(figure.key)
            row = Adw.ActionRow(title=figure.label)
            if entry["played"]:
                played = entry["played"]
                row.set_subtitle(
                    f"{played} played · {entry['solved']} finished"
                    + (f" · {entry['perfect']} in the middle" if figure.centre else "")
                )
            else:
                row.set_subtitle("Not played yet")
            value = Gtk.Label(label=str(entry["best"]) if entry["best"] else "—")
            value.add_css_class("dim-label")
            row.add_suffix(value)
            rows.append(row)
        body.append(rows)

        note = Gtk.Label(
            label=(
                "Only a board that will not move again is counted. Starting a "
                "figure over is how this game is played, not a defeat."
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
