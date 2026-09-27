// The lists and the day's word, against the GTK version's test_words.py. The
// day's word is also checked against what 0.1.0 set on three real days, so a
// person playing both on one day plays one word.
import QtQuick
import QtTest
import "../Game.js" as G
import "../Words.js" as W

TestCase {
  name: "FiveLettersWords"

  readonly property var words: W.all()

  function test_they_are_actually_there() {
    verify(words.complete, "the word lists did not load")
    compare(words.answers.length, 1510)
    compare(Object.keys(words.guesses).length, 12167)
  }
  function test_every_word_is_five_letters_of_the_alphabet() {
    for (var i = 0; i < words.answers.length; i++) verify(G.WORD.test(words.answers[i]), words.answers[i])
    for (var k in words.guesses) verify(G.WORD.test(k), k)
  }
  function test_every_answer_is_a_word_the_keyboard_will_accept() {
    for (var i = 0; i < words.answers.length; i++) verify(W.allows(words, words.answers[i]), words.answers[i])
  }
  function test_the_answers_are_a_smaller_and_different_list() {
    verify(words.answers.length < Object.keys(words.guesses).length / 4)
  }
  function test_there_are_no_duplicates_among_the_answers() {
    var seen = ({})
    for (var i = 0; i < words.answers.length; i++) {
      verify(!seen[words.answers[i]], words.answers[i])
      seen[words.answers[i]] = true
    }
  }
  function test_the_keyboard_has_every_letter_once() {
    compare(G.KEYBOARD.join("").split("").sort().join(""), G.ALPHABET)
  }
  function test_the_day_is_the_gtk_versions_day() {
    compare(W.ordinal("2026-09-12"), 739871)
    compare(W.index(words, "2026-09-12"), 50)
    compare(W.daily(words, "2026-09-12"), "ATTIC")
    compare(W.daily(words, "2026-01-01"), "FREAK")
    compare(W.daily(words, "2026-09-27"), "ABUSE")
  }
  function test_the_same_day_is_the_same_word() {
    compare(W.daily(words, "2026-09-12"), W.daily(words, "2026-09-12"))
  }
  function test_consecutive_days_do_not_walk_the_alphabet() {
    var indices = []
    for (var i = 0; i < 60; i++) indices.push(W.index(words, W.addDays("2026-01-01", i)))
    var least = Infinity
    for (var j = 1; j < indices.length; j++) least = Math.min(least, Math.abs(indices[j] - indices[j - 1]))
    verify(least > Math.floor(words.answers.length / 30), least)
    var set = ({})
    for (var k = 0; k < indices.length; k++) set[indices[k]] = true
    compare(Object.keys(set).length, indices.length)
  }
  function test_every_day_of_a_year_has_a_word() {
    for (var i = 0; i < 366; i++) verify(words.answers.indexOf(W.daily(words, W.addDays("2026-01-01", i))) >= 0)
  }
  function test_the_harness_can_pin_today() {
    compare(W.today("2026-09-12"), "2026-09-12")
    compare(W.today("not a date"), W.iso(new Date()))
    compare(W.addDays("2026-12-31", 1), "2027-01-01")
  }
  function test_it_falls_back_to_a_handful_of_words() {
    var w = W.make([], [])
    verify(!w.complete)
    compare(w.answers, W.SPARE)
    verify(W.allows(w, "CRANE"))
  }
  function test_a_short_or_odd_word_never_gets_in() {
    var w = W.make(["CRANE", "OK", "", "SÉANCE", "toast"], [])
    compare(w.answers.slice().sort(), ["CRANE", "TOAST"])
    verify(W.allows(w, "crane"))
    verify(!W.allows(w, "SÉANCE"))
  }
  function test_the_shape_of_the_game_is_five_and_six() {
    compare(G.LENGTH, 5)
    compare(G.GUESSES, 6)
  }
}
