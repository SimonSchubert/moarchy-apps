// What Open Trivia DB says, read; and a round, played. The bodies here are
// the shapes the live API answered with while this was written, encoded as
// the app asks for them (encode=url3986).
import QtQuick
import QtTest
import "../Trivia.js" as T

TestCase {
  name: "Trivia"

  readonly property string body: JSON.stringify({
    response_code: 0,
    results: [
      { type: "multiple", difficulty: "medium", category: "General%20Knowledge",
        question: "When%20was%20Hubba%20Bubba%20first%20introduced%3F",
        correct_answer: "1979", incorrect_answers: ["1984", "1972", "1980"] },
      { type: "boolean", difficulty: "easy", category: "Entertainment%3A%20Video%20Games",
        question: "Big%20the%20Cat%20is%20a%20playable%20character%20in%20%22Sonic%20Generations%22.",
        correct_answer: "False", incorrect_answers: ["True"] },
      { type: "multiple", difficulty: "hard", category: "Geography",
        question: "Which%20is%20Aloysius%20O%27Hare%3F",
        correct_answer: "The%20Lorax%E2%80%99s%20villain", incorrect_answers: ["Ted", "Norma", "Once-ler"] }
    ]
  })

  function played(n) {
    var r = T.parseQuestions(body, T.random(7))
    return T.round({ category: 9, difficulty: "any", type: "any" }, r.questions.slice(0, n || 3), 1)
  }

  function test_the_text_is_decoded_exactly() {
    var r = T.parseQuestions(body, T.random(1))
    compare(r.code, T.OK)
    compare(r.questions.length, 3)
    compare(r.questions[0].text, "When was Hubba Bubba first introduced?")
    compare(r.questions[1].text, "Big the Cat is a playable character in \"Sonic Generations\".")
    compare(r.questions[2].text, "Which is Aloysius O'Hare?")
    compare(r.questions[2].answers[r.questions[2].correct], "The Lorax’s villain")
  }

  function test_the_right_answer_is_somewhere_among_four() {
    var q = T.parseQuestions(body, T.random(3)).questions[0]
    compare(q.answers.length, 4)
    compare(q.answers[q.correct], "1979")
    compare(q.answers.slice().sort(), ["1972", "1979", "1980", "1984"])
  }

  function test_the_right_answer_does_not_always_land_first() {
    var places = ({})
    for (var seed = 1; seed < 60; seed++)
      places[T.parseQuestions(body, T.random(seed)).questions[0].correct] = true
    compare(Object.keys(places).length, 4)
  }

  function test_true_comes_before_false() {
    var q = T.parseQuestions(body, T.random(5)).questions[1]
    compare(q.type, "boolean")
    compare(q.answers, ["True", "False"])
    compare(q.correct, 1)
  }

  function test_a_question_knows_its_category_and_difficulty() {
    var qs = T.parseQuestions(body, T.random(1)).questions
    compare(qs[0].category, 9)
    compare(qs[1].category, 15)
    compare(qs[2].category, 22)
    compare(qs[1].difficulty, "easy")
    compare(qs[2].difficulty, "hard")
  }

  function test_the_codes_come_back_as_problems() {
    compare(T.parseQuestions('{"response_code":1,"results":[]}').code, T.TOO_FEW)
    compare(T.parseQuestions('{"response_code":3,"results":[]}').code, T.NO_TOKEN)
    compare(T.parseQuestions('{"response_code":4,"results":[]}').code, T.TOKEN_EMPTY)
    compare(T.parseQuestions('{"response_code":5,"result":[]}').code, T.RATE_LIMITED)
    compare(T.parseQuestions("<html>").code, -1)
    verify(T.parseQuestions('{"response_code":5}').error.length > 0)
  }

  function test_a_broken_question_is_dropped_not_the_round() {
    var r = T.parseQuestions(JSON.stringify({ response_code: 0, results: [
      { type: "multiple", question: "", correct_answer: "a", incorrect_answers: ["b"] },
      { type: "multiple", question: "Q", correct_answer: "a", incorrect_answers: ["b", "c", "d"] }
    ] }), T.random(1))
    compare(r.questions.length, 1)
    // Nothing usable at all is "not that many".
    compare(T.parseQuestions('{"response_code":0,"results":[{}]}').code, T.TOO_FEW)
  }

  function test_percent_signs_that_are_not_escapes_survive() {
    compare(T.decode("100%"), "100%")
    compare(T.decode("50%25"), "50%")
  }

  function test_the_token() {
    compare(T.parseToken('{"response_code":0,"response_message":"Token Generated Successfully!","token":"abc"}'), "abc")
    compare(T.parseToken('{"response_code":2}'), "")
    compare(T.parseToken("nope"), "")
    verify(T.tokenFresh({ value: "abc", used: 1000 }, 2000))
    verify(!T.tokenFresh({ value: "abc", used: 0 }, T.TOKEN_TTL_MS + 1))
    verify(!T.tokenFresh(null, 0))
  }

  function test_the_url_says_what_was_picked() {
    var url = T.questionsUrl({ category: 22, difficulty: "hard", type: "boolean" }, 10, "t k")
    verify(url.indexOf("amount=10") > 0)
    verify(url.indexOf("category=22") > 0)
    verify(url.indexOf("difficulty=hard") > 0)
    verify(url.indexOf("type=boolean") > 0)
    verify(url.indexOf("encode=url3986") > 0)
    verify(url.indexOf("token=t%20k") > 0)
    var any = T.questionsUrl({ category: 0, difficulty: "any", type: "any" }, 99, "")
    verify(any.indexOf("category") < 0 && any.indexOf("difficulty") < 0 && any.indexOf("type=") < 0)
    verify(any.indexOf("amount=50") > 0)
  }

  function test_a_round_is_answered_then_moved_on_from() {
    var r = played()
    var q = T.current(r)
    verify(!T.answered(r))
    r = T.answer(r, q.correct)
    verify(T.answered(r))
    compare(r.index, 0)
    // A second tap on the same question does nothing.
    compare(T.answer(r, 0).picks.length, 1)
    r = T.advance(r)
    compare(r.index, 1)
    verify(!T.answered(r))
    // Not moved on from until answered.
    compare(T.advance(r).index, 1)
  }

  function test_the_score_and_the_runs() {
    var r = played()
    r = T.advance(T.answer(r, T.current(r).correct))
    r = T.advance(T.answer(r, (T.current(r).correct + 1) % 2))
    r = T.advance(T.answer(r, T.current(r).correct))
    verify(T.finished(r))
    compare(T.score(r), 2)
    compare(T.runs(r).best, 1)
    compare(T.runs(r).now, 1)
    compare(T.current(r), null)
  }

  function test_the_words_for_a_score() {
    compare(T.verdict(10, 10), "A clean sweep")
    compare(T.verdict(8, 10), "Sharp")
    compare(T.verdict(0, 10), "One to forget")
    compare(T.verdict(0, 0), "")
  }

  function test_every_category_has_a_name_and_a_glyph() {
    var ids = ({})
    for (var i = 0; i < T.CATEGORIES.length; i++) {
      var c = T.CATEGORIES[i]
      verify(c.name.length > 0 && c.glyph.length > 0, c.id)
      verify(!ids[c.id], "twice: " + c.id)
      ids[c.id] = true
    }
    compare(T.CATEGORIES.length, 25)
    compare(T.category(12345).id, T.ANY)
  }
}
