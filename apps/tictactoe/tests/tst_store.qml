// The saved game, the series and the record, against the GTK version's
// store.py (0.1.0): the same cases, so that a file one of them wrote reads the
// same in the other and a result is counted the same way in both.
import QtQuick
import QtTest
import "../Store.js" as S
import "../Tictactoe.js" as T

TestCase {
  name: "TictactoeStore"

  function played(state, moves) { return S.withMoves(state, moves || [0, 4, 8]) }
  function roundTrip(state) { return S.parse(JSON.parse(S.serialize(state))) }

  function test_a_missing_file_is_a_new_game() {
    var s = S.parse(null)
    compare(s.moves, [])
    compare(s.mode, S.SOLO)
    compare(s.mark, T.CROSS)
    compare(s.level, "fair")
    compare(s.series, { a: 0, b: 0, drawn: 0 })
  }

  function test_a_new_game_starts_from_an_empty_board() {
    var s = S.begin(played(S.fresh()), S.SOLO, "perfect", T.NOUGHT)
    compare(s.moves, [])
    verify(!s.finished)
    compare(s.mark, T.NOUGHT)
  }

  function test_everything_written_comes_back() {
    var s = S.begin(S.fresh(), S.HOTSEAT, "easy", T.NOUGHT)
    s = S.record(played(s, [0, 4, 8]), S.WON)
    var back = roundTrip(s)
    compare(back.moves, [0, 4, 8])
    compare(back.mode, S.HOTSEAT)
    compare(back.level, "easy")
    compare(back.mark, T.NOUGHT)
    compare(back.series.a, 1)
  }

  function test_the_file_is_the_shape_store_py_wrote() {
    var raw = JSON.parse(S.serialize(S.begin(S.fresh(), S.SOLO, "fair", T.NOUGHT)))
    compare(raw.schema, 1)
    compare(raw.game.mark, "o")
    compare(raw.game.mode, "solo")
    compare(raw.series, { a: 0, b: 0, drawn: 0 })
  }

  function test_the_board_is_replayed_rather_than_stored() {
    var back = roundTrip(played(S.fresh(), [0, 3, 1, 4, 2]))
    compare(T.winner(T.replay(back.moves)), T.CROSS)
    verify(back.finished)
  }

  function test_whether_a_result_was_counted_survives_the_file() {
    var s = played(S.begin(S.fresh(), S.SOLO, "fair", T.CROSS), [0, 3, 1, 4, 2])
    var back = roundTrip(s)
    verify(back.finished)
    verify(!back.recorded)
    verify(roundTrip(S.record(back, S.WON)).recorded)
  }

  function test_a_rematch_owes_its_result_again() {
    var s = S.record(S.begin(S.fresh(), S.SOLO, "fair", T.CROSS), S.WON)
    verify(s.recorded)
    verify(!S.rematch(s).recorded)
  }

  function test_a_move_that_will_not_play_ends_the_game_there() {
    compare(S.parse({ game: { moves: [4, 4, 0] } }).moves, [4])
  }

  function test_a_finished_game_takes_no_more_moves() {
    compare(S.parse({ game: { moves: [0, 3, 1, 4, 2, 5] } }).moves, [0, 3, 1, 4, 2])
  }

  function test_junk_in_the_fields_falls_back_rather_than_raising() {
    var s = S.parse({
      game: { mode: "telepathy", level: "impossible", mark: 17, moves: "4" },
      series: "none",
      stats: { easy: { played: "lots" }, nightmare: { played: 3 } }
    })
    compare(s.mode, S.SOLO)
    compare(s.level, "fair")
    compare(s.mark, T.CROSS)
    compare(s.moves, [])
    compare(s.series.drawn, 0)
    compare(S.recordFor(s, "easy").played, 0)
    compare(s.stats.nightmare, undefined)
  }

  function test_a_file_that_is_not_an_object_is_ignored() {
    compare(S.parse([1, 2, 3]).moves, [])
    compare(S.parse("x").moves, [])
  }

  function test_a_rematch_swaps_the_marks_and_keeps_the_score() {
    var s = S.record(S.begin(S.fresh(), S.SOLO, "fair", T.CROSS), S.WON)
    s = S.rematch(played(s))
    compare(s.mark, T.NOUGHT)
    compare(s.moves, [])
    compare(s.series.a, 1)
    compare(S.rematch(s).mark, T.CROSS)
  }

  function test_a_new_game_starts_a_new_series() {
    var s = S.begin(S.fresh(), S.SOLO, "fair", T.CROSS)
    s = S.record(S.record(s, S.WON), S.DRAWN)
    compare(S.begin(s, S.SOLO, "easy", T.CROSS).series, { a: 0, b: 0, drawn: 0 })
  }

  function test_both_modes_keep_a_series() {
    var s = S.begin(S.fresh(), S.HOTSEAT, "fair", T.CROSS)
    compare(S.record(S.record(s, S.LOST), S.LOST).series.b, 2)
  }

  function test_a_result_that_is_not_one_is_ignored() {
    compare(S.record(S.fresh(), "abandoned").series, { a: 0, b: 0, drawn: 0 })
  }

  function test_only_the_computers_games_are_recorded() {
    var s = S.record(S.begin(S.fresh(), S.HOTSEAT, "fair", T.CROSS), S.WON)
    compare(S.recordFor(s, "fair").played, 0)
    compare(s.series.a, 1)
  }

  function test_a_run_without_losing_grows_and_a_loss_ends_it() {
    var s = S.begin(S.fresh(), S.SOLO, "perfect", T.CROSS)
    for (var i = 0; i < 5; i++) s = S.record(s, S.DRAWN)
    compare(S.recordFor(s, "perfect").unbeaten, 5)
    compare(S.recordFor(s, "perfect").best, 5)
    s = S.record(s, S.LOST)
    compare(S.recordFor(s, "perfect").unbeaten, 0)
    compare(S.recordFor(s, "perfect").best, 5)
    s = S.record(s, S.WON)
    compare(S.recordFor(s, "perfect").unbeaten, 1)
    compare(S.recordFor(s, "perfect").best, 5)
  }

  function test_totals_add_the_levels_up_and_take_the_best_run() {
    var s = S.begin(S.fresh(), S.SOLO, "easy", T.CROSS)
    for (var i = 0; i < 4; i++) s = S.record(s, S.WON)
    s.level = "perfect"
    for (var j = 0; j < 9; j++) s = S.record(s, S.DRAWN)
    var t = S.totals(s)
    compare(t.played, 13)
    compare(t.won, 4)
    compare(t.best, 9)
  }

  function test_the_result_is_seat_a_s_whichever_mark_it_holds() {
    var s = S.begin(S.fresh(), S.SOLO, "fair", T.NOUGHT)
    compare(S.resultOf(played(s, [0, 3, 1, 4, 2])), S.LOST)
    compare(S.resultOf(played(S.rematch(s), [0, 3, 1, 4, 2])), S.WON)
  }

  function test_nothing_changes_the_state_it_was_given() {
    var s = S.begin(S.fresh(), S.SOLO, "fair", T.CROSS)
    S.record(s, S.WON)
    S.rematch(s)
    compare(s.series.a, 0)
    compare(s.mark, T.CROSS)
  }

  function test_undo_against_the_computer_goes_back_to_your_move() {
    compare(T.takeback([4, 0, 8, 2], T.CROSS), [4, 0])
    compare(T.takeback([4], T.NOUGHT), [])
    compare(T.takeback([], T.CROSS), [])
  }
}
