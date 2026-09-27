// The file, the record and the clock, against the GTK version's store.py
// (0.1.0): the same cases, so that a file one of them wrote reads the same in
// the other.
import QtQuick
import QtTest
import "../Store.js" as S
import "../Minesweeper.js" as M

TestCase {
  name: "MinesweeperStore"

  function played(state) {
    var level = M.levelFor(state.level)
    var g = S.game(state)
    M.tap(g, M.index(Math.floor(level.height / 2), Math.floor(level.width / 2), level.width))
    M.mark(g, 0)
    return S.withMoves(state, g.moves)
  }
  function roundTrip(state) { return S.parse(JSON.parse(S.serialize(state))) }
  function mineList(g) {
    var out = []
    for (var k in g.mines) out.push(parseInt(k, 10))
    return out.sort(function (a, b) { return a - b }).join(",")
  }

  function test_a_missing_file_is_a_fresh_board() {
    var s = S.parse(null)
    compare(s.level, "standard")
    compare(s.moves, [])
    compare(s.seconds, 0)
    verify(s.seed >= 0 && s.seed < S.SEED_MAX)
  }

  function test_a_new_game_at_a_new_level_resets_the_clock() {
    var s = S.withSeconds(played(S.fresh()), 90)
    s = S.begin(s, "gentle")
    compare(s.level, "gentle")
    compare(s.seconds, 0)
    compare(s.moves, [])
  }

  function test_the_same_seed_can_be_asked_for_again() {
    var s = S.fresh()
    var seed = s.seed
    s = S.begin(played(s), s.level, seed)
    compare(s.seed, seed)
    compare(s.moves, [])
  }

  function test_everything_written_comes_back() {
    var s = played(S.begin(S.fresh(), "gentle"))
    s = S.record(S.withSeconds(s, 42), S.WON, 42)
    var back = roundTrip(s)
    compare(back.level, "gentle")
    compare(back.seed, s.seed)
    compare(back.seconds, 42)
    compare(back.moves, s.moves)
    compare(S.recordFor(back, "gentle").best, 42)
  }

  function test_the_board_comes_back_with_the_same_mines_under_it() {
    var s = played(S.begin(S.fresh(), "gentle"))
    var back = roundTrip(s)
    compare(mineList(S.game(back)), mineList(S.game(s)))
    compare(M.openedCount(S.game(back)), M.openedCount(S.game(s)))
  }

  function test_the_file_is_the_shape_store_py_wrote() {
    var raw = JSON.parse(S.serialize(S.begin(S.fresh(), "hard", 7)))
    compare(raw.schema, 1)
    compare(raw.game.level, "hard")
    compare(raw.game.seed, 7)
    verify(raw.game.moves.constructor === Array)
    compare(typeof raw.stats, "object")
  }

  function test_junk_in_the_fields_falls_back_rather_than_raising() {
    var s = S.parse({
      game: { level: "impossible", seed: "cheese", seconds: -5, moves: "many" },
      stats: { gentle: { best: "quick" }, nightmare: { played: 3 } }
    })
    compare(s.level, "standard")
    compare(s.moves, [])
    compare(s.seconds, 0)
    compare(S.recordFor(s, "gentle").best, 0)
    compare(s.stats.nightmare, undefined)
  }

  function test_a_move_that_will_not_play_ends_the_game_there() {
    var s = played(S.begin(S.fresh(), "gentle"))
    var good = s.moves.slice()
    var raw = JSON.parse(S.serialize(s))
    raw.game.moves = good.concat([99999])
    compare(S.parse(raw).moves, good)
  }

  function test_a_file_that_is_not_an_object_is_ignored() {
    compare(S.parse([1, 2, 3]).moves, [])
  }

  function test_the_fastest_clear_only_goes_down() {
    var s = S.begin(S.fresh(), "gentle")
    s = S.record(s, S.WON, 90)
    compare(S.recordFor(s, "gentle").best, 90)
    s = S.record(s, S.WON, 120)
    compare(S.recordFor(s, "gentle").best, 90)
    s = S.record(s, S.WON, 61)
    compare(S.recordFor(s, "gentle").best, 61)
  }

  function test_a_loss_does_not_set_a_time() {
    var s = S.record(S.begin(S.fresh(), "gentle"), S.LOST, 12)
    compare(S.recordFor(s, "gentle").best, 0)
    compare(S.recordFor(s, "gentle").played, 1)
  }

  function test_a_run_of_wins_grows_and_a_loss_ends_it() {
    var s = S.begin(S.fresh(), "hard")
    for (var i = 0; i < 3; i++) s = S.record(s, S.WON, 300)
    compare(S.recordFor(s, "hard").longest, 3)
    s = S.record(s, S.LOST)
    compare(S.recordFor(s, "hard").streak, 0)
    compare(S.recordFor(s, "hard").longest, 3)
  }

  function test_the_levels_are_counted_apart() {
    var s = S.record(S.begin(S.fresh(), "gentle"), S.WON, 30)
    s = S.record(S.begin(s, "hard"), S.LOST)
    compare(S.recordFor(s, "gentle").won, 1)
    compare(S.recordFor(s, "hard").won, 0)
    compare(S.totals(s).played, 2)
  }

  function test_a_result_that_is_not_one_is_ignored() {
    compare(S.recordFor(S.record(S.fresh(), "abandoned"), "standard").played, 0)
  }

  function test_the_clock_reads_as_minutes_and_seconds() {
    compare(M.clock(0), "0:00")
    compare(M.clock(9), "0:09")
    compare(M.clock(61), "1:01")
    compare(M.clock(599), "9:59")
    compare(M.clock(3600), "1:00:00")
    compare(M.clock(3725), "1:02:05")
    compare(M.clock(-5), "0:00")
  }

  function test_nothing_changes_the_state_it_was_given() {
    var s = S.begin(S.fresh(), "gentle")
    S.record(s, S.WON, 10)
    S.withSeconds(s, 99)
    compare(s.seconds, 0)
    compare(S.recordFor(s, "gentle").played, 0)
  }
}
