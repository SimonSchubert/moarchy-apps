// The solver, and the claim every figure in this app makes: that it can be
// reduced to a single peg, and -- for five of them -- that the last peg can be
// made to land in the middle. Neither is visible in a picture of a board, so
// both are checked by solving all nine on every run, and the solutions are
// replayed through the rules afterwards: a solver that agreed with itself about
// an illegal jump would pass a test that only asked whether it had found
// something. The cases 0.1.0's test_solver.py had.
import QtQuick
import QtTest
import "../Pegs.js" as P
import "../Solver.js" as S

TestCase {
  name: "PegsSolver"

  readonly property real patience: 40

  function replay(key, line) {
    var g = P.resume(key, line)
    compare(g.moves.length, line.length, key + ": the line does not play")
    return g
  }

  function test_every_figure_reduces_to_one_peg() {
    for (var i = 0; i < P.FIGURES.length; i++) {
      var f = P.FIGURES[i]
      var s = P.start(f)
      var line = S.solve(s.holes, s.pegs, -1, patience)
      verify(line !== null, f.key + " cannot be finished")
      compare(P.pegCount(replay(f.key, line).position), 1, f.key)
    }
  }

  function test_the_middle_is_claimed_only_where_it_can_be_reached() {
    for (var i = 0; i < P.FIGURES.length; i++) {
      var f = P.FIGURES[i]
      var s = P.start(f)
      var line = S.solve(s.holes, s.pegs, P.CENTRE, patience)
      compare(line !== null, f.centre, f.key + " says centre=" + f.centre)
      if (line !== null) verify(P.perfect(replay(f.key, line)), f.key)
    }
  }

  function test_it_proves_a_dead_position_dead() {
    var holes = P.start(P.figureFor("english")).holes
    var pegs = P.withCell(P.withCell(0, 14), 34)
    var a = S.search(holes, pegs, -1, patience)
    compare(a.verdict, S.IMPOSSIBLE)
    compare(a.line, [])
  }

  function test_it_answers_at_once_when_the_board_is_already_finished() {
    var holes = P.start(P.figureFor("english")).holes
    compare(S.search(holes, P.withCell(0, P.CENTRE), P.CENTRE).verdict, S.SOLVED)
    compare(S.search(holes, P.withCell(0, 14), P.CENTRE).verdict, S.IMPOSSIBLE)
  }

  function test_it_gives_up_rather_than_running_on() {
    var s = P.start(P.figureFor("english"))
    var a = S.search(s.holes, s.pegs, P.CENTRE, 0)
    compare(a.verdict, S.UNKNOWN)
    compare(a.line, [])
  }

  function test_a_clock_that_runs_out_mid_search_says_unknown() {
    // A clock that jumps an hour at every look: the search has to notice at
    // its next check and stop, not finish.
    var s = P.start(P.figureFor("english"))
    var t = 0
    var a = S.search(s.holes, s.pegs, P.CENTRE, 2, function () { t += 3600; return t })
    compare(a.verdict, S.UNKNOWN)
  }

  function test_the_line_it_returns_starts_at_the_move_it_offers() {
    var s = P.start(P.figureFor("plus"))
    var a = S.search(s.holes, s.pegs, P.CENTRE, patience)
    compare(a.verdict, S.SOLVED)
    verify(P.perfect(replay("plus", a.line)))
  }

  function test_a_hint_followed_leaves_a_line_that_still_solves() {
    // The window keeps the rest of a line and offers it again for nothing,
    // which is only sound if the tail of a solution is a solution.
    var s = P.start(P.figureFor("diamond"))
    var a = S.search(s.holes, s.pegs, P.CENTRE, patience)
    var g = P.resume("diamond", [])
    for (var i = 0; i < a.line.length; i++) {
      verify(P.isLegal(g.position, a.line[i]))
      g = P.resume("diamond", g.moves.concat([a.line[i]]))
    }
    verify(P.perfect(g))
  }

  function test_the_english_board_is_solved_inside_the_apps_own_clock() {
    var s = P.start(P.figureFor("english"))
    compare(S.search(s.holes, s.pegs, P.CENTRE, S.SECONDS).verdict, S.SOLVED)
  }

  function test_the_first_line_is_the_one_solver_py_found() {
    // The same move order, so the same first answer: the eleven jumps demo.py
    // was recorded down, which is 0.1.0's solver's line.
    var s = P.start(P.figureFor("english"))
    var line = S.solve(s.holes, s.pegs, P.CENTRE, patience)
    compare(line.slice(0, 11), [41, 63, 9, 18, 70, 59, 72, 82, 92, 9, 87])
  }
}
