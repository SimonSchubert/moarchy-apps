"""The rules. No GTK, so these run on any machine with a Python.

The cases worth having in a game this small are not the ordinary ones -- three
in a row is three in a row -- they are the edges where an implementation can be
wrong and still look right: a board that is full and won at the same time, a
board that is won with squares left on it, and a move list that stops making
sense halfway down.
"""

import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_tictactoe.tictactoe import (  # noqa: E402
    CELLS,
    EMPTY,
    LINES,
    O,
    X,
    Game,
    Position,
    index,
    other,
    row_column,
    won_line,
)


def board(moves) -> Position:
    position = EMPTY
    for cell in moves:
        position = position.play(cell)
    return position


class TheGrid(unittest.TestCase):
    def test_indexing_round_trips(self):
        for cell in range(CELLS):
            self.assertEqual(index(*row_column(cell)), cell)

    def test_the_corners_and_the_centre_are_where_they_look(self):
        self.assertEqual(index(0, 0), 0)
        self.assertEqual(index(1, 1), 4)
        self.assertEqual(index(2, 2), 8)

    def test_there_are_eight_ways_to_win_and_each_is_three_squares(self):
        self.assertEqual(len(LINES), 8)
        for mask, squares in LINES:
            self.assertEqual(len(squares), 3)
            self.assertEqual(mask.bit_count(), 3)

    def test_every_line_is_kept_in_the_order_it_is_drawn(self):
        # The line is struck through on screen as one stroke from the first
        # square to the last, so the middle one has to be in the middle. That
        # is exactly what recovering the squares from the mask would lose: it
        # gives them back in bit order, which for the anti-diagonal is 2, 4, 6
        # drawn as if it ran the other way.
        for _mask, squares in LINES:
            first, middle, last = (row_column(square) for square in squares)
            self.assertEqual(
                (middle[0] - first[0], middle[1] - first[1]),
                (last[0] - middle[0], last[1] - middle[1]),
                f"{squares} is not three evenly spaced squares in order",
            )

    def test_the_marks_are_each_others_other(self):
        self.assertEqual(other(X), O)
        self.assertEqual(other(O), X)


class Playing(unittest.TestCase):
    def test_an_empty_board_has_nine_moves_and_x_to_play(self):
        self.assertEqual(EMPTY.turn, X)
        self.assertEqual(len(EMPTY.legal()), CELLS)

    def test_playing_a_square_does_not_change_the_position_played_from(self):
        after = EMPTY.play(4)
        self.assertEqual(EMPTY.occupied(), 0)
        self.assertEqual(after.marks(X), 1 << 4)
        self.assertEqual(after.turn, O)

    def test_a_taken_square_is_not_legal(self):
        after = EMPTY.play(4)
        self.assertFalse(after.is_legal(4))
        with self.assertRaises(ValueError):
            after.play(4)

    def test_a_square_off_the_board_is_not_legal(self):
        for cell in (-1, CELLS, 99):
            self.assertFalse(EMPTY.is_legal(cell))

    def test_every_line_wins_for_either_mark(self):
        # Built rather than played, because the point is the win test and not
        # the move order: eight lines times two marks is sixteen boards, and
        # constructing them says so in one line each.
        for mask, squares in LINES:
            self.assertEqual(Position(x=mask, o=0, turn=O).winner(), X, str(squares))
            self.assertEqual(Position(x=0, o=mask, turn=X).winner(), O, str(squares))


class Endings(unittest.TestCase):
    def test_a_won_board_has_no_legal_moves_left_on_it(self):
        # Four squares are still empty, and none of them is a move: the game is
        # over. Answering with the empty squares is how a board gets a tenth
        # mark on it.
        position = board([0, 3, 1, 4, 2])
        self.assertEqual(position.winner(), X)
        self.assertEqual(position.legal(), [])
        self.assertTrue(position.is_over())
        self.assertFalse(position.is_full())

    def test_the_winning_line_comes_back_in_order(self):
        position = board([2, 0, 4, 1, 6])
        self.assertEqual(position.winner(), X)
        self.assertEqual(position.winning_line(), (2, 4, 6))

    def test_a_full_board_with_no_line_is_a_draw(self):
        position = board([4, 0, 8, 2, 1, 7, 3, 5, 6])
        self.assertTrue(position.is_full())
        self.assertTrue(position.is_over())
        self.assertIsNone(position.winner())
        self.assertEqual(position.winning_line(), ())

    def test_won_line_finds_nothing_in_an_empty_hand(self):
        self.assertIsNone(won_line(0))

    def test_wins_now_names_the_square_that_finishes_it(self):
        position = board([0, 3, 1, 4])
        self.assertEqual(position.wins_now(X), [2])
        self.assertEqual(position.wins_now(O), [5])


class TheMoveList(unittest.TestCase):
    def test_a_game_is_its_moves(self):
        game = Game()
        for cell in (4, 0, 8):
            game.play(cell)
        self.assertEqual(game.moves, [4, 0, 8])
        self.assertEqual(game.position, board([4, 0, 8]))

    def test_a_play_says_what_it_drew(self):
        game = Game()
        game.play(0)
        game.play(3)
        game.play(1)
        game.play(4)
        play = game.play(2)
        self.assertEqual(play.cell, 2)
        self.assertEqual(play.mark, X)
        self.assertEqual(play.line, (0, 1, 2))

    def test_resume_keeps_what_will_play_and_drops_the_rest(self):
        # 4 twice: the file stops being a game at the repeat, and everything
        # after it goes with it.
        game = Game.resume([0, 4, 4, 8])
        self.assertEqual(game.moves, [0, 4])

    def test_resume_stops_at_a_won_board(self):
        game = Game.resume([0, 3, 1, 4, 2, 5, 8])
        self.assertEqual(game.moves, [0, 3, 1, 4, 2])
        self.assertTrue(game.over)

    def test_a_bad_move_in_the_constructor_is_an_error(self):
        with self.assertRaises(ValueError):
            Game([0, 0])

    def test_undo_pops_one_and_nothing_from_an_empty_board(self):
        game = Game([4, 0])
        self.assertTrue(game.undo())
        self.assertEqual(game.moves, [4])
        self.assertTrue(game.undo())
        self.assertFalse(game.undo())

    def test_takeback_returns_the_turn_to_the_mark_that_asked(self):
        game = Game([4, 0])  # X played, O replied; X is on move
        game.play(8)  # X again
        game.play(1)  # O replies
        self.assertEqual(game.turn, X)
        self.assertTrue(game.takeback(X))
        self.assertEqual(game.turn, X)
        self.assertEqual(game.moves, [4, 0])

    def test_takeback_from_an_empty_board_does_nothing(self):
        game = Game()
        self.assertFalse(game.takeback(X))
        self.assertEqual(game.moves, [])


if __name__ == "__main__":
    unittest.main()
