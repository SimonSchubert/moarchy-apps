// The rules, against the GTK version's test_mill.py (0.1.0), case for case.
//
// The three that carry weight are the three this game is about: that the
// adjacency is a ring and a spoke rather than a grid, that a mill earns a
// removal made by the same side, and that the piece you may take is not one in
// a mill unless every one of them is.
import QtQuick
import QtTest
import "../Mill.js" as M

TestCase {
  name: "MillRules"

  function board(white, black, turn, placed, removing) {
    var w = 0, b = 0, i
    for (i = 0; i < (white || []).length; i++) w |= 1 << white[i]
    for (i = 0; i < (black || []).length; i++) b |= 1 << black[i]
    return M.position(w, b, turn || M.WHITE, placed || [M.PIECES, M.PIECES], removing)
  }

  function sorted(list) { return list.slice().sort(function (a, b) { return a - b }) }

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

  // --- the board

  function test_there_are_twenty_four_points_in_three_rings() {
    compare(M.POINTS, 24)
    for (var s = 0; s < M.POINTS; s++) compare(M.point(M.ringOf(s), M.placeOf(s)), s)
  }

  function test_a_corner_touches_two_points_and_a_midpoint_three_or_four() {
    for (var s = 0; s < M.POINTS; s++) {
      var ring = M.ringOf(s), place = M.placeOf(s)
      var want = place % 2 === 0 ? 2 : ring === 1 ? 4 : 3
      compare(M.NEIGHBOURS[s].length, want, M.notation(s))
    }
  }

  function test_adjacency_runs_both_ways() {
    for (var s = 0; s < M.POINTS; s++)
      for (var i = 0; i < M.NEIGHBOURS[s].length; i++)
        verify(M.NEIGHBOURS[M.NEIGHBOURS[s][i]].indexOf(s) >= 0, s + " -> " + M.NEIGHBOURS[s][i])
  }

  function test_nothing_crosses_between_rings_except_along_a_spoke() {
    for (var s = 0; s < M.POINTS; s++) {
      for (var i = 0; i < M.NEIGHBOURS[s].length; i++) {
        var n = M.NEIGHBOURS[s][i]
        if (M.ringOf(n) === M.ringOf(s)) continue
        compare(M.placeOf(s) % 2, 1)
        compare(M.placeOf(s), M.placeOf(n))
        compare(Math.abs(M.ringOf(s) - M.ringOf(n)), 1)
      }
    }
  }

  function test_there_are_sixteen_mills_and_every_point_is_in_two() {
    compare(M.MILLS.length, 16)
    var held = []
    for (var s = 0; s < M.POINTS; s++) held.push(0)
    for (var i = 0; i < M.MILLS.length; i++) {
      var mill = M.MILLS[i]
      compare(mill.length, 3)
      verify(mill[0] !== mill[1] && mill[1] !== mill[2] && mill[0] !== mill[2])
      for (var j = 0; j < 3; j++) held[mill[j]] += 1
    }
    for (var k = 0; k < M.POINTS; k++) compare(held[k], 2)
  }

  function test_every_mill_is_three_points_in_a_line() {
    for (var i = 0; i < M.MILLS.length; i++) {
      var m = M.MILLS[i]
      var oneRing = M.ringOf(m[0]) === M.ringOf(m[1]) && M.ringOf(m[1]) === M.ringOf(m[2])
      var onePlace = M.placeOf(m[0]) === M.placeOf(m[1]) && M.placeOf(m[1]) === M.placeOf(m[2])
      verify(oneRing || onePlace, String(m))
    }
  }

  function test_a_move_survives_being_a_number() {
    for (var s = 0; s < M.POINTS; s++) compare(M.unpack(M.placeMove(s)), [-1, s])
    for (var src = 0; src < M.POINTS; src++)
      for (var i = 0; i < M.NEIGHBOURS[src].length; i++)
        compare(M.unpack(M.travel(src, M.NEIGHBOURS[src][i])), [src, M.NEIGHBOURS[src][i]])
  }

  function test_a_move_says_what_it_is() {
    compare(M.notation(M.placeMove(0)), "a1")
    compare(M.notation(M.travel(0, 1)), "a1-a2")
    compare(M.notation(M.placeMove(16)), "c1")
  }

  // --- placing

  function test_the_opening_offers_every_point_and_nothing_else() {
    compare(M.moves(M.OPENING).length, M.POINTS)
    verify(M.placing(M.OPENING, M.WHITE))
    compare(M.left(M.OPENING, M.WHITE), M.PIECES)
  }

  function test_a_placement_uses_one_from_the_hand() {
    var after = M.play(M.OPENING, M.placeMove(0))
    compare(M.left(after, M.WHITE), M.PIECES - 1)
    compare(M.count(after, M.WHITE), 1)
    compare(after.turn, M.BLACK)
  }

  function test_you_cannot_place_on_a_point_that_is_taken() {
    verify(!M.isLegal(M.play(M.OPENING, M.placeMove(0)), M.placeMove(0)))
  }

  function test_the_phase_ends_when_the_hand_is_empty() {
    var p = M.OPENING
    for (var s = 0; s < 2 * M.PIECES; s++) p = M.play(p, M.placeMove(s))
    verify(!M.placing(p, M.WHITE))
    verify(!M.placing(p, M.BLACK))
    compare(M.left(p, M.WHITE), 0)
  }

  // --- moving

  function test_a_piece_moves_only_to_a_point_it_touches() {
    var p = board([0], [8])
    compare(sorted(M.destinations(p, 0)), sorted(M.NEIGHBOURS[0]))
    for (var i = 0; i < M.NEIGHBOURS[0].length; i++) verify(M.isLegal(p, M.travel(0, M.NEIGHBOURS[0][i])))
    verify(!M.isLegal(p, M.travel(0, 16)))
  }

  function test_a_side_with_three_left_may_go_anywhere() {
    var p = board([0, 2, 4], [8, 10, 12, 14])
    verify(M.flying(p, M.WHITE))
    verify(M.moves(p).indexOf(M.travel(0, 20)) >= 0)
  }

  function test_three_pieces_in_the_opening_is_not_flying() {
    verify(!M.flying(board([0, 2, 4], [8, 10, 12], M.WHITE, [3, 3]), M.WHITE))
  }

  function test_a_side_with_nowhere_to_go_has_lost() {
    var p = board([0, 1, 2, 16], [7, 9, 3, 17, 23])
    compare(M.moves(p), [])
    verify(M.lost(p, M.WHITE))
    compare(M.winner(p), M.BLACK)
  }

  function test_two_pieces_left_is_a_loss() {
    var p = board([0, 2], [8, 10, 12])
    verify(M.lost(p, M.WHITE))
    compare(M.winner(p), M.BLACK)
  }

  // --- mills

  function test_closing_one_leaves_the_same_side_owing_a_removal() {
    var after = M.play(board([0, 1], [8, 9], M.WHITE, [2, 2]), M.placeMove(2))
    verify(after.removing)
    compare(after.turn, M.WHITE)
  }

  function test_the_removal_is_a_move_of_its_own() {
    var after = M.play(board([0, 1], [8, 9], M.WHITE, [2, 2]), M.placeMove(2))
    compare(sorted(M.moves(after)), [8, 9])
    var taken = M.play(after, M.placeMove(8))
    compare(M.count(taken, M.BLACK), 1)
    compare(taken.turn, M.BLACK)
    verify(!taken.removing)
  }

  function test_a_piece_in_a_mill_is_safe_while_anything_else_is_not() {
    var after = M.play(board([0, 1], [8, 9, 10, 16], M.WHITE, [2, 4]), M.placeMove(2))
    compare(M.removable(after), [16])
  }

  function test_but_not_when_every_piece_is_in_one() {
    // The rule everybody forgets.
    var after = M.play(board([0, 1], [8, 9, 10], M.WHITE, [2, 3]), M.placeMove(2))
    compare(sorted(M.removable(after)), [8, 9, 10])
  }

  function test_a_piece_cannot_complete_a_mill_it_is_leaving() {
    var p = board([0, 1, 2, 4], [8, 10, 12, 14])
    verify(!M.closes(p, M.WHITE, 3, 2))
    verify(M.closes(p, M.WHITE, 3, -1))
  }

  function test_but_breaking_a_mill_and_reforming_it_does_count() {
    // The running mill: out and back in, a removal every second turn.
    verify(M.closes(board([0, 1, 3], [8, 10, 12, 14]), M.WHITE, 2, 3))
  }

  function test_a_mill_that_can_take_nothing_does_not_stop_the_turn() {
    verify(M.play(board([0, 1], [8, 9], M.WHITE, [2, 2]), M.placeMove(2)).removing)
    var landed = M.play(board([0, 1], [], M.WHITE, [2, 0]), M.placeMove(2))
    verify(!landed.removing)
    compare(landed.turn, M.BLACK)
  }

  // --- the move list

  function test_a_game_is_its_moves() {
    var g = M.resume([M.placeMove(0), M.placeMove(8)])
    compare(g.moves, [0, 8])
    compare(M.count(g.position, M.WHITE), 1)
  }

  function test_a_play_says_what_it_did() {
    var g = M.resume([0, 8, 1, 9])
    var did = M.describe(g.position, M.placeMove(2))
    compare(did.dst, 2)
    compare(did.colour, M.WHITE)
    compare(did.mill, [0, 1, 2])
    var after = M.resume([0, 8, 1, 9, 2])
    compare(M.describe(after.position, M.placeMove(8)).removed, 8)
  }

  function test_resume_keeps_what_will_play_and_drops_the_rest() {
    compare(M.resume([0, 8, 1, 0]).moves, [0, 8, 1])
  }

  function test_junk_in_the_move_list_ends_the_game_there() {
    var junk = [[null], ["a1"], [true], [1.5]]
    for (var i = 0; i < junk.length; i++) compare(M.resume(junk[i]).moves, [])
  }

  function test_undo_pops_one_and_nothing_from_the_opening() {
    compare(M.undo([0]), [])
    verify(M.same(M.resume(M.undo([0])).position, M.OPENING))
    compare(M.undo([]), null)
  }

  function test_takeback_returns_the_turn_and_does_not_stop_on_a_removal() {
    var g = M.resume([0, 8, 1, 9, 2, 8])
    compare(g.position.turn, M.BLACK)
    g = M.resume(g.moves.concat([10]))
    compare(g.position.turn, M.WHITE)
    var back = M.takeback(g.moves, M.WHITE)
    verify(back !== null)
    var p = M.resume(back).position
    compare(p.turn, M.WHITE)
    verify(!p.removing)
  }

  function test_a_long_quiet_endgame_is_a_draw() {
    var g = M.newGame()
    for (var s = 0; s < 2 * M.PIECES; s++) M.apply(g, M.placeMove(s))
    verify(!M.gameOver(g))
    while (!M.gameOver(g)) M.apply(g, M.moves(g.position)[0])
    verify(M.drawn(g))
    compare(g.quiet, M.QUIET_LIMIT)
  }

  function test_a_random_game_always_ends() {
    for (var seed = 0; seed < 6; seed++) {
      var dice = rng(seed)
      var g = M.newGame()
      for (var n = 0; n < 600 && !M.gameOver(g); n++) {
        var list = M.moves(g.position)
        M.apply(g, list[Math.floor(dice() * list.length)])
      }
      verify(M.gameOver(g), "seed " + seed + " would not finish")
    }
  }
}
