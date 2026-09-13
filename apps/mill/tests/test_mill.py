"""The rules. No GTK, so these run on any machine with a Python.

The three that carry weight are the three this game is actually about: that the
adjacency is a ring and a spoke rather than a grid, that a mill earns a removal
made by the same side, and that the piece you may take is not one in a mill
unless every one of them is. The last of those is the rule everybody forgets,
and without it a side that has walled itself into mills can never be touched.
"""

import random
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_mill.mill import (  # noqa: E402
    BLACK,
    MILLS,
    NEIGHBOURS,
    OPENING,
    PIECES,
    POINTS,
    QUIET_LIMIT,
    WHITE,
    Game,
    Position,
    notation,
    place_move,
    point,
    ring_place,
    travel,
    unpack,
)


def board(white=(), black=(), turn=WHITE, placed=None, removing=False) -> Position:
    """A position built by hand, for tests about a rule rather than a game."""
    w = sum(1 << spot for spot in white)
    b = sum(1 << spot for spot in black)
    if placed is None:
        placed = (PIECES, PIECES)
    return Position(w, b, turn, placed, removing)


class TheBoard(unittest.TestCase):
    def test_there_are_twenty_four_points_in_three_rings(self):
        self.assertEqual(POINTS, 24)
        for spot in range(POINTS):
            ring, place = ring_place(spot)
            self.assertEqual(point(ring, place), spot)

    def test_a_corner_touches_two_points_and_a_midpoint_touches_three_or_four(self):
        for spot in range(POINTS):
            ring, place = ring_place(spot)
            if place % 2 == 0:
                self.assertEqual(len(NEIGHBOURS[spot]), 2, notation(spot))
            elif ring == 1:
                # A midpoint of the middle ring reaches both ways along the
                # spoke as well as both ways round its own square.
                self.assertEqual(len(NEIGHBOURS[spot]), 4, notation(spot))
            else:
                self.assertEqual(len(NEIGHBOURS[spot]), 3, notation(spot))

    def test_adjacency_runs_both_ways(self):
        for spot in range(POINTS):
            for near in NEIGHBOURS[spot]:
                self.assertIn(spot, NEIGHBOURS[near], f"{spot} -> {near}")

    def test_nothing_crosses_between_rings_except_along_a_spoke(self):
        for spot in range(POINTS):
            ring, place = ring_place(spot)
            for near in NEIGHBOURS[spot]:
                other_ring, other_place = ring_place(near)
                if other_ring == ring:
                    continue
                self.assertEqual(place % 2, 1, notation(spot))
                self.assertEqual(place, other_place)
                self.assertEqual(abs(ring - other_ring), 1)

    def test_there_are_sixteen_mills_and_every_point_is_in_two(self):
        self.assertEqual(len(MILLS), 16)
        held = {spot: 0 for spot in range(POINTS)}
        for mill in MILLS:
            self.assertEqual(len(set(mill)), 3)
            for spot in mill:
                held[spot] += 1
        self.assertEqual(set(held.values()), {2})

    def test_every_mill_is_three_points_in_a_line(self):
        for mill in MILLS:
            rings = {ring_place(spot)[0] for spot in mill}
            places = {ring_place(spot)[1] for spot in mill}
            # Either one ring and three consecutive places, or one place across
            # all three rings. Nothing else is a line on this board.
            self.assertTrue(len(rings) == 1 or len(places) == 1, str(mill))

    def test_a_move_survives_being_a_number(self):
        for spot in range(POINTS):
            self.assertEqual(unpack(place_move(spot)), (-1, spot))
        for src in range(POINTS):
            for dst in NEIGHBOURS[src]:
                self.assertEqual(unpack(travel(src, dst)), (src, dst))

    def test_a_move_says_what_it_is(self):
        self.assertEqual(notation(place_move(0)), "a1")
        self.assertEqual(notation(travel(0, 1)), "a1-a2")
        self.assertEqual(notation(place_move(16)), "c1")


class Placing(unittest.TestCase):
    def test_the_opening_offers_every_point_and_nothing_else(self):
        self.assertEqual(len(OPENING.moves()), POINTS)
        self.assertTrue(OPENING.placing(WHITE))
        self.assertEqual(OPENING.left(WHITE), PIECES)

    def test_a_placement_uses_one_from_the_hand(self):
        after = OPENING.play(place_move(0))
        self.assertEqual(after.left(WHITE), PIECES - 1)
        self.assertEqual(after.count(WHITE), 1)
        self.assertEqual(after.turn, BLACK)

    def test_you_cannot_place_on_a_point_that_is_taken(self):
        after = OPENING.play(place_move(0))
        self.assertFalse(after.is_legal(place_move(0)))

    def test_the_phase_ends_when_the_hand_is_empty(self):
        position = OPENING
        for spot in range(2 * PIECES):
            position = position.play(place_move(spot))
        self.assertFalse(position.placing(WHITE))
        self.assertFalse(position.placing(BLACK))
        self.assertEqual(position.left(WHITE), 0)


class Moving(unittest.TestCase):
    def test_a_piece_moves_only_to_a_point_it_touches(self):
        position = board(white=(0,), black=(8,))
        self.assertEqual(set(position.destinations(0)), set(NEIGHBOURS[0]))
        for dst in NEIGHBOURS[0]:
            self.assertTrue(position.is_legal(travel(0, dst)))
        self.assertFalse(position.is_legal(travel(0, 16)))

    def test_a_side_with_three_left_may_go_anywhere(self):
        position = board(white=(0, 2, 4), black=(8, 10, 12, 14))
        self.assertTrue(position.flying(WHITE))
        self.assertIn(travel(0, 20), position.moves())

    def test_three_pieces_in_the_opening_is_not_flying(self):
        # Three on the board because three have been placed is not the endgame,
        # it is the third turn.
        position = board(white=(0, 2, 4), black=(8, 10, 12), placed=(3, 3))
        self.assertFalse(position.flying(WHITE))

    def test_a_side_with_nowhere_to_go_has_lost(self):
        # Four white pieces, every neighbour of every one of them taken. Four
        # and not three, because three would be flying and flying is never
        # boxed in while the board has an empty point on it.
        position = board(
            white=(0, 1, 2, 16),
            black=(7, 9, 3, 17, 23),
            placed=(PIECES, PIECES),
        )
        self.assertEqual(position.moves(), [])
        self.assertTrue(position.lost(WHITE))
        self.assertEqual(position.winner(), BLACK)

    def test_two_pieces_left_is_a_loss(self):
        position = board(white=(0, 2), black=(8, 10, 12))
        self.assertTrue(position.lost(WHITE))
        self.assertEqual(position.winner(), BLACK)


class Mills(unittest.TestCase):
    def test_closing_one_leaves_the_same_side_owing_a_removal(self):
        position = board(white=(0, 1), black=(8, 9), placed=(2, 2))
        after = position.play(place_move(2))
        self.assertTrue(after.removing)
        self.assertEqual(after.turn, WHITE)

    def test_the_removal_is_a_move_of_its_own(self):
        position = board(white=(0, 1), black=(8, 9), placed=(2, 2))
        after = position.play(place_move(2))
        self.assertEqual(set(after.moves()), {place_move(8), place_move(9)})
        taken = after.play(place_move(8))
        self.assertEqual(taken.count(BLACK), 1)
        self.assertEqual(taken.turn, BLACK)
        self.assertFalse(taken.removing)

    def test_a_piece_in_a_mill_is_safe_while_anything_else_is_not(self):
        # Black has a mill at 8, 9, 10 and one loose piece at 16.
        position = board(white=(0, 1), black=(8, 9, 10, 16), placed=(2, 4))
        after = position.play(place_move(2))
        self.assertEqual(after.removable(), [16])

    def test_but_not_when_every_piece_is_in_one(self):
        # The rule everybody forgets. Without it a side that has walled itself
        # into mills can never be touched again.
        position = board(white=(0, 1), black=(8, 9, 10), placed=(2, 3))
        after = position.play(place_move(2))
        self.assertEqual(sorted(after.removable()), [8, 9, 10])

    def test_a_piece_cannot_complete_a_mill_it_is_leaving(self):
        # White holds 0, 1, 2 and 4. Sliding the piece at 2 to 3 must not count
        # the mill 2-3-4, because the piece at 2 is the one that moved. A rule
        # that forgot to take it off the board first hands out a free removal
        # for a mill that does not exist.
        position = board(white=(0, 1, 2, 4), black=(8, 10, 12, 14))
        self.assertFalse(position.closes(WHITE, 3, without=2))
        self.assertTrue(position.closes(WHITE, 3, without=-1))

    def test_but_breaking_a_mill_and_reforming_it_does_count(self):
        # The running mill, which is the central tactic of this game: a piece
        # steps out of a mill and back into it, closing it again and earning a
        # removal every second turn. It is meant to work.
        position = board(white=(0, 1, 3), black=(8, 10, 12, 14))
        self.assertTrue(position.closes(WHITE, 2, without=3))

    def test_a_mill_that_can_take_nothing_does_not_stop_the_turn(self):
        # Black has two pieces and both are about to be irrelevant: a mill with
        # nothing legal to take must still hand the turn over.
        position = board(white=(0, 1), black=(8, 9), placed=(2, 2))
        after = position.play(place_move(2))
        self.assertTrue(after.removing)
        empty = board(white=(0, 1), black=(), placed=(2, 0))
        landed = empty.play(place_move(2))
        self.assertFalse(landed.removing)
        self.assertEqual(landed.turn, BLACK)


class TheMoveList(unittest.TestCase):
    def test_a_game_is_its_moves(self):
        game = Game()
        game.play(place_move(0))
        game.play(place_move(8))
        self.assertEqual(game.moves, [place_move(0), place_move(8)])
        self.assertEqual(game.position.count(WHITE), 1)

    def test_a_play_says_what_it_did(self):
        game = Game([place_move(0), place_move(8), place_move(1), place_move(9)])
        play = game.play(place_move(2))
        self.assertEqual(play.dst, 2)
        self.assertEqual(play.colour, WHITE)
        self.assertEqual(play.mill, (0, 1, 2))
        taken = game.play(place_move(8))
        self.assertEqual(taken.removed, 8)

    def test_resume_keeps_what_will_play_and_drops_the_rest(self):
        good = [place_move(0), place_move(8), place_move(1)]
        game = Game.resume([*good, place_move(0)])
        self.assertEqual(game.moves, good)

    def test_junk_in_the_move_list_ends_the_game_there(self):
        for junk in ([None], ["a1"], [True], [1.5]):
            self.assertEqual(Game.resume(junk).moves, [])

    def test_undo_pops_one_and_nothing_from_the_opening(self):
        game = Game([place_move(0)])
        self.assertTrue(game.undo())
        self.assertEqual(game.position, OPENING)
        self.assertFalse(game.undo())

    def test_takeback_returns_the_turn_and_does_not_stop_on_a_removal(self):
        # A turn that closed a mill is two entries in the list, and handing the
        # board back in the middle of one would be handing back a state where
        # the person owes a removal for a mill they have just un-made.
        game = Game([place_move(0), place_move(8), place_move(1), place_move(9)])
        game.play(place_move(2))
        game.play(place_move(8))
        self.assertEqual(game.turn, BLACK)
        game.play(place_move(10))
        self.assertEqual(game.turn, WHITE)
        self.assertTrue(game.takeback(WHITE))
        self.assertEqual(game.turn, WHITE)
        self.assertFalse(game.position.removing)

    def test_a_long_quiet_endgame_is_a_draw(self):
        game = Game()
        for spot in range(2 * PIECES):
            game.play(place_move(spot))
        self.assertFalse(game.over)
        while not game.over:
            game.play(game.position.moves()[0])
        self.assertTrue(game.drawn)
        self.assertEqual(game.quiet, QUIET_LIMIT)

    def test_a_random_game_always_ends(self):
        for seed in range(6):
            rng = random.Random(seed)
            game = Game()
            for _ in range(600):
                if game.over:
                    break
                game.play(rng.choice(game.position.moves()))
            self.assertTrue(game.over, f"seed {seed} would not finish")


if __name__ == "__main__":
    unittest.main()
