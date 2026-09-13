"""The rules. No GTK, so these run on any machine with a Python.

Two of these carry more weight than the rest. **The same seed puts the same
mines back** is what makes the saved game a seed rather than a list of mines,
and if it ever stopped being true a person would come back to a board whose
numbers no longer described what was under it. **The first tap is never a mine
and never a number** is the oldest fairness rule in this game, and it is the one
an implementation quietly gets half right -- avoiding the tapped cell and not
the eight around it, which produces a first tap that opens a lone 4.
"""

import random
import sys
import unittest
from itertools import pairwise
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_minesweeper.minesweeper import (  # noqa: E402
    CHORD,
    FLAG,
    LEVELS,
    OPEN,
    Field,
    Game,
    Level,
    around,
    index,
    level_for,
    place,
    row_column,
)

# A small hand-made board, so that a test about the rules is not also a test
# about where a seed happened to put things.
#
#   . . . . .      * is a mine, the rest are empty
#   . * . . .
#   . . . . .
#   . . . * .
#   . . . . .
TINY = Level("tiny", "Tiny", 5, 5, 2)
MINES = frozenset({index(1, 1, 5), index(3, 3, 5)})


def hand_made() -> Game:
    game = Game(TINY, 0)
    game.field = Field(TINY, MINES)
    return game


class TheGeometry(unittest.TestCase):
    def test_indexing_round_trips(self):
        for cell in range(TINY.cells):
            self.assertEqual(index(*row_column(cell, 5), 5), cell)

    def test_a_middle_cell_touches_eight_and_a_corner_touches_three(self):
        self.assertEqual(len(around(index(2, 2, 5), 5, 5)), 8)
        self.assertEqual(len(around(index(0, 0, 5), 5, 5)), 3)
        self.assertEqual(len(around(index(0, 2, 5), 5, 5)), 5)

    def test_neighbours_do_not_wrap_round_the_edge(self):
        # The cell at the right-hand end of a row must not touch the left-hand
        # end of the next one, which is what index arithmetic does if the column
        # is not checked.
        near = around(index(2, 4, 5), 5, 5)
        for cell in near:
            self.assertIn(row_column(cell, 5)[1], (3, 4))


class TheNumbers(unittest.TestCase):
    def test_a_cell_counts_the_mines_touching_it(self):
        field = Field(TINY, MINES)
        self.assertEqual(field.count(index(0, 0, 5)), 1)
        self.assertEqual(field.count(index(2, 2, 5)), 2)
        self.assertEqual(field.count(index(0, 4, 5)), 0)
        self.assertEqual(field.count(index(1, 1, 5)), 0)  # the mine itself


class TheFirstTap(unittest.TestCase):
    def test_it_is_never_a_mine_and_never_a_number(self):
        for level in LEVELS:
            for seed in range(25):
                first = seed * 7 % level.cells
                mines = place(level, seed, first)
                self.assertEqual(len(mines), level.mines, level.key)
                self.assertNotIn(first, mines)
                for near in around(first, level.width, level.height):
                    self.assertNotIn(near, mines, f"{level.key} seed {seed}")

    def test_so_the_first_tap_always_floods(self):
        for level in LEVELS:
            game = Game(level, 4)
            game.tap(index(level.height // 2, level.width // 2, level.width))
            self.assertGreater(len(game.opened), 9, level.key)
            self.assertFalse(game.lost)

    def test_the_same_seed_puts_the_same_mines_back(self):
        # The guarantee the saved game rests on. The shuffle is written out in
        # minesweeper.py on top of random(), which is the one thing CPython
        # promises will keep producing the same stream.
        for level in LEVELS:
            for first in (0, 17, level.cells - 1):
                once = place(level, 987654, first)
                twice = place(level, 987654, first)
                self.assertEqual(once, twice)
        self.assertNotEqual(place(LEVELS[0], 1, 0), place(LEVELS[0], 2, 0))

    def test_a_different_first_tap_is_a_different_board(self):
        level = LEVELS[0]
        self.assertNotEqual(place(level, 5, 0), place(level, 5, level.cells - 1))


class Opening(unittest.TestCase):
    def test_an_empty_cell_opens_everything_it_leads_to(self):
        game = hand_made()
        game.tap(index(0, 4, 5))
        # The whole right-hand and top of the board, stopped by the numbers
        # round the mines.
        self.assertIn(index(0, 4, 5), game.opened)
        self.assertIn(index(0, 2, 5), game.opened)
        self.assertNotIn(index(1, 1, 5), game.opened)

    def test_a_numbered_cell_opens_only_itself(self):
        game = hand_made()
        game.tap(index(0, 0, 5))
        self.assertEqual(game.opened, {index(0, 0, 5)})

    def test_a_flagged_cell_does_not_open(self):
        game = hand_made()
        cell = index(0, 0, 5)
        game.mark(cell)
        self.assertFalse(game.tap(cell))
        self.assertNotIn(cell, game.opened)

    def test_opening_a_mine_ends_it(self):
        game = hand_made()
        game.tap(index(1, 1, 5))
        self.assertTrue(game.lost)
        self.assertEqual(game.boom, index(1, 1, 5))
        self.assertTrue(game.over)
        self.assertFalse(game.won)

    def test_nothing_happens_after_it_is_over(self):
        game = hand_made()
        game.tap(index(1, 1, 5))
        self.assertFalse(game.tap(index(4, 4, 5)))
        self.assertFalse(game.mark(index(4, 4, 5)))

    def test_opening_every_safe_cell_wins(self):
        game = hand_made()
        for cell in range(TINY.cells):
            if cell not in MINES:
                game.tap(cell)
        self.assertTrue(game.won)
        self.assertFalse(game.lost)
        self.assertTrue(game.over)

    def test_the_mines_do_not_have_to_be_flagged_to_win(self):
        game = hand_made()
        for cell in range(TINY.cells):
            if cell not in MINES:
                game.tap(cell)
        self.assertEqual(game.flags, set())
        self.assertTrue(game.won)


class Flagging(unittest.TestCase):
    def test_a_flag_goes_on_and_comes_off(self):
        game = hand_made()
        cell = index(0, 0, 5)
        game.mark(cell)
        self.assertIn(cell, game.flags)
        game.mark(cell)
        self.assertNotIn(cell, game.flags)

    def test_an_opened_cell_cannot_be_flagged(self):
        game = hand_made()
        cell = index(0, 0, 5)
        game.tap(cell)
        self.assertFalse(game.mark(cell))

    def test_the_count_goes_negative_rather_than_lying(self):
        game = hand_made()
        for cell in (0, 1, 2):
            game.mark(cell)
        self.assertEqual(game.remaining, -1)

    def test_a_flag_with_nothing_under_it_is_named_once_it_is_over(self):
        game = hand_made()
        game.mark(index(0, 0, 5))
        self.assertEqual(game.wrong_flags(), {index(0, 0, 5)})
        game.mark(index(1, 1, 5))
        self.assertEqual(game.wrong_flags(), {index(0, 0, 5)})


class Chording(unittest.TestCase):
    def test_a_number_with_its_flags_opens_the_rest(self):
        game = hand_made()
        corner = index(0, 0, 5)
        game.tap(corner)
        game.mark(index(1, 1, 5))
        self.assertTrue(game.satisfied(corner))
        self.assertTrue(game.clear_around(corner))
        self.assertIn(index(0, 1, 5), game.opened)
        self.assertIn(index(1, 0, 5), game.opened)
        self.assertFalse(game.lost)

    def test_a_number_without_its_flags_opens_nothing(self):
        game = hand_made()
        corner = index(0, 0, 5)
        game.tap(corner)
        self.assertFalse(game.satisfied(corner))
        self.assertFalse(game.clear_around(corner))
        self.assertEqual(game.opened, {corner})

    def test_a_chord_on_a_wrongly_flagged_number_ends_it(self):
        # The one way chording can lose a game, and it should: the flags were
        # wrong, and the person said so by chording.
        game = hand_made()
        corner = index(0, 0, 5)
        game.tap(corner)
        game.mark(index(0, 1, 5))
        self.assertTrue(game.satisfied(corner))
        game.clear_around(corner)
        self.assertTrue(game.lost)

    def test_a_zero_and_a_covered_cell_cannot_be_chorded(self):
        game = hand_made()
        game.tap(index(0, 4, 5))
        self.assertFalse(game.clear_around(index(0, 4, 5)))
        self.assertFalse(game.clear_around(index(4, 0, 5)))


class TheMoveList(unittest.TestCase):
    def test_a_game_replays_to_the_same_board(self):
        level = level_for("gentle")
        game = Game(level, 321)
        rng = random.Random(2)
        game.tap(index(5, 4, level.width))
        for _ in range(12):
            safe = [
                c
                for c in range(level.cells)
                if c not in game.opened and not game.is_mine(c)
            ]
            if not safe:
                break
            game.tap(rng.choice(safe))
        again = Game(level, 321, list(game.moves))
        self.assertEqual(again.opened, game.opened)
        self.assertEqual(again.flags, game.flags)
        self.assertEqual(again.field.mines, game.field.mines)

    def test_a_tap_that_changes_nothing_is_not_recorded(self):
        game = hand_made()
        cell = index(0, 0, 5)
        game.tap(cell)
        before = list(game.moves)
        game.tap(cell)
        self.assertEqual(game.moves, before)

    def test_junk_in_the_move_list_ends_the_game_there(self):
        level = level_for("gentle")
        game = Game(level, 5)
        game.tap(index(4, 4, level.width))
        good = list(game.moves)
        back = Game.resume(level, 5, [*good, 99999, *good])
        self.assertEqual(back.moves, good)

    def test_a_move_survives_being_a_number(self):
        for cell in (0, 17, 79):
            for action in (OPEN, FLAG, CHORD):
                self.assertEqual(Game.decode(Game.encode(cell, action)), (cell, action))


class TheLevels(unittest.TestCase):
    def test_they_fit_a_portrait_screen(self):
        for level in LEVELS:
            self.assertLessEqual(level.width, 12, level.key)
            self.assertGreaterEqual(level.height, level.width, level.key)
            # 344px of board across a 360px screen.
            self.assertGreaterEqual(344 / level.width, 28, level.key)

    def test_the_densities_are_the_classic_ones(self):
        for level in LEVELS:
            self.assertGreater(level.density, 0.10, level.key)
            self.assertLess(level.density, 0.23, level.key)

    def test_they_get_harder_in_order(self):
        for easier, harder in pairwise(LEVELS):
            self.assertLess(easier.cells, harder.cells)
            self.assertLess(easier.mines, harder.mines)

    def test_an_unknown_level_is_the_middle_one(self):
        self.assertEqual(level_for("nonsense").key, "standard")


if __name__ == "__main__":
    unittest.main()
