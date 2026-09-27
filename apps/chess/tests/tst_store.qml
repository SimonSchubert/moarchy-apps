// The saved game and the record, against 0.1.0's test_store.py case for case,
// so a file one of them wrote reads the same in the other. The file itself --
// moved aside when it will not parse, written atomically -- is the kit's
// DataFile, and its tests are the kit's.
import QtQuick
import QtTest
import "../Chess.js" as C
import "../Store.js" as S

TestCase {
  name: "ChessStore"

  readonly property var opening: ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "a7a6"]

  function played(s, moves) { return S.remember(s, C.resumeUci(moves || opening), false) }
  function roundTrip(s) { return S.parse(JSON.parse(S.serialize(s))) }
  function write(data) { return S.parse(data) }

  function test_an_untouched_store_has_an_opening_in_it() {
    var s = S.parse(null)
    compare(S.gameOf(s).game.moves, [])
    compare(s.mode, S.SOLO)
    compare(s.human, C.WHITE)
  }
  function test_a_game_survives_being_written_and_read() {
    var back = roundTrip(played(S.fresh()))
    compare(back.moves, opening)
    compare(C.gameUci(S.gameOf(back).game), opening)
  }
  function test_the_settings_survive_too() {
    var back = roundTrip(S.begin(S.fresh(), S.HOTSEAT, "hard", C.BLACK))
    compare(back.mode, S.HOTSEAT)
    compare(back.level, "hard")
    compare(back.human, C.BLACK)
  }
  function test_the_moves_are_written_as_people_write_them() {
    var raw = JSON.parse(S.serialize(played(S.fresh())))
    compare(raw.game.moves, opening)
    compare(raw.schema, 1)
    compare(raw.game.human, "white")
  }
  function test_a_file_that_is_not_an_object_is_ignored() {
    compare(write([1, 2, 3]).moves, [])
  }
  function test_a_move_that_is_not_a_move_ends_the_game_there() {
    compare(C.gameUci(S.gameOf(write({ game: { moves: ["e2e4", "e7e5", "wat", "g1f3"] } })).game), ["e2e4", "e7e5"])
  }
  function test_a_move_that_will_not_play_ends_the_game_there() {
    compare(C.gameUci(S.gameOf(write({ game: { moves: ["e2e4", "e7e5", "e2e4", "g1f3"] } })).game), ["e2e4", "e7e5"])
  }
  function test_the_kept_part_is_what_gets_saved_back() {
    var s = S.gameOf(write({ game: { moves: ["e2e4", "nonsense"] } })).state
    compare(roundTrip(s).moves, ["e2e4"])
  }
  function test_moves_that_are_not_even_strings_are_dropped() {
    compare(write({ game: { moves: ["e2e4", 12, null] } }).moves, ["e2e4"])
  }
  function test_an_unknown_mode_or_level_falls_back() {
    var s = write({ game: { mode: "postal", level: "impossible" } })
    compare(s.mode, S.SOLO)
    compare(s.level, "medium")
  }
  function test_stats_for_a_level_that_does_not_exist_are_dropped() {
    compare(Object.keys(write({ stats: { nightmare: { played: 4 } } }).stats).length, 0)
  }
  function test_negative_counts_are_clamped() {
    var s = write({ stats: { easy: { played: -3, won: 2 } } })
    compare(S.recordFor(s, "easy").played, 0)
    compare(S.recordFor(s, "easy").won, 2)
  }

  function test_a_win_goes_in_against_the_level_it_was_won_against() {
    var s = S.record(S.begin(S.fresh(), S.SOLO, "hard", C.WHITE), S.WON, 31)
    compare(S.recordFor(s, "hard").played, 1)
    compare(S.recordFor(s, "hard").won, 1)
    compare(S.recordFor(s, "hard").quickest, 31)
  }
  function test_the_quickest_win_is_the_shortest_one() {
    var s = S.begin(S.fresh(), S.SOLO, "easy", C.WHITE)
    s = S.record(S.record(S.record(s, S.WON, 40), S.WON, 22), S.WON, 55)
    compare(S.recordFor(s, "easy").quickest, 22)
  }
  function test_a_loss_does_not_set_a_quickest() {
    compare(S.recordFor(S.record(S.begin(S.fresh(), S.SOLO, "easy", C.WHITE), S.LOST, 9), "easy").quickest, 0)
  }
  function test_nothing_is_recorded_for_two_people_at_one_phone() {
    compare(S.totals(S.record(S.begin(S.fresh(), S.HOTSEAT, "medium", C.WHITE), S.WON, 20)).played, 0)
  }
  function test_a_result_that_is_not_one_is_refused() {
    compare(S.totals(S.record(S.begin(S.fresh(), S.SOLO, "easy", C.WHITE), "abandoned")).played, 0)
  }
  function test_totals_add_up_across_levels() {
    var s = S.fresh()
    var plan = [["easy", 3, 1], ["medium", 1, 2]]
    for (var i = 0; i < plan.length; i++) {
      s.level = plan[i][0]
      for (var w = 0; w < plan[i][1]; w++) s = S.record(s, S.WON, 30)
      for (var l = 0; l < plan[i][2]; l++) s = S.record(s, S.LOST)
    }
    var t = S.totals(s)
    compare(t.played, 7)
    compare(t.won, 4)
    compare(t.lost, 3)
    compare(t.drawn, 0)
  }
  function test_the_record_survives_a_round_trip() {
    var s = S.begin(S.fresh(), S.SOLO, "medium", C.WHITE)
    var back = roundTrip(S.record(S.record(s, S.WON, 28), S.DRAWN))
    compare(S.recordFor(back, "medium").won, 1)
    compare(S.recordFor(back, "medium").drawn, 1)
    compare(S.recordFor(back, "medium").quickest, 28)
  }

  function test_a_new_game_clears_the_moves_but_not_the_record() {
    var s = S.fresh()
    s.level = "easy"
    s = played(S.record(s, S.WON, 25))
    s = S.begin(s, S.SOLO, "medium", C.BLACK)
    compare(s.moves, [])
    verify(!s.finished)
    compare(S.recordFor(s, "easy").won, 1)
  }
  function test_a_finished_game_is_remembered_as_finished() {
    verify(roundTrip(S.remember(S.fresh(), C.resumeUci(opening), true)).finished)
  }
  function test_a_nonsense_colour_becomes_white() {
    compare(S.begin(S.fresh(), S.SOLO, "easy", 7).human, C.WHITE)
  }
  function test_nothing_changes_the_state_it_was_given() {
    var s = S.begin(S.fresh(), S.SOLO, "easy", C.WHITE)
    S.record(s, S.WON, 10)
    compare(S.totals(s).played, 0)
  }
}
