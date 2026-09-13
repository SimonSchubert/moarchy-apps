"""The window, driven by calling it rather than by tapping it.

The same approach the other apps here take. What is different is the hint: it
arrives from a thread through GLib.idle_add, so those tests pump the main loop
and wait for it, which is the only way to cover the part of the app that
actually answers the question it exists to answer.

Animations are turned off for the whole module. That is not only for speed: it
is the reduced-motion path, and it is the one where a jump has to land and
settle in a single turn of the main loop rather than over a tick callback.

Needs a display. Skipped where there is none, so `python3 -m unittest` on a
machine without GTK still runs the rules, the solver and the file.
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
    from moarchy_pegsolitaire.chooser import FigureDialog
    from moarchy_pegsolitaire.theme import fallback
    from moarchy_pegsolitaire.widgets import BoardView
    from moarchy_pegsolitaire.window import PegSolitaireWindow, RecordPage

from moarchy_pegsolitaire.pegs import (  # noqa: E402
    CENTRE,
    Game,
    Position,
    decode,
    figure_for,
    index,
)
from moarchy_pegsolitaire.store import Store  # noqa: E402


def pump(until=None, seconds: float = 8.0) -> bool:
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
        self.store = Store(Path(self.dir.name) / "pegsolitaire.json")
        self.store.begin("english")

    def open(self) -> PegSolitaireWindow:
        self.window = PegSolitaireWindow(self.store)
        self.addCleanup(self.window.destroy)
        return self.window

    def settle(self, window) -> None:
        pump(lambda: not window._board.busy and not window._thinking, seconds=6)

    def tearDown(self):
        pump(seconds=0.05)
        self.dir.cleanup()


class TheBoard(WindowBase):
    def test_a_new_figure_opens_at_its_start(self):
        window = self.open()
        self.assertEqual(window.game.position, window.game.start)
        self.assertEqual(window.game.count, 32)

    def test_a_saved_game_is_picked_back_up(self):
        game = Game("english")
        game.play(game.position.moves()[0])
        self.store.remember(game)
        window = self.open()
        self.assertEqual(window.game.position, game.position)

    def test_the_board_describes_itself_for_a_screen_reader(self):
        board = BoardView()
        board.set_colours(fallback(dark=True))
        board.show(figure_for("english").start())
        self.assertIn("32 pegs", board.describe())
        board.show(Position(figure_for("english").holes, 1 << CENTRE))
        self.assertIn("one peg", board.describe())


class OneTap(WindowBase):
    def test_a_peg_with_one_jump_takes_it(self):
        window = self.open()
        # On the opening board every peg that can move has exactly one jump.
        peg = decode(window.game.position.moves()[0])[0]
        window._on_hole(window._board, peg)
        self.settle(window)
        self.assertEqual(window.game.count, 31)

    def test_a_peg_with_two_jumps_is_picked_up_and_asked_about(self):
        window = self.open()
        window.game.position = _forked()
        window.refresh()
        window._on_hole(window._board, CENTRE)
        self.assertEqual(window._picked, CENTRE)
        self.assertEqual(len(window._drops), 2)

    def test_tapping_the_peg_again_puts_it_back_down(self):
        window = self.open()
        window.game.position = _forked()
        window.refresh()
        window._on_hole(window._board, CENTRE)
        window._on_hole(window._board, CENTRE)
        self.assertEqual(window._picked, -1)
        self.assertEqual(window._drops, ())

    def test_tapping_one_of_the_two_plays_that_jump(self):
        window = self.open()
        window.game.position = _forked()
        window.refresh()
        window._on_hole(window._board, CENTRE)
        window._on_hole(window._board, index(3, 1))
        self.settle(window)
        self.assertTrue(window.game.position.has_peg(index(3, 1)))
        self.assertFalse(window.game.position.has_peg(CENTRE))

    def test_a_peg_that_cannot_move_is_a_silent_miss(self):
        window = self.open()
        window._on_hole(window._board, index(0, 2))
        self.assertEqual(window._picked, -1)
        self.assertEqual(len(window.game.moves), 0)

    def test_an_empty_hole_is_a_silent_miss_too(self):
        window = self.open()
        window._on_hole(window._board, CENTRE)
        self.assertEqual(window._picked, -1)
        self.assertEqual(len(window.game.moves), 0)


class TheHint(WindowBase):
    def test_it_offers_a_jump_that_leads_somewhere(self):
        self.store.begin("plus")
        window = self.open()
        window.hint()
        self.assertTrue(pump(lambda: not window._thinking), "the hint never came")
        self.assertTrue(window._line, "no line was found on the Plus")
        self.assertGreaterEqual(window._hint[0], 0)
        self.assertTrue(window.game.position.is_legal(window._line[0]))

    def test_following_it_keeps_the_rest_of_the_line(self):
        self.store.begin("plus")
        window = self.open()
        window.hint()
        pump(lambda: not window._thinking)
        line = list(window._line)
        window._play(line[0])
        self.settle(window)
        self.assertEqual(window._line, line[1:])

    def test_playing_something_else_throws_the_line_away(self):
        self.store.begin("plus")
        window = self.open()
        window.hint()
        pump(lambda: not window._thinking)
        other = next(
            move for move in window.game.position.moves() if move != window._line[0]
        )
        window._play(other)
        self.settle(window)
        self.assertEqual(window._line, [])

    def test_it_says_so_when_there_is_no_way_left(self):
        window = self.open()
        # Two pegs too far apart to reach each other.
        window.game.position = Position(
            figure_for("english").holes, (1 << index(2, 0)) | (1 << index(4, 6))
        )
        window.refresh()
        window.hint()
        self.assertTrue(pump(lambda: not window._thinking))
        self.assertEqual(window._line, [])
        self.assertEqual(window._hint, (-1, -1))

    def test_it_is_dead_on_a_board_that_will_not_move(self):
        window = self.open()
        window.game.position = Position(
            figure_for("english").holes, (1 << index(2, 0)) | (1 << index(4, 6))
        )
        window.refresh()
        self.assertFalse(window._help.get_sensitive())


class TheResult(WindowBase):
    def _stick(self, window) -> None:
        window.game.position = Position(
            figure_for("english").holes, (1 << index(2, 0)) | (1 << index(4, 6))
        )

    def test_a_finished_board_is_recorded_once(self):
        window = self.open()
        self._stick(window)
        window._on_settled()
        self.assertEqual(self.store.record_for("english")["played"], 1)
        self.assertEqual(self.store.record_for("english")["best"], 2)
        window._on_settled()
        self.assertEqual(self.store.record_for("english")["played"], 1)

    def test_starting_again_records_nothing(self):
        window = self.open()
        window.game.play(window.game.position.moves()[0])
        window.start_again()
        self.assertEqual(self.store.record_for("english")["played"], 0)
        self.assertEqual(window.game.count, 32)

    def test_the_banner_appears_only_when_the_board_is_finished(self):
        window = self.open()
        self.assertFalse(window._banner.get_revealed())
        self._stick(window)
        window.refresh()
        self.assertTrue(window._banner.get_revealed())
        self.assertIn("Stuck", window._banner.get_title())

    def test_one_peg_in_the_middle_is_said_to_be_the_whole_puzzle(self):
        window = self.open()
        window.game.position = Position(figure_for("english").holes, 1 << CENTRE)
        self.assertTrue(window.game.perfect)
        self.assertIn("middle", window._result_text())

    def test_one_peg_elsewhere_is_said_to_be_not_quite(self):
        window = self.open()
        window.game.position = Position(figure_for("english").holes, 1 << index(2, 0))
        self.assertTrue(window.game.solved)
        self.assertFalse(window.game.perfect)
        self.assertIn("not the one", window._result_text())


class TheButtons(WindowBase):
    def test_undo_is_dead_until_something_has_been_done(self):
        window = self.open()
        self.assertFalse(window._undo.get_sensitive())
        window._on_hole(window._board, decode(window.game.position.moves()[0])[0])
        self.settle(window)
        self.assertTrue(window._undo.get_sensitive())

    def test_undo_takes_back_one_jump(self):
        window = self.open()
        window._on_hole(window._board, decode(window.game.position.moves()[0])[0])
        self.settle(window)
        window.undo()
        self.assertEqual(window.game.count, 32)
        self.assertEqual(window.game.position, window.game.start)

    def test_undo_throws_the_hint_away(self):
        self.store.begin("plus")
        window = self.open()
        window.hint()
        pump(lambda: not window._thinking)
        window._play(window._line[0])
        self.settle(window)
        window.undo()
        self.assertEqual(window._line, [])
        self.assertEqual(window._hint, (-1, -1))


class TheOtherScreens(WindowBase):
    def test_the_record_builds_with_nothing_in_it(self):
        RecordPage(self.store)

    def test_the_record_builds_with_a_record(self):
        self.store.record(1, perfect=True)
        self.store.begin("cross")
        self.store.record(3)
        RecordPage(self.store)

    def test_the_window_can_push_it(self):
        window = self.open()
        window.show_record()
        pump(seconds=0.2)

    def test_the_figure_sheet_builds_and_answers(self):
        chosen = []
        window = self.open()
        dialog = FigureDialog(current="english", store=self.store)
        dialog.connect("chosen", lambda _d, key: chosen.append(key))
        dialog.present(window)
        pump(seconds=0.2)
        dialog._pick(None, "pyramid")
        self.assertEqual(chosen, ["pyramid"])

    def test_choosing_a_figure_starts_it(self):
        window = self.open()
        window._on_chosen(None, "goblet")
        self.assertEqual(window.game.figure.key, "goblet")
        self.assertEqual(window.game.count, 16)
        self.assertEqual(self.store.figure, "goblet")


def _forked() -> Position:
    """A peg in the middle with two jumps open to it, and nothing else.

    Built rather than played into. On the English board every peg that can move
    at all has exactly one jump for the first few turns, which is the case the
    one-tap rule is for -- and testing the other branch needs a board where
    somebody actually has a choice.
    """
    holes = figure_for("english").holes
    pegs = (1 << CENTRE) | (1 << index(3, 2)) | (1 << index(2, 3))
    return Position(holes, pegs)


def _forked() -> Position:
    """A peg in the middle with two jumps open to it, and nothing else.

    Built rather than played into. On the English board every peg that can move
    at all has exactly one jump for the first several turns -- which is the case
    the one-tap rule exists for, and means testing the other branch needs a
    board where somebody genuinely has a choice.
    """
    holes = figure_for("english").holes
    pegs = (1 << CENTRE) | (1 << index(3, 2)) | (1 << index(2, 3))
    return Position(holes, pegs)


if __name__ == "__main__":
    unittest.main()
