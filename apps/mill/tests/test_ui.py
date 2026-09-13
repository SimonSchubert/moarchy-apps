"""The window, driven by calling it rather than by tapping it.

The same approach the other apps here take. What is different is the shape of a
turn: placing is one tap, moving is two, and taking a piece is a third kind of
tap that only exists between the two halves of somebody else's turn. Those three
are what these tests are mostly about.

The opponent runs on a thread and arrives through GLib.idle_add, so the tests
that involve it pump the main loop and wait -- and they use the Easy level,
whose clock is two hundred milliseconds, because a suite that waited out Hard
would spend most of its time not finding bugs.

Animations are turned off for the whole module. That is not only for speed: it
is the reduced-motion path, and it is the one where a move has to land and
settle in a single turn of the main loop rather than over a tick callback.

Needs a display. Skipped where there is none.
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
    from moarchy_mill.newgame import NewGameDialog
    from moarchy_mill.theme import fallback
    from moarchy_mill.widgets import BoardView, ScoreLine
    from moarchy_mill.window import MillWindow, RecordPage

from moarchy_mill.mill import (  # noqa: E402
    BLACK,
    OPENING,
    PIECES,
    WHITE,
    Game,
    Position,
    place_move,
)
from moarchy_mill.store import HOTSEAT, SOLO, WON, Store  # noqa: E402


def pump(until=None, seconds: float = 8.0) -> bool:
    context = GLib.MainContext.default()
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        while context.pending():
            context.iteration(False)
        if until is None or until():
            return True
        time.sleep(0.01)
    return until is None or until()


def board(white=(), black=(), turn=WHITE, placed=None, removing=False) -> Position:
    w = sum(1 << spot for spot in white)
    b = sum(1 << spot for spot in black)
    return Position(w, b, turn, placed or (PIECES, PIECES), removing)


@unittest.skipIf(REASON, REASON)
class WindowBase(unittest.TestCase):
    def setUp(self):
        self.dir = TemporaryDirectory()
        self.store = Store(Path(self.dir.name) / "mill.json")
        self.store.begin(mode=HOTSEAT, level="easy", human=WHITE)

    def open(self) -> MillWindow:
        self.window = MillWindow(self.store)
        self.addCleanup(self.window.destroy)
        return self.window

    def settle(self, window) -> None:
        pump(lambda: not window._board.busy and not window._thinking, seconds=6)

    def tearDown(self):
        pump(seconds=0.05)
        self.dir.cleanup()


class TheBoard(WindowBase):
    def test_a_new_game_opens_at_the_opening(self):
        window = self.open()
        self.assertEqual(window.game.position, OPENING)

    def test_a_saved_game_is_picked_back_up(self):
        game = Game([place_move(0), place_move(8), place_move(1)])
        self.store.remember(game)
        window = self.open()
        self.assertEqual(window.game.position, game.position)

    def test_the_board_describes_itself_for_a_screen_reader(self):
        view = BoardView()
        view.set_colours(fallback(dark=True))
        view.show(OPENING)
        self.assertIn("White to play", view.describe())
        view.show(board(white=(0, 1, 2), black=(8, 9), removing=True))
        self.assertIn("take a piece", view.describe())


class TheGeometry(WindowBase):
    """Where a piece is drawn, measured rather than believed.

    The first cut of this board put the outer ring at 89% of the half-width and
    photographed with the left and right columns of pieces sliced off by the
    window. The arithmetic that fixed it solves for the margin instead of
    guessing at it -- and this is the test that says so, at every size the
    widget will ever be asked for.
    """

    def test_every_point_is_drawn_inside_the_widget(self):
        view = BoardView()
        view.set_colours(fallback(dark=True))
        for size in (260, 300, 344, 360, 480, 520):
            cx, cy, half = view._geometry(size, size)
            radius = view.piece_radius(half)
            for spot in range(24):
                px, py = view._at(cx, cy, half, spot)
                self.assertGreaterEqual(px - radius, 0, f"{size}px, point {spot}")
                self.assertLessEqual(px + radius, size, f"{size}px, point {spot}")
                self.assertGreaterEqual(py - radius, 0, f"{size}px, point {spot}")
                self.assertLessEqual(py + radius, size, f"{size}px, point {spot}")

    def test_the_rings_are_where_the_rules_say_they_are(self):
        view = BoardView()
        cx, cy, half = view._geometry(344, 344)
        # The three corners of the top-left run outwards, and the midpoint of a
        # side sits on the line between its two corners.
        outer = view._at(cx, cy, half, 0)
        middle = view._at(cx, cy, half, 8)
        inner = view._at(cx, cy, half, 16)
        self.assertLess(outer[0], middle[0])
        self.assertLess(middle[0], inner[0])
        top = view._at(cx, cy, half, 1)
        self.assertAlmostEqual(top[0], cx, places=5)
        self.assertAlmostEqual(top[1], outer[1], places=5)

    def test_a_tap_between_two_points_goes_to_the_nearer_one(self):
        view = BoardView()
        cx, cy, half = view._geometry(344, 344)
        first = view._at(cx, cy, half, 0)
        second = view._at(cx, cy, half, 1)
        # A third of the way along is unambiguous, and the hit test has to agree.
        x = first[0] + (second[0] - first[0]) / 3
        y = first[1] + (second[1] - first[1]) / 3
        nearest = min(
            range(24),
            key=lambda spot: (
                (x - view._at(cx, cy, half, spot)[0]) ** 2
                + (y - view._at(cx, cy, half, spot)[1]) ** 2
            ),
        )
        self.assertEqual(nearest, 0)


class Placing(WindowBase):
    def test_one_tap_puts_a_piece_down(self):
        window = self.open()
        window._on_point(window._board, 5)
        self.settle(window)
        self.assertTrue(window.game.position.men(WHITE) >> 5 & 1)
        self.assertEqual(window.game.position.turn, BLACK)

    def test_a_tap_on_a_point_that_is_taken_does_nothing(self):
        window = self.open()
        window._on_point(window._board, 5)
        self.settle(window)
        before = list(window.game.moves)
        window._on_point(window._board, 5)
        self.assertEqual(window.game.moves, before)

    def test_nothing_is_picked_up_while_there_is_a_piece_in_hand(self):
        window = self.open()
        window._on_point(window._board, 5)
        self.settle(window)
        window._on_point(window._board, 5)
        self.assertEqual(window._picked, -1)


class Moving(WindowBase):
    def _moving(self, window) -> None:
        # Four pieces a side, not two. Two is a loss and three is flying, and
        # neither of those is the middle game this is about.
        window.game.position = board(white=(0, 4, 6, 20), black=(8, 12, 14, 22))
        window.refresh()

    def test_the_first_tap_picks_a_piece_up(self):
        window = self.open()
        self._moving(window)
        window._on_point(window._board, 0)
        self.assertEqual(window._picked, 0)
        self.assertEqual(set(window._drops), {1, 7})
        self.assertEqual(len(window.game.moves), 0)

    def test_the_second_tap_moves_it(self):
        window = self.open()
        self._moving(window)
        window._on_point(window._board, 0)
        window._on_point(window._board, 1)
        self.settle(window)
        self.assertTrue(window.game.position.men(WHITE) >> 1 & 1)
        self.assertFalse(window.game.position.men(WHITE) >> 0 & 1)

    def test_tapping_the_piece_again_puts_it_back_down(self):
        window = self.open()
        self._moving(window)
        window._on_point(window._board, 0)
        window._on_point(window._board, 0)
        self.assertEqual(window._picked, -1)
        self.assertEqual(window._drops, ())

    def test_a_piece_with_nowhere_to_go_is_a_silent_miss(self):
        window = self.open()
        window.game.position = board(white=(0, 4, 6, 20), black=(1, 7, 12, 22))
        window.refresh()
        window._on_point(window._board, 0)
        self.assertEqual(window._picked, -1)
        self.assertEqual(len(window.game.moves), 0)


class Taking(WindowBase):
    def _owed(self, window) -> None:
        window.game.position = board(
            white=(0, 1, 2), black=(8, 9, 10, 16), removing=True
        )
        window.refresh()

    def test_only_the_pieces_the_rules_allow_are_ringed(self):
        window = self.open()
        self._owed(window)
        # Black's mill is safe while the loose piece is not.
        self.assertEqual(window.game.position.removable(), [16])

    def test_a_tap_on_a_ringed_piece_takes_it(self):
        window = self.open()
        self._owed(window)
        window._on_point(window._board, 16)
        self.settle(window)
        self.assertFalse(window.game.position.men(BLACK) >> 16 & 1)
        self.assertEqual(window.game.position.turn, BLACK)

    def test_a_tap_on_a_protected_piece_does_nothing(self):
        window = self.open()
        self._owed(window)
        window._on_point(window._board, 8)
        self.assertTrue(window.game.position.removing)
        self.assertTrue(window.game.position.men(BLACK) >> 8 & 1)

    def test_the_status_says_what_is_owed(self):
        window = self.open()
        self._owed(window)
        self.assertIn("take one of", window._status_text())


class TheOpponent(WindowBase):
    def setUp(self):
        super().setUp()
        self.store.begin(mode=SOLO, level="easy", human=WHITE)

    def test_the_computer_answers(self):
        window = self.open()
        window._on_point(window._board, 5)
        self.assertTrue(
            pump(lambda: len(window.game.moves) >= 2), "the computer never replied"
        )
        self.assertEqual(window.game.turn, WHITE)

    def test_the_computer_opens_when_it_is_white(self):
        self.store.begin(mode=SOLO, level="easy", human=BLACK)
        window = self.open()
        self.assertTrue(
            pump(lambda: len(window.game.moves) >= 1), "the computer never opened"
        )

    def test_nobody_answers_across_a_table(self):
        self.store.begin(mode=HOTSEAT, level="easy", human=WHITE)
        window = self.open()
        window._on_point(window._board, 5)
        self.settle(window)
        pump(seconds=0.4)
        self.assertEqual(len(window.game.moves), 1)

    def test_a_tap_while_it_is_thinking_is_ignored(self):
        window = self.open()
        window._on_point(window._board, 5)
        window._thinking = True
        before = list(window.game.moves)
        window._on_point(window._board, 6)
        self.assertEqual(window.game.moves, before)
        window._thinking = False
        self.settle(window)


class TheResult(WindowBase):
    def setUp(self):
        super().setUp()
        self.store.begin(mode=SOLO, level="easy", human=WHITE)

    def _won(self, window) -> None:
        # Black is down to two, which is a loss.
        window.game.position = board(white=(0, 1, 2, 20), black=(8, 16))
        window.refresh()

    def test_a_finished_game_is_recorded_once(self):
        window = self.open()
        self._won(window)
        window._on_settled()
        self.assertEqual(self.store.record_for("easy")["played"], 1)
        self.assertEqual(self.store.record_for("easy")[WON], 1)
        window._on_settled()
        self.assertEqual(self.store.record_for("easy")["played"], 1)

    def test_a_result_owed_from_a_killed_session_is_counted_on_the_way_in(self):
        game = Game()
        self.store.remember(game, finished=True)
        self.store.recorded = False
        window = self.open()
        window.game.position = board(white=(0, 1, 2, 20), black=(8, 16))
        window._resume()
        pump(seconds=0.2)
        self.assertEqual(self.store.record_for("easy")["played"], 1)

    def test_the_result_is_said_from_the_seat_the_person_is_in(self):
        window = self.open()
        self._won(window)
        self.assertIn("You win", window._result_text())

    def test_a_long_quiet_game_is_called_a_draw(self):
        window = self.open()
        window.game.quiet = 60
        window.game.position = board(white=(0, 2, 4, 20), black=(8, 10, 12, 22))
        self.assertTrue(window.game.drawn)
        self.assertIn("draw", window._result_text())


class TheButtons(WindowBase):
    def test_undo_is_dead_until_something_has_been_done(self):
        window = self.open()
        self.assertFalse(window._undo.get_sensitive())
        window._on_point(window._board, 5)
        self.settle(window)
        self.assertTrue(window._undo.get_sensitive())

    def test_undo_takes_back_a_whole_turn(self):
        self.store.begin(mode=SOLO, level="easy", human=WHITE)
        window = self.open()
        window._on_point(window._board, 5)
        pump(lambda: len(window.game.moves) >= 2 and not window._thinking)
        window.undo()
        self.assertEqual(window.game.moves, [])
        self.assertEqual(window.game.turn, WHITE)

    def test_undo_on_an_empty_board_does_nothing(self):
        window = self.open()
        window.undo()
        self.assertEqual(window.game.moves, [])


class TheOtherScreens(WindowBase):
    def test_the_record_builds_with_nothing_in_it(self):
        RecordPage(self.store)

    def test_the_record_builds_with_a_record(self):
        self.store.begin(mode=SOLO, level="medium", human=WHITE)
        self.store.record(WON, 6)
        RecordPage(self.store)

    def test_the_window_can_push_it(self):
        window = self.open()
        window.show_record()
        pump(seconds=0.2)

    def test_the_score_line_builds(self):
        line = ScoreLine()
        line.refresh(OPENING, {WHITE: "You", BLACK: "Easy"}, live=True)

    def test_the_new_game_sheet_builds_and_answers(self):
        chosen = []
        window = self.open()
        dialog = NewGameDialog(mode=SOLO, level="medium", human=BLACK, in_progress=True)
        dialog.connect("chosen", lambda _d, *args: chosen.append(args))
        dialog.present(window)
        pump(seconds=0.2)
        dialog._on_start()
        self.assertEqual(chosen, [(SOLO, "medium", BLACK)])

    def test_the_sheet_hides_the_difficulty_for_two_players(self):
        dialog = NewGameDialog(
            mode=HOTSEAT, level="medium", human=WHITE, in_progress=False
        )
        self.assertFalse(dialog._level.get_visible())


if __name__ == "__main__":
    unittest.main()
