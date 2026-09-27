// The one thing written down: the sum that was half typed when the window went
// away, and whether it was an answer or something being typed.
import QtQuick
import QtTest
import "../Store.js" as Store

TestCase {
  name: "Store"

  function test_a_sum_goes_out_and_comes_back() {
    var back = Store.parse(JSON.parse(Store.serialize({ entry: "12+", answered: false })))
    compare(back.entry, "12+")
    compare(back.answered, false)
  }

  function test_an_answer_and_a_number_being_typed_look_the_same_in_a_file() {
    // Which is why the flag is written down rather than worked out: it decides
    // whether the next digit starts a new sum or lands on the end of this one.
    compare(Store.parse(JSON.parse(Store.serialize({ entry: "1428", answered: true }))).answered, true)
    compare(Store.parse(JSON.parse(Store.serialize({ entry: "1428", answered: false }))).answered, false)
  }

  function test_nothing_at_all_is_an_empty_sum_rather_than_a_failure() {
    compare(Store.parse(null).entry, "")
    compare(Store.parse(null).answered, false)
    compare(Store.parse({}).entry, "")
  }

  function test_a_file_somebody_has_edited_cannot_put_anything_but_text_on_screen() {
    compare(Store.parse({ entry: 12, answered: "yes" }).entry, "")
    compare(Store.parse({ entry: "1+1", answered: "yes" }).answered, true)
  }

  function test_a_file_without_a_tape_has_an_empty_one() {
    compare(Store.parse({ entry: "2", answered: true }).tape, [])
  }

  function test_the_tape_goes_out_and_comes_back() {
    var tape = Store.remember([], "12+3*4", "24")
    var back = Store.parse(JSON.parse(Store.serialize({ entry: "24", answered: true, tape: tape })))
    compare(back.tape, [{ sum: "12+3*4", answer: "24" }])
  }

  function test_the_same_sum_answered_twice_is_one_line() {
    compare(Store.remember(Store.remember([], "1+1", "2"), "1+1", "2").length, 1)
  }

  function test_the_tape_keeps_its_newest_lines() {
    var tape = []
    for (var i = 0; i < Store.TAPE + 7; i++) tape = Store.remember(tape, i + "+0", String(i))
    compare(tape.length, Store.TAPE)
    compare(tape[tape.length - 1].answer, String(Store.TAPE + 6))
  }

  function test_a_tape_line_that_is_not_text_is_dropped() {
    compare(Store.parse({ tape: [{ sum: 1, answer: "1" }, { sum: "2", answer: "2" }, "x"] }).tape,
            [{ sum: "2", answer: "2" }])
  }
}
