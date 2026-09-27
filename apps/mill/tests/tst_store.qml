// The saved game and the record, against the GTK version's test_store.py
// (0.1.0): the same cases, so a file one of them wrote reads the same in the
// other and a result is counted the same way in both.
import QtQuick
import QtTest
import "../Mill.js" as M
import "../Store.js" as S

TestCase {
  name: "MillStore"

  // Four placements and the one that closes a mill: white still to move, and
  // owing a piece.
  readonly property var milled: [0, 8, 1, 9, 2]

  function roundTrip(state) { return S.parse(JSON.parse(S.serialize(state))) }

  function test_a_missing_file_is_a_new_game_and_not_an_error() {
    var s = S.parse(null)
    compare(s.moves, [])
    verify(M.same(M.resume(s.moves).position, M.OPENING))
    compare(s.mode, S.SOLO)
    compare(s.human, M.WHITE)
    compare(s.level, "medium")
  }

  function test_a_new_game_starts_from_the_opening() {
    var s = S.begin(S.withMoves(S.fresh(), [0, 8]), S.SOLO, "hard", M.BLACK)
    compare(s.moves, [])
    verify(!s.finished)
    verify(!s.recorded)
    compare(s.human, M.BLACK)
  }

  function test_everything_written_comes_back() {
    var s = S.withMoves(S.begin(S.fresh(), S.HOTSEAT, "easy", M.BLACK), [0, 8, 1, 9])
    var back = roundTrip(s)
    compare(back.moves, [0, 8, 1, 9])
    compare(back.mode, S.HOTSEAT)
    compare(back.level, "easy")
    compare(back.human, M.BLACK)
  }

  function test_the_file_is_the_shape_store_py_wrote() {
    var raw = JSON.parse(S.serialize(S.begin(S.fresh(), S.SOLO, "hard", M.BLACK)))
    compare(raw.schema, 1)
    compare(raw.game.human, "black")
    compare(raw.game.mode, "solo")
    compare(raw.game.level, "hard")
    compare(raw.game.recorded, false)
  }

  function test_a_turn_that_owes_a_removal_survives_the_file() {
    var s = S.withMoves(S.fresh(), milled)
    verify(M.resume(s.moves).position.removing)
    var p = M.resume(roundTrip(s).moves).position
    verify(p.removing)
    compare(p.turn, M.WHITE)
    verify(M.same(p, M.resume(milled).position))
  }

  function test_a_move_that_will_not_play_ends_the_game_there() {
    compare(S.parse({ game: { moves: [0, 0, 8] } }).moves, [0])
  }

  function test_junk_in_the_fields_falls_back_rather_than_raising() {
    var s = S.parse({
      game: { mode: "telepathy", level: "impossible", human: 17, moves: "8" },
      stats: { easy: { played: "lots" }, nightmare: { played: 3 } }
    })
    compare(s.mode, S.SOLO)
    compare(s.level, "medium")
    compare(s.human, M.WHITE)
    compare(s.moves, [])
    compare(S.recordFor(s, "easy").played, 0)
    compare(s.stats.nightmare, undefined)
  }

  function test_a_file_that_is_not_an_object_is_ignored() {
    compare(S.parse([1, 2, 3]).moves, [])
    compare(S.parse("x").moves, [])
  }

  function test_only_the_computers_games_are_recorded() {
    var s = S.record(S.begin(S.fresh(), S.HOTSEAT, "medium", M.WHITE), S.WON, 6)
    compare(S.recordFor(s, "medium").played, 0)
  }

  function test_a_win_keeps_the_best_margin() {
    var s = S.begin(S.fresh(), S.SOLO, "hard", M.WHITE)
    s = S.record(s, S.WON, 4)
    compare(S.recordFor(s, "hard").best, 4)
    s = S.record(s, S.WON, 7)
    compare(S.recordFor(s, "hard").best, 7)
    s = S.record(s, S.WON, 3)
    compare(S.recordFor(s, "hard").best, 7)
  }

  function test_recording_marks_the_game_as_counted() {
    var s = S.begin(S.fresh(), S.SOLO, "easy", M.WHITE)
    verify(!s.recorded)
    s = S.record(s, S.DRAWN)
    verify(s.recorded)
    verify(!S.begin(s, S.SOLO, "easy", M.WHITE).recorded)
  }

  function test_whether_a_result_was_counted_survives_the_file() {
    verify(roundTrip(S.record(S.begin(S.fresh(), S.SOLO, "easy", M.WHITE), S.DRAWN)).recorded)
  }

  function test_the_levels_are_counted_apart() {
    var s = S.record(S.begin(S.fresh(), S.SOLO, "easy", M.WHITE), S.WON, 5)
    s = S.record(S.begin(s, S.SOLO, "hard", M.WHITE), S.LOST)
    compare(S.recordFor(s, "easy").won, 1)
    compare(S.recordFor(s, "hard").lost, 1)
  }

  function test_a_result_that_is_not_one_is_ignored() {
    var s = S.record(S.begin(S.fresh(), S.SOLO, "easy", M.WHITE), "abandoned")
    compare(S.recordFor(s, "easy").played, 0)
  }

  function test_totals_add_the_levels_up() {
    var s = S.begin(S.fresh(), S.SOLO, "easy", M.WHITE)
    for (var i = 0; i < 3; i++) s = S.record(s, S.WON, 5)
    s.level = "hard"
    s = S.record(s, S.LOST)
    var t = S.totals(s)
    compare(t.played, 4)
    compare(t.won, 3)
    compare(t.best, 5)
  }

  // A whole game, played by 0.1.0's own opponent at two levels: white wins
  // with three left.
  readonly property var won: [0, 3, 2, 1, 6, 7, 5, 4, 13, 21, 12, 14, 10, 11, 19, 15, 23, 8, 2, 273, 50, 12, 25, 300, 498, 323, 473, 11, 550, 450, 573, 473, 21, 107, 357, 291, 5, 173, 373, 550, 350, 5, 448, 7, 125, 425, 3, 75, 448, 3, 157, 425, 13, 376, 573, 422, 23, 541, 404, 341, 519, 5, 59, 217, 440, 61, 298, 13]

  function test_the_result_is_the_persons_and_the_margin_is_their_pieces() {
    var g = M.resume(won)
    compare(g.moves.length, won.length)
    verify(M.gameOver(g))
    compare(M.winner(g.position), M.WHITE)
    var mine = S.withMoves(S.begin(S.fresh(), S.SOLO, "medium", M.WHITE), won)
    verify(mine.finished)
    compare(S.resultOf(mine), { result: S.WON, margin: 3 })
    compare(S.resultOf(S.withMoves(S.begin(S.fresh(), S.SOLO, "medium", M.BLACK), won)).result, S.LOST)
  }

  function test_nothing_changes_the_state_it_was_given() {
    var s = S.begin(S.fresh(), S.SOLO, "easy", M.WHITE)
    S.record(s, S.WON, 3)
    S.withMoves(s, [0])
    compare(s.moves, [])
    compare(S.recordFor(s, "easy").played, 0)
  }
}
