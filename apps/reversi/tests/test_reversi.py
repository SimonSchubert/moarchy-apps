"""The rules.

No GTK here, so this suite runs anywhere -- which is the point of keeping
reversi.py free of it. The bitboard shifts are the sort of code that is either
right or subtly, invisibly wrong, so most of what is below is aimed at the edges
of the board, where a shift that forgets its mask wraps around and flips a disc
eight squares away on the other side.
"""

import random
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_reversi.reversi import (  # noqa: E402
    CORNERS,
    DARK,
    LIGHT,
    OPENING,
    PASS,
    SIZE,
    Game,
    Position,
    cells,
    index,
    legal_moves,
    notation,
    row_column,
)


def named(board_or_cells) -> set:
    if isinstance(board_or_cells, int):
        board_or_cells = cells(board_or_cells)
    return {notation(cell) for cell in board_or_cells}


class TestGeometry(unittest.TestCase):
    def test_a1_is_the_top_left(self):
        self.assertEqual(notation(0), "a1")
        self.assertEqual(notation(index(0, 7)), "h1")
        self.assertEqual(notation(index(7, 0)), "a8")
        self.assertEqual(notation(63), "h8")

    def test_row_and_column_round_trip(self):
        for cell in range(SIZE * SIZE):
            self.assertEqual(index(*row_column(cell)), cell)

    def test_a_pass_has_its_own_notation(self):
        self.assertEqual(notation(PASS), "--")


class TestOpening(unittest.TestCase):
    def test_the_four_discs_are_where_the_rules_put_them(self):
        self.assertEqual(named(OPENING.dark), {"e4", "d5"})
        self.assertEqual(named(OPENING.light), {"d4", "e5"})
        self.assertEqual(OPENING.turn, DARK)

    def test_dark_has_exactly_four_moves(self):
        self.assertEqual(named(OPENING.moves()), {"d3", "c4", "f5", "e6"})

    def test_the_board_starts_level(self):
        self.assertEqual(OPENING.counts(), (2, 2))
        self.assertEqual(OPENING.empties(), 60)


class TestPlaying(unittest.TestCase):
    def test_a_move_flips_the_line_it_closes(self):
        after = OPENING.play(index(2, 3))  # d3, closing on d5 through d4
        self.assertEqual(named(after.dark), {"d3", "d4", "e4", "d5"})
        self.assertEqual(named(after.light), {"e5"})
        self.assertEqual(after.turn, LIGHT)

    def test_the_turn_changes_hands(self):
        self.assertEqual(OPENING.play(index(2, 3)).turn, LIGHT)

    def test_an_empty_square_that_closes_nothing_is_not_a_move(self):
        self.assertFalse(OPENING.is_legal(index(0, 0)))
        with self.assertRaises(ValueError):
            OPENING.play(index(0, 0))

    def test_an_occupied_square_is_not_a_move(self):
        self.assertFalse(OPENING.is_legal(index(3, 3)))

    def test_a_square_off_the_board_is_not_a_move(self):
        self.assertFalse(OPENING.is_legal(-1))
        self.assertFalse(OPENING.is_legal(64))

    def test_one_move_can_flip_in_two_directions(self):
        # A dark disc played at the middle of a cross of light discs, with dark
        # behind two of the arms.
        dark = (1 << index(4, 2)) | (1 << index(2, 4))
        light = (1 << index(4, 3)) | (1 << index(3, 4))
        turned = Position(dark, light, DARK).flipped_by(index(4, 4))
        self.assertEqual(named(turned), {"d5", "e4"})

    def test_a_line_that_runs_off_the_edge_flips_nothing(self):
        """The mask on every shift exists for this.

        Light on h4, dark playing g4: east of h4 is the edge, and without the
        file mask it would be a1 of the next rank -- so a wrapped board would
        find one of dark's own discs there and flip h4 for free.
        """
        dark = (1 << index(3, 0)) | (1 << index(4, 0))
        light = 1 << index(3, 7)
        position = Position(dark, light, DARK)
        self.assertNotIn("g4", named(position.moves()))

    def test_no_move_wraps_from_one_rank_to_the_next(self):
        # Dark a2, light h1: nothing dark plays may flip h1, which is only
        # adjacent to a2 if the board is treated as one long line of 64.
        position = Position(1 << index(1, 0), 1 << index(0, 7), DARK)
        for cell in position.legal():
            self.assertNotIn("h1", named(position.flipped_by(cell)))


class TestEndings(unittest.TestCase):
    def test_a_side_with_nothing_to_play_must_pass(self):
        # Light on b1 with dark on a1 behind it: every line from b1 runs into
        # the edge or into empty squares.
        position = Position(1 << index(0, 0), 1 << index(0, 1), LIGHT)
        self.assertTrue(position.must_pass())
        self.assertFalse(position.is_over())

    def test_a_game_can_end_with_the_board_half_empty(self):
        """Over means neither side can move, not that the board is full.

        Counting squares instead of moves is a bug people actually ship, and it
        leaves the loser staring at a board nobody can play on.
        """
        position = Position(1 << index(0, 0), 0, DARK)
        self.assertTrue(position.is_over())
        self.assertEqual(position.empties(), 63)

    def test_the_side_with_more_discs_wins(self):
        self.assertEqual(Position(0b111, 0b1000).winner(), DARK)
        self.assertEqual(Position(0b1, 0b110).winner(), LIGHT)
        self.assertIsNone(Position(0b1, 0b10).winner())


class TestGameRecord(unittest.TestCase):
    def test_a_game_records_what_was_played(self):
        game = Game()
        game.play(index(2, 3))
        self.assertEqual(game.moves, [index(2, 3)])
        self.assertEqual(game.last_move(), index(2, 3))

    def test_a_pass_is_recorded_like_any_other_turn(self):
        """It has to be: the move list is the saved game, and a replay that
        invented its own passes would be a second copy of the rule."""
        game = Game(_playout(3))
        self.assertIn(PASS, game.moves)
        self.assertEqual(Game(game.moves).position, game.position)

    def test_the_last_move_skips_over_passes(self):
        game = Game()
        game.play(index(2, 3))
        game.moves.append(PASS)
        self.assertEqual(game.last_move(), index(2, 3))

    def test_replaying_a_finished_game_reaches_the_same_board(self):
        moves = _playout(1)
        self.assertEqual(Game(moves).position, Game(list(moves)).position)

    def test_undo_puts_the_board_back(self):
        game = Game()
        game.play(index(2, 3))
        self.assertTrue(game.undo())
        self.assertEqual(game.position, OPENING)
        self.assertEqual(game.moves, [])

    def test_undo_at_the_opening_does_nothing(self):
        self.assertFalse(Game().undo())

    def test_undo_takes_any_passes_with_it(self):
        game = Game(_playout(3))
        before = len(game.moves)
        game.undo()
        self.assertLess(len(game.moves), before)
        self.assertNotEqual(game.moves[-1:], [PASS])

    def test_a_takeback_hands_the_board_back_to_the_same_side(self):
        game = Game()
        game.play(index(2, 3))  # dark
        game.play(game.position.legal()[0])  # light answers
        self.assertTrue(game.takeback(DARK))
        self.assertEqual(game.turn, DARK)

    def test_a_takeback_with_nothing_to_take_back_says_so(self):
        self.assertFalse(Game().takeback(DARK))


class TestPlayouts(unittest.TestCase):
    """Properties that have to hold for every game, checked over several."""

    def test_every_game_ends_and_the_discs_add_up(self):
        for seed in range(8):
            game = Game(_playout(seed))
            dark, light = game.position.counts()
            self.assertTrue(game.over)
            self.assertLessEqual(dark + light, SIZE * SIZE)
            self.assertEqual(dark + light + game.position.empties(), SIZE * SIZE)

    def test_neither_side_ever_holds_a_square_twice(self):
        for seed in range(4):
            game = Game()
            for cell in _playout(seed):
                if cell != PASS:
                    game.play(cell)
                    self.assertFalse(game.position.dark & game.position.light)

    def test_a_corner_never_changes_hands(self):
        """The one permanent fact on the board, and the whole reason the
        evaluation in ai.py treats corners the way it does."""
        for seed in range(4):
            game, held = Game(), {}
            for cell in _playout(seed):
                if cell == PASS:
                    continue
                game.play(cell)
                for corner in cells(CORNERS):
                    bit = 1 << corner
                    if game.position.dark & bit:
                        owner = DARK
                    elif game.position.light & bit:
                        owner = LIGHT
                    else:
                        continue
                    self.assertEqual(held.setdefault(corner, owner), owner)

    def test_every_move_played_flips_at_least_one_disc(self):
        game = Game()
        for cell in _playout(5):
            if cell == PASS:
                continue
            self.assertTrue(game.position.flipped_by(cell))
            game.play(cell)


def _playout(seed: int) -> list[int]:
    """A whole game of legal random moves. Deterministic, so a failure repeats."""
    rng = random.Random(seed)
    game = Game()
    while not game.over:
        game.play(rng.choice(game.position.legal()))
    return list(game.moves)


class TestMoveGeneration(unittest.TestCase):
    def test_a_move_is_always_on_an_empty_square(self):
        for seed in range(4):
            game = Game()
            for cell in _playout(seed):
                if cell == PASS:
                    continue
                occupied = game.position.dark | game.position.light
                self.assertFalse(game.position.moves() & occupied)
                game.play(cell)

    def test_a_side_with_no_discs_has_no_moves(self):
        self.assertEqual(legal_moves(0, OPENING.light), 0)


if __name__ == "__main__":
    unittest.main()
