"""The rules. No GTK, so these run on any machine with a Python.

The one worth reading is at the bottom: every figure this app ships is checked
for being a board of the right shape with the right number of pegs on it, drawn
from the art in `pegs.py`. The art is the content of this app, and a typo in a
row of dots is a puzzle nobody can finish and a picture nobody can see is wrong.
"""

import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_pegsolitaire.pegs import (  # noqa: E402
    CELLS,
    CENTRE,
    DOWN,
    FIGURES,
    LEFT,
    RIGHT,
    SIZE,
    UP,
    Game,
    Position,
    decode,
    encode,
    figure_for,
    index,
    notation,
    parse,
    row_column,
)

# Two pegs at the right-hand end of a row, with the row below it empty. A
# rightward jump from the first of them would land on the left-hand end of the
# next row if the shifts were not masked -- which is the classic bitboard bug,
# is legal-looking, and is invisible on a board whose edges are never used.
EDGE = """
.......
.......
.....oo
.......
.......
.......
.......
"""


class TheGeometry(unittest.TestCase):
    def test_indexing_round_trips(self):
        for cell in range(CELLS):
            self.assertEqual(index(*row_column(cell)), cell)

    def test_the_middle_is_where_it_looks(self):
        self.assertEqual(CENTRE, index(3, 3))

    def test_a_move_survives_being_a_number(self):
        for cell in range(CELLS):
            for direction in (UP, DOWN, LEFT, RIGHT):
                self.assertEqual(decode(encode(cell, direction)), (cell, direction))

    def test_a_move_says_what_it_is(self):
        self.assertEqual(notation(encode(index(3, 3), UP)), "d4 up")
        self.assertEqual(notation(encode(index(0, 0), RIGHT)), "a1 right")

    def test_a_jump_does_not_wrap_round_the_edge(self):
        holes, pegs = parse(EDGE)
        position = Position(holes, pegs)
        # Leftwards, back along the row, is the only jump there is.
        self.assertEqual(position.moves(), [encode(index(2, 6), LEFT)])
        self.assertFalse(position.is_legal(encode(index(2, 5), RIGHT)))


class Jumping(unittest.TestCase):
    def setUp(self):
        self.figure = figure_for("english")
        self.position = self.figure.start()

    def test_the_opening_board_has_four_jumps_into_the_middle(self):
        moves = self.position.moves()
        self.assertEqual(len(moves), 4)
        for move in moves:
            self.assertEqual(self.position.landing(move)[1], CENTRE)

    def test_a_jump_takes_the_peg_it_went_over(self):
        move = self.position.moves()[0]
        cell, _ = decode(move)
        over, landed = self.position.landing(move)
        after = self.position.play(move)
        self.assertFalse(after.has_peg(cell))
        self.assertFalse(after.has_peg(over))
        self.assertTrue(after.has_peg(landed))
        self.assertEqual(after.count, self.position.count - 1)

    def test_playing_does_not_change_the_position_played_from(self):
        before = self.position.pegs
        self.position.play(self.position.moves()[0])
        self.assertEqual(self.position.pegs, before)

    def test_an_illegal_jump_raises(self):
        # Nothing to jump over: the hole two along is full, not empty.
        with self.assertRaises(ValueError):
            self.position.play(encode(index(0, 2), DOWN))

    def test_a_jump_off_the_board_is_not_legal(self):
        for move in (encode(-1, UP), encode(CELLS, UP), encode(0, 9)):
            self.assertFalse(self.position.is_legal(move))

    def test_jumps_from_names_only_that_pegs_jumps(self):
        for move in self.position.moves():
            cell, _ = decode(move)
            self.assertIn(move, self.position.jumps_from(cell))
        self.assertEqual(self.position.jumps_from(CENTRE), [])


class Endings(unittest.TestCase):
    def test_a_board_with_no_jumps_is_over(self):
        # Two pegs in opposite corners of the cross: neither can reach the other.
        holes = figure_for("english").holes
        position = Position(holes, (1 << index(2, 0)) | (1 << index(4, 6)))
        self.assertTrue(position.stuck)
        self.assertFalse(position.solved)

    def test_one_peg_is_solved_and_the_middle_one_is_perfect(self):
        holes = figure_for("english").holes
        middle = Position(holes, 1 << CENTRE)
        self.assertTrue(middle.solved)
        self.assertTrue(middle.perfect(CENTRE))
        elsewhere = Position(holes, 1 << index(2, 0))
        self.assertTrue(elsewhere.solved)
        self.assertFalse(elsewhere.perfect(CENTRE))

    def test_perfect_is_only_claimed_where_the_figure_allows_it(self):
        # The Cross can be reduced to one peg and that peg can never be the
        # middle one, so the game must not dangle the middle as a goal.
        game = Game("cross")
        self.assertFalse(game.figure.centre)
        while not game.over:
            game.play(game.position.moves()[0])
        self.assertFalse(game.perfect)


class TheMoveList(unittest.TestCase):
    def test_a_game_is_its_jumps(self):
        game = Game("english")
        first = game.position.moves()[0]
        game.play(first)
        self.assertEqual(game.moves, [first])
        self.assertEqual(game.count, 31)

    def test_resume_keeps_what_will_play_and_drops_the_rest(self):
        game = Game("english")
        good = []
        for _ in range(6):
            move = game.position.moves()[0]
            game.play(move)
            good.append(move)
        back = Game.resume("english", [*good, encode(CENTRE, UP)])
        self.assertEqual(back.moves, good)
        self.assertEqual(back.position, game.position)

    def test_junk_in_the_move_list_ends_the_game_there(self):
        for junk in ([None], ["up"], [True], [0.5]):
            self.assertEqual(Game.resume("english", junk).moves, [])

    def test_an_unknown_figure_is_the_english_board(self):
        self.assertEqual(figure_for("nonsense").key, "english")
        self.assertEqual(Game.resume("nonsense", []).figure.key, "english")

    def test_a_bad_move_in_the_constructor_is_an_error(self):
        with self.assertRaises(ValueError):
            Game("english", [encode(CENTRE, UP)])

    def test_undo_pops_one_and_nothing_from_the_start(self):
        game = Game("english")
        game.play(game.position.moves()[0])
        self.assertTrue(game.undo())
        self.assertEqual(game.position, game.start)
        self.assertFalse(game.undo())


class TheFigures(unittest.TestCase):
    """The art is the content. A typo in it is a puzzle, not a formatting slip."""

    def test_every_figure_is_on_the_same_thirty_three_hole_cross(self):
        for figure in FIGURES:
            holes = figure.holes
            self.assertEqual(holes.bit_count(), 33, figure.key)
            for row in range(SIZE):
                for column in range(SIZE):
                    inside = 2 <= row <= 4 or 2 <= column <= 4
                    self.assertEqual(
                        bool(holes >> index(row, column) & 1),
                        inside,
                        f"{figure.key} at {row},{column}",
                    )

    def test_every_figure_has_at_least_one_jump_in_it(self):
        for figure in FIGURES:
            self.assertTrue(figure.start().moves(), figure.key)

    def test_every_figure_has_a_distinct_key_and_label(self):
        keys = [figure.key for figure in FIGURES]
        labels = [figure.label for figure in FIGURES]
        self.assertEqual(len(set(keys)), len(keys))
        self.assertEqual(len(set(labels)), len(labels))

    def test_the_pegs_a_figure_claims_are_the_pegs_it_has(self):
        counted = {figure.key: figure.pegs.bit_count() for figure in FIGURES}
        self.assertEqual(counted["english"], 32)
        self.assertEqual(counted["cross"], 6)
        self.assertEqual(counted["goblet"], 16)
        for figure in FIGURES:
            self.assertGreater(counted[figure.key], 1, figure.key)
            self.assertLessEqual(counted[figure.key], 32, figure.key)

    def test_a_figure_that_can_finish_in_the_middle_starts_with_it_reachable(self):
        for figure in FIGURES:
            # Not a proof -- test_solver.py does that -- but the cheap half of
            # it: a figure claiming the middle has to have a middle to claim.
            self.assertTrue(figure.start().is_hole(CENTRE), figure.key)


if __name__ == "__main__":
    unittest.main()
