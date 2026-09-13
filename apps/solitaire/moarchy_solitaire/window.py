"""The window: a table, a banner that appears when it has something to say, and
two buttons a thumb can reach.

The whole app is one screen. There is no list to navigate and no detail to open,
so the only thing pushed onto the navigation view is the record, and the two
controls the game needs are in a bar along the bottom rather than in the header
-- on a 720px-tall phone the header is the far end of a stretch and the bottom
bar is under the thumb already holding the device.

**A tap moves the card when there is one place for it to go, and asks when there
is more than one.** That is the whole interaction, and it is the thing this app
has instead of dragging. Dragging a 46px card with a finger that covers it is a
gesture nobody can aim, and a two-tap protocol for every move is two taps for
the ninety per cent of moves that have exactly one answer. So a tap that is
unambiguous simply happens; a tap that is not picks the run up, rings it, and
rings everywhere it may be put down until one of those is tapped.

The other thing here is the **banner**, which is the app noticing on the
player's behalf. Klondike has no rule that ends a lost game -- the stock can
always be turned over again -- so a person can cycle a pack forever without
being told there is nothing in it. And at the other end, a table with every card
face up is a table that is already won and needs a hundred taps to prove it. The
banner says both, and offers the one button that answers.
"""

from __future__ import annotations

import os

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gio, GLib, Gtk  # noqa: E402
from moarchy_ui.icons import icon  # noqa: E402

from .klondike import (  # noqa: E402
    DRAWS,
    PILES,
    STOCK,
    TABLEAU,
    WASTE,
    Game,
    Move,
    homeward,
)
from .newgame import NewGameDialog  # noqa: E402
from .store import LOST, WON, Store  # noqa: E402
from .widgets import TableView  # noqa: E402

APP_ICON = "org.moarchy.Solitaire"

DRAW_NAMES = {1: "Draw one", 3: "Draw three"}


class SolitaireWindow(Adw.ApplicationWindow):
    __gtype_name__ = "SolitaireWindow"

    def __init__(self, store: Store, **kwargs) -> None:
        super().__init__(**kwargs)
        self.store = store
        self.game: Game = store.game()
        # The run a tap picked up and could not place on its own, and where it
        # may go. Both are None or empty the rest of the time, which is most of
        # the time -- see the module docstring.
        self._selected: tuple[int, int] | None = None
        self._drops: tuple[int, ...] = ()
        # Moves still to play from Send them home, one per settled animation.
        self._queue: list[Move] = []
        self._recorded = store.recorded

        self.set_title("Solitaire")
        self.set_default_size(360, 720)

        self._nav = Adw.NavigationView()
        self._nav.add(self._game_page())
        self.set_content(self._nav)

        for name, handler in (
            ("new", lambda *_: self.ask_new_game()),
            ("again", lambda *_: self.deal_again()),
            ("undo", lambda *_: self.undo()),
            ("home", lambda *_: self.send_home()),
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
        self._title = Adw.WindowTitle(title="Solitaire", subtitle="")
        header.set_title_widget(self._title)

        menu = Gtk.MenuButton(
            icon_name=icon("open-menu-symbolic", "view-more-symbolic")
        )
        menu.set_tooltip_text("Menu")
        menu.update_property([Gtk.AccessibleProperty.LABEL], ["Menu"])
        model = Gio.Menu()
        model.append("New deal…", "win.new")
        model.append("Deal this one again", "win.again")
        model.append("Record", "win.stats")
        model.append("About Solitaire", "app.about")
        menu.set_menu_model(model)
        header.pack_end(menu)

        self._banner = Adw.Banner()
        self._banner.set_revealed(False)
        self._banner.connect("button-clicked", self._on_banner)

        self._table = TableView()
        self._table.connect("pile-tapped", self._on_tap)
        self._table.connect("settled", self._on_settled)

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        body.append(self._banner)
        body.append(self._table)

        self._toasts = Adw.ToastOverlay()
        self._toasts.set_child(body)

        view = Adw.ToolbarView()
        view.add_top_bar(header)
        view.set_content(self._toasts)
        view.add_bottom_bar(self._actions())
        return Adw.NavigationPage.new(view, "Solitaire")

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
        self._undo.set_tooltip_text("Take back the last move")
        self._undo.connect("clicked", lambda *_: self.undo())
        bar.append(self._undo)

        self._deal = Gtk.Button()
        self._deal.set_child(
            Adw.ButtonContent(
                icon_name=icon("view-refresh-symbolic", "document-new-symbolic"),
                label="New deal",
            )
        )
        self._deal.add_css_class("pill")
        self._deal.connect("clicked", lambda *_: self.ask_new_game())
        bar.append(self._deal)
        return bar

    def set_palette(self, palette) -> None:
        """The theme changed. The widgets repaint themselves from the reloaded
        stylesheet; the table is drawn by hand and has to be told."""
        self._table.set_colours(palette)

    # --- drawing the state -----------------------------------------------

    def refresh(self) -> None:
        table = self.game.table
        self._table.show(table, selected=self._selected, drops=self._drops)
        moves = self.game.count
        plural = "" if moves == 1 else "s"
        self._title.set_subtitle(
            f"{DRAW_NAMES.get(self.game.draw, 'Draw one')} · {moves} move{plural}"
        )
        self._undo.set_sensitive(bool(self.game.moves) and not self._queue)
        if self.game.won:
            self._deal.add_css_class("suggested-action")
        else:
            self._deal.remove_css_class("suggested-action")
        self._show_banner()

    def _show_banner(self) -> None:
        """What the app has noticed, if it has noticed anything."""
        table = self.game.table
        if self._queue:
            self._banner.set_revealed(False)
            return
        if table.won:
            moves = self.game.count
            self._banner.set_title(f"Every card home, in {moves} moves")
            self._banner.set_button_label("New deal")
            self._banner.set_revealed(True)
            return
        if table.finishable:
            self._banner.set_title("Nothing left face down")
            self._banner.set_button_label("Send them home")
            self._banner.set_revealed(True)
            return
        if self.game.stuck:
            # The one thing the rules will never tell anybody. Without this an
            # unwinnable deal is an invitation to turn the stock over for ten
            # minutes looking for the move that is not there.
            self._banner.set_title("No moves left on this deal")
            self._banner.set_button_label("New deal")
            self._banner.set_revealed(True)
            return
        self._banner.set_revealed(False)

    def _on_banner(self, *_args) -> None:
        if self.game.table.finishable:
            self.send_home()
        else:
            self.ask_new_game()

    # --- playing ---------------------------------------------------------

    def _on_tap(self, _view: TableView, pile: int, position: int) -> None:
        if self._queue:
            # Somebody tapped during the run home. They have watched enough of
            # it: the rest is played at once rather than making them wait out an
            # animation for a game that is already decided.
            self._flush_queue()
            return
        if self._table.busy:
            return
        table = self.game.table

        if pile == STOCK:
            self._clear()
            if table.stock:
                self._play(Move(STOCK, WASTE, min(table.draw, len(table.stock))))
            elif table.waste:
                self._play(Move(WASTE, STOCK, len(table.waste)))
            else:
                self.refresh()
            return

        if self._selected is not None:
            held, at = self._selected
            if pile in self._drops:
                count = len(table.run_from(held, at))
                self._clear()
                self._play(Move(held, pile, count))
                return
            if pile == held:
                # Tapping the run you picked up puts it back down. There is no
                # other way to change your mind, and a selection with no way out
                # is a selection people tap around.
                self._clear()
                self.refresh()
                return
            self._clear()

        run = table.run_from(pile, position)
        if not run:
            self.refresh()
            return
        drops = table.destinations(pile, position)
        if len(drops) == 1:
            self._play(Move(pile, drops[0], len(run)))
            return
        if drops:
            self._selected = (pile, position)
            self._drops = tuple(drops)
        # No destinations is silent. A tap on a card with nowhere to go is a
        # miss, and an app that scolds you for a miss on a touch screen scolds
        # you all day long.
        self.refresh()

    def _play(self, move: Move) -> None:
        before = self.game.table
        if not self.game.play(move):
            self.refresh()
            return
        self.store.remember(self.game, finished=self.game.won)
        self._save()
        self.refresh()
        self._table.animate(before, move, self.game.table)

    def _on_settled(self, *_args) -> None:
        if self._queue:
            self._play(self._queue.pop(0))
            return
        self.refresh()
        if self.game.won:
            self._finish()

    def _clear(self) -> None:
        self._selected = None
        self._drops = ()

    # --- the run home ----------------------------------------------------

    def send_home(self) -> None:
        """Play out a table with nothing left face down.

        The moves are the rules', not a shortcut round them: `homeward` sends
        home whatever will go and turns the stock over when nothing will, which
        is exactly what a person would do with the same table and a hundred more
        taps. Every move goes into the move list, so the game that is saved is
        the game that was played and undo still walks back through it.
        """
        if not self.game.table.finishable or self._queue:
            return
        self._clear()
        self._queue = homeward(self.game.table)
        if not self._queue:
            return
        self.refresh()
        self._play(self._queue.pop(0))

    def _flush_queue(self) -> None:
        queued, self._queue = self._queue, []
        for move in queued:
            if not self.game.play(move):
                break
        self.store.remember(self.game, finished=self.game.won)
        self._save()
        self._table.show(self.game.table)
        self.refresh()
        if self.game.won:
            self._finish()

    # --- finishing -------------------------------------------------------

    def _finish(self) -> None:
        """Record the win once, and say what it was."""
        if self._recorded or not self.game.won:
            return
        self._recorded = True
        self.store.record(WON, self.game.count)
        self.store.remember(self.game, finished=True)
        self._save()
        self.refresh()
        self._toast(f"Won in {self.game.count} moves")

    def _abandon(self) -> None:
        """A deal left unfinished counts as a loss.

        Only if it was ever started. Dealing, looking at it and dealing again is
        not a game anybody played, and counting it would make the tally a
        measure of how often somebody did not like the look of a table.
        """
        if self.game.moves and not self.game.won and not self._recorded:
            self.store.record(LOST)

    # --- the rest --------------------------------------------------------

    def undo(self) -> None:
        if self._table.busy or self._queue:
            return
        self._clear()
        if not self.game.undo():
            return
        # A win taken back is a win that has already been counted, and there is
        # no way to count it off again that is not a way to count it twice.
        self.store.remember(self.game, finished=self.game.won)
        self._save()
        self.refresh()

    def deal_again(self) -> None:
        """The same fifty-two cards, from the top."""
        self._abandon()
        self._clear()
        self._queue = []
        self.game = self.store.again()
        self._recorded = False
        self._save()
        self.refresh()
        self._toast("The same deal again")

    def ask_new_game(self) -> None:
        dialog = NewGameDialog(
            draw=self.game.draw,
            in_progress=bool(self.game.moves) and not self.game.won,
        )
        dialog.connect("chosen", self._on_chosen)
        dialog.present(self)

    def _on_chosen(self, _dialog, draw: int) -> None:
        self._abandon()
        self._clear()
        self._queue = []
        self.game = self.store.begin(draw=draw if draw in DRAWS else 1)
        self._recorded = False
        self._save()
        self.refresh()

    def pick_something(self) -> bool:
        """Pick up the first run on the table that has a choice to make.

        For the screenshot harness, and only for it: the ring round a picked-up
        run and the rings round everywhere it may go are the one thing this app
        draws that no environment variable can otherwise reach, because reaching
        it means tapping a card whose position depends on the deal.
        """
        table = self.game.table
        for pile, position in _every_card(table):
            if len(table.destinations(pile, position)) > 1:
                self._selected = (pile, position)
                self._drops = tuple(table.destinations(pile, position))
                self.refresh()
                return True
        return False

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
        opens straight into the screen it should photograph needs none.
        """
        if os.environ.get("MOARCHY_SOLITAIRE_PAGE") == "record":
            self.show_record()
        if os.environ.get("MOARCHY_SOLITAIRE_NEW"):
            GLib.idle_add(self.ask_new_game)
        if os.environ.get("MOARCHY_SOLITAIRE_PICK"):
            self.pick_something()

    def _on_close(self, *_args) -> bool:
        self.store.remember(self.game, finished=self.game.won)
        self._save()
        return False


class RecordPage(Adw.NavigationPage):
    """Games played, by how many cards a tap on the stock turns over.

    Two tallies and not one, because they are two different games. Draw one is
    winnable about four times in five with good play and draw three is not, so a
    single win percentage across both would mostly be reporting which setting
    somebody had been using that month.
    """

    __gtype_name__ = "SolitaireRecord"

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
                ("Fewest", totals["best"] or "—"),
            )
        )

        heading = Gtk.Label(label="BY DEAL", xalign=0.0)
        heading.add_css_class("section-heading")
        body.append(heading)

        rows = Gtk.ListBox()
        rows.set_selection_mode(Gtk.SelectionMode.NONE)
        rows.add_css_class("boxed-list")
        for draw in DRAWS:
            entry = store.record_for(draw)
            row = Adw.ActionRow(title=DRAW_NAMES[draw])
            played = entry["played"]
            if played:
                best = entry["best"]
                row.set_subtitle(
                    f"{entry[WON]} won · longest run {entry['longest']}"
                    + (f" · fewest {best} moves" if best else "")
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

        note = Gtk.Label(
            label=(
                "A deal you walk away from counts as a loss. A deal you look at "
                "and replace without playing does not."
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


def _every_card(table):
    """Every place a tap could land, in the order a person's eye goes."""
    for pile in range(TABLEAU, PILES):
        for position in range(table.hidden(pile), len(table.column(pile))):
            yield pile, position
    if table.waste:
        yield WASTE, len(table.waste) - 1


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
