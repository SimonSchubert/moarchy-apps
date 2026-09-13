"""The window: a board, a line of text, and a keyboard of our own.

The keyboard is the decision this app is built around. A phone has one already,
and using it would mean the on-screen keyboard sliding up over the bottom two
rows of a board that is the entire game -- plus autocorrect, plus a space bar, a
number row and a comma, none of which this game has any use for. So the app
draws twenty-eight keys, and gets three things for free: the board is never
covered, the keys can be **coloured by what is known about each letter**, and
there is nothing to type that is not a move.

It still takes a physical keyboard, because this runs on a desktop too and
somebody with one will try. Letters, Return and Backspace, and nothing else.

The other thing here is the day. This is a game with one puzzle a day, and a
phone left open overnight comes back to yesterday's board -- which with today's
word on it would be a board claiming three letters are green and meaning nothing
by it. So the date is checked every time the game is loaded and the board is
cleared when it has moved on.
"""

from __future__ import annotations

import os

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gdk, Gio, Gtk  # noqa: E402
from moarchy_ui.icons import icon  # noqa: E402

from .fiveletters import Game  # noqa: E402
from .store import DAILY, PRACTICE, Store, share  # noqa: E402
from .widgets import BoardView, Keyboard  # noqa: E402
from .words import ALPHABET, GUESSES, LENGTH, Words, today  # noqa: E402

APP_ICON = "org.moarchy.FiveLetters"

# What the app says when a guess is turned away. Both are said in words as well
# as shaken, because "reduced motion" is a setting and a person who has turned
# it on still has to be told why nothing happened.
SHORT = "Not enough letters"
UNKNOWN = "Not a word this app knows"

# Six ways to say well done, one per number of guesses. The newspaper does this
# and it is right to: "solved in two" is a fact, and this is the only line in
# the app that is allowed to be pleased about it.
PRAISE = (
    "Extraordinary",
    "Wonderful",
    "Very good",
    "Good",
    "Close one",
    "Got there",
)


class FiveLettersWindow(Adw.ApplicationWindow):
    __gtype_name__ = "FiveLettersWindow"

    def __init__(self, store: Store, words: Words, **kwargs) -> None:
        super().__init__(**kwargs)
        self.store = store
        self.words = words
        self.day = today()
        self.game: Game = store.game(words, self.day)
        self._typed = ""
        self._said = ""

        self.set_title("Five Letters")
        self.set_default_size(360, 720)

        self._nav = Adw.NavigationView()
        self._nav.add(self._game_page())
        self.set_content(self._nav)

        for name, handler in (
            ("daily", lambda *_: self.show_daily()),
            ("practice", lambda *_: self.new_practice()),
            ("share", lambda *_: self.copy_result()),
            ("stats", lambda *_: self.show_record()),
        ):
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", handler)
            self.add_action(action)

        keys = Gtk.EventControllerKey()
        keys.connect("key-pressed", self._on_key)
        self.add_controller(keys)

        self.connect("close-request", self._on_close)
        self.refresh()
        self._open_requested()

    # --- the page --------------------------------------------------------

    def _game_page(self) -> Adw.NavigationPage:
        header = Adw.HeaderBar()
        self._title = Adw.WindowTitle(title="Five Letters", subtitle="")
        header.set_title_widget(self._title)

        menu = Gtk.MenuButton(
            icon_name=icon("open-menu-symbolic", "view-more-symbolic")
        )
        menu.set_tooltip_text("Menu")
        menu.update_property([Gtk.AccessibleProperty.LABEL], ["Menu"])
        model = Gio.Menu()
        model.append("Today's word", "win.daily")
        model.append("A practice word", "win.practice")
        model.append("Copy result", "win.share")
        model.append("Record", "win.stats")
        model.append("About Five Letters", "app.about")
        menu.set_menu_model(model)
        header.pack_end(menu)

        self._banner = Adw.Banner()
        self._banner.set_revealed(not self.words.complete)
        self._banner.set_title("The word list is missing")

        self._board = BoardView()
        self._board.set_margin_start(16)
        self._board.set_margin_end(16)
        self._board.set_margin_top(10)
        self._board.connect("settled", self._on_settled)

        self._status = Gtk.Label()
        self._status.add_css_class("status")
        self._status.set_margin_top(8)
        self._status.set_margin_bottom(4)
        self._status.set_ellipsize(3)

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        body.set_vexpand(True)
        body.set_valign(Gtk.Align.CENTER)
        body.append(self._board)
        body.append(self._status)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        outer.append(self._banner)
        outer.append(body)

        self._toasts = Adw.ToastOverlay()
        self._toasts.set_child(outer)

        self._keyboard = Keyboard()
        self._keyboard.set_margin_top(4)
        self._keyboard.set_margin_bottom(10)
        self._keyboard.connect("letter", self._on_letter)
        self._keyboard.connect("enter", lambda *_: self.enter())
        self._keyboard.connect("back", lambda *_: self.back())

        view = Adw.ToolbarView()
        view.add_top_bar(header)
        view.set_content(self._toasts)
        view.add_bottom_bar(self._keyboard)
        return Adw.NavigationPage.new(view, "Five Letters")

    def set_palette(self, palette) -> None:
        """The theme changed. The keyboard repaints itself from the reloaded
        stylesheet; the board is drawn by hand and has to be told."""
        self._board.set_colours(palette)

    # --- drawing the state -----------------------------------------------

    def refresh(self) -> None:
        self._board.show(self.game, self._typed)
        self._keyboard.refresh(self.game.keys())
        self._status.set_text(self._status_text())
        if self.game.over:
            self._status.add_css_class("alert")
        else:
            self._status.remove_css_class("alert")
        if self.store.mode == PRACTICE:
            self._title.set_subtitle("Practice")
        else:
            self._title.set_subtitle(f"Today · no. {self.number}")

    @property
    def number(self) -> int:
        """Which day's word this is. A number people compare, so it is the
        index into the answer list rather than the day of the year -- two people
        on the same word see the same number."""
        return self.words.index(self.day) + 1

    def _status_text(self) -> str:
        if self._said:
            return self._said
        if self.game.solved:
            return f"{PRAISE[min(self.game.used, GUESSES) - 1]} — in {self.game.used}"
        if self.game.out:
            return f"It was {self.game.secret}"
        if not self.words.complete:
            return "Running on a handful of built-in words"
        left = self.game.left
        return f"{left} guess{'' if left == 1 else 'es'} left"

    # --- typing ----------------------------------------------------------

    def _on_letter(self, _keyboard, letter: str) -> None:
        self.type_letter(letter)

    def type_letter(self, letter: str) -> None:
        if self.game.over or self._board.busy:
            return
        letter = letter.upper()
        if letter not in ALPHABET or len(self._typed) >= LENGTH:
            return
        self._typed += letter
        self._said = ""
        self.refresh()

    def back(self) -> None:
        if self.game.over or self._board.busy or not self._typed:
            return
        self._typed = self._typed[:-1]
        self._said = ""
        self.refresh()

    def enter(self) -> None:
        """Submit the row, or say why it is not going anywhere."""
        if self.game.over or self._board.busy:
            return
        row = self.game.used
        if len(self._typed) < LENGTH:
            self._refuse(row, SHORT)
            return
        if not self.game.accepts(self._typed):
            self._refuse(row, UNKNOWN)
            return
        self.game.submit(self._typed)
        self._typed = ""
        self._said = ""
        self.store.remember(self.game)
        self._save()
        self.refresh()
        self._board.reveal(row)

    def _refuse(self, row: int, reason: str) -> None:
        # The word is kept in the row rather than cleared. Somebody who has
        # mistyped one letter of a five-letter word should not have to type the
        # other four again, which is what every version of this game that
        # clears the row makes them do.
        self._said = reason
        self.refresh()
        self._board.refuse(row)

    def _on_key(self, _controller, keyval: int, _code: int, state) -> bool:
        if state & Gdk.ModifierType.CONTROL_MASK:
            return False
        if keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            self.enter()
            return True
        if keyval == Gdk.KEY_BackSpace:
            self.back()
            return True
        name = Gdk.keyval_name(keyval) or ""
        if len(name) == 1 and name.upper() in ALPHABET:
            self.type_letter(name)
            return True
        return False

    def _on_settled(self, *_args) -> None:
        self.refresh()
        if self.game.over:
            self._finish()

    # --- finishing -------------------------------------------------------

    def _finish(self) -> None:
        """Count the day once, and say what it was."""
        if self.store.mode != DAILY or self.store.counted(self.day):
            return
        self.store.record(self.game, self.day)
        self._save()
        self.refresh()
        if self.game.solved:
            streak = self.store.stats["streak"]
            self._toast(
                f"{PRAISE[self.game.used - 1]} — {streak} day"
                f"{'' if streak == 1 else 's'} in a row"
            )
        else:
            self._toast(f"The word was {self.game.secret}")

    # --- the rest --------------------------------------------------------

    def show_daily(self) -> None:
        self.day = today()
        self.game = self.store.show_daily(self.words, self.day)
        self._typed = ""
        self._said = ""
        self._save()
        self.refresh()

    def new_practice(self) -> None:
        """A word to play when today's is done. Never counted -- see store.py."""
        self.game = self.store.begin_practice(self.words)
        self._typed = ""
        self._said = ""
        self._save()
        self.refresh()

    def copy_result(self) -> None:
        """The board as coloured squares, on the clipboard.

        The one thing this game is famous for outside itself, and the only place
        in this repository where an app puts something on a clipboard. It is
        spoiler-free by construction: squares say how a word went and nothing
        about what it was.
        """
        if not self.game.over:
            self._toast("Finish it first")
            return
        text = share(self.game, self.day, self.number)
        display = Gdk.Display.get_default()
        if display is None:
            return
        display.get_clipboard().set(text)
        self._toast("Copied")

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
        if os.environ.get("MOARCHY_FIVELETTERS_PAGE") == "record":
            self.show_record()
        typed = os.environ.get("MOARCHY_FIVELETTERS_TYPED")
        if typed:
            for letter in typed.upper()[:LENGTH]:
                self.type_letter(letter)

    def _on_close(self, *_args) -> bool:
        self.store.remember(self.game)
        self._save()
        return False


class RecordPage(Adw.NavigationPage):
    """Days played, days solved, and how many guesses each of them took.

    The bar chart is the point of this page. Played and won are the same two
    numbers every game in this repository reports; the spread is the only
    statistic here that says anything about *how* somebody plays, which is the
    thing a person who has done a hundred of these actually wants to look at.
    """

    __gtype_name__ = "FiveLettersRecord"

    def __init__(self, store: Store) -> None:
        super().__init__()
        self.set_title("Record")

        header = Adw.HeaderBar()

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        body.set_margin_top(16)
        body.set_margin_bottom(24)
        body.set_margin_start(14)
        body.set_margin_end(14)

        stats = store.stats
        body.append(
            _tally(
                ("Played", stats["played"]),
                ("Solved", f"{store.rate()}%"),
                ("Streak", stats["streak"]),
                ("Best", stats["best"]),
            )
        )

        heading = Gtk.Label(label="GUESSES", xalign=0.0)
        heading.add_css_class("section-heading")
        body.append(heading)
        body.append(_spread(stats["spread"]))

        note = Gtk.Label(
            label=(
                "A streak is days in a row. The day you skip ends it as surely "
                "as the day you miss. Practice words are not counted."
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


def _spread(counts: list[int]) -> Gtk.Widget:
    """One bar per number of guesses, each as wide as its share of the days."""
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    most = max(counts) if counts else 0
    for index, count in enumerate(counts):
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        number = Gtk.Label(label=str(index + 1), xalign=0.0)
        number.add_css_class("bar-label")
        row.append(number)

        bar = Gtk.Label(label=str(count), xalign=1.0)
        bar.add_css_class("bar")
        if not count:
            bar.add_css_class("empty")
        # A bar with nothing in it still gets a sliver, so that the chart reads
        # as six rows rather than as however many have been used.
        share = (count / most) if most else 0.0
        bar.set_hexpand(False)
        holder = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        holder.set_hexpand(True)
        holder.append(bar)
        spacer = Gtk.Box()
        spacer.set_hexpand(True)
        holder.append(spacer)
        bar.set_size_request(int(24 + share * 220), -1)
        row.append(holder)
        box.append(row)
    return box


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
