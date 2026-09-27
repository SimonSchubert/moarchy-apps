// The opponent, against the GTK version's test_ai.py (0.1.0), case for case.
//
// The test that matters most is not about strength: **a turn is not always one
// ply.** Closing a mill earns a removal made by the same side, and a search
// that flips the sign there plays well until it makes a mill and then throws a
// piece away -- so it is tested directly, where the difference is one piece.
//
// The clock is held still wherever a result depends on depth, so the depth is
// the level's ceiling and not how fast this machine is.
import QtQuick
import QtTest
import "../Mill.js" as M
import "../Ai.js" as Ai

TestCase {
  name: "MillAi"

  function board(white, black, turn, placed, removing) {
    var w = 0, b = 0, i
    for (i = 0; i < (white || []).length; i++) w |= 1 << white[i]
    for (i = 0; i < (black || []).length; i++) b |= 1 << black[i]
    return M.position(w, b, turn || M.WHITE, placed || [M.PIECES, M.PIECES], removing)
  }

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

  function still() { return 0 }

  // A shipped level with the clock and ceiling turned down.
  function quick(key, depth) {
    var base = Ai.levelFor(key)
    return { key: base.key, label: base.label, blurb: base.blurb, seconds: 1, depth: depth || 4, slack: base.slack }
  }

  // One move's worth, to a fixed depth with a full window: bounds from a
  // narrowing window are not comparable with each other.
  function value(p, move, depth) {
    var child = M.play(p, move)
    var limit = Ai.WIN * 2
    if (child.turn === p.turn) return Ai.search(child, depth - 1, -limit, limit, 1, still)
    return -Ai.search(child, depth - 1, -limit, limit, 1, still)
  }

  // --- the half turn

  function test_it_takes_a_mill_that_wins_the_game() {
    // Black is down to three, so the piece a mill takes is the game.
    var p = board([0, 1, 3, 20], [8, 14, 19])
    var depths = [2, 4, 6]
    for (var i = 0; i < depths.length; i++) {
      var level = { key: "hard", seconds: 1, depth: depths[i], slack: 0 }
      compare(M.unpack(Ai.choose(p, level, still, rng(1))), [3, 2], "at depth " + depths[i])
    }
  }

  function test_it_takes_the_loose_piece_rather_than_the_one_in_a_mill() {
    var p = board([0, 1, 2], [8, 9, 10, 16], M.WHITE, [3, 4], true)
    compare(M.unpack(Ai.choose(p, quick("medium"), still, rng(1)))[1], 16)
  }

  function test_a_removal_is_valued_as_a_gain_and_not_a_loss() {
    var p = board([0, 1, 22], [8, 19, 5], M.WHITE, [3, 3])
    var mill = value(p, M.placeMove(2), 2)
    var quiet = value(p, M.placeMove(23), 2)
    verify(mill > quiet + Ai.MAN, "mill " + mill + ", quiet " + quiet)
  }

  function test_taking_a_piece_leaves_the_board_worth_more() {
    var owed = board([0, 1, 2], [8, 16, 18], M.WHITE, [3, 3], true)
    var settled = board([0, 1, 2], [8, 16, 18], M.BLACK, [3, 3])
    verify(Ai.evaluate(M.play(owed, M.placeMove(8)), M.WHITE) > Ai.evaluate(settled, M.WHITE))
  }

  function test_it_blocks_a_mill_it_can_see_coming() {
    var p = board([20], [8, 9], M.WHITE, [1, 2])
    var level = { key: "hard", seconds: 1, depth: 4, slack: 0 }
    compare(M.unpack(Ai.choose(p, level, still, rng(1)))[1], 10)
  }

  // --- the search

  function test_every_move_offered_is_a_legal_one() {
    var dice = rng(3)
    for (var k = 0; k < Ai.LEVEL_KEYS.length; k++) {
      var level = quick(Ai.LEVEL_KEYS[k], 2)
      var g = M.newGame()
      for (var n = 0; n < 40 && !M.gameOver(g); n++) {
        var move = Ai.choose(g.position, level, still, dice)
        verify(M.isLegal(g.position, move), Ai.LEVEL_KEYS[k] + " " + move)
        M.apply(g, move)
      }
    }
  }

  function test_a_board_with_nothing_to_play_offers_nothing() {
    verify(M.lost(board([0, 2], [8, 10, 12]), M.WHITE))
    compare(Ai.choose(board([0, 1, 2, 16], [7, 9, 3, 17, 23]), quick("easy"), still, rng(1)), -1)
  }

  function test_the_only_move_on_the_board_is_played_without_thinking() {
    var lone = board([0, 1], [8], M.WHITE, [2, 1], true)
    compare(M.moves(lone).length, 1)
    // A clock that has already run out: the answer must not need it.
    var late = function () { return 1e9 }
    compare(Ai.choose(lone, { seconds: 5, depth: 12, slack: 0 }, late, rng(1)), M.placeMove(8))
    compare(M.moves(board([0, 1], [8, 9], M.WHITE, [2, 2], true)).length, 2)
  }

  function test_an_unknown_level_is_the_middle_one() {
    compare(Ai.levelFor("nonsense").key, "medium")
  }

  function test_the_opening_is_answered_inside_its_own_clock() {
    var level = Ai.levelFor("hard")
    var clock = function () { return Date.now() / 1000 }
    var started = Date.now()
    Ai.choose(M.OPENING, level, clock, rng(1))
    // The clock plus one ply's overshoot: the deadline is checked on the way
    // into a node, so the last node started is allowed to finish.
    verify((Date.now() - started) / 1000 < level.seconds * 2 + 1)
  }

  // --- the evaluation

  function test_a_piece_is_worth_more_than_anything_else() {
    var ahead = board([0, 1, 20, 22], [8, 10, 12])
    var level = board([0, 1, 20], [8, 10, 12])
    verify(Ai.evaluate(ahead, M.WHITE) > Ai.evaluate(level, M.WHITE) + 50)
  }

  function test_a_mill_is_worth_having_and_less_than_a_piece() {
    var better = Ai.evaluate(board([0, 1, 2], [8, 10, 12]), M.WHITE)
      - Ai.evaluate(board([0, 1, 20], [8, 10, 12]), M.WHITE)
    verify(better > 0)
    verify(better < Ai.MAN)
  }

  function test_a_lost_board_is_worth_losing() {
    var lost = board([0, 2], [8, 10, 12])
    verify(Ai.evaluate(lost, M.WHITE) <= -Ai.WIN)
    verify(Ai.evaluate(lost, M.BLACK) >= Ai.WIN)
  }

  function test_it_is_symmetrical() {
    var p = board([0, 1, 20], [8, 10, 12])
    compare(Ai.evaluate(p, M.WHITE), -Ai.evaluate(p, M.BLACK))
  }

  // --- the levels are ordered

  function test_a_deeper_search_beats_a_shallower_one() {
    // Played at a fixed depth rather than on a clock: the ordering comes from
    // the depth reached, and a clock would make it this machine's speed.
    var deep = { key: "deep", seconds: 1, depth: 3, slack: 0 }
    var shallow = { key: "shallow", seconds: 1, depth: 1, slack: 0 }
    var dice = rng(20260913)
    var better = 0, worse = 0
    for (var n = 0; n < 4; n++) {
      var sides = n % 2 === 0 ? [deep, shallow] : [shallow, deep]
      var g = M.newGame()
      while (!M.gameOver(g) && g.moves.length < 260)
        M.apply(g, Ai.choose(g.position, sides[g.position.turn], still, dice))
      var w = M.winner(g.position)
      if (w === null || M.drawn(g)) continue
      if (sides[w] === deep) better += 1
      else worse += 1
    }
    verify(better > worse, "deep " + better + ", shallow " + worse)
  }

  function test_the_shipped_levels_get_slower_and_deeper_in_order() {
    for (var i = 0; i + 1 < Ai.LEVELS.length; i++) {
      var easier = Ai.LEVELS[i], harder = Ai.LEVELS[i + 1]
      verify(easier.seconds <= harder.seconds, easier.key)
      verify(easier.depth <= harder.depth, easier.key)
      verify(easier.slack >= harder.slack, easier.key)
    }
    compare(Ai.levelFor("hard").slack, 0)
  }

  function test_easy_errs_without_giving_pieces_away() {
    var dice = rng(7)
    var scored = [[0, 1], [-Ai.MAN * 3, 2], [-5, 3]]
    for (var i = 0; i < 50; i++) verify([1, 3].indexOf(Ai.casual(scored, dice)) >= 0)
  }

  // --- travelling

  function test_it_moves_a_piece_rather_than_placing_one_after_the_hand_is_empty() {
    var move = Ai.choose(board([0, 20], [8, 22]), quick("medium"), still, rng(2))
    verify(M.unpack(move)[0] >= 0)
  }

  function test_and_flies_when_it_is_down_to_three() {
    var p = board([0, 2, 4], [9, 11, 13, 15])
    verify(M.flying(p, M.WHITE))
    verify(M.isLegal(p, Ai.choose(p, quick("easy"), still, rng(2))))
    verify(M.moves(p).indexOf(M.travel(0, 20)) >= 0)
  }
}
