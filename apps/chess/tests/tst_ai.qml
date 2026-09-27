// The opponent, against 0.1.0's test_ai.py case for case: the cheap claims
// about one position (takes the free queen, finds the mate, answers inside
// the clock), the running evaluation agreeing with a full count, and the
// levels ordered by strength -- played out on short clocks with seeded dice.
import QtQuick
import QtTest
import "../Chess.js" as C
import "../Ai.js" as Ai

TestCase {
  name: "ChessAi"

  readonly property var quick: ({ seconds: 0.2 })

  // mulberry32: the same dice on every run.
  function rng(seed) {
    var a = seed >>> 0
    return function () {
      a = (a + 0x6D2B79F5) >>> 0
      var t = a
      t = Math.imul(t ^ (t >>> 15), t | 1)
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296
    }
  }
  function level(key, changes) { return Ai.withLevel(key, changes || {}) }
  function clock() { return Date.now() / 1000 }
  function choose(p, lv, dice) { return Ai.choose(p, lv, dice || rng(1), clock) }

  // --- levels ---------------------------------------------------------------

  function test_every_level_has_a_key_a_file_can_hold() {
    compare(Ai.LEVELS.length, 3)
    verify(Ai.LEVEL_KEYS.indexOf(Ai.DEFAULT_LEVEL) >= 0)
  }
  function test_an_unknown_key_falls_back_rather_than_raising() {
    compare(Ai.levelFor("impossible").key, Ai.DEFAULT_LEVEL)
  }
  function test_they_get_deeper_and_slower_in_order() {
    for (var i = 0; i + 1 < Ai.LEVELS.length; i++) {
      verify(Ai.LEVELS[i].depth < Ai.LEVELS[i + 1].depth)
      verify(Ai.LEVELS[i].seconds < Ai.LEVELS[i + 1].seconds)
    }
  }

  // --- choosing ---------------------------------------------------------------

  function test_it_plays_a_legal_move() {
    var p = C.start()
    for (var i = 0; i < Ai.LEVEL_KEYS.length; i++) {
      var code = choose(C.copy(p), level(Ai.LEVEL_KEYS[i], quick))
      verify(C.moves(p).indexOf(code) >= 0, Ai.LEVEL_KEYS[i])
    }
  }
  function test_nothing_to_move_is_no_move() {
    compare(choose(C.fromFen("7k/6Q1/5K2/8/8/8/8/8 b - - 0 1"), level("hard", quick)), null)
  }
  function test_one_legal_move_is_played_without_thinking() {
    var p = C.fromFen("k7/7Q/8/8/8/8/8/7K b - - 0 1")
    compare(C.moves(p).length, 1)
    var t = Ai.think(p, level("hard"), rng(1), clock)
    compare(t.nodes, 0)
    compare(C.uci(t.move), C.uci(C.moves(p)[0]))
  }
  function test_the_position_it_was_given_is_not_touched() {
    var p = C.start()
    var before = C.fen(p)
    choose(p, level("hard", quick))
    compare(C.fen(p), before)
    compare(p.keysH.length, 1)
  }

  // --- play ----------------------------------------------------------------------

  function test_it_takes_a_free_queen() {
    var p = C.fromFen("4k3/8/8/3q4/4P3/8/8/4K3 w - - 0 1")
    compare(C.uci(choose(C.copy(p), level("medium", quick))), "e4d5")
    compare(C.uci(choose(C.copy(p), level("hard", quick))), "e4d5")
  }
  function test_it_finds_mate_in_one() {
    var p = C.fromFen("6k1/5ppp/8/8/8/8/8/R3K2R w KQ - 0 1")
    compare(C.uci(choose(C.copy(p), level("medium", quick))), "a1a8")
    compare(C.uci(choose(C.copy(p), level("hard", quick))), "a1a8")
  }
  function test_it_gets_out_of_check() {
    var p = C.fromFen("4k3/8/8/8/8/8/4r3/4K3 w - - 0 1")
    verify(C.moves(p).indexOf(choose(C.copy(p), level("medium", quick))) >= 0)
  }
  function test_it_does_not_walk_into_a_recapture() {
    var p = C.fromFen("3qk3/8/8/3p4/8/5B2/8/4K3 w - - 0 1")
    verify(C.uci(choose(C.copy(p), level("hard", quick))) !== "f3d5")
  }
  function test_without_quiescence_it_does() {
    var p = C.fromFen("3qk3/8/8/3p4/8/5B2/8/4K3 w - - 0 1")
    compare(C.uci(choose(C.copy(p), level("easy", { seconds: 0.2, blunder: 0, depth: 1 }))), "f3d5")
  }

  // --- the clock -------------------------------------------------------------------

  function test_a_short_clock_still_answers() {
    var p = C.start()
    var started = Date.now()
    verify(C.moves(p).indexOf(choose(C.copy(p), level("hard", { seconds: 0.05 }))) >= 0)
    verify(Date.now() - started < 2000)
  }
  function test_a_longer_clock_reaches_further() {
    var p = C.fromFen("r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 0 1")
    var shallow = Ai.think(C.copy(p), level("hard", { seconds: 0.02, depth: 6 }), rng(1), clock)
    var deep = Ai.think(C.copy(p), level("hard", { seconds: 2.0, depth: 6 }), rng(1), clock)
    verify(shallow.depth < deep.depth, shallow.depth + " vs " + deep.depth)
  }
  function test_the_clock_leaves_nothing_behind_on_the_board() {
    var p = C.start()
    var before = C.fen(p)
    Ai.think(p, level("hard", { seconds: 0.01, depth: 6 }), rng(1), clock)
    compare(C.fen(p), before)
  }

  // --- blunders ----------------------------------------------------------------------

  function test_easy_sometimes_plays_something_else_entirely() {
    var p = C.fromFen("4k3/8/8/3q4/4P3/8/8/4K3 w - - 0 1")
    var always = level("easy", { seconds: 0.2, blunder: 1 })
    var played = ({})
    for (var seed = 0; seed < 12; seed++) played[C.uci(choose(C.copy(p), always, rng(seed)))] = true
    verify(Object.keys(played).length > 1)
  }
  function test_but_never_while_in_check() {
    var p = C.fromFen("4q3/8/8/8/8/8/PPP2PPP/4K3 w - - 0 1")
    verify(C.inCheck(p))
    verify(C.moves(p).length > 1)
    var always = level("easy", { seconds: 0.2, blunder: 1 })
    var played = ({})
    for (var seed = 0; seed < 8; seed++) played[C.uci(choose(C.copy(p), always, rng(seed)))] = true
    compare(Object.keys(played).length, 1)
  }

  // --- evaluation ----------------------------------------------------------------------

  function test_the_running_total_agrees_with_a_full_count() {
    var dice = rng(11)
    var g = C.game()
    var score = Ai.advantage(g.position)
    for (var i = 0; i < 140; i++) {
      var legal = C.moves(g.position)
      if (!legal.length) break
      var code = legal[Math.floor(dice() * legal.length)]
      var made = C.make(g.position, code)
      g.moves.push(code); g.made.push(made)
      score += Ai.delta(made)
      compare(score, Ai.advantage(g.position), C.uci(code))
    }
  }
  function test_material_outweighs_position() {
    var even = C.start()
    var ahead = C.fromFen("rnb1kbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
    verify(Ai.advantage(ahead) > Ai.advantage(even) + Ai.VALUES[5] / 2)
  }
  function test_a_king_alone_is_driven_to_the_edge() {
    var middle = C.fromFen("8/8/3k4/8/8/8/R7/4K3 w - - 0 1")
    var corner = C.fromFen("8/8/8/8/8/8/R7/k3K3 w - - 0 1")
    verify(Ai.evaluate(corner, Ai.advantage(corner), 3) > Ai.evaluate(middle, Ai.advantage(middle), 3))
  }

  // --- endgames ---------------------------------------------------------------------------

  function mate(fen, key, plies) {
    var g = C.game(C.fromFen(fen))
    var strong = level(key, { seconds: 0.3 }), weak = level("easy", { seconds: 0.05 })
    var dice = rng(3)
    while (C.outcome(g.position).state === C.ONGOING && g.moves.length < plies) {
      var side = g.position.turn === C.WHITE ? strong : weak
      verify(C.apply(g, choose(g.position, side, dice)))
    }
    return C.outcome(g.position)
  }
  function test_a_rook_mates() {
    var o = mate("8/8/8/4k3/8/8/8/R3K3 w Q - 0 1", "hard", 70)
    compare(o.state, C.CHECKMATE)
    compare(o.winner, C.WHITE)
  }
  function test_a_queen_mates() {
    var o = mate("8/8/8/3k4/8/8/8/3QK3 w - - 0 1", "medium", 70)
    compare(o.state, C.CHECKMATE)
    compare(o.winner, C.WHITE)
  }

  // --- strength ------------------------------------------------------------------------------

  function test_hard_beats_easy_from_both_sides() {
    var strong = level("hard", { seconds: 0.12, depth: 3 })
    var weak = level("easy", { seconds: 0.04 })
    var wins = 0
    for (var seed = 0; seed < 4; seed++) {
      var dice = rng(seed)
      var g = C.game()
      var hard = seed % 2 === 0 ? C.WHITE : C.BLACK
      while (C.outcome(g.position).state === C.ONGOING && g.moves.length < 160)
        C.apply(g, choose(g.position, g.position.turn === hard ? strong : weak, dice))
      if (C.outcome(g.position).winner === hard) wins += 1
    }
    verify(wins >= 3, wins + " of 4")
  }

  // --- ordering ------------------------------------------------------------------------------

  function test_captures_are_tried_before_quiet_moves() {
    var p = C.fromFen("4k3/8/8/3q4/4P3/8/8/4K3 w - - 0 1")
    compare(C.uci(Ai.ordered(p, C.moves(p))[0]), "e4d5")
  }
  function test_a_richer_victim_comes_first() {
    var p = C.fromFen("4k3/8/8/2n1q3/3P4/8/8/5K2 w - - 0 1")
    var o = Ai.ordered(p, C.moves(p))
    compare(C.uci(o[0]), "d4e5")
    compare(C.uci(o[1]), "d4c5")
  }
  function test_a_promotion_counts_as_tactical() {
    var p = C.fromFen("4k3/P7/8/8/8/8/8/4K3 w - - 0 1")
    compare(C.pseudoMoves(p, true).map(C.uci), ["a7a8q"])
  }
  function test_parse_uci_and_the_search_agree_about_promotion() {
    var p = C.fromFen("4k3/P7/8/8/8/8/8/4K3 w - - 0 1")
    compare(choose(C.copy(p), level("medium", quick)), C.parseUci("a7a8q"))
  }
}
