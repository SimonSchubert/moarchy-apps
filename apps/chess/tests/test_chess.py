"""The rules.

Chess has more rules than Reversi has lines, and most of them are the sort that
look right until a particular board arrives: castling through a square that is
attacked but not occupied, an en passant capture that would expose the king
along the fourth rank, a fifty-move counter that a check does not reset. So the
spine of this file is `perft` -- play every legal move to a fixed depth and
count the leaves -- against the positions the chess programming community keeps
for exactly this, because a single wrong number there is a rule that is wrong
somewhere, and no ordinary test finds the ones nobody thought of.

Everything else in here is a claim about one board, stated in a FEN so that the
board is readable in the test rather than assembled by twelve moves.

No GTK. These run on any machine with a Python.
"""

import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_chess.chess import (  # noqa: E402
    BLACK,
    CHECKMATE,
    FIFTY_MOVE,
    INSUFFICIENT,
    KNIGHT,
    ONGOING,
    QUEEN,
    REPETITION,
    STALEMATE,
    WHITE,
    Game,
    Position,
    move_promotion,
    move_to,
    name,
    parse_square,
    parse_uci,
    uci,
)


def perft(position: Position, depth: int) -> int:
    if depth == 0:
        return 1
    us = position.turn
    total = 0
    for code in position.pseudo_moves():
        made = position.make(code)
        if not position.attacked(position.kings[us], position.turn):
            total += 1 if depth == 1 else perft(position, depth - 1)
        position.unmake(made)
    return total


def play(*moves: str, position: Position | None = None) -> Game:
    return Game([parse_uci(m) for m in moves], position=position)


class Squares(unittest.TestCase):
    def test_a1_is_zero_and_h8_is_sixty_three(self):
        self.assertEqual(parse_square("a1"), 0)
        self.assertEqual(parse_square("h8"), 63)
        self.assertEqual(name(0), "a1")
        self.assertEqual(name(63), "h8")

    def test_every_square_survives_the_round_trip(self):
        for cell in range(64):
            self.assertEqual(parse_square(name(cell)), cell)

    def test_a_move_survives_the_round_trip(self):
        for text in ("e2e4", "a7a8q", "e1g1", "h2g1n"):
            self.assertEqual(uci(parse_uci(text)), text)

    def test_nonsense_is_refused(self):
        for text in ("", "e2", "j2j4", "e2e9", "e7e8k", "e7e8x"):
            with self.assertRaises(ValueError):
                parse_uci(text)


class Perft(unittest.TestCase):
    """The counts everybody checks against.

    Each of these positions exists to catch a different family of mistake: the
    second is Kiwipete, which is dense with castling and pins; the third is a
    rook-and-pawn ending whose en passant captures are illegal because of a
    discovered check along the rank; the fourth is full of promotions.
    """

    def assert_perft(self, fen: str, counts):
        position = Position.from_fen(fen)
        for depth, expected in enumerate(counts, 1):
            self.assertEqual(
                perft(position, depth), expected, f"{fen} at depth {depth}"
            )
            # ...and the position is exactly as it was before the walk, which is
            # the other half of what make/unmake has to be true for.
            self.assertEqual(position.fen(), fen)

    def test_the_opening(self):
        self.assert_perft(Position.start().fen(), [20, 400, 8902, 197281])

    def test_kiwipete(self):
        self.assert_perft(
            "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
            [48, 2039, 97862],
        )

    def test_an_ending_where_en_passant_is_pinned(self):
        self.assert_perft("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", [14, 191, 2812])

    def test_promotions(self):
        self.assert_perft(
            "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
            [6, 264, 9467],
        )

    def test_a_middlegame(self):
        self.assert_perft(
            "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10",
            [46, 2079],
        )


class Fen(unittest.TestCase):
    def test_the_opening_writes_itself_back(self):
        self.assertEqual(
            Position.start().fen(),
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        )

    def test_a_double_push_leaves_an_en_passant_square(self):
        game = play("e2e4")
        self.assertEqual(game.position.fen().split()[3], "e3")

    def test_a_quiet_move_does_not(self):
        game = play("e2e4", "e7e5", "g1f3")
        self.assertEqual(game.position.fen().split()[3], "-")


class Castling(unittest.TestCase):
    BOTH = "r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1"

    def test_both_sides_are_offered(self):
        position = Position.from_fen(self.BOTH)
        kings = {uci(m) for m in position.moves() if m & 63 == parse_square("e1")}
        self.assertIn("e1g1", kings)
        self.assertIn("e1c1", kings)

    def test_the_rook_comes_too(self):
        game = play("e1g1", position=Position.from_fen(self.BOTH))
        self.assertEqual(game.position.fen().split()[0].split("/")[-1], "R4RK1")

    def test_not_out_of_check(self):
        position = Position.from_fen(
            "r3k2r/pppp1ppp/8/4q3/8/8/PPPP1PPP/R3K2R w KQkq - 0 1"
        )
        self.assertNotIn("e1g1", {uci(m) for m in position.moves()})

    def test_not_through_an_attacked_square(self):
        # The rook on f8 covers f1, which the king would have to cross. The
        # f-file has to be genuinely open for that: with a black pawn still on
        # f7 this position says nothing, which is how the first version of this
        # test passed against a board that castled anyway.
        position = Position.from_fen("4kr2/pppp2pp/8/8/8/8/PPPP2PP/R3K2R w KQ - 0 1")
        self.assertNotIn("e1g1", {uci(m) for m in position.moves()})
        self.assertIn("e1c1", {uci(m) for m in position.moves()})

    def test_moving_the_king_ends_both(self):
        game = play(
            "e1f1", "h7h6", "f1e1", "h6h5", position=Position.from_fen(self.BOTH)
        )
        self.assertEqual(game.position.fen().split()[2], "kq")

    def test_capturing_a_rook_on_its_corner_ends_that_side(self):
        position = Position.from_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        game = play("a1a8", position=position)
        self.assertEqual(game.position.fen().split()[2], "Kk")


class EnPassant(unittest.TestCase):
    def test_the_capture_removes_the_pawn_beside_it(self):
        game = play("e2e4", "a7a6", "e4e5", "d7d5", "e5d6")
        board = game.position.fen().split()[0]
        self.assertEqual(board, "rnbqkbnr/1pp1pppp/p2P4/8/8/8/PPPP1PPP/RNBQKBNR")

    def test_it_expires_after_one_move(self):
        game = play("e2e4", "a7a6", "e4e5", "d7d5", "a2a3", "a6a5")
        self.assertNotIn("e5d6", {uci(m) for m in game.legal()})

    def test_it_is_illegal_when_it_would_expose_the_king(self):
        # White king a5, black rook h5: taking on b6 empties the fifth rank.
        position = Position.from_fen("8/8/8/KPp4r/8/8/8/7k w - c6 0 2")
        self.assertNotIn("b5c6", {uci(m) for m in position.moves()})


class Promotion(unittest.TestCase):
    def test_a_pawn_on_the_last_rank_offers_four_pieces(self):
        position = Position.from_fen("8/P7/8/8/8/8/8/K6k w - - 0 1")
        moves = [m for m in position.moves() if move_to(m) == parse_square("a8")]
        self.assertEqual(len(moves), 4)
        self.assertEqual(
            sorted(uci(m) for m in moves), ["a7a8b", "a7a8n", "a7a8q", "a7a8r"]
        )

    def test_the_piece_asked_for_is_the_piece_that_lands(self):
        game = play("a7a8n", position=Position.from_fen("8/P7/8/8/8/8/8/K6k w - - 0 1"))
        self.assertEqual(game.position.fen().split()[0], "N7/8/8/8/8/8/8/K6k")

    def test_a_promotion_is_worth_eight_points_and_takes_nothing(self):
        game = play("a7a8q", position=Position.from_fen("8/P7/8/8/8/8/8/K6k w - - 0 1"))
        self.assertEqual(game.captured(), [])
        self.assertEqual(game.balance(), 9)


class Endings(unittest.TestCase):
    def test_fools_mate(self):
        game = play("f2f3", "e7e5", "g2g4", "d8h4")
        self.assertEqual(game.outcome(), (CHECKMATE, BLACK))
        self.assertTrue(game.over)

    def test_stalemate(self):
        position = Position.from_fen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
        self.assertEqual(position.outcome(), (STALEMATE, None))

    def test_mate_beats_the_fifty_move_rule_to_it(self):
        """A mated king is mated on the hundredth quiet move as well."""
        position = Position.from_fen("7k/6Q1/5K2/8/8/8/8/8 b - - 100 80")
        self.assertEqual(position.outcome()[0], CHECKMATE)

    def test_fifty_moves_without_a_capture(self):
        position = Position.from_fen("8/8/4k3/8/8/4K3/8/R7 w - - 100 80")
        self.assertEqual(position.outcome(), (FIFTY_MOVE, None))

    def test_bare_kings(self):
        self.assertEqual(
            Position.from_fen("8/8/4k3/8/8/4K3/8/8 w - - 0 1").outcome(),
            (INSUFFICIENT, None),
        )

    def test_a_single_minor_cannot_mate(self):
        for fen in (
            "8/8/4k3/8/8/4K3/8/5B2 w - - 0 1",
            "8/8/4kn2/8/8/4K3/8/8 w - - 0 1",
        ):
            self.assertEqual(Position.from_fen(fen).outcome(), (INSUFFICIENT, None))

    def test_two_knights_is_not_called_a_draw(self):
        """Mate cannot be forced, but it is on the board, so the game is on."""
        position = Position.from_fen("8/8/4k3/8/8/4K3/8/5NN1 w - - 0 1")
        self.assertEqual(position.outcome()[0], ONGOING)

    def test_bishops_on_the_same_colour_are_a_draw_and_on_opposite_ones_are_not(self):
        # c7 and c1 are both dark squares; f1 is a light one.
        same = Position.from_fen("8/2b5/4k3/8/8/4K3/8/2B5 w - - 0 1")
        other = Position.from_fen("8/2b5/4k3/8/8/4K3/8/5B2 w - - 0 1")
        self.assertEqual(same.outcome(), (INSUFFICIENT, None))
        self.assertEqual(other.outcome()[0], ONGOING)

    def test_the_same_position_three_times(self):
        game = play(*(("g1f3", "g8f6", "f3g1", "f6g8") * 2))
        self.assertEqual(game.outcome(), (REPETITION, None))

    def test_twice_is_not_three_times(self):
        game = play("g1f3", "g8f6", "f3g1", "f6g8")
        self.assertEqual(game.outcome()[0], ONGOING)


class Clocks(unittest.TestCase):
    def test_a_quiet_move_advances_the_halfmove_counter(self):
        game = play("g1f3", "g8f6")
        self.assertEqual(game.position.halfmove, 2)

    def test_a_pawn_move_resets_it(self):
        game = play("g1f3", "g8f6", "e2e4")
        self.assertEqual(game.position.halfmove, 0)

    def test_a_capture_resets_it(self):
        game = play("e2e4", "d7d5", "g1f3", "g8f6", "e4d5")
        self.assertEqual(game.position.halfmove, 0)

    def test_the_move_number_counts_black_replies(self):
        self.assertEqual(play("e2e4").position.fullmove, 1)
        self.assertEqual(play("e2e4", "e7e5").position.fullmove, 2)


class Playing(unittest.TestCase):
    def test_an_illegal_move_is_refused(self):
        game = Game()
        with self.assertRaises(ValueError):
            game.play(parse_uci("e2e5"))
        self.assertEqual(game.moves, [])

    def test_undo_puts_the_board_back_exactly(self):
        game = play("e2e4", "d7d5")
        before = game.position.fen()
        game.play(parse_uci("e4d5"))
        self.assertTrue(game.undo())
        self.assertEqual(game.position.fen(), before)

    def test_undo_puts_back_a_castle_rook_and_all(self):
        position = Position.from_fen(
            "r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1"
        )
        game = Game(position=position)
        before = game.position.fen()
        game.play(parse_uci("e1c1"))
        game.undo()
        self.assertEqual(game.position.fen(), before)

    def test_undo_puts_back_an_en_passant_capture(self):
        game = play("e2e4", "a7a6", "e4e5", "d7d5")
        before = game.position.fen()
        game.play(parse_uci("e5d6"))
        game.undo()
        self.assertEqual(game.position.fen(), before)

    def test_undo_on_an_untouched_board_does_nothing(self):
        self.assertFalse(Game().undo())

    def test_takeback_returns_the_turn_to_the_person(self):
        game = play("e2e4", "e7e5", "g1f3")
        self.assertTrue(game.takeback(WHITE))
        self.assertEqual(game.turn, WHITE)
        self.assertEqual(game.uci(), ["e2e4", "e7e5"])

    def test_takeback_undoes_the_reply_as_well(self):
        game = play("e2e4", "e7e5", "g1f3", "b8c6")
        game.takeback(WHITE)
        self.assertEqual(game.uci(), ["e2e4", "e7e5"])

    def test_resume_keeps_as_much_as_plays(self):
        game = Game.resume([parse_uci(m) for m in ("e2e4", "e7e5", "e2e4", "g1f3")])
        self.assertEqual(game.uci(), ["e2e4", "e7e5"])

    def test_a_game_is_its_moves(self):
        moves = ("e2e4", "e7e5", "g1f3", "b8c6", "f1b5")
        self.assertEqual(play(*moves).uci(), list(moves))


class Material(unittest.TestCase):
    def test_captures_are_listed_in_the_order_they_happened(self):
        game = play("e2e4", "d7d5", "e4d5", "d8d5", "b1c3", "d5e5", "f1e2")
        self.assertEqual([code & 7 for code in game.captured()], [1, 1])

    def test_the_balance_follows_the_board(self):
        game = play("e2e4", "d7d5", "e4d5")
        self.assertEqual(game.balance(), 1)

    def test_a_promoted_queen_counts_for_its_side(self):
        game = play("a7a8q", position=Position.from_fen("8/P7/8/8/8/8/8/K6k w - - 0 1"))
        self.assertEqual(game.balance(), 9)


class Check(unittest.TestCase):
    def test_a_pinned_piece_may_not_move(self):
        # The knight on e2 is the only thing between the king and the rook.
        position = Position.from_fen("4k3/8/8/8/8/4r3/4N3/4K3 w - - 0 1")
        self.assertFalse(position.in_check())
        self.assertNotIn("e2c3", {uci(m) for m in position.moves()})
        self.assertIn("e1d1", {uci(m) for m in position.moves()})

    def test_in_check_only_the_moves_that_answer_it_are_legal(self):
        position = Position.from_fen("4k3/8/8/8/8/8/8/4K2r w - - 0 1")
        self.assertTrue(position.in_check())
        for code in position.moves():
            made = position.make(code)
            still = position.attacked(position.kings[WHITE], BLACK)
            position.unmake(made)
            self.assertFalse(still, uci(code))

    def test_a_king_may_not_step_next_to_a_king(self):
        position = Position.from_fen("8/8/8/3k4/8/3K4/8/8 w - - 0 1")
        self.assertNotIn("d3d4", {uci(m) for m in position.moves()})


class Promotions(unittest.TestCase):
    def test_the_promotion_field_survives_encoding(self):
        code = parse_uci("a7a8n")
        self.assertEqual(move_promotion(code), KNIGHT)
        self.assertEqual(move_promotion(parse_uci("a7a8q")), QUEEN)
        self.assertEqual(move_promotion(parse_uci("a2a4")), 0)


if __name__ == "__main__":
    unittest.main()
