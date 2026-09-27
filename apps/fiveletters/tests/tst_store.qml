// The games in progress, the streak and the share, against the GTK version's
// test_store.py (0.1.0): the same cases, over the same fiveletters.json.
import QtQuick
import QtTest
import "../Game.js" as G
import "../Words.js" as W
import "../Store.js" as S

TestCase {
  name: "FiveLettersStore"

  readonly property var words: W.all()
  readonly property string day: "2026-09-12"

  function next(d, n) { return W.addDays(d, n) }
  function roundTrip(s) { return S.parse(JSON.parse(S.serialize(s))) }
  function wrong(g) { return g.secret !== "CRANE" ? "CRANE" : "SLOTH" }

  // A day finished on the second guess: { state, game }.
  function solved(s, d) {
    s = S.rollOver(s, d)
    var g = S.game(s, words, d)
    g = G.submit(g, wrong(g))
    g = G.submit(g, g.secret)
    return { state: S.remember(s, g), game: g }
  }

  function test_a_missing_file_is_a_fresh_day_and_not_an_error() {
    var s = S.parse(null)
    compare(s.mode, S.DAILY)
    compare(s.daily, [])
    compare(s.stats.played, 0)
  }
  function test_the_game_it_hands_back_is_the_day_it_was_asked_for() {
    var s = S.rollOver(S.fresh(1), day)
    compare(S.game(s, words, day).secret, W.daily(words, day))
    compare(s.day, day)
  }
  function test_yesterdays_board_is_not_shown_against_todays_word() {
    var s = S.rollOver(S.fresh(1), day)
    s = S.remember(s, G.submit(S.game(s, words, day), "CRANE"))
    compare(s.daily.length, 1)
    var tomorrow = next(day, 1)
    s = S.rollOver(s, tomorrow)
    compare(s.daily, [])
    var g = S.game(s, words, tomorrow)
    compare(G.used(g), 0)
    compare(g.secret, W.daily(words, tomorrow))
  }
  function test_the_same_day_keeps_its_guesses() {
    var s = S.rollOver(S.fresh(1), day)
    s = S.remember(s, G.submit(S.game(s, words, day), "CRANE"))
    s = S.rollOver(s, day)
    compare(G.words(S.game(s, words, day)), ["CRANE"])
  }
  function test_roll_over_says_whether_it_happened() {
    var s = S.fresh(1)
    var t = S.rollOver(s, day)
    verify(t !== s)
    verify(S.rollOver(t, day) === t)
    verify(S.rollOver(t, next(day, 1)) !== t)
  }
  function test_everything_written_comes_back() {
    var r = solved(S.fresh(1), day)
    var s = S.record(r.state, r.game, day)
    var back = roundTrip(s)
    compare(back.day, day)
    compare(back.daily, G.words(r.game))
    compare(back.stats.won, 1)
    compare(back.stats.spread[1], 1)
    compare(G.words(S.game(back, words, day)), G.words(r.game))
  }
  function test_the_file_is_the_shape_store_py_wrote() {
    var raw = JSON.parse(S.serialize(S.fresh(7)))
    compare(raw.schema, 1)
    compare(raw.mode, "daily")
    compare(raw.practice.seed, 7)
    compare(raw.stats.spread, [0, 0, 0, 0, 0, 0])
    compare(raw.stats.last, "")
  }
  function test_the_secret_is_not_in_the_file() {
    var r = solved(S.fresh(1), day)
    var raw = JSON.parse(S.serialize(r.state))
    verify(raw.daily.guesses[0] !== W.daily(words, day))
    var p = S.beginPractice(r.state, 7)
    var text = S.serialize(p)
    verify(JSON.parse(text).practice.guesses.indexOf(W.practice(words, 7)) < 0)
  }
  function test_a_practice_word_comes_back_from_its_seed() {
    var s = S.beginPractice(S.fresh(1), 4242)
    var g = G.submit(S.game(s, words, day), "CRANE")
    s = S.remember(s, g)
    var back = roundTrip(s)
    compare(back.mode, S.PRACTICE)
    compare(S.game(back, words, day).secret, g.secret)
    compare(G.words(S.game(back, words, day)), ["CRANE"])
  }
  function test_junk_in_the_fields_falls_back_rather_than_raising() {
    var s = S.parse({
      mode: "telepathy",
      daily: { day: 7, guesses: ["CRANE", "NO", 5, null] },
      practice: { seed: "cheese" },
      stats: { played: "many", spread: "none" }
    })
    compare(s.mode, S.DAILY)
    compare(s.day, "")
    compare(s.daily, ["CRANE"])
    compare(s.stats.played, 0)
    compare(s.stats.spread, [0, 0, 0, 0, 0, 0])
  }
  function test_more_guesses_than_the_game_allows_are_cut_off() {
    var many = []
    for (var i = 0; i < 20; i++) many.push("CRANE")
    compare(S.parse({ daily: { guesses: many } }).daily.length, G.GUESSES)
  }
  function test_a_file_that_is_not_an_object_is_ignored() {
    compare(S.parse([1, 2, 3]).daily, [])
  }
  function test_days_in_a_row_build_it() {
    var s = S.fresh(1)
    for (var i = 0; i < 4; i++) {
      var d = next(day, i)
      var r = solved(s, d)
      s = S.record(r.state, r.game, d)
    }
    compare(s.stats.streak, 4)
    compare(s.stats.best, 4)
    compare(s.stats.played, 4)
  }
  function test_a_day_skipped_ends_it() {
    var s = S.fresh(1)
    for (var i = 0; i < 2; i++) {
      var r = solved(s, next(day, i))
      s = S.record(r.state, r.game, next(day, i))
    }
    compare(s.stats.streak, 2)
    var later = next(day, 5)
    var l = solved(s, later)
    s = S.record(l.state, l.game, later)
    compare(s.stats.streak, 1)
    compare(s.stats.best, 2)
  }
  function test_a_day_missed_ends_it_too() {
    var r = solved(S.fresh(1), day)
    var s = S.record(r.state, r.game, day)
    var lost = next(day, 1)
    s = S.rollOver(s, lost)
    var g = S.game(s, words, lost)
    for (var i = 0; i < G.GUESSES; i++) g = G.submit(g, wrong(g))
    s = S.record(s, g, lost)
    compare(s.stats.streak, 0)
    compare(s.stats.played, 2)
    compare(s.stats.won, 1)
  }
  function test_a_day_is_only_counted_once() {
    var r = solved(S.fresh(1), day)
    var s = S.record(S.record(r.state, r.game, day), r.game, day)
    compare(s.stats.played, 1)
    verify(S.counted(s, day))
  }
  function test_practice_is_not_counted_at_all() {
    var s = S.beginPractice(S.fresh(1), 1)
    var g = S.game(s, words, day)
    g = G.submit(g, g.secret)
    compare(S.record(s, g, day).stats.played, 0)
  }
  function test_an_unfinished_day_is_not_counted() {
    var s = S.rollOver(S.fresh(1), day)
    var g = S.game(s, words, day)
    compare(S.record(s, G.submit(g, wrong(g)), day).stats.played, 0)
  }
  function test_the_rate_is_a_percentage_and_not_a_crash() {
    compare(S.rate(S.fresh(1)), 0)
    var r = solved(S.fresh(1), day)
    compare(S.rate(S.record(r.state, r.game, day)), 100)
  }
  function test_the_share_is_squares_and_a_score_and_nothing_else() {
    var r = solved(S.fresh(1), day)
    var text = S.share(r.game, 51)
    verify(text.indexOf("2/6") >= 0)
    var green = String.fromCodePoint(0x1F7E9)
    verify(text.indexOf(green + green + green + green + green) >= 0)
    var letters = r.game.secret.split("")
    // Spoiler-free: no capital of the answer appears in it.
    for (var i = 0; i < letters.length; i++) verify(text.indexOf(letters[i]) < 0, letters[i])
  }
  function test_an_unsolved_day_scores_an_x() {
    var s = S.rollOver(S.fresh(1), day)
    var g = S.game(s, words, day)
    for (var i = 0; i < G.GUESSES; i++) g = G.submit(g, wrong(g))
    verify(S.share(g, 51).indexOf("X/6") >= 0)
  }
  function test_nothing_changes_the_state_it_was_given() {
    var s = S.rollOver(S.fresh(1), day)
    var r = solved(s, day)
    S.record(r.state, r.game, day)
    compare(r.state.stats.played, 0)
    compare(s.daily, [])
  }
}
