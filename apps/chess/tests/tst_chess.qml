// The rules, against 0.1.0's test_chess.py case for case. The spine is perft
// -- every legal move to a fixed depth, the leaves counted -- against the
// positions the chess programming community keeps for exactly this: a single
// wrong number is a rule that is wrong somewhere.
import QtQuick
import QtTest
import "../Chess.js" as C

TestCase {
  name: "ChessRules"

  function perft(p, depth) {
    if (depth === 0) return 1
    var us = p.turn
    var total = 0
    var list = C.pseudoMoves(p, false)
    for (var i = 0; i < list.length; i++) {
      var made = C.make(p, list[i])
      if (!C.attacked(p, p.kings[us], p.turn)) total += depth === 1 ? 1 : perft(p, depth - 1)
      C.unmake(p, made)
    }
    return total
  }

  function play(moves, fen) {
    var g = C.game(fen ? C.fromFen(fen) : null)
    for (var i = 0; i < moves.length; i++) {
      var code = C.parseUci(moves[i])
      verify(C.apply(g, code), moves[i] + " should be legal")
    }
    return g
  }

  function ucis(p) { return C.moves(p).map(C.uci) }

  function assertPerft(fen, counts) {
    var p = C.fromFen(fen)
    for (var d = 0; d < counts.length; d++) {
      compare(perft(p, d + 1), counts[d], fen + " at depth " + (d + 1))
      compare(C.fen(p), fen)
    }
  }

  // --- squares --------------------------------------------------------------

  function test_a1_is_zero_and_h8_is_sixty_three() {
    compare(C.parseSquare("a1"), 0)
    compare(C.parseSquare("h8"), 63)
    compare(C.name(0), "a1")
    compare(C.name(63), "h8")
  }

  function test_every_square_survives_the_round_trip() {
    for (var c = 0; c < 64; c++) compare(C.parseSquare(C.name(c)), c)
  }

  function test_a_move_survives_the_round_trip() {
    var list = ["e2e4", "a7a8q", "e1g1", "h2g1n"]
    for (var i = 0; i < list.length; i++) compare(C.uci(C.parseUci(list[i])), list[i])
  }

  function test_nonsense_is_refused() {
    var list = ["", "e2", "j2j4", "e2e9", "e7e8k", "e7e8x"]
    for (var i = 0; i < list.length; i++) compare(C.parseUci(list[i]), -1, list[i])
  }

  // --- perft ------------------------------------------------------------------

  function test_perft_the_opening() { assertPerft(C.fen(C.start()), [20, 400, 8902, 197281]) }
  function test_perft_kiwipete() {
    assertPerft("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", [48, 2039, 97862])
  }
  function test_perft_an_ending_where_en_passant_is_pinned() {
    assertPerft("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", [14, 191, 2812])
  }
  function test_perft_promotions() {
    assertPerft("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", [6, 264, 9467])
  }
  function test_perft_a_middlegame() {
    assertPerft("r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10", [46, 2079])
  }

  // --- fen ----------------------------------------------------------------------

  function test_the_opening_writes_itself_back() {
    compare(C.fen(C.start()), "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
  }
  function test_a_double_push_leaves_an_en_passant_square() {
    compare(C.fen(play(["e2e4"]).position).split(" ")[3], "e3")
  }
  function test_a_quiet_move_does_not() {
    compare(C.fen(play(["e2e4", "e7e5", "g1f3"]).position).split(" ")[3], "-")
  }

  // --- castling -----------------------------------------------------------------

  readonly property string both: "r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1"

  function test_both_sides_are_offered() {
    var list = ucis(C.fromFen(both))
    verify(list.indexOf("e1g1") >= 0)
    verify(list.indexOf("e1c1") >= 0)
  }
  function test_the_rook_comes_too() {
    var ranks = C.fen(play(["e1g1"], both).position).split(" ")[0].split("/")
    compare(ranks[7], "R4RK1")
  }
  function test_not_out_of_check() {
    verify(ucis(C.fromFen("r3k2r/pppp1ppp/8/4q3/8/8/PPPP1PPP/R3K2R w KQkq - 0 1")).indexOf("e1g1") < 0)
  }
  function test_not_through_an_attacked_square() {
    var list = ucis(C.fromFen("4kr2/pppp2pp/8/8/8/8/PPPP2PP/R3K2R w KQ - 0 1"))
    verify(list.indexOf("e1g1") < 0)
    verify(list.indexOf("e1c1") >= 0)
  }
  function test_moving_the_king_ends_both() {
    compare(C.fen(play(["e1f1", "h7h6", "f1e1", "h6h5"], both).position).split(" ")[2], "kq")
  }
  function test_capturing_a_rook_on_its_corner_ends_that_side() {
    compare(C.fen(play(["a1a8"], "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1").position).split(" ")[2], "Kk")
  }

  // --- en passant ---------------------------------------------------------------

  function test_the_capture_removes_the_pawn_beside_it() {
    compare(C.fen(play(["e2e4", "a7a6", "e4e5", "d7d5", "e5d6"]).position).split(" ")[0],
            "rnbqkbnr/1pp1pppp/p2P4/8/8/8/PPPP1PPP/RNBQKBNR")
  }
  function test_it_expires_after_one_move() {
    verify(ucis(play(["e2e4", "a7a6", "e4e5", "d7d5", "a2a3", "a6a5"]).position).indexOf("e5d6") < 0)
  }
  function test_it_is_illegal_when_it_would_expose_the_king() {
    verify(ucis(C.fromFen("8/8/8/KPp4r/8/8/8/7k w - c6 0 2")).indexOf("b5c6") < 0)
  }

  // --- promotion ------------------------------------------------------------------

  readonly property string pawnFen: "8/P7/8/8/8/8/8/K6k w - - 0 1"

  function test_a_pawn_on_the_last_rank_offers_four_pieces() {
    var p = C.fromFen(pawnFen)
    var list = C.moves(p).filter(function (m) { return C.moveTo(m) === C.parseSquare("a8") }).map(C.uci).sort()
    compare(list, ["a7a8b", "a7a8n", "a7a8q", "a7a8r"])
  }
  function test_the_piece_asked_for_is_the_piece_that_lands() {
    compare(C.fen(play(["a7a8n"], pawnFen).position).split(" ")[0], "N7/8/8/8/8/8/8/K6k")
  }
  function test_a_promotion_is_worth_eight_points_and_takes_nothing() {
    var g = play(["a7a8q"], pawnFen)
    compare(C.captured(g), [])
    compare(C.balance(g.position), 9)
  }
  function test_the_promotion_field_survives_encoding() {
    compare(C.movePromotion(C.parseUci("a7a8n")), C.KNIGHT)
    compare(C.movePromotion(C.parseUci("a7a8q")), C.QUEEN)
    compare(C.movePromotion(C.parseUci("a2a4")), 0)
  }

  // --- endings --------------------------------------------------------------------

  function test_fools_mate() {
    var o = C.outcome(play(["f2f3", "e7e5", "g2g4", "d8h4"]).position)
    compare(o.state, C.CHECKMATE)
    compare(o.winner, C.BLACK)
  }
  function test_stalemate() {
    compare(C.outcome(C.fromFen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")).state, C.STALEMATE)
  }
  function test_mate_beats_the_fifty_move_rule_to_it() {
    compare(C.outcome(C.fromFen("7k/6Q1/5K2/8/8/8/8/8 b - - 100 80")).state, C.CHECKMATE)
  }
  function test_fifty_moves_without_a_capture() {
    compare(C.outcome(C.fromFen("8/8/4k3/8/8/4K3/8/R7 w - - 100 80")).state, C.FIFTY_MOVE)
  }
  function test_bare_kings() {
    compare(C.outcome(C.fromFen("8/8/4k3/8/8/4K3/8/8 w - - 0 1")).state, C.INSUFFICIENT)
  }
  function test_a_single_minor_cannot_mate() {
    compare(C.outcome(C.fromFen("8/8/4k3/8/8/4K3/8/5B2 w - - 0 1")).state, C.INSUFFICIENT)
    compare(C.outcome(C.fromFen("8/8/4kn2/8/8/4K3/8/8 w - - 0 1")).state, C.INSUFFICIENT)
  }
  function test_two_knights_is_not_called_a_draw() {
    compare(C.outcome(C.fromFen("8/8/4k3/8/8/4K3/8/5NN1 w - - 0 1")).state, C.ONGOING)
  }
  function test_bishops_on_the_same_colour_are_a_draw_and_on_opposite_ones_are_not() {
    compare(C.outcome(C.fromFen("8/2b5/4k3/8/8/4K3/8/2B5 w - - 0 1")).state, C.INSUFFICIENT)
    compare(C.outcome(C.fromFen("8/2b5/4k3/8/8/4K3/8/5B2 w - - 0 1")).state, C.ONGOING)
  }
  function test_the_same_position_three_times() {
    var seq = ["g1f3", "g8f6", "f3g1", "f6g8"]
    compare(C.outcome(play(seq.concat(seq)).position).state, C.REPETITION)
  }
  function test_twice_is_not_three_times() {
    compare(C.outcome(play(["g1f3", "g8f6", "f3g1", "f6g8"]).position).state, C.ONGOING)
  }

  // --- clocks -----------------------------------------------------------------------

  function test_a_quiet_move_advances_the_halfmove_counter() {
    compare(play(["g1f3", "g8f6"]).position.halfmove, 2)
  }
  function test_a_pawn_move_resets_it() {
    compare(play(["g1f3", "g8f6", "e2e4"]).position.halfmove, 0)
  }
  function test_a_capture_resets_it() {
    compare(play(["e2e4", "d7d5", "g1f3", "g8f6", "e4d5"]).position.halfmove, 0)
  }
  function test_the_move_number_counts_black_replies() {
    compare(play(["e2e4"]).position.fullmove, 1)
    compare(play(["e2e4", "e7e5"]).position.fullmove, 2)
  }

  // --- playing ------------------------------------------------------------------------

  function test_an_illegal_move_is_refused() {
    var g = C.game()
    verify(!C.apply(g, C.parseUci("e2e5")))
    compare(g.moves, [])
  }
  function test_undo_puts_the_board_back_exactly() {
    var g = play(["e2e4", "d7d5"])
    var before = C.fen(g.position)
    C.apply(g, C.parseUci("e4d5"))
    verify(C.undo(g))
    compare(C.fen(g.position), before)
  }
  function test_undo_puts_back_a_castle_rook_and_all() {
    var g = C.game(C.fromFen(both))
    var before = C.fen(g.position)
    C.apply(g, C.parseUci("e1c1"))
    C.undo(g)
    compare(C.fen(g.position), before)
  }
  function test_undo_puts_back_an_en_passant_capture() {
    var g = play(["e2e4", "a7a6", "e4e5", "d7d5"])
    var before = C.fen(g.position)
    C.apply(g, C.parseUci("e5d6"))
    C.undo(g)
    compare(C.fen(g.position), before)
  }
  function test_undo_on_an_untouched_board_does_nothing() { verify(!C.undo(C.game())) }
  function test_takeback_returns_the_turn_to_the_person() {
    var g = play(["e2e4", "e7e5", "g1f3"])
    verify(C.takeback(g, C.WHITE))
    compare(g.position.turn, C.WHITE)
    compare(C.gameUci(g), ["e2e4", "e7e5"])
  }
  function test_takeback_undoes_the_reply_as_well() {
    var g = play(["e2e4", "e7e5", "g1f3", "b8c6"])
    C.takeback(g, C.WHITE)
    compare(C.gameUci(g), ["e2e4", "e7e5"])
  }
  function test_resume_keeps_as_much_as_plays() {
    compare(C.gameUci(C.resumeUci(["e2e4", "e7e5", "e2e4", "g1f3"])), ["e2e4", "e7e5"])
  }
  function test_a_game_is_its_moves() {
    var moves = ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5"]
    compare(C.gameUci(play(moves)), moves)
  }

  // --- material ---------------------------------------------------------------------

  function test_captures_are_listed_in_the_order_they_happened() {
    var g = play(["e2e4", "d7d5", "e4d5", "d8d5", "b1c3", "d5e5", "f1e2"])
    compare(C.captured(g).map(function (c) { return c & 7 }), [1, 1])
  }
  function test_the_balance_follows_the_board() {
    compare(C.balance(play(["e2e4", "d7d5", "e4d5"]).position), 1)
  }

  // --- check ------------------------------------------------------------------------

  function test_a_pinned_piece_may_not_move() {
    var p = C.fromFen("4k3/8/8/8/8/4r3/4N3/4K3 w - - 0 1")
    verify(!C.inCheck(p))
    verify(ucis(p).indexOf("e2c3") < 0)
    verify(ucis(p).indexOf("e1d1") >= 0)
  }
  function test_in_check_only_the_moves_that_answer_it_are_legal() {
    var p = C.fromFen("4k3/8/8/8/8/8/8/4K2r w - - 0 1")
    verify(C.inCheck(p))
    var list = C.moves(p)
    for (var i = 0; i < list.length; i++) {
      var made = C.make(p, list[i])
      var still = C.attacked(p, p.kings[C.WHITE], C.BLACK)
      C.unmake(p, made)
      verify(!still, C.uci(list[i]))
    }
  }
  function test_a_king_may_not_step_next_to_a_king() {
    verify(ucis(C.fromFen("8/8/8/3k4/8/3K4/8/8 w - - 0 1")).indexOf("d3d4") < 0)
  }

  // --- notation (new: the move list) ------------------------------------------------

  function test_moves_are_named_as_people_write_them() {
    var g = play(["e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "a7a6", "b5c6", "d7c6", "e1g1"])
    compare(C.sanList(g), ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6", "Bxc6", "dxc6", "O-O"])
  }
  function test_check_mate_and_promotion_are_marked() {
    compare(C.sanList(play(["f2f3", "e7e5", "g2g4", "d8h4"]))[3], "Qh4#")
    compare(C.sanList(play(["a7a8q"], pawnFen)), ["a8=Q+"])
  }
  function test_two_knights_to_one_square_say_which() {
    var p = C.fromFen("4k3/8/8/8/8/8/8/1N2KN2 w - - 0 1")
    compare(C.san(p, C.parseUci("b1d2")), "Nbd2")
  }
}
