// The file: what is written comes back, what is broken is dropped rather
// than believed, and every answer is counted once.
import QtQuick
import QtTest
import "../Store.js" as S
import "../Trivia.js" as T

TestCase {
  name: "TriviaStore"

  function questions() {
    return [
      { text: "One?", category: 22, difficulty: "easy", type: "multiple", answers: ["a", "b", "c", "d"], correct: 2 },
      { text: "Two?", category: 22, difficulty: "hard", type: "boolean", answers: ["True", "False"], correct: 0 }
    ]
  }
  function started() {
    return S.withRound(S.fresh(), T.round({ category: 22, difficulty: "any", type: "any" }, questions(), 5))
  }
  function roundTrip(state) { return S.parse(JSON.parse(S.serialize(state))) }

  function test_a_missing_file_is_a_fresh_start() {
    var s = S.parse(null)
    compare(s.round, null)
    compare(s.pick.amount, T.DEFAULT_LENGTH)
    compare(s.stats.answered, 0)
  }

  function test_an_answer_is_counted_when_it_is_given() {
    var s = S.answer(started(), 2)
    compare(s.stats.answered, 1)
    compare(s.stats.right, 1)
    compare(s.stats.streak, 1)
    compare(s.stats.byDifficulty.easy.right, 1)
    compare(S.categoryRecord(s, 22).answered, 1)
    // The round itself is not counted until its score is reached.
    compare(s.stats.rounds, 0)
    // And not twice.
    compare(S.answer(s, 1).stats.answered, 1)
  }

  function test_a_wrong_answer_ends_the_run() {
    var s = S.answer(started(), 2)
    s = S.advance(s, 10)
    s = S.answer(s, 1)
    compare(s.stats.streak, 0)
    compare(s.stats.bestStreak, 1)
    compare(s.stats.byDifficulty.hard.answered, 1)
    compare(s.stats.byDifficulty.hard.right, 0)
  }

  function test_the_round_is_counted_once_at_the_score() {
    var s = S.advance(S.answer(started(), 2), 10)
    s = S.advance(S.answer(s, 0), 20)
    verify(T.finished(s.round))
    verify(s.round.recorded)
    compare(s.stats.rounds, 1)
    compare(s.stats.sweeps, 1)
    compare(S.categoryRecord(s, 22).best, 100)
    compare(s.recent.length, 1)
    compare(s.recent[0].right, 2)
    compare(s.recent[0].at, 20)
    compare(S.advance(s, 30).stats.rounds, 1)
  }

  function test_a_round_in_progress_comes_back_where_it_was() {
    var s = S.answer(started(), 1)
    var back = roundTrip(s)
    compare(back.round.index, 0)
    compare(back.round.picks, [1])
    verify(T.answered(back.round))
    compare(back.round.questions[1].answers, ["True", "False"])
    compare(back.stats.answered, 1)
  }

  function test_a_round_that_will_not_play_is_no_round() {
    var raw = JSON.parse(S.serialize(started()))
    raw.round.questions[1].correct = 7
    compare(S.parse(raw).round, null)
    raw = JSON.parse(S.serialize(started()))
    raw.round.questions = []
    compare(S.parse(raw).round, null)
  }

  function test_picks_past_the_screen_are_cut() {
    var raw = JSON.parse(S.serialize(started()))
    raw.round.picks = [2, 0]
    raw.round.index = 0
    compare(S.parse(raw).round.picks, [2])
    raw.round.picks = [9]
    compare(S.parse(raw).round.picks, [])
  }

  function test_the_pick_is_kept_and_checked() {
    var s = S.withPick(S.fresh(), { category: 18, difficulty: "hard", amount: 20, type: "boolean" })
    var back = roundTrip(s)
    compare(back.pick, { category: 18, difficulty: "hard", type: "boolean", amount: 20 })
    compare(S.withPick(s, { amount: 7, category: 99 }).pick.amount, 20)
    compare(S.withPick(s, { category: 99 }).pick.category, 18)
  }

  function test_right_is_never_more_than_answered() {
    var s = S.parse({ stats: { answered: 3, right: 9, byCategory: { "22": { answered: 1, right: 4 }, "nope": {} } } })
    compare(s.stats.right, 3)
    compare(S.categoryRecord(s, 22).right, 1)
    compare(Object.keys(s.stats.byCategory), ["22"])
  }

  function test_the_token_is_kept_with_when_it_was_used() {
    var back = roundTrip(S.withToken(S.fresh(), "abc", 42))
    compare(back.token, { value: "abc", used: 42 })
    compare(roundTrip(S.withToken(S.fresh(), "", 0)).token, null)
  }

  function test_the_played_categories_most_answered_first() {
    var s = S.parse({ stats: { answered: 5, right: 3, byCategory: {
      "22": { answered: 1, right: 1 }, "18": { answered: 4, right: 2 }, "9": { answered: 0, right: 0 } } } })
    var list = S.playedCategories(s)
    compare(list.length, 2)
    compare(list[0].id, 18)
  }
}
