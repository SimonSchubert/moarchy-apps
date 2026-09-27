// What the app does to habits beyond the arithmetic: the editor's rules, a
// tap on a mark, taking a habit out and putting it back, the history grid --
// and the cases of 0.1.2's Python tests that the arithmetic tests did not
// already carry.
import QtQuick
import QtTest
import "../Habits.js" as H
import "../Game.js" as Game

TestCase {
  name: "HabitsApp"

  readonly property string today: "2026-09-15"   // a Tuesday

  function daily(name, back) {
    var e = ({})
    for (var i = 0; i < back.length; i++) e[H.addDays(today, -back[i])] = 1.0
    return H.make({ name: name, entries: e, created: 0 })
  }

  function test_the_editor_writes_only_the_fields_it_owns() {
    var h = daily("Read", [0, 1, 2])
    H.apply(h, { name: "  Read more ", question: "", kind: H.BOOLEAN, target: 9, unit: "pages",
                 frequency: 4, colour: "blue" })
    compare(h.name, "Read more")
    compare(h.freq_num, 3)
    compare(h.freq_den, 7)
    compare(h.colour, "blue")
    // A yes-or-no habit keeps a target of one and no unit.
    compare(h.target, 1)
    compare(h.unit, "")
    compare(Object.keys(h.entries).length, 3)
  }

  function test_a_counted_habit_keeps_its_target_and_unit() {
    var h = H.apply(H.make({}), { name: "Water", kind: H.MEASURABLE, target: 8, unit: "glasses",
                                   frequency: 0, colour: "cyan" })
    compare(h.kind, H.MEASURABLE)
    compare(h.target, 8)
    compare(h.unit, "glasses")
  }

  function test_nonsense_from_the_editor_falls_back() {
    var h = H.apply(H.make({}), { name: "X", kind: H.MEASURABLE, target: NaN, frequency: 99, colour: "plaid" })
    compare(h.target, 1)
    compare(h.freq_num, 1)
    compare(h.freq_den, 1)
    compare(h.colour, "green")
  }

  function test_the_frequency_index_finds_the_editors_row() {
    compare(H.frequencyIndex(H.make({ freq_num: 3, freq_den: 7 })), 4)
    compare(H.frequencyIndex(H.make({ freq_num: 2, freq_den: 9 })), 0)
  }

  function test_frequency_labels() {
    compare(H.frequencyLabel(H.make({ freq_num: 1, freq_den: 1 })), "Every day")
    compare(H.frequencyLabel(H.make({ freq_num: 3, freq_den: 7 })), "3× a week")
    compare(H.frequencyLabel(H.make({ freq_num: 2, freq_den: 30 })), "2× a month")
    compare(H.frequencyLabel(H.make({ freq_num: 2, freq_den: 10 })), "2× in 10 days")
  }

  function test_a_tap_on_a_counted_habit_adds_one_then_clears_at_the_target() {
    var h = H.make({ kind: H.MEASURABLE, target: 2 })
    verify(!H.tap(h, today))
    compare(H.value(h, today), 1)
    verify(H.tap(h, today))
    compare(H.value(h, today), 2)
    verify(!H.tap(h, today))
    compare(h.entries[today], undefined)
  }

  function test_a_tap_on_a_yes_or_no_habit_toggles() {
    var h = H.make({})
    verify(H.tap(h, today))
    verify(!H.tap(h, today))
  }

  function test_delete_and_restore_keeps_position() {
    var list = [daily("a", []), daily("b", []), daily("c", [])]
    var out = H.remove(list, list[1].id)
    compare(out.index, 1)
    compare(out.habits.length, 2)
    var back = H.restore(out.habits, out.habit, out.index)
    compare(back.map(function (h) { return h.name }).join(""), "abc")
    compare(H.remove(list, "nope").index, -1)
  }

  function test_archived_habits_do_not_count() {
    var a = daily("a", [0]), b = daily("b", [])
    b.archived = true
    compare(H.todayProgress([a, b], today).done, 1)
    compare(H.todayProgress([a, b], today).due, 1)
    compare(H.todayProgress([], today).due, 0)
  }

  function test_recent_days_end_today_oldest_first() {
    compare(H.recentDays(3, today), ["2026-09-13", "2026-09-14", "2026-09-15"])
  }

  function test_recent_days_count_for_more_and_a_lapse_lowers_the_score() {
    var recent = daily("r", [0, 1, 2, 3, 4, 5, 6])
    var old = daily("o", [40, 41, 42, 43, 44, 45, 46])
    verify(H.score(recent, today) > H.score(old, today))
    var steady = daily("s", [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
    var lapsed = daily("l", [2, 3, 4, 5, 6, 7, 8, 9])
    verify(H.score(lapsed, today) < H.score(steady, today))
  }

  function test_the_history_grid_is_mondays_down_and_ends_this_week() {
    var g = H.historyGrid(today, 16)
    compare(g.length, 16)
    compare(g[15][0], "2026-09-14")    // this Monday
    compare(g[15][1], today)
    compare(g[15][2], null)            // tomorrow has not happened
    compare(g[0][0], H.addDays("2026-09-14", -15 * 7))
    compare(H.weekday("2026-09-14"), 0)
    compare(H.weekday("2026-09-20"), 6)
  }

  function test_a_schema_1_file_loads_with_none_earned() {
    var got = H.parse({ schema: 1, habits: [{ name: "Read", entries: { "2026-09-15": 1 } }] })
    compare(got.habits.length, 1)
    compare(Object.keys(got.achievements).length, 0)
  }

  function test_achievements_survive_a_round_trip() {
    var got = H.parse(JSON.parse(H.serialize([daily("a", [0])], { first: "2026-09-01" })))
    compare(got.achievements.first, "2026-09-01")
  }

  function test_a_week_streak_earns_the_week_and_a_short_one_does_not() {
    verify(Game.qualifies([daily("a", [0, 1, 2, 3, 4, 5, 6])], "week", today))
    verify(!Game.qualifies([daily("a", [0, 1, 2, 3, 4, 5])], "week", today))
  }

  function test_four_habits_are_not_a_handful() {
    verify(!Game.qualifies([daily("a", []), daily("b", []), daily("c", []), daily("d", [])], "handful", today))
  }

  function test_an_unbroken_run_is_not_a_comeback() {
    verify(!Game.qualifies([daily("a", [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])], "comeback", today))
  }

  function test_nothing_is_earned_by_an_empty_store() {
    compare(Game.newlyEarned([], ({}), today), [])
  }
}
