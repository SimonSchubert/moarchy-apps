"""The opponent. No GTK, so these run anywhere too.

The test that matters most is at the top and it is not about strength: **a turn
is not always one ply.** Closing a mill earns a removal made by the same side,
so a child position can have the same player to move as its parent, and
negamax's flip-the-sign is wrong exactly there. A search that gets it wrong
plays well right up until it makes a mill and then throws a piece away, which is
easy to write and very hard to see -- so it is tested directly, on a position
where the difference is one piece.

The clocks here are turned right down. Four hundred milliseconds of thinking per
move is the app's setting and a test suite's enemy; every level below is a copy
of a shipped one with the clock cut, which changes how deep it reaches and
nothing about whether it reaches the right answer.
"""

import random
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_mill import ai  # noqa: E402
from moarchy_mill.mill import (  # noqa: E402
    BLACK,
    OPENING,
    PIECES,
    WHITE,
    Game,
    Position,
    place_move,
    travel,
    unpack,
)


def board(white=(), black=(), turn=WHITE, placed=None, removing=False) -> Position:
    w = sum(1 << spot for spot in white)
    b = sum(1 << spot for spot in black)
    return Position(w, b, turn, placed or (PIECES, PIECES), removing)


def quick(key: str, seconds: float = 0.05, depth: int = 4) -> ai.Level:
    base = ai.level_for(key)
    return ai.Level(base.key, base.label, base.blurb, seconds, depth, base.slack)


def _value(position: Position, move: int, depth: int) -> int:
    """What one move is worth, searched to a fixed depth with a full window.

    A full window rather than the narrowing one `choose` uses, because these
    are compared against each other: alpha-beta returns a bound rather than a
    value for anything that fails low, and two bounds are not comparable.
    """
    import time

    child = position.play(move)
    deadline = time.monotonic() + 60
    limit = ai.WIN * 2
    if child.turn == position.turn:
        return ai._search(child, depth - 1, -limit, limit, deadline)
    return -ai._search(child, depth - 1, -limit, limit, deadline)


class TheHalfTurn(unittest.TestCase):
    """Closing a mill does not hand the turn over, and the search knows."""

    def test_it_takes_a_mill_that_wins_the_game(self):
        # Black is down to three, so the piece a mill takes is the game. White
        # slides 3 to 2 and closes 0-1-2.
        #
        # Deliberately a position where the mill is *decisive* rather than
        # merely good. A mill that is only worth a piece is a move a deeper
        # search will sometimes delay by a turn -- correctly, because the mill
        # is still there next turn -- and a test that called that a failure
        # would be a test asserting the search is shallow.
        position = board(white=(0, 1, 3, 20), black=(8, 14, 19))
        for depth in (2, 4, 6):
            move = ai.choose(position, quick("hard", 0.5, depth), random.Random(1))
            self.assertEqual(unpack(move), (3, 2), f"at depth {depth}")

    def test_it_takes_the_loose_piece_rather_than_the_one_in_a_mill(self):
        # Black holds a mill at 8, 9, 10 and one loose piece. The rules only
        # offer the loose one, and the search must not be confused by being
        # given a position where it is still its own turn.
        position = board(
            white=(0, 1, 2), black=(8, 9, 10, 16), placed=(3, 4), removing=True
        )
        move = ai.choose(position, quick("medium"), random.Random(1))
        self.assertEqual(unpack(move)[1], 16)

    def test_a_removal_is_valued_as_a_gain_and_not_a_loss(self):
        # The sign test, stated as a value rather than as a move. A search that
        # negated at the removal node would come back with a mill being worth
        # roughly minus a piece, and nothing else in the suite would notice.
        position = board(white=(0, 1, 22), black=(8, 19, 5), placed=(3, 3))
        mill = _value(position, place_move(2), 2)
        quiet = _value(position, place_move(23), 2)
        self.assertGreater(mill, quiet + ai.MAN, f"mill {mill}, quiet {quiet}")

    def test_taking_a_piece_leaves_the_board_worth_more(self):
        owed = board(white=(0, 1, 2), black=(8, 16, 18), placed=(3, 3), removing=True)
        settled = board(white=(0, 1, 2), black=(8, 16, 18), placed=(3, 3), turn=BLACK)
        self.assertGreater(
            ai.evaluate(owed.play(place_move(8)), WHITE),
            ai.evaluate(settled, WHITE),
        )

    def test_it_blocks_a_mill_it_can_see_coming(self):
        # Black has 8 and 9 with 10 empty, and white has nothing better to do.
        position = board(white=(20,), black=(8, 9), placed=(1, 2))
        move = ai.choose(position, quick("hard", 0.6, 6), random.Random(1))
        self.assertEqual(unpack(move)[1], 10)


class TheSearch(unittest.TestCase):
    def test_every_move_offered_is_a_legal_one(self):
        rng = random.Random(3)
        for key in ai.LEVEL_KEYS:
            level = quick(key)
            game = Game()
            for _ in range(40):
                if game.over:
                    break
                move = ai.choose(game.position, level, rng)
                self.assertTrue(game.position.is_legal(move), f"{key} {move}")
                game.play(move)

    def test_a_board_with_nothing_to_play_offers_nothing(self):
        position = board(white=(0, 2), black=(8, 10, 12))
        self.assertTrue(position.lost(WHITE))
        stuck = board(white=(0, 1, 2, 16), black=(7, 9, 3, 17, 23))
        self.assertEqual(ai.choose(stuck, quick("easy")), -1)

    def test_the_only_move_on_the_board_is_played_without_thinking(self):
        position = board(white=(0, 1), black=(8, 9), placed=(2, 2), removing=True)
        # Both of black's pieces are loose, so this is not it -- build one where
        # only a single removal is legal.
        lone = board(white=(0, 1), black=(8,), placed=(2, 1), removing=True)
        self.assertEqual(len(lone.moves()), 1)
        self.assertEqual(ai.choose(lone, quick("hard", 5.0, 12)), place_move(8))
        self.assertEqual(len(position.moves()), 2)

    def test_an_unknown_level_is_the_middle_one(self):
        self.assertEqual(ai.level_for("nonsense").key, "medium")

    def test_the_opening_is_answered_inside_its_own_clock(self):
        import time

        level = ai.level_for("hard")
        started = time.monotonic()
        ai.choose(OPENING, level, random.Random(1))
        # The clock plus one ply's overshoot: the deadline is checked on the way
        # into a node, so the last node started is allowed to finish.
        self.assertLess(time.monotonic() - started, level.seconds * 2 + 1.0)


class TheEvaluation(unittest.TestCase):
    def test_a_piece_is_worth_more_than_anything_else(self):
        ahead = board(white=(0, 1, 20, 22), black=(8, 10, 12))
        level = board(white=(0, 1, 20), black=(8, 10, 12))
        self.assertGreater(ai.evaluate(ahead, WHITE), ai.evaluate(level, WHITE) + 50)

    def test_a_mill_is_worth_having_and_less_than_a_piece(self):
        milled = board(white=(0, 1, 2), black=(8, 10, 12))
        spread = board(white=(0, 1, 20), black=(8, 10, 12))
        better = ai.evaluate(milled, WHITE) - ai.evaluate(spread, WHITE)
        self.assertGreater(better, 0)
        self.assertLess(better, ai.MAN)

    def test_a_lost_board_is_worth_losing(self):
        lost = board(white=(0, 2), black=(8, 10, 12))
        self.assertLessEqual(ai.evaluate(lost, WHITE), -ai.WIN)
        self.assertGreaterEqual(ai.evaluate(lost, BLACK), ai.WIN)

    def test_it_is_symmetrical(self):
        position = board(white=(0, 1, 20), black=(8, 10, 12))
        self.assertEqual(ai.evaluate(position, WHITE), -ai.evaluate(position, BLACK))


class TheLevelsAreOrdered(unittest.TestCase):
    """The one property somebody can feel, and the one a tweak can break.

    Played at a fraction of the shipped clocks, because the ordering comes from
    the depth reached and the slack, not from the wall time -- and a suite that
    played eight full-strength games would take ten minutes.
    """

    def test_a_deeper_search_beats_a_shallower_one(self):
        deep = ai.Level("deep", "Deep", "", 0.05, 5, 0.0)
        shallow = ai.Level("shallow", "Shallow", "", 0.05, 1, 0.0)
        rng = random.Random(20260913)
        better = worse = 0
        for game_number in range(4):
            game = Game()
            sides = (
                {WHITE: deep, BLACK: shallow}
                if game_number % 2 == 0
                else {WHITE: shallow, BLACK: deep}
            )
            while not game.over and len(game.moves) < 260:
                game.play(ai.choose(game.position, sides[game.turn], rng))
            winner = game.position.winner()
            if winner is None:
                continue
            if sides[winner] is deep:
                better += 1
            else:
                worse += 1
        self.assertGreater(better, worse, f"deep {better}, shallow {worse}")

    def test_the_shipped_levels_get_slower_and_deeper_in_order(self):
        for easier, harder in zip(ai.LEVELS, ai.LEVELS[1:], strict=False):
            self.assertLessEqual(easier.seconds, harder.seconds, easier.key)
            self.assertLessEqual(easier.depth, harder.depth, easier.key)
            self.assertGreaterEqual(easier.slack, harder.slack, easier.key)
        self.assertEqual(ai.level_for("hard").slack, 0.0)

    def test_easy_errs_without_giving_pieces_away(self):
        # Casual is not random: the pool is every move within a piece of the
        # best one, which is an opponent that misses things rather than one
        # that is not playing.
        rng = random.Random(7)
        scored = [(0, 1), (-ai.MAN * 3, 2), (-5, 3)]
        for _ in range(50):
            self.assertIn(ai._casual(scored, rng), (1, 3))


class Travelling(unittest.TestCase):
    def test_it_moves_a_piece_rather_than_placing_one_after_the_hand_is_empty(self):
        position = board(white=(0, 20), black=(8, 22))
        move = ai.choose(position, quick("medium"), random.Random(2))
        src, _ = unpack(move)
        self.assertGreaterEqual(src, 0)

    def test_and_flies_when_it_is_down_to_three(self):
        position = board(white=(0, 2, 4), black=(9, 11, 13, 15))
        self.assertTrue(position.flying(WHITE))
        move = ai.choose(position, quick("easy"), random.Random(2))
        self.assertTrue(position.is_legal(move))
        self.assertIn(travel(0, 20), position.moves())


if __name__ == "__main__":
    unittest.main()
