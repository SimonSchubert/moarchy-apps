"""The opponent.

Two kinds of claim are checked here. The cheap ones -- a legal move, a forced
move, the clock -- are ordinary unit tests. The expensive one is that the levels
are actually ordered by strength, which cannot be asserted about a position and
has to be played out; those games use a shortened clock so the suite stays quick
enough to run on every change, and fixed seeds so a failure repeats.
"""

import random
import sys
import time
import unittest
from dataclasses import replace
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_reversi import ai  # noqa: E402
from moarchy_reversi.reversi import (  # noqa: E402
    DARK,
    LIGHT,
    OPENING,
    PASS,
    Game,
    Position,
    index,
)


def _wound_down(seed: int, empties: int) -> Game:
    """A game played on until only this many squares are left."""
    rng = random.Random(seed)
    game = Game()
    while game.position.empties() > empties and not game.over:
        game.play(rng.choice(game.position.legal()))
    return game


def midgame(seed: int, plies: int) -> Position:
    rng = random.Random(seed)
    game = Game()
    while len(game.moves) < plies and not game.over:
        game.play(rng.choice(game.position.legal()))
    return game.position


class TestLevels(unittest.TestCase):
    def test_the_levels_are_distinct_and_ordered(self):
        self.assertEqual(len(set(ai.LEVEL_KEYS)), len(ai.LEVELS))
        depths = [level.depth for level in ai.LEVELS]
        self.assertEqual(depths, sorted(depths))

    def test_an_easier_level_is_readier_to_play_a_worse_move(self):
        slack = [level.slack for level in ai.LEVELS]
        self.assertEqual(slack, sorted(slack, reverse=True))
        self.assertEqual(ai.LEVELS[-1].slack, 0)

    def test_the_default_level_exists(self):
        self.assertIn(ai.DEFAULT_LEVEL, ai.LEVEL_KEYS)

    def test_an_unknown_level_still_gives_a_level(self):
        self.assertIn(ai.level_for("impossible"), ai.LEVELS)


class TestEvaluation(unittest.TestCase):
    def test_a_corner_is_worth_more_than_the_square_that_gives_one_away(self):
        """The whole of the app's opening and middlegame judgement is this
        table being the right way round."""
        corner = Position(1 << index(0, 0), 1 << index(3, 3))
        x_square = Position(1 << index(1, 1), 1 << index(3, 3))
        self.assertGreater(
            ai.evaluate(corner.dark, corner.light),
            ai.evaluate(x_square.dark, x_square.light),
        )

    def test_a_finished_game_outranks_any_arrangement_of_discs(self):
        """However good a board looks, a won one is better and a lost one is
        worse -- otherwise the search trades the game for a tidy position."""
        self.assertGreater(ai.terminal(0xFFFFFFFFFFFFFFFF, 0), ai.WIN)
        self.assertLess(ai.terminal(0, 0xFFFFFFFFFFFFFFFF), -ai.WIN)
        self.assertEqual(ai.terminal(0xFFFFFFFF, 0xFFFFFFFF << 32), 0)
        best = max(
            ai.evaluate(m.dark, m.light) for m in (midgame(s, 30) for s in range(6))
        )
        self.assertGreater(ai.terminal(0xFFFFFFFFFFFFFFFF, 0), best)

    def test_the_evaluation_is_symmetrical(self):
        position = midgame(4, 20)
        self.assertEqual(
            ai.evaluate(position.own, position.opp),
            -ai.evaluate(position.opp, position.own),
        )


class TestChoosing(unittest.TestCase):
    def test_every_level_returns_a_legal_move(self):
        for level in ai.LEVELS:
            # On a short clock: this is about every level answering with a
            # legal move, not about how long each one is allowed to take.
            quick = replace(level, seconds=0.05)
            for seed in range(3):
                position = midgame(seed, 14)
                cell = ai.choose(position, quick, rng=random.Random(seed))
                self.assertTrue(
                    position.is_legal(cell),
                    f"{level.key} played an illegal move from seed {seed}",
                )

    def test_a_forced_move_is_played_without_thinking_about_it(self):
        # A position with one legal move: dark on c1, light on b1, a1 empty.
        position = Position(1 << index(0, 2), 1 << index(0, 1), DARK)
        self.assertEqual(len(position.legal()), 1)
        thought = ai.think(position, ai.level_for("hard"))
        self.assertEqual(thought.cell, index(0, 0))
        self.assertEqual(thought.nodes, 0)

    def test_a_side_with_no_move_is_told_to_pass(self):
        position = Position(1 << index(0, 0), 1 << index(0, 1), LIGHT)
        self.assertEqual(ai.think(position, ai.level_for("easy")).cell, PASS)

    def test_a_whole_game_of_legal_moves(self):
        rng = random.Random(11)
        game = Game()
        level = ai.level_for("easy")
        while not game.over:
            cell = ai.choose(game.position, level, rng=rng)
            self.assertTrue(game.position.is_legal(cell))
            game.play(cell)


class TestTheClock(unittest.TestCase):
    """The reason a level names seconds rather than only a depth."""

    def test_a_deep_level_on_a_short_clock_still_answers(self):
        position = midgame(2, 16)
        level = ai.Level("test", "Test", "", depth=20, seconds=0.05, slack=0)
        started = time.monotonic()
        thought = ai.think(position, level)
        self.assertLess(time.monotonic() - started, 2.0)
        self.assertTrue(position.is_legal(thought.cell))

    def test_more_time_buys_more_depth(self):
        position = midgame(2, 16)
        hurried = ai.Level("a", "A", "", depth=8, seconds=0.01, slack=0)
        patient = ai.Level("b", "B", "", depth=8, seconds=0.5, slack=0)
        self.assertLess(
            ai.think(position, hurried).depth, ai.think(position, patient).depth
        )

    def test_the_endgame_is_played_out_rather_than_evaluated(self):
        """Past a dozen empty squares the depth cap gives way, so the last
        moves are known rather than guessed at."""
        # Nine squares left: comfortably inside the window, and a position the
        # search can finish while this suite is still quick.
        game = _wound_down(6, ai.EXACT_FROM - 3)
        hard = replace(ai.level_for("hard"), seconds=0.5)
        self.assertGreater(ai.think(game.position, hard).depth, hard.depth)

    def test_only_the_level_that_asks_for_it_plays_the_endgame_out(self):
        game = _wound_down(6, ai.EXACT_FROM - 3)
        easy = ai.level_for("easy")
        self.assertFalse(easy.exact)
        self.assertLessEqual(ai.think(game.position, easy).depth, easy.depth)


class TestStrength(unittest.TestCase):
    """The levels are meant to differ in strength, not only in patience."""

    def test_hard_beats_easy_from_either_side(self):
        hard = ai.Level("h", "Hard", "", depth=4, seconds=0.05, slack=0)
        easy = ai.level_for("easy")
        for seed, strong in ((0, DARK), (1, LIGHT)):
            rng = random.Random(seed)
            game = Game()
            while not game.over:
                level = hard if game.turn == strong else easy
                game.play(ai.choose(game.position, level, rng=rng))
            self.assertEqual(
                game.position.winner(),
                strong,
                f"easy won game {seed}: {game.position.counts()}",
            )

    def test_easy_does_not_always_play_the_best_move(self):
        """Its slack is the point: an opponent that never errs is not an easy
        one, it is a strong one that has been given less to think with."""
        position = midgame(3, 12)
        easy = ai.level_for("easy")
        seen = {ai.choose(position, easy, rng=random.Random(s)) for s in range(20)}
        self.assertGreater(len(seen), 1)


class TestOpeningSanity(unittest.TestCase):
    def test_the_four_opening_moves_are_all_the_same_move(self):
        """Reversi's opening is symmetrical: every first move is a rotation of
        the others, so any of them is correct and none of them is a blunder."""
        cell = ai.choose(OPENING, ai.level_for("hard"), rng=random.Random(1))
        self.assertIn(cell, OPENING.legal())


if __name__ == "__main__":
    unittest.main()
