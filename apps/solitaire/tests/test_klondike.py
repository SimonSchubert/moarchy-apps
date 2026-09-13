"""The rules. No GTK, so these run on any machine with a Python.

Two of these are property tests over a lot of random play rather than examples,
and they are the two that matter. **Every card exists exactly once** and **the
face-up part of a column is always a run** are the invariants the whole app is
built on -- the second is why a tap can pick up a run without validating it, and
the first is the thing a card game gets wrong in a way nobody notices until
there are two aces of spades on the table.
"""

import random
import sys
import unittest
from itertools import pairwise
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_solitaire.klondike import (  # noqa: E402
    ACE,
    COLUMNS,
    DECK,
    FOUNDATION,
    KING,
    PILES,
    STOCK,
    SUITS,
    TABLEAU,
    WASTE,
    Game,
    Move,
    Table,
    deal,
    homeward,
    is_red,
    name,
    rank,
    shuffled,
    stuck,
    suit,
)


def card(r: int, s: int) -> int:
    return r * SUITS + s


def every_card(table: Table) -> list[int]:
    out = list(table.stock) + list(table.waste)
    for column in table.piles:
        out.extend(column)
    for index, count in enumerate(table.up):
        out.extend(card(r, index) for r in range(count))
    return out


def runs_hold(table: Table) -> bool:
    """Is every face-up section a descending alternating sequence?"""
    for index in range(COLUMNS):
        shown = table.face_up(TABLEAU + index)
        for above, below in pairwise(shown):
            if rank(above) != rank(below) + 1 or is_red(above) == is_red(below):
                return False
    return True


class TheDeal(unittest.TestCase):
    def test_it_puts_twenty_eight_cards_out_and_twenty_four_away(self):
        table = deal(shuffled(random.Random(1)))
        self.assertEqual(sum(len(column) for column in table.piles), 28)
        self.assertEqual(len(table.stock), 24)
        self.assertEqual(table.down, tuple(range(COLUMNS)))
        self.assertEqual(table.up, (0,) * SUITS)

    def test_one_card_of_each_column_is_face_up(self):
        table = deal(shuffled(random.Random(2)))
        for index in range(COLUMNS):
            self.assertEqual(len(table.face_up(TABLEAU + index)), 1)

    def test_it_refuses_anything_that_is_not_a_deck(self):
        for bad in ((), tuple(range(51)), (0,) * DECK):
            with self.assertRaises(ValueError):
                deal(bad)

    def test_every_card_is_dealt_exactly_once(self):
        table = deal(shuffled(random.Random(3)))
        self.assertEqual(sorted(every_card(table)), list(range(DECK)))


class WhatALandingNeeds(unittest.TestCase):
    def setUp(self):
        self.empty = deal(tuple(range(DECK)))._with(
            stock=(), waste=(), piles=((),) * COLUMNS, down=(0,) * COLUMNS
        )

    def test_a_foundation_takes_the_ace_first_and_then_in_order(self):
        table = self.empty
        self.assertTrue(table.accepts(FOUNDATION + 3, card(ACE, 3)))
        self.assertFalse(table.accepts(FOUNDATION + 3, card(1, 3)))
        self.assertFalse(table.accepts(FOUNDATION + 3, card(ACE, 0)))
        table = table._with(up=(0, 0, 0, 1))
        self.assertTrue(table.accepts(FOUNDATION + 3, card(1, 3)))

    def test_an_empty_column_takes_a_king_and_nothing_else(self):
        for rank_ in range(13):
            self.assertEqual(self.empty.accepts(TABLEAU, card(rank_, 0)), rank_ == KING)

    def test_a_column_builds_down_in_alternating_colours(self):
        table = self.empty._with(piles=((card(7, 3),),) + ((),) * 6)  # 8 of spades
        self.assertTrue(table.accepts(TABLEAU, card(6, 1)))  # 7 of diamonds
        self.assertFalse(table.accepts(TABLEAU, card(6, 0)))  # 7 of clubs, black
        self.assertFalse(table.accepts(TABLEAU, card(5, 1)))  # 6, too low

    def test_nothing_lands_on_the_stock_or_the_waste_by_accepting(self):
        self.assertFalse(self.empty.accepts(STOCK, 0))
        self.assertFalse(self.empty.accepts(WASTE, 0))


class WhereATapCanGo(unittest.TestCase):
    def setUp(self):
        self.table = deal(tuple(range(DECK)))._with(
            stock=(), waste=(), piles=((),) * COLUMNS, down=(0,) * COLUMNS
        )

    def test_an_ace_only_ever_goes_home(self):
        # The rules let a black ace sit on a red two. Nobody has ever wanted it.
        table = self.table._with(piles=((card(1, 1),), (card(ACE, 0),)) + ((),) * 5)
        self.assertEqual(table.destinations(TABLEAU + 1, 0), [FOUNDATION + 0])

    def test_three_empty_columns_are_one_decision(self):
        table = self.table._with(
            piles=((card(5, 0), card(KING, 3)),) + ((),) * 6, down=(1,) + (0,) * 6
        )
        self.assertEqual(table.destinations(TABLEAU, 1), [TABLEAU + 1])

    def test_a_whole_column_does_not_move_to_an_empty_one(self):
        table = self.table._with(piles=((card(KING, 3),),) + ((),) * 6)
        self.assertEqual(table.destinations(TABLEAU, 0), [])
        self.assertEqual(table.moves(), [])

    def test_a_face_down_card_picks_up_nothing(self):
        table = deal(shuffled(random.Random(4)))
        self.assertEqual(table.run_from(TABLEAU + 6, 0), ())
        self.assertEqual(table.destinations(TABLEAU + 6, 0), [])

    def test_a_run_picks_up_from_where_it_was_tapped(self):
        column = (card(7, 3), card(6, 1), card(5, 0))  # 8s 7d 6c
        table = self.table._with(piles=(column,) + ((),) * 6)
        self.assertEqual(table.run_from(TABLEAU, 1), column[1:])
        self.assertEqual(table.run_from(TABLEAU, 0), column)


class DoingIt(unittest.TestCase):
    def test_a_deal_turns_them_over_one_at_a_time(self):
        table = deal(tuple(range(DECK)), 3)
        top = table.stock[-1]
        table = table.apply(Move(STOCK, WASTE, 3))
        self.assertEqual(len(table.waste), 3)
        self.assertEqual(table.waste[-1], top)
        self.assertEqual(table.top(WASTE), top)

    def test_turning_the_waste_back_over_reverses_it(self):
        table = deal(tuple(range(DECK)), 1)
        for _ in range(24):
            table = table.apply(Move(STOCK, WASTE, 1))
        was = table.waste
        table = table.apply(Move(WASTE, STOCK, len(was)))
        self.assertEqual(table.waste, ())
        self.assertEqual(table.stock, tuple(reversed(was)))
        # And the card that was on top of the waste comes off the stock last.
        self.assertEqual(table.stock[0], was[-1])

    def test_the_card_under_the_one_that_left_turns_over(self):
        # One hidden card with the ace of spades on top of it. Built rather
        # than dealt, because a dealt column has whatever is in it and this
        # test is about the flip, not about the luck.
        pile = TABLEAU
        table = deal(tuple(range(DECK)))._with(
            stock=(),
            waste=(),
            piles=((card(5, 1), card(ACE, 3)),) + ((),) * 6,
            down=(1,) + (0,) * 6,
        )
        self.assertEqual(table.hidden(pile), 1)
        table = table.apply(Move(pile, FOUNDATION + 3, 1))
        self.assertEqual(table.hidden(pile), 0)
        self.assertEqual(table.face_up(pile), (card(5, 1),))

    def test_an_illegal_move_raises(self):
        # The ace of clubs is the first card dealt, so the move that is not
        # legal is the one putting it on the wrong foundation.
        table = deal(tuple(range(DECK)))
        with self.assertRaises(ValueError):
            table.apply(Move(TABLEAU, FOUNDATION + 1, 1))
        with self.assertRaises(ValueError):
            table.apply(Move(WASTE, TABLEAU, 1))
        with self.assertRaises(ValueError):
            table.apply(Move(TABLEAU + 6, TABLEAU, 7))

    def test_only_a_column_can_move_more_than_one_card(self):
        table = deal(tuple(range(DECK)))
        self.assertFalse(table.is_legal(Move(WASTE, TABLEAU, 2)))
        self.assertFalse(table.is_legal(Move(TABLEAU, FOUNDATION, 2)))


class TheInvariants(unittest.TestCase):
    """The two properties the app is built on, over a lot of random play."""

    def test_every_card_exists_exactly_once_all_the_way_through(self):
        rng = random.Random(20260913)
        for seed in range(12):
            game = Game(shuffled(random.Random(seed)), 1 if seed % 2 else 3)
            for _ in range(300):
                moves = game.table.moves()
                if not moves:
                    break
                game.play(rng.choice(moves))
                self.assertEqual(
                    sorted(every_card(game.table)),
                    list(range(DECK)),
                    f"seed {seed} after {game.count} moves",
                )

    def test_the_face_up_part_of_a_column_is_always_a_run(self):
        rng = random.Random(11)
        for seed in range(12):
            game = Game(shuffled(random.Random(seed)), 1)
            for _ in range(300):
                moves = game.table.moves()
                if not moves:
                    break
                game.play(rng.choice(moves))
                self.assertTrue(runs_hold(game.table), f"seed {seed}")

    def test_replaying_a_game_gives_back_the_same_table(self):
        rng = random.Random(7)
        game = Game(shuffled(random.Random(3)), 1)
        for _ in range(80):
            moves = game.table.moves()
            if not moves:
                break
            game.play(rng.choice(moves))
        again = Game(game.deck, 1, list(game.moves))
        self.assertEqual(again.table, game.table)


class Finishing(unittest.TestCase):
    def _laid_out(self) -> Table:
        """Four columns holding the whole deck as four legal runs."""
        runs = []
        for high, low in ((3, 2), (2, 3), (0, 1), (1, 0)):
            runs.append(
                tuple(
                    card(r, high if index % 2 == 0 else low)
                    for index, r in enumerate(range(KING, -1, -1))
                )
            )
        return Table(
            stock=(),
            waste=(),
            up=(0,) * SUITS,
            piles=tuple(runs) + ((),) * 3,
            down=(0,) * COLUMNS,
            draw=1,
        )

    def test_a_table_with_nothing_face_down_can_be_finished(self):
        table = self._laid_out()
        self.assertTrue(table.finishable)
        for move in homeward(table):
            table = table.apply(move)
        self.assertTrue(table.won)

    def test_it_finishes_a_stock_full_of_cards_too(self):
        table = Table(
            stock=tuple(range(DECK)),
            waste=(),
            up=(0,) * SUITS,
            piles=((),) * COLUMNS,
            down=(0,) * COLUMNS,
            draw=3,
        )
        for move in homeward(table):
            table = table.apply(move)
        self.assertTrue(table.won)

    def test_a_won_table_is_not_finishable_and_a_fresh_one_is_not_either(self):
        table = self._laid_out()
        for move in homeward(table):
            table = table.apply(move)
        self.assertFalse(table.finishable)
        self.assertFalse(deal(shuffled(random.Random(1))).finishable)


class BeingStuck(unittest.TestCase):
    def test_a_table_where_nothing_moves_is_stuck(self):
        # Seven single black cards, no aces, no stock. Nothing builds on
        # anything, and there is no stock to turn over looking for one.
        table = Table(
            stock=(),
            waste=(),
            up=(0,) * SUITS,
            piles=tuple(
                (card(r, 3 if index % 2 else 0),)
                for index, r in enumerate((KING, KING - 1, 10, 9, 8, 7, 6))
            ),
            down=(0,) * COLUMNS,
            draw=1,
        )
        self.assertTrue(stuck(table))

    def test_a_card_in_the_stock_that_can_be_played_is_not_stuck(self):
        table = Table(
            stock=(card(ACE, 0),),
            waste=(),
            up=(0,) * SUITS,
            piles=((card(KING, 3),),) + ((),) * 6,
            down=(0,) * COLUMNS,
            draw=1,
        )
        self.assertFalse(stuck(table))

    def test_a_fresh_deal_is_never_stuck(self):
        for seed in range(20):
            self.assertFalse(stuck(deal(shuffled(random.Random(seed)))))


class TheMoveList(unittest.TestCase):
    def test_resume_keeps_what_will_play_and_drops_the_rest(self):
        deck = shuffled(random.Random(9))
        game = Game(deck, 1)
        good = []
        for _ in range(12):
            moves = game.table.moves()
            if not moves:
                break
            game.play(moves[0])
            good.append(moves[0].as_list())
        back = Game.resume(deck, 1, [*good, [TABLEAU, FOUNDATION, 9]])
        self.assertEqual(len(back.moves), len(good))
        self.assertEqual(back.table, game.table)

    def test_resume_from_a_deck_that_is_not_one_deals_a_fresh_game(self):
        game = Game.resume([1, 2, 3], 1, [])
        self.assertEqual(len(game.deck), DECK)
        self.assertEqual(game.moves, [])

    def test_junk_in_the_move_list_ends_the_game_there(self):
        deck = shuffled(random.Random(10))
        game = Game.resume(deck, 1, [["deal"], None, 7])
        self.assertEqual(game.moves, [])

    def test_undo_pops_one_and_nothing_from_a_fresh_deal(self):
        game = Game(shuffled(random.Random(6)), 1)
        game.play(Move(STOCK, WASTE, 1))
        self.assertTrue(game.undo())
        self.assertEqual(game.table, game.start)
        self.assertFalse(game.undo())

    def test_a_move_survives_the_round_trip_through_a_list(self):
        move = Move(TABLEAU + 2, FOUNDATION + 1, 1)
        self.assertEqual(Move.of(move.as_list()), move)
        for bad in (None, [1, 2], [1, 2, "3"], [True, 2, 3], "abc"):
            self.assertIsNone(Move.of(bad))


class Naming(unittest.TestCase):
    def test_a_card_says_what_it_is(self):
        self.assertEqual(name(card(ACE, 3)), "A of spades")
        self.assertEqual(name(card(9, 2)), "10 of hearts")

    def test_the_piles_are_numbered_the_way_the_file_says_they_are(self):
        self.assertEqual((STOCK, WASTE, FOUNDATION, TABLEAU, PILES), (0, 1, 2, 6, 13))
        self.assertTrue(is_red(card(0, 1)) and is_red(card(0, 2)))
        self.assertFalse(is_red(card(0, 0)) or is_red(card(0, 3)))
        self.assertEqual(suit(card(4, 2)), 2)


if __name__ == "__main__":
    unittest.main()
