// The file: what is written, what is read back, and what a bad one does.
// The cases 0.1.0's test_store.py had, against the same pegsolitaire.json.
import QtQuick
import QtTest
import "../Pegs.js" as P
import "../Store.js" as S

TestCase {
  name: "PegsStore"

  function played(state, jumps) {
    var g = P.resume(state.figure, [])
    for (var i = 0; i < (jumps === undefined ? 4 : jumps); i++) {
      var m = P.moves(g.position)
      if (!m.length) break
      g = P.resume(state.figure, g.moves.concat([m[0]]))
    }
    return S.withMoves(state, g.moves)
  }
  function roundTrip(state) { return S.parse(JSON.parse(S.serialize(state))) }

  function test_a_missing_file_is_the_english_board() {
    var s = S.parse(null)
    compare(s.figure, "english")
    compare(s.moves, [])
    compare(P.pegCount(P.resume(s.figure, s.moves).position), 32)
  }

  function test_a_new_figure_starts_from_its_own_beginning() {
    var s = S.begin(played(S.fresh()), "cross")
    compare(s.figure, "cross")
    compare(s.moves, [])
    verify(!s.finished)
  }

  function test_starting_again_keeps_the_figure() {
    var s = S.again(played(S.begin(S.fresh(), "plus")))
    compare(s.figure, "plus")
    compare(s.moves, [])
  }

  function test_everything_written_comes_back() {
    var s = played(S.begin(S.fresh(), "diamond"))
    s = S.record(s, 3, false)
    var back = roundTrip(s)
    compare(back.figure, "diamond")
    compare(back.moves, s.moves)
    compare(S.recordFor(back, "diamond").best, 3)
    verify(back.recorded)
  }

  function test_the_file_is_the_shape_store_py_wrote() {
    var raw = JSON.parse(S.serialize(played(S.fresh(), 2)))
    compare(raw.schema, 1)
    compare(raw.game.figure, "english")
    compare(raw.game.moves.length, 2)
    compare(typeof raw.game.finished, "boolean")
    compare(typeof raw.stats, "object")
  }

  function test_a_jump_that_will_not_play_ends_the_game_there() {
    var s = played(S.fresh(), 3)
    var data = JSON.parse(S.serialize(s))
    // Upwards out of the top row: off the board from any position.
    data.game.moves.push(P.encode(P.index(0, 2), P.UP))
    compare(S.parse(data).moves, s.moves)
  }

  function test_junk_in_the_fields_falls_back_rather_than_raising() {
    var s = S.parse({ game: { figure: "rhombus", moves: "several" },
                      stats: { english: { best: "three" }, rhombus: { best: 2 } } })
    compare(s.figure, "english")
    compare(s.moves, [])
    compare(S.recordFor(s, "english").best, 0)
    compare(S.recordFor(s, "rhombus").best, 0)
  }

  function test_a_file_that_is_not_an_object_is_ignored() {
    compare(S.parse([1, 2, 3]).moves, [])
    compare(S.parse("x").moves, [])
  }

  function test_fewest_pegs_only_ever_goes_down() {
    var s = S.begin(S.fresh(), "english")
    s = S.record(s, 5)
    compare(S.recordFor(s, "english").best, 5)
    s = S.record(s, 8)
    compare(S.recordFor(s, "english").best, 5)
    s = S.record(s, 2)
    compare(S.recordFor(s, "english").best, 2)
  }

  function test_finishing_and_finishing_in_the_middle_are_counted_apart() {
    var s = S.record(S.begin(S.fresh(), "english"), 1)
    compare(S.recordFor(s, "english").solved, 1)
    compare(S.recordFor(s, "english").perfect, 0)
    s = S.record(s, 1, true)
    compare(S.recordFor(s, "english").solved, 2)
    compare(S.recordFor(s, "english").perfect, 1)
  }

  function test_a_board_with_no_pegs_on_it_is_not_a_result() {
    compare(S.recordFor(S.record(S.fresh(), 0), "english").played, 0)
  }

  function test_the_figures_are_counted_apart() {
    var s = S.record(S.begin(S.fresh(), "cross"), 1)
    s = S.record(S.begin(s, "plus"), 4)
    compare(S.recordFor(s, "cross").solved, 1)
    compare(S.recordFor(s, "plus").solved, 0)
  }

  function test_totals_count_the_figures_that_have_been_finished() {
    var s = S.fresh()
    var runs = [["cross", 1], ["plus", 1], ["pyramid", 3]]
    for (var i = 0; i < runs.length; i++) s = S.record(S.begin(s, runs[i][0]), runs[i][1])
    var t = S.totals(s)
    compare(t.played, 3)
    compare(t.solved, 2)
    compare(t.best, 2)
  }

  function test_a_figure_has_a_name_to_put_on_a_row() {
    compare(S.figureLabel("english"), "English board")
    compare(S.figureLabel("nonsense"), "English board")
  }

  function test_nothing_changes_the_state_it_was_given() {
    var s = S.begin(S.fresh(), "cross")
    S.record(s, 1)
    S.withMoves(s, [P.moves(P.start(P.figureFor("cross")))[0]])
    compare(s.moves, [])
    compare(S.recordFor(s, "cross").played, 0)
  }

  function test_a_played_out_board_is_finished_and_owes_its_result() {
    var s = S.withMoves(S.begin(S.fresh(), "pyramid"), [96, 128, 120])
    verify(s.finished)
    verify(!s.recorded)
  }
}
