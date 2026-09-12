"""The storage layer and every date calculation in it.

No GTK here, so this suite runs anywhere -- which is the point of keeping
habits.py free of it.
"""

import json
import os
import sys
import tempfile
import unittest
from datetime import date, timedelta
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

os.environ["MOARCHY_HABITS_TODAY"] = "2026-06-15"

from moarchy_habits.habits import (  # noqa: E402
    MEASURABLE,
    MILESTONES,
    Habit,
    Store,
    recent_days,
)

TODAY = date(2026, 6, 15)


def days_back(habit: Habit, offsets, amount=1.0):
    for off in offsets:
        habit.set_value(TODAY - timedelta(days=off), amount)


class TestTicking(unittest.TestCase):
    def test_toggle_sets_and_clears(self):
        h = Habit(name="Read")
        self.assertFalse(h.kept(TODAY))
        self.assertTrue(h.toggle(TODAY))
        self.assertTrue(h.kept(TODAY))
        self.assertFalse(h.toggle(TODAY))
        self.assertFalse(h.kept(TODAY))

    def test_cleared_day_leaves_no_entry(self):
        """A zero must not linger, or the file grows a row per untick."""
        h = Habit(name="Read")
        h.toggle(TODAY)
        h.toggle(TODAY)
        self.assertEqual(h.entries, {})

    def test_measurable_needs_the_target(self):
        h = Habit(name="Water", kind=MEASURABLE, target=8, unit="glasses")
        h.set_value(TODAY, 5)
        self.assertFalse(h.kept(TODAY))
        h.set_value(TODAY, 8)
        self.assertTrue(h.kept(TODAY))

    def test_toggling_measurable_fills_the_target(self):
        h = Habit(name="Water", kind=MEASURABLE, target=8)
        h.toggle(TODAY)
        self.assertEqual(h.value(TODAY), 8)


class TestStreak(unittest.TestCase):
    def test_counts_consecutive_days(self):
        h = Habit(name="Read")
        days_back(h, range(5))
        self.assertEqual(h.streak(TODAY), 5)

    def test_today_undone_does_not_break_it(self):
        """The day is not over. Yesterday's gap is what ends a streak."""
        h = Habit(name="Read")
        days_back(h, range(1, 6))
        self.assertEqual(h.streak(TODAY), 5)

    def test_yesterday_undone_does_break_it(self):
        h = Habit(name="Read")
        days_back(h, [0, 2, 3, 4])
        self.assertEqual(h.streak(TODAY), 1)

    def test_empty_habit_has_no_streak(self):
        self.assertEqual(Habit(name="Read").streak(TODAY), 0)

    def test_best_streak_finds_the_longest_past_run(self):
        h = Habit(name="Read")
        days_back(h, [10, 11, 12, 13, 14, 15, 16])  # a run of 7
        days_back(h, [0, 1])  # a run of 2 now
        self.assertEqual(h.best_streak(), 7)


class TestFrequency(unittest.TestCase):
    def test_three_times_a_week_is_on_track_at_three(self):
        h = Habit(name="Gym", freq_num=3, freq_den=7)
        days_back(h, [0, 2, 4])
        self.assertTrue(h.on_track(TODAY))

    def test_three_times_a_week_is_off_track_at_two(self):
        h = Habit(name="Gym", freq_num=3, freq_den=7)
        days_back(h, [0, 2])
        self.assertFalse(h.on_track(TODAY))

    def test_a_weekly_habit_keeps_its_streak_between_sessions(self):
        """The point of 3x/week: the off days must not zero the streak."""
        h = Habit(name="Gym", freq_num=3, freq_den=7)
        days_back(h, [0, 2, 4, 7, 9, 11, 14, 16, 18])
        self.assertGreater(h.streak(TODAY), 1)

    def test_daily_habit_is_on_track_only_when_kept(self):
        h = Habit(name="Read")
        self.assertFalse(h.on_track(TODAY))
        h.toggle(TODAY)
        self.assertTrue(h.on_track(TODAY))


class TestScore(unittest.TestCase):
    def test_empty_is_zero(self):
        self.assertEqual(Habit(name="Read").score(TODAY), 0.0)

    def test_perfect_month_is_near_one(self):
        h = Habit(name="Read")
        days_back(h, range(30))
        self.assertGreater(h.score(TODAY), 0.9)

    def test_score_is_bounded(self):
        h = Habit(name="Read")
        days_back(h, range(400))
        self.assertLessEqual(h.score(TODAY), 1.0)

    def test_recent_days_count_for_more(self):
        """Same number of days kept; the one who kept them lately scores higher."""
        recent, distant = Habit(name="a"), Habit(name="b")
        days_back(recent, range(10))
        days_back(distant, range(60, 70))
        self.assertGreater(recent.score(TODAY), distant.score(TODAY))

    def test_lapse_lowers_the_score(self):
        kept = Habit(name="a")
        days_back(kept, range(30))
        lapsed = Habit(name="b")
        days_back(lapsed, range(15, 45))
        self.assertGreater(kept.score(TODAY), lapsed.score(TODAY))


class TestMilestones(unittest.TestCase):
    def test_crossing_a_milestone_is_announced_once(self):
        h = Habit(name="Read")
        self.assertEqual(h.milestone_crossed(6, 7), 7)

    def test_not_crossing_announces_nothing(self):
        h = Habit(name="Read")
        self.assertIsNone(h.milestone_crossed(7, 8))

    def test_reticking_inside_a_long_streak_announces_nothing(self):
        """The reward is for crossing. A 40-day streak must not keep
        re-announcing the 30 every time a day inside it is touched."""
        h = Habit(name="Read")
        self.assertIsNone(h.milestone_crossed(40, 40))

    def test_going_backwards_announces_nothing(self):
        h = Habit(name="Read")
        self.assertIsNone(h.milestone_crossed(30, 12))

    def test_a_jump_past_several_takes_the_first(self):
        h = Habit(name="Read")
        self.assertEqual(h.milestone_crossed(1, 200), 7)

    def test_next_milestone_counts_down(self):
        h = Habit(name="Read")
        days_back(h, range(5))
        self.assertEqual(h.next_milestone(TODAY), (7, 2))

    def test_next_milestone_is_none_past_the_last(self):
        h = Habit(name="Read")
        days_back(h, range(MILESTONES[-1] + 10))
        self.assertIsNone(h.next_milestone(TODAY))


class TestTodayProgress(unittest.TestCase):
    def setUp(self):
        self.store = Store(Path(tempfile.mkdtemp()) / "habits.json")

    def test_counts_kept_out_of_active(self):
        a = self.store.create("a")
        self.store.create("b")
        a.toggle(TODAY)
        self.assertEqual(self.store.today_progress(TODAY), (1, 2))

    def test_archived_habits_do_not_count(self):
        a = self.store.create("a")
        b = self.store.create("b")
        b.archived = True
        a.toggle(TODAY)
        self.assertEqual(self.store.today_progress(TODAY), (1, 1))

    def test_empty_store_is_zero_of_zero(self):
        self.assertEqual(self.store.today_progress(TODAY), (0, 0))


class TestStore(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.path = Path(self.dir.name) / "habits.json"

    def tearDown(self):
        self.dir.cleanup()

    def test_round_trip(self):
        store = Store(self.path)
        h = store.create("Read", question="Did you read?")
        h.toggle(TODAY)
        store.save()

        again = Store(self.path)
        again.load()
        self.assertEqual(len(again.habits), 1)
        self.assertEqual(again.habits[0].name, "Read")
        self.assertTrue(again.habits[0].kept(TODAY))

    def test_missing_file_is_not_an_error(self):
        store = Store(self.path)
        store.load()
        self.assertEqual(store.habits, [])

    def test_broken_file_is_moved_aside_not_overwritten(self):
        self.path.write_text("{not json", encoding="utf-8")
        store = Store(self.path)
        store.load()
        self.assertEqual(store.habits, [])
        rescued = list(self.path.parent.glob("*.broken-*.json"))
        self.assertEqual(len(rescued), 1)

    def test_junk_entries_are_dropped_not_fatal(self):
        self.path.write_text(
            json.dumps(
                {
                    "schema": 1,
                    "habits": [
                        {"name": "Read", "entries": {"not-a-date": 1, "2026-06-15": 1}}
                    ],
                }
            ),
            encoding="utf-8",
        )
        store = Store(self.path)
        store.load()
        self.assertEqual(list(store.habits[0].entries), ["2026-06-15"])

    def test_delete_and_restore_keeps_position(self):
        store = Store(self.path)
        store.create("a")
        b = store.create("b")
        store.create("c")
        index = store.delete(b)
        self.assertEqual([h.name for h in store.habits], ["a", "c"])
        store.restore(b, index)
        self.assertEqual([h.name for h in store.habits], ["a", "b", "c"])

    def test_save_is_atomic_leaving_no_temp_behind(self):
        store = Store(self.path)
        store.create("Read")
        store.save()
        self.assertEqual(list(self.path.parent.glob("*.tmp")), [])


class TestStrip(unittest.TestCase):
    def test_recent_days_ends_today_and_is_oldest_first(self):
        days = recent_days(5, TODAY)
        self.assertEqual(days[-1], TODAY)
        self.assertEqual(days[0], TODAY - timedelta(days=4))
        self.assertEqual(len(days), 5)


if __name__ == "__main__":
    unittest.main()
