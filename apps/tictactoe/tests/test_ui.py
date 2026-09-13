"""The window, driven by calling it rather than by tapping it.

The same approach Keep and Reversi take: build the real widgets on a real
display and call the methods the buttons call. What is different here is the
opponent's timeout -- the computer answers from a GLib source rather than from a
thread -- so these tests pump the main loop and wait for it, which is the only
way to cover the part of the app that actually plays.

Animations are turned off for the whole module. That is not only for speed: it
is the reduced-motion path, and it is the one where a mark has to land and
settle in a single turn of the main loop rather than over a tick callback.

Needs a display. Skipped where there is none, so `python3 -m unittest` on a
machine without GTK still runs the rules, the opponent and the file.
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
    from moarchy_tictactoe.newgame import NewGameDialog
    from moarchy_tictactoe.theme import fallback
    from moarchy_tictactoe.widgets import BoardView, ScoreLine
    from moarchy_tictactoe.window import RecordPage, TicTacToeWindow

from moarchy_tictactoe.store import (  # noqa: E402
    DRAWN,
    HOTSEAT,
    LOST,
    SOLO,
    WON,
    Store,
)
from moarchy_tictactoe.tictactoe import EMPTY, O, X, Game  # noqa: E402


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


@unittest.skipIf(REASON, REASON)
class WindowBase(unittest.TestCase):
    def setUp(self):
        self.dir = TemporaryDirectory()
        self.store = Store(Path(self.dir.name) / "tictactoe.json")
        self.store.begin(mode=SOLO, level="easy", mark=X)

    def open(self) -> TicTacToeWindow:
        self.window = TicTacToeWindow(self.store)
        self.addCleanup(self.window.destroy)
        return self.window

    def tearDown(self):
        pump(seconds=0.05)
        self.dir.cleanup()


class TheBoard(WindowBase):
    def test_a_new_game_opens_on_an_empty_board(self):
        window = self.open()
        self.assertEqual(window.game.position, EMPTY)

    def test_a_saved_game_is_picked_back_up(self):
        game = Game([4, 0, 8])
        self.store.remember(game)
        window = self.open()
        self.assertEqual(window.game.position, game.position)

    def test_a_tap_on_an_empty_square_plays_it(self):
        window = self.open()
        window._on_cell(window._board, 4)
        self.assertEqual(window.game.moves[0], 4)

    def test_a_tap_on_a_taken_square_does_nothing_and_says_nothing(self):
        window = self.open()
        window._on_cell(window._board, 4)
        pump(lambda: not window._thinking and len(window.game.moves) >= 2)
        before = list(window.game.moves)
        window._on_cell(window._board, 4)
        self.assertEqual(window.game.moves, before)

    def test_the_board_describes_itself_for_a_screen_reader(self):
        board = BoardView()
        board.set_colours(fallback(dark=True))
        board.show(EMPTY)
        self.assertIn("X to play", board.describe())
        board.show(Game([0, 3, 1, 4, 2]).position)
        self.assertIn("won", board.describe())


class TheOpponent(WindowBase):
    def test_the_computer_answers(self):
        window = self.open()
        window._on_cell(window._board, 4)
        self.assertTrue(
            pump(lambda: len(window.game.moves) >= 2), "the computer never replied"
        )
        self.assertEqual(window.game.turn, X)

    def test_the_computer_moves_first_when_it_holds_x(self):
        self.store.begin(mode=SOLO, level="easy", mark=O)
        window = self.open()
        self.assertTrue(
            pump(lambda: len(window.game.moves) >= 1), "the computer never opened"
        )

    def test_a_game_plays_itself_out_to_a_result(self):
        window = self.open()
        for _ in range(9):
            if window.game.over:
                break
            legal = window.game.position.legal()
            if window.game.turn == X and legal:
                window._on_cell(window._board, legal[0])
            pump(lambda: not window._thinking and not window._board.busy, seconds=3)
        self.assertTrue(window.game.over)
        self.assertTrue(self.store.finished)

    def test_nobody_answers_across_a_table(self):
        self.store.begin(mode=HOTSEAT, level="easy", mark=X)
        window = self.open()
        window._on_cell(window._board, 4)
        pump(seconds=0.6)
        self.assertEqual(len(window.game.moves), 1)
        self.assertEqual(window.game.turn, O)


class TheButtons(WindowBase):
    def test_undo_is_live_during_a_game_and_play_again_is_not(self):
        window = self.open()
        window._on_cell(window._board, 4)
        pump(lambda: not window._thinking and not window._board.busy)
        self.assertTrue(window._undo.get_sensitive())
        self.assertFalse(window._again.get_sensitive())

    def test_they_trade_places_when_the_game_ends(self):
        self.store.remember(Game([0, 3, 1, 4, 2]), finished=True)
        window = self.open()
        self.assertTrue(window.game.over)
        self.assertFalse(window._undo.get_sensitive())
        self.assertTrue(window._again.get_sensitive())

    def test_undo_gives_the_turn_back_rather_than_one_ply(self):
        window = self.open()
        window._on_cell(window._board, 4)
        pump(lambda: len(window.game.moves) >= 2 and not window._thinking)
        window.undo()
        self.assertEqual(window.game.moves, [])
        self.assertEqual(window.game.turn, X)

    def test_undo_on_an_empty_board_does_nothing(self):
        window = self.open()
        window.undo()
        self.assertEqual(window.game.moves, [])

    def test_a_rematch_swaps_the_marks_and_keeps_the_score(self):
        self.store.remember(Game([0, 3, 1, 4, 2]), finished=True)
        window = self.open()
        pump(seconds=0.2)
        self.assertEqual(self.store.series["a"], 1)
        window.rematch()
        self.assertEqual(self.store.mark, O)
        self.assertEqual(window.game.moves, [])
        self.assertEqual(self.store.series["a"], 1)


class TheResult(WindowBase):
    def test_a_finished_game_is_recorded_once(self):
        self.store.remember(Game([0, 3, 1, 4, 2]), finished=False)
        window = self.open()
        pump(lambda: self.store.record_for("easy")["played"] == 1)
        self.assertEqual(self.store.record_for("easy")[WON], 1)
        # Settling again must not count it twice, and neither must reopening.
        window._on_settled()
        self.assertEqual(self.store.record_for("easy")["played"], 1)

    def test_a_game_already_counted_is_not_counted_again(self):
        self.store.remember(Game([0, 3, 1, 4, 2]), finished=True)
        self.store.recorded = True
        self.open()
        pump(seconds=0.3)
        self.assertEqual(self.store.record_for("easy")["played"], 0)

    def test_a_result_owed_from_a_killed_session_is_counted_on_the_way_back_in(
        self,
    ):
        # finished, but never counted: the phone died between the move being
        # written and the mark finishing being drawn.
        self.store.remember(Game([0, 3, 1, 4, 2]), finished=True)
        self.store.recorded = False
        self.open()
        pump(lambda: self.store.record_for("easy")["played"] == 1)
        self.assertEqual(self.store.record_for("easy")[WON], 1)

    def test_the_result_is_said_from_the_seat_the_person_is_in(self):
        self.store.remember(Game([0, 3, 1, 4, 2]), finished=True)
        window = self.open()
        self.assertIn("You win", window._result_text())

    def test_a_drawn_game_says_so(self):
        self.store.remember(Game([4, 0, 8, 2, 1, 7, 3, 5, 6]), finished=True)
        window = self.open()
        self.assertIn("draw", window._result_text())
        pump(lambda: self.store.record_for("easy")[DRAWN] == 1)

    def test_losing_is_recorded_as_a_loss(self):
        self.store.begin(mode=SOLO, level="easy", mark=O)
        self.store.remember(Game([0, 3, 1, 4, 2]), finished=False)
        self.open()
        pump(lambda: self.store.record_for("easy")[LOST] == 1)


class TheScoreLine(WindowBase):
    def test_it_names_the_seats_rather_than_the_marks(self):
        window = self.open()
        self.assertEqual(window.names["a"], "You")
        self.assertEqual(window.names["b"], "Easy")

    def test_across_a_table_it_names_two_players(self):
        self.store.begin(mode=HOTSEAT, level="easy", mark=X)
        window = self.open()
        self.assertEqual(set(window.names.values()), {"One", "Two"})

    def test_it_builds_with_a_score_on_it(self):
        line = ScoreLine()
        line.refresh(
            EMPTY,
            {"a": X, "b": O},
            {"a": "You", "b": "Fair"},
            {"a": 2, "b": 1, DRAWN: 1},
            live=True,
        )


class TheOtherScreens(WindowBase):
    def test_the_record_builds_with_nothing_in_it(self):
        RecordPage(self.store)

    def test_the_record_builds_with_a_record(self):
        for _ in range(3):
            self.store.record(DRAWN)
        RecordPage(self.store)

    def test_the_window_can_push_it(self):
        window = self.open()
        window.show_record()
        pump(seconds=0.2)

    def test_the_new_game_sheet_builds_and_answers(self):
        chosen = []
        window = self.open()
        dialog = NewGameDialog(mode=SOLO, level="fair", mark=O, in_progress=True)
        dialog.connect("chosen", lambda _d, *args: chosen.append(args))
        # Presented before Start is pressed, because closing a dialog that was
        # never presented is a libadwaita critical -- and one that would be
        # shouted into a log nobody reads if it happened on a phone.
        dialog.present(window)
        pump(seconds=0.2)
        dialog._on_start()
        self.assertEqual(chosen, [(SOLO, "fair", O)])

    def test_the_sheet_hides_the_difficulty_for_two_players(self):
        dialog = NewGameDialog(mode=HOTSEAT, level="fair", mark=X, in_progress=False)
        self.assertFalse(dialog._level.get_visible())


if __name__ == "__main__":
    unittest.main()
