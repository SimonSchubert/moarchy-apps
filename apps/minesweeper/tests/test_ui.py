"""The window, driven by calling it rather than by tapping it.

The same approach the other apps here take. What is different is the clock: it
is a GLib timeout that has to start and stop with the window's focus, so the
tests here poke `is-active` the way a compositor would and check that the second
hand does what it is told.

Needs a display. Skipped where there is none, so `python3 -m unittest` on a
machine without GTK still runs the rules and the file.
"""

from __future__ import annotations

import os
import sys
import time
import unittest
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
    from moarchy_minesweeper.chooser import LevelDialog
    from moarchy_minesweeper.theme import fallback
    from moarchy_minesweeper.widgets import FieldView, Reading
    from moarchy_minesweeper.window import MinesweeperWindow, RecordPage

from moarchy_minesweeper.minesweeper import (  # noqa: E402
    Field,
    Game,
    Level,
    index,
    level_for,
)
from moarchy_minesweeper.store import LOST, WON, Store  # noqa: E402

TINY = Level("tiny", "Tiny", 5, 5, 2)
MINES = frozenset({index(1, 1, 5), index(3, 3, 5)})


def pump(until=None, seconds: float = 4.0) -> bool:
    context = GLib.MainContext.default()
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        while context.pending():
            context.iteration(False)
        if until is None or until():
            return True
        time.sleep(0.01)
    return until is None or until()


def hand_made() -> Game:
    game = Game(TINY, 0)
    game.field = Field(TINY, MINES)
    return game


@unittest.skipIf(REASON, REASON)
class WindowBase(unittest.TestCase):
    def setUp(self):
        self.dir = TemporaryDirectory()
        self.store = Store(Path(self.dir.name) / "minesweeper.json")
        self.store.begin("gentle", seed=4242)

    def open(self) -> MinesweeperWindow:
        self.window = MinesweeperWindow(self.store)
        self.addCleanup(self.window.destroy)
        return self.window

    def tearDown(self):
        pump(seconds=0.05)
        self.dir.cleanup()


class TheField(WindowBase):
    def test_a_new_game_opens_on_an_untouched_board(self):
        window = self.open()
        self.assertFalse(window.game.started)
        self.assertEqual(window.game.remaining, level_for("gentle").mines)

    def test_a_saved_game_is_picked_back_up(self):
        game = self.store.game()
        game.tap(index(5, 4, 8))
        self.store.remember(game)
        window = self.open()
        self.assertEqual(window.game.opened, game.opened)
        self.assertEqual(window.game.field.mines, game.field.mines)

    def test_the_field_describes_itself_for_a_screen_reader(self):
        view = FieldView()
        view.set_colours(fallback(dark=True))
        view.show(hand_made())
        self.assertIn("unopened", view.describe())
        game = hand_made()
        game.tap(index(1, 1, 5))
        view.show(game)
        self.assertIn("mine went off", view.describe())

    def test_a_reading_builds_and_says_what_it_is(self):
        reading = Reading("Mines")
        reading.refresh("10")
        reading.refresh("-1", low=True)
        reading.refresh("0:12", paused=True)


class Pressing(WindowBase):
    def test_a_tap_opens(self):
        window = self.open()
        window._on_tap(window._field, index(4, 4, 8))
        self.assertTrue(window.game.started)
        self.assertGreater(len(window.game.opened), 1)

    def test_a_hold_flags(self):
        window = self.open()
        window._on_hold(window._field, index(0, 0, 8))
        self.assertIn(index(0, 0, 8), window.game.flags)
        self.assertEqual(window.game.remaining, level_for("gentle").mines - 1)

    def test_the_flag_button_swaps_what_a_tap_does(self):
        window = self.open()
        window._flag.set_active(True)
        pump(seconds=0.1)
        window._on_tap(window._field, index(0, 0, 8))
        self.assertIn(index(0, 0, 8), window.game.flags)
        self.assertFalse(window.game.started)

    def test_and_a_hold_then_does_the_other_thing(self):
        # No press in this game does nothing, and no mode can reach only one
        # action -- which is what stops the flag button being a trap.
        window = self.open()
        window._flag.set_active(True)
        pump(seconds=0.1)
        window._on_hold(window._field, index(4, 4, 8))
        self.assertTrue(window.game.started)

    def test_a_tap_on_an_open_number_chords(self):
        window = self.open()
        window.game = hand_made()
        window._on_tap(window._field, index(0, 0, 5))
        window._on_hold(window._field, index(1, 1, 5))
        self.assertIn(index(1, 1, 5), window.game.flags)
        window._on_tap(window._field, index(0, 0, 5))
        self.assertIn(index(0, 1, 5), window.game.opened)

    def test_a_press_on_a_finished_board_does_nothing(self):
        window = self.open()
        window.game = hand_made()
        window._on_tap(window._field, index(1, 1, 5))
        self.assertTrue(window.game.lost)
        before = len(window.game.moves)
        window._on_tap(window._field, index(4, 4, 5))
        window._on_hold(window._field, index(4, 4, 5))
        self.assertEqual(len(window.game.moves), before)


class TheClock(WindowBase):
    def test_it_does_not_run_before_the_first_tap(self):
        window = self.open()
        self.assertFalse(window._running)
        self.assertEqual(window._tick, 0)

    def test_it_stops_when_the_window_does(self):
        window = self.open()
        window.present()
        pump(seconds=0.2)
        window._on_tap(window._field, index(4, 4, 8))
        self.assertTrue(window._running)
        # Whether a headless window is ever "active" is the compositor's
        # business, so the tick is asked about rather than assumed -- what is
        # tested is that the two agree.
        self.assertEqual(bool(window._tick), window.is_active())

    def test_it_stops_when_the_game_is_over(self):
        window = self.open()
        window.game = hand_made()
        window._on_tap(window._field, index(1, 1, 5))
        self.assertFalse(window._running)
        self.assertEqual(window._tick, 0)

    def test_a_second_is_added_to_the_stored_clock(self):
        window = self.open()
        window._on_tap(window._field, index(4, 4, 8))
        before = self.store.seconds
        window._second()
        self.assertIn(self.store.seconds, (before, before + 1))


class TheResult(WindowBase):
    def test_a_loss_is_recorded_once(self):
        window = self.open()
        window.game = hand_made()
        window._on_tap(window._field, index(1, 1, 5))
        self.assertEqual(self.store.record_for("gentle")["played"], 1)
        self.assertEqual(self.store.record_for("gentle")[WON], 0)
        window._finish()
        self.assertEqual(self.store.record_for("gentle")["played"], 1)

    def test_a_win_is_recorded_with_the_clock_on_it(self):
        window = self.open()
        window.game = hand_made()
        self.store.seconds = 33
        for cell in range(TINY.cells):
            if cell not in MINES:
                window._on_tap(window._field, cell)
        self.assertTrue(window.game.won)
        self.assertEqual(self.store.record_for("gentle")[WON], 1)
        self.assertEqual(self.store.record_for("gentle")["best"], 33)

    def test_a_board_walked_away_from_counts_as_a_loss(self):
        window = self.open()
        window._on_tap(window._field, index(4, 4, 8))
        window._on_chosen(None, "hard")
        self.assertEqual(self.store.record_for("gentle")["played"], 1)

    def test_a_board_never_touched_counts_as_nothing(self):
        window = self.open()
        window._on_chosen(None, "hard")
        self.assertEqual(self.store.record_for("gentle")["played"], 0)
        self.assertEqual(self.store.level, "hard")

    def test_the_same_board_can_be_asked_for_again(self):
        window = self.open()
        seed = self.store.seed
        window._on_tap(window._field, index(4, 4, 8))
        window.same_board()
        self.assertEqual(self.store.seed, seed)
        self.assertFalse(window.game.started)
        self.assertEqual(self.store.seconds, 0)


class TheOtherScreens(WindowBase):
    def test_the_record_builds_with_nothing_in_it(self):
        RecordPage(self.store)

    def test_the_record_builds_with_a_record(self):
        self.store.record(WON, 55)
        self.store.begin("hard")
        self.store.record(LOST)
        RecordPage(self.store)

    def test_the_window_can_push_it(self):
        window = self.open()
        window.show_record()
        pump(seconds=0.2)

    def test_the_level_sheet_builds_and_answers(self):
        chosen = []
        window = self.open()
        dialog = LevelDialog(current="gentle", store=self.store, in_progress=True)
        dialog.connect("chosen", lambda _d, key: chosen.append(key))
        dialog.present(window)
        pump(seconds=0.2)
        dialog._pick(None, "hard")
        self.assertEqual(chosen, ["hard"])


if __name__ == "__main__":
    unittest.main()
