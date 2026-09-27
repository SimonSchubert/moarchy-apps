// The saved game, the record and the game's own bookkeeping (passes, undo,
// takeback), against the GTK version's store.py and reversi.py (0.1.0): the
// same cases, so a file one wrote reads the same in the other.
import QtQuick
import QtTest
import "../Store.js" as S
import "../Reversi.js" as R

TestCase {
  name: "ReversiStore"

  // A game 0.1.0's own AI played to the end, passes and all: hard against
  // easy, dark winning 43-20.
  readonly property var full: [19, 34, 41, 33, 44, 37, 26, 18, 17, 12, 11, 8, 38, 20, 29, 45, 4, 39, 46, 5, 9, 55, 47, 43, 13, 3, 2, 0, 6, 21, 42, 52, 63, 31, 23, 40, 30, 22, 53, 14, 51, 50, 57, 60, 7, 58, 15, 56, 61, 62, 54, -1, 32, 25, 24, 16, 48, 49, 59, -1, 10]

  // The first legal move each time: short, and always the same.
  function played(plies) {
    var moves = []
    for (var i = 0; i < plies; i++) moves = R.playTurn(moves, R.legal(R.replay(moves).position)[0]).moves
    return moves
  }
  function roundTrip(state) { return S.parse(JSON.parse(S.serialize(state))) }
  function same(a, b) { return R.replay(a).position.dark.hi === R.replay(b).position.dark.hi
    && R.replay(a).position.dark.lo === R.replay(b).position.dark.lo
    && R.replay(a).position.light.hi === R.replay(b).position.light.hi
    && R.replay(a).position.light.lo === R.replay(b).position.light.lo }

  function test_a_missing_file_is_a_new_game() {
    var s = S.parse(null)
    compare(s.moves, [])
    compare(s.mode, S.SOLO)
    compare(s.human, R.DARK)
    compare(s.level, "medium")
  }

  function test_a_new_game_starts_from_the_opening() {
    var s = S.begin(S.withMoves(S.fresh(), played(6)), S.SOLO, "hard", R.LIGHT)
    compare(s.moves, [])
    verify(!s.finished)
    compare(s.human, R.LIGHT)
  }

  function test_a_game_comes_back_as_the_same_board() {
    var moves = played(10)
    verify(same(roundTrip(S.withMoves(S.fresh(), moves)).moves, moves))
  }

  function test_the_settings_come_back_too() {
    var back = roundTrip(S.begin(S.fresh(), S.HOTSEAT, "hard", R.LIGHT))
    compare(back.mode, S.HOTSEAT)
    compare(back.level, "hard")
    compare(back.human, R.LIGHT)
  }

  function test_the_record_comes_back_too() {
    var s = S.record(S.record(S.fresh(), S.WON, 12), S.LOST)
    var back = roundTrip(s)
    compare(S.recordFor(back, "medium").played, 2)
    compare(S.recordFor(back, "medium").best, 12)
  }

  function test_what_is_written_is_a_list_of_moves_a_person_could_read() {
    var moves = played(4)
    var raw = JSON.parse(S.serialize(S.withMoves(S.fresh(), moves)))
    compare(raw.schema, 1)
    compare(raw.game.moves, moves)
    compare(raw.game.human, "dark")
    compare(raw.game.mode, "solo")
  }

  function test_a_move_that_will_not_play_ends_the_game_there() {
    var legal = played(6)
    compare(S.parse({ game: { moves: legal.concat([0]) } }).moves, legal)
  }

  function test_a_move_list_of_nonsense_is_simply_a_new_game() {
    compare(S.parse({ game: { moves: [999, -4, 17] } }).moves, [])
  }

  function test_a_file_that_is_not_even_a_table_is_ignored() {
    compare(S.parse([1, 2, 3]).moves, [])
  }

  function test_a_level_that_no_longer_exists_falls_back() {
    var s = S.parse({ game: { level: "impossible", mode: "duel" } })
    compare(s.mode, S.SOLO)
    compare(s.level, "medium")
  }

  function test_a_record_with_negative_numbers_in_it_is_cleaned_up() {
    var s = S.parse({ stats: { easy: { played: -5, won: "lots" } } })
    compare(S.recordFor(s, "easy").played, 0)
    compare(S.recordFor(s, "easy").won, 0)
  }

  function test_a_win_is_counted_against_the_level_it_was_won_at() {
    var s = S.record(S.begin(S.fresh(), S.SOLO, "hard", R.DARK), S.WON, 20)
    compare(S.recordFor(s, "hard").won, 1)
    compare(S.recordFor(s, "easy").played, 0)
  }

  function test_the_best_win_is_the_biggest_margin_not_the_last() {
    var s = S.begin(S.fresh(), S.SOLO, "easy", R.DARK)
    s = S.record(S.record(s, S.WON, 30), S.WON, 4)
    compare(S.recordFor(s, "easy").best, 30)
  }

  function test_a_loss_does_not_count_as_a_best_win() {
    compare(S.recordFor(S.record(S.begin(S.fresh(), S.SOLO, "easy", R.DARK), S.LOST, 40), "easy").best, 0)
  }

  function test_two_people_on_one_phone_are_not_in_the_record() {
    compare(S.totals(S.record(S.begin(S.fresh(), S.HOTSEAT, "medium", R.DARK), S.WON, 10)).played, 0)
  }

  function test_something_that_is_not_a_result_is_not_recorded() {
    compare(S.totals(S.record(S.fresh(), "abandoned")).played, 0)
  }

  function test_the_totals_add_the_levels_up() {
    var s = S.fresh()
    var rows = [["easy", S.WON], ["medium", S.LOST], ["hard", S.DRAWN]]
    for (var i = 0; i < rows.length; i++) { s.level = rows[i][0]; s = S.record(s, rows[i][1], 6) }
    var t = S.totals(s)
    compare(t.played, 3)
    compare([t.won, t.lost, t.drawn], [1, 1, 1])
    compare(t.best, 6)
  }

  function test_a_finished_game_is_seen_as_finished_and_scored() {
    var s = S.withMoves(S.fresh(), full)
    verify(s.finished)
    compare(S.resultOf(s).result, S.WON)
    compare(S.resultOf(s).margin, 23)
  }

  // --- the game's bookkeeping, from test_reversi.py ------------------------

  function test_a_game_records_what_was_played() {
    var t = R.playTurn([], R.index(2, 3))
    compare(t.moves, [R.index(2, 3)])
    compare(R.lastMove(t.moves), R.index(2, 3))
  }

  function test_a_pass_is_recorded_like_any_other_turn() {
    verify(full.indexOf(R.PASS) >= 0)
    compare(R.resume(full), full)
  }

  function test_the_last_move_skips_over_passes() {
    compare(R.lastMove([R.index(2, 3), R.PASS]), R.index(2, 3))
    compare(R.lastMove([]), -1)
  }

  function test_undo_puts_the_board_back() {
    compare(R.undo([R.index(2, 3)]), [])
  }

  function test_undo_at_the_opening_does_nothing() {
    compare(R.undo([]), null)
  }

  function test_undo_takes_any_passes_with_it() {
    var cut = full.slice(0, full.lastIndexOf(R.PASS) + 1)
    var back = R.undo(cut)
    verify(back.length < cut.length - 1)
    verify(back[back.length - 1] !== R.PASS)
  }

  function test_a_takeback_hands_the_board_back_to_the_same_side() {
    var moves = R.playTurn([], R.index(2, 3)).moves
    moves = R.playTurn(moves, R.legal(R.replay(moves).position)[0]).moves
    var back = R.takeback(moves, R.DARK)
    compare(R.replay(back).position.turn, R.DARK)
  }

  function test_a_takeback_with_nothing_to_take_back_says_so() {
    compare(R.takeback([], R.DARK), null)
  }

  function test_a_forced_pass_is_played_for_whoever_it_falls_on() {
    // Just before the first pass in the full game: the move that forces it.
    var at = full.indexOf(R.PASS)
    var t = R.playTurn(full.slice(0, at - 1), full[at - 1])
    compare(t.passes, 1)
    compare(t.moves, full.slice(0, at + 1))
  }
}
