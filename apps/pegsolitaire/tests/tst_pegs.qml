// The rules, against the GTK version's pegs.py (0.1.0): the same cases.
//
// The one worth reading is at the bottom: every figure this app ships is
// checked for being a board of the right shape with the right number of pegs
// on it, drawn from the art in Pegs.js. The art is the content of this app,
// and a typo in a row of dots is a puzzle nobody can finish.
import QtQuick
import QtTest
import "../Pegs.js" as P

TestCase {
  name: "PegsRules"

  // Two pegs at the right-hand end of a row with the row below empty. A jump
  // rightwards from the first would land on the next row's left if the edge
  // were not minded: the classic bitboard bug, invisible on a board whose
  // edges are never used.
  readonly property string edge: "\n.......\n.......\n.....oo\n.......\n.......\n.......\n.......\n"

  function english() { return P.start(P.figureFor("english")) }
  function only(cellsList) {
    var m = 0
    for (var i = 0; i < cellsList.length; i++) m = P.withCell(m, cellsList[i])
    return m
  }

  function test_indexing_round_trips() {
    for (var c = 0; c < P.CELLS; c++) compare(P.index(P.rowOf(c), P.columnOf(c)), c)
  }

  function test_the_middle_is_where_it_looks() { compare(P.CENTRE, P.index(3, 3)) }

  function test_a_move_survives_being_a_number() {
    for (var c = 0; c < P.CELLS; c++)
      for (var d = 0; d < 4; d++) compare(P.decode(P.encode(c, d)), [c, d])
  }

  function test_a_move_says_what_it_is() {
    compare(P.notation(P.encode(P.index(3, 3), P.UP)), "d4 up")
    compare(P.notation(P.encode(P.index(0, 0), P.RIGHT)), "a1 right")
  }

  function test_a_jump_does_not_wrap_round_the_edge() {
    var b = P.parse(edge)
    var p = P.position(b.holes, b.pegs)
    compare(P.moves(p), [P.encode(P.index(2, 6), P.LEFT)])
    verify(!P.isLegal(p, P.encode(P.index(2, 5), P.RIGHT)))
  }

  function test_the_opening_board_has_four_jumps_into_the_middle() {
    var p = english()
    var m = P.moves(p)
    compare(m.length, 4)
    for (var i = 0; i < m.length; i++) compare(P.landing(m[i])[1], P.CENTRE)
  }

  function test_a_jump_takes_the_peg_it_went_over() {
    var p = english()
    var move = P.moves(p)[0]
    var cell = P.decode(move)[0]
    var l = P.landing(move)
    var after = P.play(p, move)
    verify(!P.has(after.pegs, cell))
    verify(!P.has(after.pegs, l[0]))
    verify(P.has(after.pegs, l[1]))
    compare(P.pegCount(after), P.pegCount(p) - 1)
  }

  function test_playing_does_not_change_the_position_played_from() {
    var p = english()
    var before = p.pegs
    P.play(p, P.moves(p)[0])
    compare(p.pegs, before)
  }

  function test_an_illegal_jump_is_refused() {
    // Nothing to jump over: the hole two along is full, not empty.
    compare(P.play(english(), P.encode(P.index(0, 2), P.DOWN)), null)
  }

  function test_a_jump_off_the_board_is_not_legal() {
    var p = english()
    verify(!P.isLegal(p, P.encode(-1, P.UP)))
    verify(!P.isLegal(p, P.encode(P.CELLS, P.UP)))
    verify(!P.isLegal(p, P.encode(0, 9)))
  }

  function test_jumps_from_names_only_that_pegs_jumps() {
    var p = english()
    var m = P.moves(p)
    for (var i = 0; i < m.length; i++) verify(P.jumpsFrom(p, P.decode(m[i])[0]).indexOf(m[i]) >= 0)
    compare(P.jumpsFrom(p, P.CENTRE), [])
  }

  function test_a_board_with_no_jumps_is_over() {
    var holes = english().holes
    var p = P.position(holes, only([P.index(2, 0), P.index(4, 6)]))
    verify(P.stuck(p))
    verify(!P.solved(p))
  }

  function test_one_peg_is_solved_and_the_middle_one_is_perfect() {
    var holes = english().holes
    var middle = P.position(holes, only([P.CENTRE]))
    verify(P.solved(middle))
    verify(P.perfectAt(middle, P.CENTRE))
    var elsewhere = P.position(holes, only([P.index(2, 0)]))
    verify(P.solved(elsewhere))
    verify(!P.perfectAt(elsewhere, P.CENTRE))
  }

  function test_perfect_is_only_claimed_where_the_figure_allows_it() {
    var g = P.resume("cross", [])
    verify(!g.figure.centre)
    while (!P.over(g)) g = P.resume("cross", g.moves.concat([P.moves(g.position)[0]]))
    verify(!P.perfect(g))
  }

  function test_a_game_is_its_jumps() {
    var first = P.moves(english())[0]
    var g = P.resume("english", [first])
    compare(g.moves, [first])
    compare(P.pegCount(g.position), 31)
  }

  function test_resume_keeps_what_will_play_and_drops_the_rest() {
    var g = P.resume("english", [])
    for (var i = 0; i < 6; i++) g = P.resume("english", g.moves.concat([P.moves(g.position)[0]]))
    var back = P.resume("english", g.moves.concat([P.encode(P.CENTRE, P.UP)]))
    compare(back.moves, g.moves)
    compare(back.position.pegs, g.position.pegs)
  }

  function test_junk_in_the_move_list_ends_the_game_there() {
    var junk = [[null], ["up"], [true], [0.5]]
    for (var i = 0; i < junk.length; i++) compare(P.resume("english", junk[i]).moves, [])
  }

  function test_an_unknown_figure_is_the_english_board() {
    compare(P.figureFor("nonsense").key, "english")
    compare(P.resume("nonsense", []).figure.key, "english")
  }

  function test_undo_is_the_list_less_one() {
    var first = P.moves(english())[0]
    var back = P.resume("english", [first].slice(0, -1))
    compare(back.position.pegs, english().pegs)
  }

  function test_every_figure_is_on_the_same_thirty_three_hole_cross() {
    for (var i = 0; i < P.FIGURES.length; i++) {
      var f = P.FIGURES[i]
      var holes = P.parse(f.art).holes
      compare(P.count(holes), 33, f.key)
      for (var r = 0; r < P.SIZE; r++)
        for (var c = 0; c < P.SIZE; c++) {
          var inside = (r >= 2 && r <= 4) || (c >= 2 && c <= 4)
          compare(P.has(holes, P.index(r, c)), inside, f.key + " at " + r + "," + c)
        }
    }
  }

  function test_every_figure_has_at_least_one_jump_in_it() {
    for (var i = 0; i < P.FIGURES.length; i++) verify(P.moves(P.start(P.FIGURES[i])).length > 0, P.FIGURES[i].key)
  }

  function test_every_figure_has_a_distinct_key_and_label() {
    var keys = {}, labels = {}
    for (var i = 0; i < P.FIGURES.length; i++) { keys[P.FIGURES[i].key] = 1; labels[P.FIGURES[i].label] = 1 }
    compare(Object.keys(keys).length, P.FIGURES.length)
    compare(Object.keys(labels).length, P.FIGURES.length)
  }

  function test_the_pegs_a_figure_claims_are_the_pegs_it_has() {
    compare(P.count(P.parse(P.figureFor("english").art).pegs), 32)
    compare(P.count(P.parse(P.figureFor("cross").art).pegs), 6)
    compare(P.count(P.parse(P.figureFor("goblet").art).pegs), 16)
    for (var i = 0; i < P.FIGURES.length; i++) {
      var n = P.count(P.parse(P.FIGURES[i].art).pegs)
      verify(n > 1 && n <= 32, P.FIGURES[i].key)
    }
  }

  function test_a_figure_that_can_finish_in_the_middle_starts_with_it_reachable() {
    for (var i = 0; i < P.FIGURES.length; i++)
      verify(P.has(P.parse(P.FIGURES[i].art).holes, P.CENTRE), P.FIGURES[i].key)
  }

  function test_masks_are_exact_past_thirty_two_bits() {
    // The bottom rows are cells 32 to 48: past what a bitwise operator reaches.
    var m = P.withCell(0, 48)
    verify(P.has(m, 48))
    verify(!P.has(m, 47))
    compare(P.cells(P.withCell(m, 33)), [33, 48])
    compare(P.without(m, 48), 0)
  }
}
