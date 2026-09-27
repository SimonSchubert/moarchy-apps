// The rules, against the GTK version's (0.1.0) test_fiveletters.py, case for
// case: the colouring above all, because duplicate letters are the one thing
// implementations of this game get wrong.
import QtQuick
import QtTest
import "../Game.js" as G

TestCase {
  name: "FiveLettersGame"

  readonly property var allowed: ({ CRANE: true, SLOTH: true, ALLOY: true, LOYAL: true, SPEED: true,
                                    ERASE: true, ABBEY: true, EERIE: true, GEESE: true })
  readonly property int a: G.ABSENT
  readonly property int p: G.PRESENT
  readonly property int c: G.CORRECT

  function test_an_exact_match_is_correct_and_a_miss_is_absent() {
    compare(G.evaluate("CRANE", "CRANE"), [c, c, c, c, c])
    compare(G.evaluate("SLOTH", "BUMPY"), [a, a, a, a, a])
  }
  function test_a_letter_in_the_wrong_place_is_present() {
    compare(G.evaluate("ARC", "CAR"), [p, p, p])
  }
  function test_an_anagram_is_five_yellows() {
    compare(G.evaluate("ALLOY", "LOYAL"), [p, p, p, p, p])
  }
  function test_a_repeated_letter_only_lights_as_often_as_the_secret_has_it() {
    compare(G.evaluate("SPEED", "ERASE"), [p, a, p, p, a])
  }
  function test_an_exact_match_consumes_its_letter_first() {
    var marks = G.evaluate("GEESE", "EERIE")
    compare(marks[4], c)
    compare(marks.filter(function (m) { return m !== G.ABSENT }).length, 3)
  }
  function test_a_letter_the_secret_has_once_lights_once() {
    compare(G.evaluate("ABBEY", "ABODE"), [c, c, a, p, a])
  }
  function test_the_marks_are_ordered_so_a_key_never_goes_backwards() {
    verify(G.ABSENT < G.PRESENT)
    verify(G.PRESENT < G.CORRECT)
  }

  function test_a_guess_is_taken_and_answered() {
    var g = G.submit(G.make("CRANE", allowed), "SLOTH")
    compare(G.used(g), 1)
    compare(G.left(g), G.GUESSES - 1)
    verify(!G.over(g))
  }
  function test_the_right_word_ends_it() {
    var g = G.submit(G.make("CRANE", allowed), "CRANE")
    verify(G.solved(g))
    verify(G.over(g))
    verify(!G.out(g))
    verify(G.submit(g, "SLOTH") === g)
  }
  function test_six_wrong_ones_end_it_too() {
    var g = G.make("CRANE", null)
    for (var i = 0; i < G.GUESSES; i++) g = G.submit(g, "SLOTH")
    verify(G.out(g))
    verify(G.over(g))
    verify(!G.solved(g))
    compare(G.left(g), 0)
  }
  function test_a_word_that_is_not_on_the_list_is_refused() {
    compare(G.used(G.submit(G.make("CRANE", allowed), "ZZZZZ")), 0)
  }
  function test_a_word_of_the_wrong_length_is_refused() {
    var bad = ["CRAN", "CRANES", "", "CR4NE", "CRAN E"]
    for (var i = 0; i < bad.length; i++) verify(!G.accepts(bad[i], null), bad[i])
  }
  function test_anything_goes_when_there_is_no_list() {
    compare(G.used(G.submit(G.make("CRANE", null), "ZZZZZ")), 1)
  }
  function test_a_game_is_rebuilt_from_its_guesses() {
    var g = G.make("CRANE", allowed, ["SLOTH", "ALLOY"])
    compare(G.words(g), ["SLOTH", "ALLOY"])
    var again = G.make("CRANE", allowed, G.words(g))
    compare(again.guesses.map(function (x) { return x.marks }), g.guesses.map(function (x) { return x.marks }))
  }
  function test_a_word_that_will_not_play_ends_the_replay_there() {
    compare(G.words(G.make("CRANE", allowed, ["SLOTH", "NOPE", "ALLOY"])), ["SLOTH"])
  }
  function test_the_lowercase_is_taken_and_kept_upper() {
    var g = G.make("crane", allowed)
    compare(g.secret, "CRANE")
    compare(G.words(G.submit(g, "sloth")), ["SLOTH"])
  }
  function test_a_letter_never_goes_backwards() {
    compare(G.keys(G.make("ABODE", null, ["ABBEY", "EERIE"])).E, G.CORRECT)
  }
  function test_it_only_knows_letters_that_have_been_guessed() {
    compare(Object.keys(G.keys(G.make("CRANE", null, ["SLOTH"]))).sort(), ["H", "L", "O", "S", "T"])
  }
  function test_what_is_known_reads_as_a_pattern() {
    compare(G.known(G.make("CRANE", null, ["CRUMB"])), "CR___")
  }
  function test_a_guess_knows_whether_it_was_right() {
    verify(G.right({ word: "CRANE", marks: G.evaluate("CRANE", "CRANE") }))
    verify(!G.right({ word: "CRANE", marks: G.evaluate("CRANE", "SLOTH") }))
  }
}
