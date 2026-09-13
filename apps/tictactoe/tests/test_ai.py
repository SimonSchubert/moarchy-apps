"""The opponent. No GTK, so these run anywhere too.

The test that matters is the one at the bottom: the three levels have to stay
ordered by strength. It is the only property of an opponent a person can feel,
it is the one a tweak to any of the numbers in ai.py can quietly break, and no
amount of looking at the code says whether it still holds.

The games here are played with a fixed seed, so a failure is reproducible and a
pass is not luck.
"""

import random
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_tictactoe import ai  # noqa: E402
from moarchy_tictactoe.tictactoe import EMPTY, O, X, Game, Position  # noqa: E402

# Every reachable position, which is a number this game is famous for.
REACHABLE = 5478


def play(computer: int, level, rng, opponent=None) -> Game:
    """One game: `computer` is the level's mark, the other side is `opponent`.

    `opponent` defaults to a player that taps at random, which is the honest
    model of somebody not paying attention on a bus and the only opponent an
    easy level is meant to be able to lose to.
    """
    game = Game()
    while not game.over:
        if game.turn == computer:
            cell = ai.choose(game.position, level, rng)
        elif opponent is None:
            cell = rng.choice(game.position.legal())
        else:
            cell = ai.choose(game.position, opponent, rng)
        game.play(cell)
    return game


def outcomes(level, rng, games=240, opponent=None) -> dict[str, int]:
    tally = {"won": 0, "lost": 0, "drawn": 0}
    for number in range(games):
        computer = X if number % 2 else O
        winner = play(computer, level, rng, opponent).position.winner()
        if winner is None:
            tally["drawn"] += 1
        elif winner == computer:
            tally["won"] += 1
        else:
            tally["lost"] += 1
    return tally


class TheTable(unittest.TestCase):
    def test_the_whole_game_is_solved_and_it_is_the_size_it_should_be(self):
        # Cleared first, because the table is a module global shared with every
        # other test in this file and the count is the whole point of this one:
        # 5,478 is how many positions this game can reach, and a table that had
        # picked up a board from somewhere else would quietly not be it.
        ai._SOLVED.clear()
        self.assertEqual(ai.warm(), REACHABLE)

    def test_an_empty_board_is_worth_a_draw(self):
        self.assertEqual(ai.value(EMPTY), ai.DRAW)

    def test_a_won_board_is_a_loss_for_whoever_is_to_move(self):
        # X played 0, 1, 2 against O's 3 and 4, so O is to play on a board it
        # has already lost. Nothing it does helps.
        position = Position(x=0b111, o=0b11000, turn=O)
        self.assertLess(ai.value(position), 0)

    def test_a_win_in_one_beats_a_win_in_three(self):
        # Both are wins; the value carries the distance so that a solved player
        # finishes rather than dawdling, and so that a lost one plays on.
        soon = Position(x=0b011, o=0b011000, turn=X)
        self.assertGreater(ai.value(soon), ai.WIN)


class TheMoves(unittest.TestCase):
    def setUp(self):
        self.rng = random.Random(11)

    def test_every_move_offered_is_a_legal_one(self):
        for level in ai.LEVELS:
            game = Game()
            while not game.over:
                cell = ai.choose(game.position, level, self.rng)
                self.assertTrue(game.position.is_legal(cell), f"{level.key} {cell}")
                game.play(cell)

    def test_a_finished_board_has_no_move_to_offer(self):
        game = Game([0, 3, 1, 4, 2])
        self.assertTrue(game.over)
        self.assertEqual(ai.choose(game.position, ai.level_for("perfect")), -1)

    def test_the_only_move_on_the_board_is_played_without_thinking(self):
        game = Game([0, 4, 8, 2, 6, 3, 5, 1])
        self.assertEqual(len(game.position.legal()), 1)
        for level in ai.LEVELS:
            self.assertEqual(
                ai.choose(game.position, level, self.rng), game.position.legal()[0]
            )

    def test_an_unknown_level_is_the_middle_one(self):
        self.assertEqual(ai.level_for("nonsense").key, "fair")

    def test_perfect_opens_where_a_mistake_is_most_likely(self):
        # A corner. Every reply to it loses except the centre, which is more
        # ways to go wrong than any other opening leaves -- and against two
        # perfect players every opening draws, so there is nothing else to
        # choose on.
        self.assertIn(ai.best(EMPTY)[0], (0, 2, 6, 8))


class WhatALevelSees(unittest.TestCase):
    def setUp(self):
        self.rng = random.Random(3)

    def test_every_level_takes_a_win_it_is_handed(self):
        # X to play with 0 and 1: 2 wins immediately. A level that plays
        # anything else does not read as easy, it reads as broken.
        position = Position(x=0b011, o=0b011000, turn=X)
        for level in ai.LEVELS:
            for _ in range(40):
                self.assertEqual(ai.choose(position, level, self.rng), 2)

    def test_easy_will_walk_past_a_threat_and_fair_will_not(self):
        # O to play; X threatens 2. Fair blocks it, Easy often does not.
        position = Position(x=0b011, o=0b1000, turn=O)
        easy = sum(
            ai.choose(position, ai.level_for("easy"), self.rng) != 2 for _ in range(200)
        )
        fair = sum(
            ai.choose(position, ai.level_for("fair"), self.rng) != 2 for _ in range(200)
        )
        self.assertGreater(easy, 40, "Easy never misses a threat")
        self.assertEqual(fair, 0, "Fair walked past a threat it can see")

    def test_perfect_never_plays_a_careless_move(self):
        self.assertEqual(ai.level_for("perfect").careless, 0.0)


class TheLevelsAreOrdered(unittest.TestCase):
    """The one property somebody can feel, and the one a tweak can break."""

    def setUp(self):
        self.rng = random.Random(20260913)

    def test_perfect_never_loses_a_game_from_either_side(self):
        tally = outcomes(ai.level_for("perfect"), self.rng, games=400)
        self.assertEqual(tally["lost"], 0, tally)

    def test_perfect_against_perfect_is_always_a_draw(self):
        perfect = ai.level_for("perfect")
        for _ in range(30):
            game = play(X, perfect, self.rng, opponent=perfect)
            self.assertIsNone(game.position.winner())

    def test_each_level_loses_more_often_than_the_one_above_it(self):
        easy = outcomes(ai.level_for("easy"), self.rng)
        fair = outcomes(ai.level_for("fair"), self.rng)
        self.assertGreater(easy["lost"], fair["lost"], f"{easy} {fair}")
        self.assertGreater(fair["lost"], 0, "Fair never loses, which is not fair")

    def test_easy_still_wins_most_of_its_games_against_a_random_player(self):
        # Easy is meant to be beatable, not hopeless: it still finishes you off
        # when you leave it a win, which against random taps is most games.
        easy = outcomes(ai.level_for("easy"), self.rng)
        self.assertGreater(easy["won"], easy["lost"], easy)


if __name__ == "__main__":
    unittest.main()
