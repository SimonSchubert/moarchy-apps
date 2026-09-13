"""The solver, and the claim every figure in this app makes.

This is the test the app's content depends on. `pegs.py` ships nine figures and
says of each one that it can be reduced to a single peg, and of five of them
that the last peg can be made to land in the middle. Neither claim is visible in
a picture of a board: a figure that cannot be finished looks exactly like one
that can, which is the whole reason this app has a solver in the first place.

So both claims are checked by solving all nine, on every run, in about a fifth
of a second -- and the solutions are replayed through the rules afterwards,
because a solver that agreed with itself about an illegal jump would pass a test
that only asked whether it had found something.
"""

import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_pegsolitaire.pegs import (  # noqa: E402
    CENTRE,
    FIGURES,
    Game,
    Position,
    figure_for,
)
from moarchy_pegsolitaire.solver import (  # noqa: E402
    IMPOSSIBLE,
    SOLVED,
    UNKNOWN,
    search,
    solve,
)

# Generous, because a failure here is a figure nobody can finish and a pass is
# worth waiting for. Nothing in the app ever asks for more than two seconds.
PATIENCE = 40.0


class EveryFigureCanBeFinished(unittest.TestCase):
    def test_every_figure_reduces_to_one_peg(self):
        for figure in FIGURES:
            line = solve(figure.start(), -1, PATIENCE)
            self.assertIsNotNone(line, f"{figure.key} cannot be finished")
            game = Game(figure, line)
            self.assertEqual(game.count, 1, figure.key)

    def test_the_middle_is_claimed_only_where_it_can_be_reached(self):
        for figure in FIGURES:
            line = solve(figure.start(), CENTRE, PATIENCE)
            reachable = line is not None
            self.assertEqual(
                reachable,
                figure.centre,
                f"{figure.key} says centre={figure.centre} and it is {reachable}",
            )
            if reachable:
                game = Game(figure, line)
                self.assertTrue(game.perfect, figure.key)

    def test_a_solution_is_a_legal_game(self):
        # Replayed through the rules rather than trusted. A solver that made its
        # own illegal jump would find a line for every figure ever written.
        figure = figure_for("goblet")
        line = solve(figure.start(), CENTRE, PATIENCE)
        game = Game(figure)
        for move in line:
            self.assertTrue(game.play(move), f"{move} would not play")
        self.assertTrue(game.perfect)


class WhatTheSearchWillSay(unittest.TestCase):
    def test_it_proves_a_dead_position_dead(self):
        # Two pegs too far apart to reach each other. There is nothing to search
        # and the answer is a proof rather than a guess, which is the whole
        # point of the hint.
        holes = figure_for("english").holes
        position = Position(holes, (1 << 14) | (1 << 34))
        answer = search(position, -1, seconds=PATIENCE)
        self.assertEqual(answer.verdict, IMPOSSIBLE)
        self.assertIsNone(answer.move)

    def test_it_answers_at_once_when_the_board_is_already_finished(self):
        holes = figure_for("english").holes
        self.assertEqual(search(Position(holes, 1 << CENTRE), CENTRE).verdict, SOLVED)
        self.assertEqual(search(Position(holes, 1 << 14), CENTRE).verdict, IMPOSSIBLE)

    def test_it_gives_up_rather_than_running_on(self):
        # A clock of nothing at all. The answer has to be "no answer", not a
        # wrong one and not a wait -- a phone that has stopped answering is the
        # failure this budget exists to prevent.
        answer = search(figure_for("english").start(), CENTRE, seconds=0.0)
        self.assertEqual(answer.verdict, UNKNOWN)
        self.assertIsNone(answer.move)

    def test_the_line_it_returns_starts_at_the_move_it_offers(self):
        answer = search(figure_for("plus").start(), CENTRE, seconds=PATIENCE)
        self.assertEqual(answer.verdict, SOLVED)
        self.assertEqual(answer.move, answer.line[0])
        game = Game("plus", answer.line)
        self.assertTrue(game.perfect)

    def test_a_hint_followed_leaves_a_line_that_still_solves(self):
        # The window keeps the rest of a line and offers it again for nothing.
        # That is only sound if the tail of a solution is a solution.
        figure = figure_for("diamond")
        answer = search(figure.start(), CENTRE, seconds=PATIENCE)
        game = Game(figure)
        for move in answer.line:
            self.assertTrue(game.position.is_legal(move))
            game.play(move)
        self.assertTrue(game.perfect)

    def test_the_english_board_is_solved_inside_the_apps_own_clock(self):
        # Two seconds is what the Hint button allows, and the opening position
        # of the whole board is the worst case it will ever be asked about.
        answer = search(figure_for("english").start(), CENTRE, seconds=2.0)
        self.assertEqual(answer.verdict, SOLVED)


if __name__ == "__main__":
    unittest.main()
