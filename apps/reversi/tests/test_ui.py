"""The window, driven by calling it rather than by tapping it.

The same approach Keep's suite takes: build the real widgets on a real display
and call the methods the buttons call. What is different here is that one of the
paths under test runs on a thread -- the computer's move arrives through
GLib.idle_add from a search -- so these tests pump the main loop and wait for it,
which is the only way to cover the part of the app that actually plays.

Animations are turned off for the whole module. That is not only for speed: it
is the reduced-motion path, and it is the one where a move has to land and
settle in a single turn of the main loop rather than over a tick callback.

Needs a display. Skipped where there is none, so `python3 -m unittest` on a
machine without GTK still runs the rules, the search and the file.
"""

from __future__ import annotations

import os
import random
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
    from moarchy_reversi.theme import fallback
    from moarchy_reversi.widgets import BoardView
    from moarchy_reversi.window import RecordPage, ReversiWindow

from moarchy_reversi.reversi import (  # noqa: E402
    DARK,
    LIGHT,
    OPENING,
    SIZE,
    Game,
    index,
)
from moarchy_reversi.store import SOLO, WON, Store  # noqa: E402


def pump(until=None, seconds: float = 6.0) -> bool:
    """Run the main loop until something has happened, or give up."""
    context = GLib.MainContext.default()
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        while context.pending():
            context.iteration(False)
        if until is None or until():
            return True
        time.sleep(0.01)
    return until is None or until()


def finished_game(seed: int = 1) -> list[int]:
    rng = random.Random(seed)
    game = Game()
    while not game.over:
        game.play(rng.choice(game.position.legal()))
    return list(game.moves)


@unittest.skipIf(REASON, REASON)
class WindowBase(unittest.TestCase):
    def setUp(self):
        self.dir = TemporaryDirectory()
        self.store = Store(Path(self.dir.name) / "reversi.json")
        self.store.begin(mode=SOLO, level="easy", human=DARK)

    def open(self) -> ReversiWindow:
        self.window = ReversiWindow(self.store)
        self.addCleanup(self.window.destroy)
        return self.window

    def tearDown(self):
        pump(seconds=0.05)
        self.dir.cleanup()


class TheBoard(WindowBase):
    def test_a_new_game_opens_at_the_opening(self):
        window = self.open()
        self.assertEqual(window.game.position, OPENING)

    def test_a_saved_game_is_picked_back_up(self):
        game = Game()
        for _ in range(6):
            game.play(game.position.legal()[0])
        self.store.remember(game)
        window = self.open()
        self.assertEqual(window.game.position, game.position)

    def test_a_tap_on_a_legal_square_plays_it(self):
        window = self.open()
        cell = index(2, 3)
        window._on_cell(window._board, cell)
        self.assertEqual(window.game.moves[0], cell)

    def test_a_tap_on_a_square_with_no_move_in_it_does_nothing(self):
        window = self.open()
        window._on_cell(window._board, index(0, 0))
        self.assertEqual(window.game.moves, [])

    def test_a_move_is_written_out_at_once(self):
        """Not on a timer. The app is killed rather than closed on a phone, and
        a game that loses its last move to that is a game nobody finishes."""
        window = self.open()
        window._on_cell(window._board, index(2, 3))
        again = Store(self.store.path)
        again.load()
        self.assertEqual(again.moves, window.game.moves)

    def test_the_board_says_what_is_on_it(self):
        window = self.open()
        self.assertIn("dark 2", window._board.describe())

    def test_a_theme_change_repaints_the_board(self):
        window = self.open()
        window.set_palette(fallback(dark=False))
        window.set_palette(fallback(dark=True))


class TheOpponent(WindowBase):
    def test_the_computer_answers(self):
        window = self.open()
        window._on_cell(window._board, index(2, 3))
        self.assertTrue(pump(lambda: window.game.turn == DARK and not window._thinking))
        self.assertEqual(len(window.game.moves), 2)
        self.assertEqual(window.game.position.counts(), (3, 3))

    def test_the_computer_moves_first_when_it_is_dark(self):
        self.store.begin(mode=SOLO, level="easy", human=LIGHT)
        window = self.open()
        self.assertTrue(pump(lambda: window.game.turn == LIGHT))
        self.assertEqual(len(window.game.moves), 1)

    def test_a_tap_meant_for_the_other_side_is_ignored(self):
        window = self.open()
        window._thinking = True
        window._on_cell(window._board, index(2, 3))
        self.assertEqual(window.game.moves, [])

    def test_a_move_from_a_game_that_no_longer_exists_is_dropped(self):
        """A search is started for a board. If it comes back holding a move for
        a board that has been taken back or restarted, the move is rubbish."""
        window = self.open()
        window._on_cell(window._board, index(2, 3))
        stale = window._generation - 1
        moves = list(window.game.moves)
        window._thought(index(0, 0), stale)
        self.assertEqual(window.game.moves, moves)


class TakingItBack(WindowBase):
    def test_undo_hands_the_board_back_to_the_person(self):
        window = self.open()
        window._on_cell(window._board, index(2, 3))
        self.assertTrue(pump(lambda: window.game.turn == DARK and not window._thinking))
        window.undo()
        self.assertEqual(window.game.moves, [])
        self.assertEqual(window.game.turn, DARK)

    def test_taking_back_the_computers_first_move_sets_it_thinking_again(self):
        """The one undo that does not end on the person's turn. Without the
        restart the board sits there with nobody whose turn it is to tap."""
        self.store.begin(mode=SOLO, level="easy", human=LIGHT)
        window = self.open()
        self.assertTrue(pump(lambda: window.game.turn == LIGHT))
        window.undo()
        self.assertTrue(
            pump(lambda: window.game.turn == LIGHT and not window._thinking)
        )
        self.assertEqual(len(window.game.moves), 1)

    def test_undo_at_the_opening_does_nothing(self):
        window = self.open()
        window.undo()
        self.assertEqual(window.game.moves, [])

    def test_undo_is_offered_only_when_there_is_something_to_take_back(self):
        window = self.open()
        self.assertFalse(window._undo.get_sensitive())
        window._on_cell(window._board, index(2, 3))
        self.assertTrue(pump(lambda: window.game.turn == DARK and not window._thinking))
        self.assertTrue(window._undo.get_sensitive())

    def test_what_was_taken_back_is_written_out_too(self):
        window = self.open()
        window._on_cell(window._board, index(2, 3))
        self.assertTrue(pump(lambda: window.game.turn == DARK and not window._thinking))
        window.undo()
        again = Store(self.store.path)
        again.load()
        self.assertEqual(again.moves, [])


class Finishing(WindowBase):
    def _one_move_short(self) -> int:
        """A saved game with a single move left in it, and the person to play."""
        moves = finished_game()
        last = moves[-1]
        game = Game(moves[:-1])
        self.store.begin(mode=SOLO, level="easy", human=game.turn)
        self.store.remember(game)
        return last

    def test_the_result_goes_into_the_record_once(self):
        last = self._one_move_short()
        window = self.open()
        window._on_cell(window._board, last)
        self.assertTrue(pump(lambda: window.game.over))
        self.assertEqual(self.store.totals()["played"], 1)
        window._on_settled()
        self.assertEqual(self.store.totals()["played"], 1)

    def test_a_finished_game_is_not_recorded_again_when_reopened(self):
        last = self._one_move_short()
        window = self.open()
        window._on_cell(window._board, last)
        self.assertTrue(pump(lambda: window.game.over))
        window.destroy()

        again = Store(self.store.path)
        again.load()
        second = ReversiWindow(again)
        self.addCleanup(second.destroy)
        second._on_settled()
        self.assertEqual(again.totals()["played"], 1)

    def test_a_finished_game_says_who_won(self):
        last = self._one_move_short()
        window = self.open()
        window._on_cell(window._board, last)
        self.assertTrue(pump(lambda: window.game.over))
        self.assertRegex(window._status.get_text(), r"win|draw")

    def test_a_finished_board_cannot_be_played_on(self):
        last = self._one_move_short()
        window = self.open()
        window._on_cell(window._board, last)
        self.assertTrue(pump(lambda: window.game.over))
        moves = list(window.game.moves)
        window._on_cell(window._board, index(0, 0))
        self.assertEqual(window.game.moves, moves)


class StartingOver(WindowBase):
    def test_a_new_game_clears_the_board_and_the_file(self):
        window = self.open()
        window._on_cell(window._board, index(2, 3))
        self.assertTrue(pump(lambda: window.game.turn == DARK and not window._thinking))
        window._on_chosen(None, SOLO, "medium", DARK)
        self.assertEqual(window.game.position, OPENING)
        self.assertEqual(self.store.moves, [])
        self.assertEqual(window.level.key, "medium")

    def test_two_people_get_both_turns(self):
        window = self.open()
        window._on_chosen(None, "hotseat", "easy", DARK)
        window._on_cell(window._board, index(2, 3))
        pump(seconds=0.2)
        self.assertEqual(window.game.turn, LIGHT)
        self.assertFalse(window._thinking)
        # ...and the person holding the phone plays that turn too.
        window._on_cell(window._board, window.game.position.legal()[0])
        self.assertEqual(len(window.game.moves), 2)


class TheRecordPage(WindowBase):
    def test_it_builds_with_nothing_in_it(self):
        RecordPage(self.store)

    def test_it_builds_with_a_record(self):
        self.store.level = "hard"
        self.store.record(WON, 14)
        page = RecordPage(self.store)
        self.assertEqual(page.get_title(), "Record")

    def test_the_window_can_push_it(self):
        window = self.open()
        window.show_record()


@unittest.skipIf(REASON, REASON)
class Geometry(unittest.TestCase):
    """The board is drawn, so a tap is arithmetic rather than a widget."""

    def test_the_board_is_square_and_centred(self):
        board = BoardView()
        ox, oy, cell = board._geometry(360, 500)
        self.assertEqual(cell, 45)
        self.assertEqual(oy, 70)
        self.assertEqual(ox, 0)

    def test_a_tap_in_each_corner_lands_on_that_corner(self):
        board = BoardView()
        ox, oy, cell = board._geometry(344, 344)
        for row, column in ((0, 0), (0, 7), (7, 0), (7, 7)):
            x = ox + (column + 0.5) * cell
            y = oy + (row + 0.5) * cell
            self.assertEqual(
                (int((y - oy) // cell) * SIZE) + int((x - ox) // cell),
                index(row, column),
            )

    def test_a_board_with_no_size_yet_swallows_the_tap(self):
        """Rather than dividing by a cell size of zero, which is what an
        unrealised widget reports."""
        board = BoardView()
        board._on_pressed(Gtk.GestureClick(), 1, 10.0, 10.0)


if __name__ == "__main__":
    unittest.main()
