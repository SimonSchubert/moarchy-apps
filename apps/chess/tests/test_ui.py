"""The window, driven by calling it rather than by tapping it.

The same approach Keep's suite takes and Reversi's repeats: build the real
widgets on a real display and call the methods the buttons call. What is
different here is that one of the paths under test runs on a thread -- the
computer's move arrives through GLib.idle_add from a search -- so these tests
pump the main loop and wait for it, which is the only way to cover the part of
the app that actually plays.

The other thing this suite has that Reversi's did not is the *two-tap* move. A
move in chess is a square and then a square, and between them the window is
holding a piece; picking one up, putting it down, changing your mind and tapping
a square the piece cannot reach are four different things that all arrive as the
same signal. They are the most likely thing in this app to be wrong, and they
are the cheapest thing in it to test.

Animations are turned off for the whole module. That is not only for speed: it
is the reduced-motion path, and it is the one where a move has to land and
settle in a single turn of the main loop rather than over a tick callback.

Needs a display. Skipped where there is none, so `python3 -m unittest` on a
machine without GTK still runs the rules, the pieces, the search and the file.
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
    from moarchy_chess.theme import fallback
    from moarchy_chess.widgets import BoardView, CapturedView, PieceIcon, ScoreLine
    from moarchy_chess.window import ChessWindow, RecordPage

from moarchy_chess.chess import (  # noqa: E402
    BLACK,
    KING,
    KNIGHT,
    NO_SQUARE,
    PAWN,
    QUEEN,
    WHITE,
    Game,
    Position,
    parse_square,
    parse_uci,
    piece,
)
from moarchy_chess.store import HOTSEAT, SOLO, WON, Store  # noqa: E402


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


def moves(*texts: str) -> list[int]:
    return [parse_uci(text) for text in texts]


@unittest.skipIf(REASON, REASON)
class WindowBase(unittest.TestCase):
    def setUp(self):
        self.dir = TemporaryDirectory()
        self.store = Store(Path(self.dir.name) / "chess.json")
        self.store.begin(mode=SOLO, level="easy", human=WHITE)

    def open(self) -> ChessWindow:
        self.window = ChessWindow(self.store)
        self.window.set_palette(fallback(dark=True))
        self.addCleanup(self.window.destroy)
        return self.window

    def tap(self, window, square: str) -> None:
        window._on_square(window._board, parse_square(square))

    def tearDown(self):
        pump(seconds=0.05)
        self.dir.cleanup()


class TheBoard(WindowBase):
    def test_a_new_game_opens_at_the_opening(self):
        window = self.open()
        self.assertEqual(window.game.position.fen(), Position.start().fen())

    def test_a_saved_game_is_picked_back_up(self):
        game = Game(moves("e2e4", "e7e5", "g1f3"))
        self.store.remember(game)
        window = self.open()
        self.assertEqual(window.game.position.fen(), game.position.fen())

    def test_the_board_says_what_is_on_it(self):
        window = self.open()
        self.assertIn("32 pieces", window._board.describe())
        self.assertIn("White to play", window._board.describe())

    def test_a_theme_change_repaints_everything_that_is_drawn(self):
        window = self.open()
        window.set_palette(fallback(dark=False))
        window.set_palette(fallback(dark=True))

    def test_the_board_is_turned_round_for_black(self):
        self.store.begin(mode=SOLO, level="easy", human=BLACK)
        window = self.open()
        self.assertTrue(window._board._flipped)

    def test_and_is_not_for_two_people_at_one_phone(self):
        self.store.begin(mode=HOTSEAT, level="easy", human=BLACK)
        window = self.open()
        self.assertFalse(window._board._flipped)


class PickingUp(WindowBase):
    def test_tapping_a_piece_picks_it_up_and_shows_where_it_goes(self):
        window = self.open()
        self.tap(window, "e2")
        self.assertEqual(window._selected, parse_square("e2"))
        self.assertEqual(
            window._board._targets, {parse_square("e3"), parse_square("e4")}
        )

    def test_tapping_it_again_puts_it_down(self):
        window = self.open()
        self.tap(window, "e2")
        self.tap(window, "e2")
        self.assertEqual(window._selected, NO_SQUARE)
        self.assertEqual(window._board._targets, frozenset())

    def test_tapping_a_different_piece_picks_that_one_up_instead(self):
        window = self.open()
        self.tap(window, "e2")
        self.tap(window, "d2")
        self.assertEqual(window._selected, parse_square("d2"))

    def test_tapping_an_empty_square_puts_the_piece_down(self):
        window = self.open()
        self.tap(window, "e2")
        self.tap(window, "h5")
        self.assertEqual(window._selected, NO_SQUARE)
        self.assertEqual(window.game.moves, [])

    def test_a_piece_with_nowhere_to_go_cannot_be_picked_up(self):
        window = self.open()
        self.tap(window, "a1")
        self.assertEqual(window._selected, NO_SQUARE)

    def test_the_other_side_cannot_be_picked_up(self):
        window = self.open()
        self.tap(window, "e7")
        self.assertEqual(window._selected, NO_SQUARE)

    def test_a_tap_on_nothing_at_all_does_nothing(self):
        window = self.open()
        self.tap(window, "d4")
        self.assertEqual(window._selected, NO_SQUARE)
        self.assertEqual(window.game.moves, [])


class Moving(WindowBase):
    def test_two_taps_play_a_move(self):
        window = self.open()
        self.tap(window, "e2")
        self.tap(window, "e4")
        self.assertEqual(window.game.uci()[0], "e2e4")
        self.assertEqual(window._selected, NO_SQUARE)

    def test_a_move_is_written_out_at_once(self):
        """Not on a timer. The app is killed rather than closed on a phone, and
        a game that loses its last move to that is a game nobody finishes."""
        window = self.open()
        self.tap(window, "e2")
        self.tap(window, "e4")
        again = Store(self.store.path)
        again.load()
        self.assertEqual(again.moves[0], "e2e4")

    def test_a_move_the_piece_cannot_make_is_not_played(self):
        window = self.open()
        self.tap(window, "e2")
        self.tap(window, "e5")
        self.assertEqual(window.game.moves, [])

    def test_castling_is_one_move_and_the_rook_comes_too(self):
        self.store.begin(mode=HOTSEAT, level="easy", human=WHITE)
        self.store.remember(Game(moves("e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "f8c5")))
        window = self.open()
        self.tap(window, "e1")
        self.tap(window, "g1")
        self.assertEqual(window.game.uci()[-1], "e1g1")
        self.assertEqual(
            window.game.position.squares[parse_square("f1")], piece(WHITE, 4)
        )

    def test_a_tap_while_the_computer_is_thinking_is_ignored(self):
        window = self.open()
        window._thinking = True
        self.tap(window, "e2")
        self.assertEqual(window._selected, NO_SQUARE)


class Promoting(WindowBase):
    """A pawn on the last rank is the one move this app stops and asks about."""

    def arrange(self) -> ChessWindow:
        """A board with a pawn one square from the end.

        Put on the window rather than through the store, because the store
        holds a list of moves from the standard opening and has no way to say
        "this board" -- which is right for an app that only ever plays chess
        from the beginning, and no use at all for testing one position.
        """
        self.store.begin(mode=HOTSEAT, level="easy", human=WHITE)
        window = self.open()
        window.game = Game(position=Position.from_fen("4k3/P7/8/8/8/8/8/4K3 w - - 0 1"))
        window.refresh()
        return window

    def test_four_squares_are_offered_as_one_destination(self):
        window = self.arrange()
        self.tap(window, "a7")
        self.assertIn(parse_square("a8"), window._board._targets)
        self.assertEqual(len(window._board._targets), 1)

    def test_the_move_is_not_played_until_the_piece_is_chosen(self):
        window = self.arrange()
        self.tap(window, "a7")
        self.tap(window, "a8")
        pump(seconds=0.2)
        self.assertEqual(window.game.moves, [])
        self.assertIsNotNone(window.get_visible_dialog())

    def test_choosing_a_piece_plays_that_promotion(self):
        window = self.arrange()
        self.tap(window, "a7")
        self.tap(window, "a8")
        pump(seconds=0.2)
        window.get_visible_dialog().emit("chosen", KNIGHT)
        self.assertEqual(window.game.uci(), ["a7a8n"])

    def test_the_queen_is_what_a_tap_on_the_queen_gives(self):
        window = self.arrange()
        self.tap(window, "a7")
        self.tap(window, "a8")
        pump(seconds=0.2)
        window.get_visible_dialog().emit("chosen", QUEEN)
        self.assertEqual(window.game.uci(), ["a7a8q"])

    def test_a_move_with_only_one_form_is_played_without_asking(self):
        window = self.arrange()
        self.tap(window, "e1")
        self.tap(window, "d1")
        self.assertEqual(window.game.uci(), ["e1d1"])
        self.assertIsNone(window.get_visible_dialog())


class TheOpponent(WindowBase):
    def test_the_computer_answers(self):
        window = self.open()
        self.tap(window, "e2")
        self.tap(window, "e4")
        self.assertTrue(
            pump(lambda: window.game.turn == WHITE and not window._thinking)
        )
        self.assertEqual(len(window.game.moves), 2)

    def test_the_computer_moves_first_when_it_is_white(self):
        self.store.begin(mode=SOLO, level="easy", human=BLACK)
        window = self.open()
        self.assertTrue(pump(lambda: window.game.turn == BLACK))
        self.assertEqual(len(window.game.moves), 1)

    def test_a_move_from_a_game_that_no_longer_exists_is_dropped(self):
        """A search is started for a board. If it comes back holding a move for
        a board that has been taken back or restarted, the move is rubbish."""
        window = self.open()
        self.tap(window, "e2")
        self.tap(window, "e4")
        stale = window._generation - 1
        recorded = list(window.game.moves)
        window._thought(parse_uci("a7a6"), stale)
        self.assertEqual(window.game.moves, recorded)

    def test_a_move_that_is_not_legal_here_is_dropped(self):
        window = self.open()
        window._thinking = True
        window._thought(parse_uci("a1a8"), window._generation)
        self.assertEqual(window.game.moves, [])

    def test_a_game_saved_on_the_computer_s_turn_starts_thinking_again(self):
        self.store.remember(Game(moves("e2e4")))
        window = self.open()
        self.assertTrue(pump(lambda: len(window.game.moves) == 2))


class TakingItBack(WindowBase):
    def test_undo_hands_the_board_back_to_the_person(self):
        window = self.open()
        self.tap(window, "e2")
        self.tap(window, "e4")
        self.assertTrue(
            pump(lambda: window.game.turn == WHITE and not window._thinking)
        )
        window.undo()
        self.assertEqual(window.game.moves, [])
        self.assertEqual(window.game.turn, WHITE)

    def test_undo_takes_one_move_each_in_a_two_player_game(self):
        self.store.begin(mode=HOTSEAT, level="easy", human=WHITE)
        window = self.open()
        self.tap(window, "e2")
        self.tap(window, "e4")
        window.undo()
        self.assertEqual(window.game.moves, [])

    def test_undo_on_an_untouched_board_does_nothing(self):
        window = self.open()
        window.undo()
        self.assertEqual(window.game.moves, [])

    def test_undo_puts_down_whatever_was_picked_up(self):
        self.store.begin(mode=HOTSEAT, level="easy", human=WHITE)
        window = self.open()
        self.tap(window, "e2")
        self.tap(window, "e4")
        self.tap(window, "e7")
        window.undo()
        self.assertEqual(window._selected, NO_SQUARE)


class Finishing(WindowBase):
    MATE = ("f2f3", "e7e5", "g2g4", "d8h4")

    def arrange(self) -> ChessWindow:
        self.store.begin(mode=SOLO, level="easy", human=WHITE)
        self.store.remember(Game(moves(*self.MATE)))
        return self.open()

    def test_a_finished_game_says_so(self):
        window = self.arrange()
        self.assertIn("Checkmate", window._status.get_text())

    def test_the_result_goes_into_the_record_once(self):
        window = self.arrange()
        window._finish()
        window._finish()
        self.assertEqual(self.store.totals()["played"], 1)

    def test_a_finished_game_is_not_recorded_again_on_the_way_back_in(self):
        window = self.arrange()
        window._finish()
        window.destroy()
        again = ChessWindow(self.store)
        self.addCleanup(again.destroy)
        again._on_settled()
        self.assertEqual(self.store.totals()["played"], 1)

    def test_nothing_can_be_played_on_a_finished_board(self):
        window = self.arrange()
        self.tap(window, "b1")
        self.assertEqual(len(window.game.moves), len(self.MATE))

    def test_undo_stops_at_the_end_of_a_recorded_game(self):
        window = self.arrange()
        window.undo()
        self.assertEqual(len(window.game.moves), len(self.MATE))


class Starting(WindowBase):
    def test_a_new_game_clears_the_board(self):
        window = self.open()
        self.tap(window, "e2")
        self.tap(window, "e4")
        window._on_chosen(None, SOLO, "medium", WHITE)
        self.assertEqual(window.game.moves, [])
        self.assertEqual(window.level.key, "medium")

    def test_choosing_black_starts_the_computer_off(self):
        window = self.open()
        window._on_chosen(None, SOLO, "easy", BLACK)
        self.assertTrue(pump(lambda: len(window.game.moves) == 1))

    def test_the_sheet_can_be_opened(self):
        window = self.open()
        window.ask_new_game()
        pump(seconds=0.1)


class Pages(WindowBase):
    def test_the_record_opens(self):
        self.store.mode = SOLO
        self.store.level = "easy"
        self.store.record(WON, 24)
        window = self.open()
        window.show_record()
        self.assertIsInstance(window._nav.get_visible_page(), RecordPage)

    def test_the_record_opens_with_nothing_in_it(self):
        window = self.open()
        window.show_record()
        pump(seconds=0.1)


@unittest.skipIf(REASON, REASON)
class Drawing(unittest.TestCase):
    """The widgets, without a window round them."""

    def test_the_board_asks_to_be_square(self):
        board = BoardView()
        wide, natural, _, _ = board.do_measure(Gtk.Orientation.VERTICAL, 344)
        self.assertEqual((wide, natural), (344, 344))

    def test_the_board_refuses_to_be_smaller_than_a_thumb(self):
        board = BoardView()
        wide, _, _, _ = board.do_measure(Gtk.Orientation.VERTICAL, 100)
        self.assertGreaterEqual(wide, 272)

    def test_the_board_stops_growing(self):
        board = BoardView()
        wide, _, _, _ = board.do_measure(Gtk.Orientation.VERTICAL, 2000)
        self.assertLessEqual(wide, 560)

    def test_the_board_can_be_told_what_to_show(self):
        board = BoardView()
        game = Game(moves("e2e4", "e7e5"))
        board.show(game.position, last=(parse_square("e7"), parse_square("e5")))
        self.assertIn("White to play", board.describe())

    def test_a_held_piece_is_described(self):
        board = BoardView()
        board.show(Position.start(), selected=parse_square("e2"))
        self.assertIn("pawn on e2 selected", board.describe())

    def test_every_piece_has_an_icon(self):
        for kind in (PAWN, QUEEN, KING):
            icon = PieceIcon(piece(WHITE, kind), 24)
            icon.set_colours(fallback(dark=True))

    def test_captured_pieces_are_sorted_by_what_they_are_worth(self):
        view = CapturedView()
        view.show([piece(BLACK, PAWN), piece(BLACK, QUEEN), piece(BLACK, PAWN)])
        self.assertEqual(view._codes[0] & 7, QUEEN)

    def test_a_coordinate_is_drawn_in_the_other_square_s_colour(self):
        """Not the colour of the square it is on, which is invisible."""
        board = BoardView()
        board.set_colours(fallback(dark=True))
        light = board._ink["light"]
        dark = board._ink["dark"]
        self.assertEqual(board.label_ink(0, 0), dark)  # a light square
        self.assertEqual(board.label_ink(0, 1), light)  # a dark one
        self.assertEqual(board.label_ink(7, 0), light)
        self.assertEqual(board.label_ink(7, 7), dark)

    def test_the_score_line_follows_the_game(self):
        line = ScoreLine()
        line.set_colours(fallback(dark=True))
        game = Game(moves("e2e4", "d7d5", "e4d5"))
        line.refresh(game, {WHITE: "You", BLACK: "Easy"}, live=True)


if __name__ == "__main__":
    unittest.main()
