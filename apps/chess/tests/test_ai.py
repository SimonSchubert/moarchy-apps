"""The opponent.

Three kinds of claim. The cheap ones -- takes the free queen, finds the mate,
answers inside the clock -- are ordinary unit tests about one position. The
middling one is that the running evaluation the search carries is the same
number a full count of the board would give, which cannot be asserted about a
position and has to be walked: a drifting total is a search reading a board
nobody is playing, and it would show up as an engine that is subtly, unfixably
bad rather than as anything that looks like a failure.

The expensive one is that the levels are ordered by strength, which has to be
played out. Those games use shortened clocks so the suite stays quick enough to
run on every change, and fixed seeds so a failure repeats.
"""

import random
import sys
import time
import unittest
from dataclasses import replace
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_chess import ai  # noqa: E402
from moarchy_chess.chess import (  # noqa: E402
    BLACK,
    CHECKMATE,
    WHITE,
    Game,
    Position,
    parse_uci,
    uci,
)

QUICK = {"seconds": 0.2}


def level(key: str, **changes) -> ai.Level:
    return replace(ai.level_for(key), **changes)


class Levels(unittest.TestCase):
    def test_every_level_has_a_key_a_file_can_hold(self):
        self.assertEqual(len(set(ai.LEVEL_KEYS)), len(ai.LEVELS))
        self.assertIn(ai.DEFAULT_LEVEL, ai.LEVEL_KEYS)

    def test_an_unknown_key_falls_back_rather_than_raising(self):
        self.assertEqual(ai.level_for("impossible").key, ai.DEFAULT_LEVEL)

    def test_they_get_deeper_and_slower_in_order(self):
        for weaker, stronger in zip(ai.LEVELS, ai.LEVELS[1:]):
            self.assertLess(weaker.depth, stronger.depth)
            self.assertLess(weaker.seconds, stronger.seconds)


class Choosing(unittest.TestCase):
    def test_it_plays_a_legal_move(self):
        position = Position.start()
        for key in ai.LEVEL_KEYS:
            code = ai.choose(position.copy(), level(key, **QUICK), rng=random.Random(1))
            self.assertIn(code, position.moves(), key)

    def test_nothing_to_move_is_no_move(self):
        # Mated: the search is asked for a move on a board that has none.
        position = Position.from_fen("7k/6Q1/5K2/8/8/8/8/8 b - - 0 1")
        self.assertIsNone(ai.choose(position, level("hard", **QUICK)))

    def test_one_legal_move_is_played_without_thinking(self):
        # The queen on h7 holds the seventh rank and the h file, which leaves
        # the king on a8 exactly one square to go to and no check to answer.
        position = Position.from_fen("k7/7Q/8/8/8/8/8/7K b - - 0 1")
        self.assertEqual(len(position.moves()), 1)
        thought = ai.think(position, level("hard"))
        self.assertEqual(thought.nodes, 0)
        self.assertEqual(uci(thought.move), uci(position.moves()[0]))

    def test_the_position_it_was_given_is_not_touched(self):
        """The search plays moves into a board. It had better not be this one."""
        position = Position.start()
        before = position.fen()
        ai.choose(position, level("hard", **QUICK))
        self.assertEqual(position.fen(), before)
        self.assertEqual(len(position.keys), 1)


class Play(unittest.TestCase):
    def test_it_takes_a_free_queen(self):
        position = Position.from_fen("4k3/8/8/3q4/4P3/8/8/4K3 w - - 0 1")
        for key in ("medium", "hard"):
            self.assertEqual(
                uci(ai.choose(position.copy(), level(key, **QUICK))), "e4d5", key
            )

    def test_it_finds_mate_in_one(self):
        position = Position.from_fen("6k1/5ppp/8/8/8/8/8/R3K2R w KQ - 0 1")
        for key in ("medium", "hard"):
            self.assertEqual(
                uci(ai.choose(position.copy(), level(key, **QUICK))), "a1a8", key
            )

    def test_it_gets_out_of_check(self):
        position = Position.from_fen("4k3/8/8/8/8/8/4r3/4K3 w - - 0 1")
        code = ai.choose(position.copy(), level("medium", **QUICK))
        self.assertIn(code, position.moves())

    def test_it_does_not_walk_into_a_recapture(self):
        """A bishop can take the pawn on d5 and be taken by the queen. The
        quiescence search is what sees the second half of that."""
        position = Position.from_fen("3qk3/8/8/3p4/8/5B2/8/4K3 w - - 0 1")
        self.assertNotEqual(
            uci(ai.choose(position.copy(), level("hard", **QUICK))), "f3d5"
        )

    def test_without_quiescence_it_does(self):
        """...which is exactly what makes Easy easy, and is checked so that
        turning it off stays a decision rather than an accident."""
        position = Position.from_fen("3qk3/8/8/3p4/8/5B2/8/4K3 w - - 0 1")
        blind = level("easy", seconds=0.2, blunder=0.0, depth=1)
        self.assertEqual(uci(ai.choose(position.copy(), blind)), "f3d5")


class Clock(unittest.TestCase):
    def test_a_short_clock_still_answers(self):
        position = Position.start()
        started = time.monotonic()
        code = ai.choose(position.copy(), level("hard", seconds=0.05))
        self.assertIn(code, position.moves())
        self.assertLess(time.monotonic() - started, 2.0)

    def test_a_longer_clock_reaches_further(self):
        position = Position.from_fen(
            "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 0 1"
        )
        shallow = ai.think(position.copy(), level("hard", seconds=0.02, depth=6))
        deep = ai.think(position.copy(), level("hard", seconds=2.0, depth=6))
        self.assertLess(shallow.depth, deep.depth)

    def test_the_clock_leaves_nothing_behind_on_the_board(self):
        """Running out of time unwinds through an exception with moves still
        played into the board; if the copy in `think` ever went away, this is
        the test that would notice."""
        position = Position.start()
        before = position.fen()
        ai.think(position, level("hard", seconds=0.01, depth=6))
        self.assertEqual(position.fen(), before)


class Blunders(unittest.TestCase):
    def test_easy_sometimes_plays_something_else_entirely(self):
        position = Position.from_fen("4k3/8/8/3q4/4P3/8/8/4K3 w - - 0 1")
        always = level("easy", seconds=0.2, blunder=1.0)
        played = {
            uci(ai.choose(position.copy(), always, rng=random.Random(seed)))
            for seed in range(12)
        }
        self.assertGreater(len(played), 1)

    def test_but_never_while_in_check(self):
        """A random move in check is as likely to be illegal-looking flailing as
        anything else, and reads as broken rather than as casual."""
        position = Position.from_fen("4q3/8/8/8/8/8/PPP2PPP/4K3 w - - 0 1")
        self.assertTrue(position.in_check())
        self.assertGreater(len(position.moves()), 1)
        always = level("easy", seconds=0.2, blunder=1.0)
        played = {
            uci(ai.choose(position.copy(), always, rng=random.Random(seed)))
            for seed in range(8)
        }
        self.assertEqual(len(played), 1)


class Evaluation(unittest.TestCase):
    def test_the_running_total_agrees_with_a_full_count(self):
        rng = random.Random(11)
        game = Game()
        score = ai.advantage(game.position)
        for _ in range(140):
            legal = game.legal()
            if not legal:
                break
            made = game.play(rng.choice(legal))
            score += ai._delta(made, game.position)
            self.assertEqual(score, ai.advantage(game.position), uci(made.move))

    def test_material_outweighs_position(self):
        even = Position.start()
        ahead = Position.from_fen(
            "rnb1kbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        )
        self.assertGreater(ai.advantage(ahead), ai.advantage(even) + ai.VALUES[5] // 2)

    def test_a_king_alone_is_driven_to_the_edge(self):
        """The ending term, which is the whole of the mating technique."""
        middle = Position.from_fen("8/8/3k4/8/8/8/R7/4K3 w - - 0 1")
        corner = Position.from_fen("8/8/8/8/8/8/R7/k3K3 w - - 0 1")
        self.assertGreater(
            ai.evaluate(corner, ai.advantage(corner), 3),
            ai.evaluate(middle, ai.advantage(middle), 3),
        )


class Endgames(unittest.TestCase):
    """The thing a weak engine is worst at: converting a won ending."""

    def _mate(self, fen: str, key: str, plies: int) -> Game:
        game = Game(position=Position.from_fen(fen))
        strong, weak = level(key, seconds=0.3), level("easy", seconds=0.05)
        rng = random.Random(3)
        while not game.over and len(game.moves) < plies:
            side = strong if game.turn == WHITE else weak
            game.play(ai.choose(game.position, side, rng=rng))
        return game

    def test_a_rook_mates(self):
        game = self._mate("8/8/8/4k3/8/8/8/R3K3 w Q - 0 1", "hard", 70)
        self.assertEqual(game.outcome(), (CHECKMATE, WHITE))

    def test_a_queen_mates(self):
        game = self._mate("8/8/8/3k4/8/8/8/3QK3 w - - 0 1", "medium", 70)
        self.assertEqual(game.outcome(), (CHECKMATE, WHITE))


class Strength(unittest.TestCase):
    """Hard beats Easy. Slow, so it is four games rather than forty -- enough
    that a level which stopped searching at all would be caught."""

    def test_hard_beats_easy_from_both_sides(self):
        strong = level("hard", seconds=0.12, depth=3)
        weak = level("easy", seconds=0.04)
        results = []
        for seed in range(4):
            rng = random.Random(seed)
            game = Game()
            hard = WHITE if seed % 2 == 0 else BLACK
            sides = {hard: strong, hard ^ 1: weak}
            while not game.over and len(game.moves) < 160:
                game.play(ai.choose(game.position, sides[game.turn], rng=rng))
            _kind, winner = game.outcome()
            results.append(winner == hard)
        self.assertGreaterEqual(sum(results), 3, results)


class Moves(unittest.TestCase):
    def test_captures_are_tried_before_quiet_moves(self):
        position = Position.from_fen("4k3/8/8/3q4/4P3/8/8/4K3 w - - 0 1")
        ordered = ai._ordered(position, position.moves())
        self.assertEqual(uci(ordered[0]), "e4d5")

    def test_a_richer_victim_comes_first(self):
        # The king is on f1 rather than e1 on purpose: on e1 the queen on e5
        # is giving check down an open file, and then taking the knight is not
        # a question of ordering, it is illegal.
        position = Position.from_fen("4k3/8/8/2n1q3/3P4/8/8/5K2 w - - 0 1")
        ordered = ai._ordered(position, position.moves())
        self.assertEqual(uci(ordered[0]), "d4e5")
        self.assertEqual(uci(ordered[1]), "d4c5")

    def test_a_promotion_counts_as_tactical(self):
        position = Position.from_fen("4k3/P7/8/8/8/8/8/4K3 w - - 0 1")
        tactical = position.pseudo_moves(tactical=True)
        self.assertEqual([uci(m) for m in tactical], ["a7a8q"])

    def test_parse_uci_and_the_search_agree_about_promotion(self):
        position = Position.from_fen("4k3/P7/8/8/8/8/8/4K3 w - - 0 1")
        code = ai.choose(position.copy(), level("medium", **QUICK))
        self.assertEqual(code, parse_uci("a7a8q"))


if __name__ == "__main__":
    unittest.main()
