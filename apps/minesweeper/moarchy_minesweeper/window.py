"""The window: two readings, a minefield, and a flag button that latches.

The whole app is one screen. The only thing pushed onto the navigation view is
the record, and the two controls the game needs are in a bar along the bottom
rather than in the header -- on a 720px-tall phone the header is the far end of
a stretch and the bottom bar is under the thumb already holding the device.

Three decisions here are the app.

**The flag button is a mode, and it latches.** A hold always flags, which is the
gesture everybody knows, and holding is also the thing this game asks for twenty
or forty times in a row -- four hundred milliseconds each, which is fifteen
seconds of a two-minute game spent waiting. So the button swaps what a plain tap
does, and it is styled as something you are *in* rather than something you
pressed, because a mode nobody can see they are in is, on this board, a tap that
opens a mine.

**A tap on an opened number chords.** Once its flags are down, clearing the rest
of a number is one tap on a cell that is already open and therefore safe. On a
28px grid that is the difference between a playable board and an exercise in
aiming.

**The clock stops when the window is not on screen.** Solitaire in this
repository refuses a clock outright, on the grounds that a phone game is one you
are interrupted in the middle of and a timer that counts through the
interruption is measuring the interruption. That argument is right, and
Minesweeper cannot follow it, because a best time is most of what this game's
record has ever been -- so the clock is kept and the argument is answered
instead: it runs only while the window is visible, and the reading goes dim to
say so.

Visible rather than focused -- see `_on_screen`. The phone's app drawer takes
keyboard focus from every toplevel at once, so a clock that stopped on focus
would stop under a drawer pulled up over a board somebody can still see.
"""

from __future__ import annotations

import os

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gio, GLib, Gtk  # noqa: E402
from moarchy_ui.icons import icon  # noqa: E402

from .chooser import LevelDialog  # noqa: E402
from .minesweeper import LEVELS, Game, level_for  # noqa: E402
from .store import LOST, WON, Store, clock  # noqa: E402
from .widgets import FieldView, Reading  # noqa: E402

APP_ICON = "org.moarchy.Minesweeper"

# How often the clock is added to. Once a second, and only while the game is
# running: a timer on an idle board is a wakeup a second for nothing, which on a
# phone is a battery reading somebody will blame on the wrong app.
TICK_MS = 1000


class MinesweeperWindow(Adw.ApplicationWindow):
    __gtype_name__ = "MinesweeperWindow"

    def __init__(self, store: Store, **kwargs) -> None:
        super().__init__(**kwargs)
        self.store = store
        self.game: Game = store.game()
        self._recorded = store.recorded
        self._marking = False
        self._tick = 0

        self.set_title("Minesweeper")
        self.set_default_size(360, 720)

        self._nav = Adw.NavigationView()
        self._nav.add(self._game_page())
        self.set_content(self._nav)

        for name, handler in (
            ("new", lambda *_: self.ask_level()),
            ("again", lambda *_: self.same_board()),
            ("stats", lambda *_: self.show_record()),
        ):
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", handler)
            self.add_action(action)

        self.connect("close-request", self._on_close)
        for signal in ("notify::is-active", "notify::suspended"):
            self.connect(signal, lambda *_: self._sync_clock())
        self.refresh()
        self._open_requested()

    # --- the page --------------------------------------------------------

    def _game_page(self) -> Adw.NavigationPage:
        header = Adw.HeaderBar()
        self._title = Adw.WindowTitle(title="Minesweeper", subtitle="")
        header.set_title_widget(self._title)

        menu = Gtk.MenuButton(
            icon_name=icon("open-menu-symbolic", "view-more-symbolic")
        )
        menu.set_tooltip_text("Menu")
        menu.update_property([Gtk.AccessibleProperty.LABEL], ["Menu"])
        model = Gio.Menu()
        model.append("New game…", "win.new")
        model.append("This board again", "win.again")
        model.append("Record", "win.stats")
        model.append("About Minesweeper", "app.about")
        menu.set_menu_model(model)
        header.pack_end(menu)

        self._mines = Reading("Mines")
        self._clock = Reading("Time")
        readings = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        readings.set_homogeneous(True)
        readings.set_margin_start(24)
        readings.set_margin_end(24)
        readings.set_margin_top(4)
        readings.append(self._mines)
        readings.append(self._clock)

        self._field = FieldView()
        self._field.set_margin_start(8)
        self._field.set_margin_end(8)
        self._field.set_margin_top(6)
        self._field.connect("cell-tapped", self._on_tap)
        self._field.connect("cell-held", self._on_hold)

        self._status = Gtk.Label()
        self._status.add_css_class("status")
        self._status.set_margin_top(2)
        self._status.set_margin_bottom(2)
        self._status.set_ellipsize(3)

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        body.set_vexpand(True)
        body.set_valign(Gtk.Align.CENTER)
        body.append(readings)
        body.append(self._field)
        body.append(self._status)

        self._toasts = Adw.ToastOverlay()
        self._toasts.set_child(body)

        view = Adw.ToolbarView()
        view.add_top_bar(header)
        view.set_content(self._toasts)
        view.add_bottom_bar(self._actions())
        return Adw.NavigationPage.new(view, "Minesweeper")

    def _actions(self) -> Gtk.Widget:
        bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        bar.add_css_class("actionbar")
        bar.set_homogeneous(True)

        self._flag = Gtk.ToggleButton()
        self._flag.set_child(
            Adw.ButtonContent(
                icon_name=icon(
                    "flag-outline-thick-symbolic",
                    "starred-symbolic",
                    "view-pin-symbolic",
                    "dialog-information-symbolic",
                ),
                label="Flag",
            )
        )
        self._flag.add_css_class("pill")
        self._flag.set_tooltip_text("Tap to flag instead of opening")
        self._flag.connect("toggled", self._on_marking)
        bar.append(self._flag)

        self._new = Gtk.Button()
        self._new.set_child(
            Adw.ButtonContent(
                icon_name=icon("view-refresh-symbolic", "document-new-symbolic"),
                label="New game",
            )
        )
        self._new.add_css_class("pill")
        self._new.connect("clicked", lambda *_: self.ask_level())
        bar.append(self._new)
        return bar

    def set_palette(self, palette) -> None:
        """The theme changed. The widgets repaint themselves from the reloaded
        stylesheet; the field is drawn by hand and has to be told."""
        self._field.set_colours(palette)

    # --- drawing the state -----------------------------------------------

    def refresh(self) -> None:
        game = self.game
        self._field.show(game)
        left = game.remaining
        self._mines.refresh(str(left), low=left < 0)
        self._clock.refresh(
            clock(self.store.seconds), paused=self._running and not self._on_screen()
        )
        self._title.set_subtitle(level_for(self.store.level).label)
        self._status.set_text(self._status_text())
        if game.over:
            self._status.add_css_class("alert")
        else:
            self._status.remove_css_class("alert")
        if game.over:
            self._new.add_css_class("suggested-action")
        else:
            self._new.remove_css_class("suggested-action")
        self._flag.set_sensitive(not game.over)
        if self._marking:
            self._flag.add_css_class("marking")
        else:
            self._flag.remove_css_class("marking")
        self._sync_clock()

    def _status_text(self) -> str:
        game = self.game
        if game.won:
            return f"Cleared in {clock(self.store.seconds)}"
        if game.lost:
            wrong = len(game.wrong_flags())
            if wrong:
                return f"A mine — and {wrong} flag{'' if wrong == 1 else 's'} wrong"
            return "A mine."
        if not game.started:
            return "The first tap is never a mine"
        if self._marking:
            return "Tap to flag · hold to open"
        return "Tap to open · hold to flag"

    # --- the clock -------------------------------------------------------

    @property
    def _running(self) -> bool:
        return self.game.started and not self.game.over

    def _on_screen(self) -> bool:
        """Is this window visible to somebody?

        `suspended` and not `is-active`, and the difference is the whole reason
        this method exists. Active means *keyboard focus*, and on this phone the
        app drawer is a layer-shell surface that takes focus away from every
        toplevel at once -- `swaymsg -t get_seats` reports `focus: 0` while a
        perfectly visible app is on screen. Pausing on that means pausing
        whenever the drawer is pulled up over the game, and reporting "Paused"
        on a window somebody is looking at.

        Suspended means *not visible*: minimised, occluded, on another
        workspace. That is the question a game actually wants answered, and it
        still covers the case that matters for a battery -- an app buried under
        another app is suspended.

        Falls back to `is-active` where the property does not exist. It arrived
        in GTK 4.12 and this phone runs 4.22, but the fallback costs one line
        and the alternative is an app that will not start on an older stack.
        """
        try:
            return not self.props.suspended
        except (AttributeError, TypeError):  # pragma: no cover - old GTK
            return self.is_active()

    def _sync_clock(self) -> None:
        """Start or stop the second hand, whichever the window now wants."""
        wanted = self._running and self._on_screen()
        if wanted and not self._tick:
            self._tick = GLib.timeout_add(TICK_MS, self._second)
        elif not wanted and self._tick:
            GLib.source_remove(self._tick)
            self._tick = 0
            # A game being put down is a game whose clock has to be on disk: the
            # next thing that happens to a phone app is usually being killed.
            self._save()
        if self._tick == 0 or not wanted:
            self._clock.refresh(
                clock(self.store.seconds), paused=self._running and not wanted
            )

    def _second(self) -> bool:
        if not self._running or not self._on_screen():
            self._tick = 0
            return GLib.SOURCE_REMOVE
        self.store.seconds += 1
        self._clock.refresh(clock(self.store.seconds))
        # Once a minute rather than once a second. An fsync per second for an
        # hour is three and a half thousand writes to a phone's flash, and the
        # most a crash can cost is the minute it happened in.
        if self.store.seconds % 60 == 0:
            self._save()
        return GLib.SOURCE_CONTINUE

    # --- playing ---------------------------------------------------------

    def _on_marking(self, button: Gtk.ToggleButton) -> None:
        self._marking = button.get_active()
        self.refresh()

    def _on_tap(self, _field: FieldView, cell: int) -> None:
        if self.game.over:
            self._toast("That board is finished. Tap New game.")
            return
        if self._marking:
            self._do(self.game.mark(cell))
        elif cell in self.game.opened:
            self._do(self.game.clear_around(cell))
        else:
            self._do(self.game.tap(cell))

    def _on_hold(self, _field: FieldView, cell: int) -> None:
        """A hold does the other thing, whichever mode the button is in.

        Which means the hold is never wasted: in flag mode it opens, and in the
        ordinary mode it flags. There is no press in this game that does
        nothing, and no way to be in a mode that cannot reach an action.
        """
        if self.game.over:
            return
        if cell in self.game.opened:
            self._do(self.game.clear_around(cell))
        elif self._marking:
            self._do(self.game.tap(cell))
        else:
            self._do(self.game.mark(cell))

    def _do(self, changed: bool) -> None:
        if not changed:
            # A press that changed nothing -- an already-open cell, a number
            # whose flags do not add up -- is silent. An app that scolds you for
            # a miss on a touch screen scolds you all day long.
            return
        self.store.remember(self.game, finished=self.game.over)
        self._save()
        self.refresh()
        if self.game.over:
            self._finish()

    # --- finishing -------------------------------------------------------

    def _finish(self) -> None:
        """Record the result once, and say what it was."""
        if self._recorded or not self.game.over:
            return
        self._recorded = True
        self.store.record(WON if self.game.won else LOST, self.store.seconds)
        self.store.remember(self.game, finished=True)
        self._save()
        self.refresh()
        if self.game.won:
            best = self.store.record_for(self.store.level)["best"]
            first = self.store.record_for(self.store.level)[WON] == 1
            if best == self.store.seconds and not first:
                self._toast(f"Cleared in {clock(self.store.seconds)} — a best")
            else:
                self._toast(f"Cleared in {clock(self.store.seconds)}")

    def _abandon(self) -> None:
        """A board walked away from counts as a loss, once it has been started.

        Tapping nothing and choosing another level is not a game anybody played;
        opening half a board and leaving because it was going badly is.
        """
        if self.game.started and not self.game.over and not self._recorded:
            self.store.record(LOST, self.store.seconds)

    # --- the rest --------------------------------------------------------

    def ask_level(self) -> None:
        dialog = LevelDialog(
            current=self.store.level,
            store=self.store,
            in_progress=self.game.started and not self.game.over,
        )
        dialog.connect("chosen", self._on_chosen)
        dialog.present(self)

    def _on_chosen(self, _dialog, key: str) -> None:
        self._abandon()
        self._start(self.store.begin(key))

    def same_board(self) -> None:
        """The same mines again. What everybody wants after losing one."""
        self._abandon()
        self._start(self.store.begin(self.store.level, seed=self.store.seed))
        self._toast("The same mines again")

    def _start(self, game: Game) -> None:
        self.game = game
        self._recorded = False
        self._marking = False
        self._flag.set_active(False)
        self._save()
        self.refresh()

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
        if os.environ.get("MOARCHY_MINESWEEPER_PAGE") == "record":
            self.show_record()
        if os.environ.get("MOARCHY_MINESWEEPER_NEW"):
            GLib.idle_add(self.ask_level)
        if os.environ.get("MOARCHY_MINESWEEPER_MARKING"):
            self._flag.set_active(True)

    def _on_close(self, *_args) -> bool:
        self.store.remember(self.game, finished=self.game.over)
        self._save()
        return False


class RecordPage(Adw.NavigationPage):
    """Games played, by board, with the fastest clear on each.

    A best time and not a win percentage at the top, because a win percentage in
    this game is mostly a report on how often somebody guessed -- every board
    has positions where nothing can be deduced, and the only honest thing to say
    about losing one of those is that it happened.
    """

    __gtype_name__ = "MinesweeperRecord"

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
                ("Cleared", totals[WON]),
                ("In a row", totals["longest"]),
            )
        )

        heading = Gtk.Label(label="FASTEST CLEAR", xalign=0.0)
        heading.add_css_class("section-heading")
        body.append(heading)

        rows = Gtk.ListBox()
        rows.set_selection_mode(Gtk.SelectionMode.NONE)
        rows.add_css_class("boxed-list")
        for level in LEVELS:
            entry = store.record_for(level.key)
            row = Adw.ActionRow(title=level.label)
            if entry["played"]:
                row.set_subtitle(
                    f"{entry[WON]} of {entry['played']} cleared"
                    f" · best run {entry['longest']}"
                )
            else:
                row.set_subtitle(f"{level.width} × {level.height}, {level.mines} mines")
            value = Gtk.Label(label=clock(entry["best"]) if entry["best"] else "—")
            value.add_css_class("dim-label")
            row.add_suffix(value)
            rows.append(row)
        body.append(rows)

        note = Gtk.Label(
            label=(
                "The clock only runs while the app is on screen. A board left "
                "open in a pocket is not a slow game."
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
