"""The window, driven by calling it rather than by tapping it.

Most of this is about typing: a letter goes in, backspace takes one out, and
enter either submits a row or says why it will not. The part worth a comment is
what happens to a refused word -- it stays in the row rather than being cleared,
because somebody who has mistyped one letter of a five-letter word should not
have to type the other four again.

Animations are turned off for the whole module. That is not only for speed: it
is the reduced-motion path, and it is the one where a row has to reveal and
settle in a single turn of the main loop rather than over a tick callback -- and
where a refusal cannot shake, so the words have to carry it.

Needs a display. Skipped where there is none.
"""

from __future__ import annotations

import os
import sys
import time
import unittest
from datetime import date
from pathlib import Path
from tempfile import TemporaryDirectory

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

REASON = ""
try:
    import gi

    gi.require_version("Gtk", "4.0")
    gi.require_version("Adw", "1")
    from gi.repository import Adw, GLib, Gtk

    if not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        REASON = "no display"
    elif not Gtk.init_check():
        REASON = "GTK could not open the display"
except (ImportError, ValueError) as exc:  # pragma: no cover - depends on host
    REASON = f"no GTK: {exc}"

if not REASON:
    Adw.init()
    settings = Gtk.Settings.get_default()
    if settings is not None:
        settings.props.gtk_enable_animations = False
    from moarchy_fiveletters.theme import _apart, _on, board_colours, fallback
    from moarchy_fiveletters.widgets import BoardView, Keyboard
    from moarchy_fiveletters.window import SHORT, UNKNOWN, FiveLettersWindow, RecordPage

from moarchy_fiveletters.fiveletters import CORRECT, Game  # noqa: E402
from moarchy_fiveletters.store import DAILY, PRACTICE, Store  # noqa: E402
from moarchy_fiveletters.words import GUESSES, Words  # noqa: E402

WORDS = Words()
DAY = date(2026, 9, 12)


def pump(until=None, seconds: float = 5.0) -> bool:
    context = GLib.MainContext.default()
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        while context.pending():
            context.iteration(False)
        if until is None or until():
            return True
        time.sleep(0.01)
    return until is None or until()


@unittest.skipIf(REASON, REASON)
class WindowBase(unittest.TestCase):
    def setUp(self):
        os.environ["MOARCHY_FIVELETTERS_TODAY"] = DAY.isoformat()
        self.addCleanup(os.environ.pop, "MOARCHY_FIVELETTERS_TODAY", None)
        self.dir = TemporaryDirectory()
        self.store = Store(Path(self.dir.name) / "fiveletters.json")

    def open(self) -> FiveLettersWindow:
        self.window = FiveLettersWindow(self.store, WORDS)
        self.addCleanup(self.window.destroy)
        return self.window

    def settle(self, window) -> None:
        pump(lambda: not window._board.busy, seconds=3)

    def type(self, window, word: str) -> None:
        for letter in word:
            window.type_letter(letter)

    def tearDown(self):
        pump(seconds=0.05)
        self.dir.cleanup()


class TheBoard(WindowBase):
    def test_it_opens_on_todays_word(self):
        window = self.open()
        self.assertEqual(window.game.secret, WORDS.daily(DAY))
        self.assertEqual(window.game.used, 0)
        self.assertEqual(self.store.mode, DAILY)

    def test_a_saved_day_is_picked_back_up(self):
        self.store.day = DAY.isoformat()
        self.store.daily = ["CRANE"]
        window = self.open()
        self.assertEqual(window.game.words, ["CRANE"])

    def test_it_describes_itself_for_a_screen_reader(self):
        view = BoardView()
        view.set_colours(fallback(dark=True))
        view.show(Game("CRANE", None, ["SLOTH"]))
        self.assertIn("SLOTH", view.describe())
        view.show(Game("CRANE", None, ["CRANE"]))
        self.assertIn("solved", view.describe())


class Typing(WindowBase):
    def test_letters_go_in_and_backspace_takes_them_out(self):
        window = self.open()
        self.type(window, "CRA")
        self.assertEqual(window._typed, "CRA")
        window.back()
        self.assertEqual(window._typed, "CR")

    def test_a_row_never_takes_more_than_five(self):
        window = self.open()
        self.type(window, "CRANES")
        self.assertEqual(window._typed, "CRANE")

    def test_anything_that_is_not_a_letter_is_ignored(self):
        window = self.open()
        for junk in ("1", "!", " ", "É"):
            window.type_letter(junk)
        self.assertEqual(window._typed, "")

    def test_enter_on_a_short_row_says_so_and_keeps_it(self):
        window = self.open()
        self.type(window, "CRA")
        window.enter()
        self.settle(window)
        self.assertEqual(window._said, SHORT)
        self.assertEqual(window._typed, "CRA")
        self.assertEqual(window.game.used, 0)

    def test_enter_on_a_word_it_does_not_know_says_so_and_keeps_it(self):
        window = self.open()
        self.type(window, "ZZZZZ")
        window.enter()
        self.settle(window)
        self.assertEqual(window._said, UNKNOWN)
        # Kept, not cleared. Somebody who mistyped one letter should not have to
        # type the other four again.
        self.assertEqual(window._typed, "ZZZZZ")
        self.assertEqual(window.game.used, 0)

    def test_enter_on_a_real_word_submits_it(self):
        window = self.open()
        self.type(window, "CRANE")
        window.enter()
        self.settle(window)
        self.assertEqual(window.game.words, ["CRANE"])
        self.assertEqual(window._typed, "")

    def test_nothing_is_typed_into_a_finished_game(self):
        window = self.open()
        self.type(window, window.game.secret)
        window.enter()
        self.settle(window)
        self.assertTrue(window.game.solved)
        self.type(window, "CRANE")
        self.assertEqual(window._typed, "")


class TheKeyboard(WindowBase):
    def test_it_builds_every_letter_once(self):
        keyboard = Keyboard()
        self.assertEqual(len(keyboard._keys), 26)

    def test_it_colours_a_letter_by_the_best_thing_known(self):
        keyboard = Keyboard()
        keyboard.refresh({"A": CORRECT})
        self.assertTrue(keyboard._keys["A"].has_css_class("correct"))
        self.assertFalse(keyboard._keys["B"].has_css_class("correct"))
        keyboard.refresh({})
        self.assertFalse(keyboard._keys["A"].has_css_class("correct"))

    def test_a_tap_on_a_key_types_it(self):
        window = self.open()
        window._on_letter(window._keyboard, "C")
        self.assertEqual(window._typed, "C")


class TheDay(WindowBase):
    def test_the_number_is_the_same_for_everybody_on_that_word(self):
        window = self.open()
        self.assertEqual(window.number, WORDS.index(DAY) + 1)

    def test_a_practice_word_is_not_the_days_word(self):
        window = self.open()
        window.new_practice()
        self.assertEqual(self.store.mode, PRACTICE)
        # Not guaranteed to differ -- one answer in fifteen hundred -- so what
        # is asserted is that it is an answer and that the day is untouched.
        self.assertIn(window.game.secret, WORDS.answers)
        self.assertEqual(self.store.daily, [])

    def test_going_back_to_the_day_brings_the_day_back(self):
        window = self.open()
        self.type(window, "CRANE")
        window.enter()
        self.settle(window)
        window.new_practice()
        window.show_daily()
        self.assertEqual(self.store.mode, DAILY)
        self.assertEqual(window.game.words, ["CRANE"])


class TheResult(WindowBase):
    def _finish(self, window, solved: bool) -> None:
        secret = window.game.secret
        wrong = "CRANE" if secret != "CRANE" else "SLOTH"
        if solved:
            self.type(window, secret)
            window.enter()
            self.settle(window)
            return
        for _ in range(GUESSES):
            self.type(window, wrong)
            window.enter()
            self.settle(window)

    def test_a_solved_day_is_counted_once(self):
        window = self.open()
        self._finish(window, solved=True)
        self.assertEqual(self.store.stats["played"], 1)
        self.assertEqual(self.store.stats["won"], 1)
        self.assertEqual(self.store.stats["spread"][0], 1)
        window._on_settled()
        self.assertEqual(self.store.stats["played"], 1)

    def test_a_lost_day_is_counted_and_the_word_is_shown(self):
        window = self.open()
        self._finish(window, solved=False)
        self.assertTrue(window.game.out)
        self.assertEqual(self.store.stats["played"], 1)
        self.assertEqual(self.store.stats["won"], 0)
        self.assertIn(window.game.secret, window._status_text())

    def test_practice_is_never_counted(self):
        window = self.open()
        window.new_practice()
        self.type(window, window.game.secret)
        window.enter()
        self.settle(window)
        self.assertEqual(self.store.stats["played"], 0)

    def test_the_share_needs_a_finished_game(self):
        window = self.open()
        window.copy_result()
        self.assertEqual(self.store.stats["played"], 0)
        self._finish(window, solved=True)
        window.copy_result()


class TheColours(WindowBase):
    def test_the_letter_on_a_tile_is_readable_against_it(self):
        # White on a theme's yellow is the failure this exists to prevent.
        for dark in (True, False):
            palette = fallback(dark=dark)
            board = board_colours(palette)
            for tile, ink in (
                (board.correct, board.on_correct),
                (board.present, board.on_present),
                (board.absent, board.on_absent),
            ):
                self.assertTrue(_apart(tile, ink), f"{tile} on {ink}")

    def test_green_and_yellow_are_never_the_same_colour(self):
        for dark in (True, False):
            board = board_colours(fallback(dark=dark))
            self.assertTrue(_apart(board.correct, board.present))

    def test_the_ink_is_whichever_extreme_is_further_away(self):
        palette = fallback(dark=False)
        self.assertEqual(_on("#000000", palette), palette.background)
        self.assertEqual(_on("#ffffff", palette), palette.foreground)


class TheOtherScreens(WindowBase):
    def test_the_record_builds_with_nothing_in_it(self):
        RecordPage(self.store)

    def test_the_record_builds_with_a_record(self):
        self.store.stats.update(
            {
                "played": 30,
                "won": 28,
                "streak": 4,
                "best": 9,
                "spread": [0, 3, 9, 10, 5, 1],
            }
        )
        RecordPage(self.store)

    def test_the_window_can_push_it(self):
        window = self.open()
        window.show_record()
        pump(seconds=0.2)


if __name__ == "__main__":
    unittest.main()
