"""Points, levels and achievements.

GTK-free like the storage layer, so this runs anywhere.
"""

import os
import sys
import tempfile
import unittest
from datetime import date, timedelta
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

os.environ["MOARCHY_HABITS_TODAY"] = "2026-06-15"

from moarchy_habits import game  # noqa: E402
from moarchy_habits.habits import Store  # noqa: E402

TODAY = date(2026, 6, 15)


def store_with(*specs):
    s = Store(Path(tempfile.mkdtemp()) / "habits.json")
    for name, offsets in specs:
        h = s.create(name)
        for off in offsets:
            h.set_value(TODAY - timedelta(days=off), 1)
    return s


class TestPoints(unittest.TestCase):
    def test_an_unkept_day_is_worth_nothing(self):
        s = store_with(("Read", []))
        self.assertEqual(game.day_points(s.habits[0], TODAY), 0)

    def test_a_kept_day_is_worth_the_base_plus_its_streak(self):
        s = store_with(("Read", [0]))
        self.assertEqual(game.day_points(s.habits[0], TODAY), game.BASE_POINTS + 1)

    def test_the_streak_bonus_is_capped(self):
        s = store_with(("Read", range(60)))
        self.assertEqual(
            game.day_points(s.habits[0], TODAY),
            game.BASE_POINTS + game.STREAK_BONUS_CAP,
        )

    def test_points_only_ever_go_up(self):
        """Nothing in the scoring can subtract. A tracker that punishes is one
        you stop opening on the days it matters most."""
        s = store_with(("Read", range(10)))
        before = game.total_points(s)
        s.create("Gym")  # a new, empty habit
        self.assertGreaterEqual(game.total_points(s), before)

    def test_an_empty_store_scores_zero(self):
        self.assertEqual(game.total_points(store_with()), 0)


class TestLevels(unittest.TestCase):
    def test_zero_is_the_first_level(self):
        number, name, into, togo = game.level_for(0)
        self.assertEqual((number, name, into), (1, game.LEVELS[0][1], 0))
        self.assertEqual(togo, game.LEVELS[1][0])

    def test_a_threshold_advances_the_level(self):
        below = game.level_for(game.LEVELS[1][0] - 1)[0]
        at = game.level_for(game.LEVELS[1][0])[0]
        self.assertEqual(at, below + 1)

    def test_the_last_level_has_nowhere_to_go(self):
        _, _, _, togo = game.level_for(game.LEVELS[-1][0] + 10_000)
        self.assertIsNone(togo)

    def test_levels_are_ordered_and_start_at_zero(self):
        thresholds = [t for t, _ in game.LEVELS]
        self.assertEqual(thresholds[0], 0)
        self.assertEqual(thresholds, sorted(thresholds))
        self.assertEqual(len(set(thresholds)), len(thresholds))


class TestAchievements(unittest.TestCase):
    def test_nothing_is_earned_by_an_empty_store(self):
        self.assertEqual(game.newly_earned(store_with()), [])

    def test_one_kept_day_earns_the_first(self):
        self.assertIn("first", game.newly_earned(store_with(("Read", [0]))))

    def test_a_week_streak_earns_the_week(self):
        self.assertIn("week", game.newly_earned(store_with(("Read", range(7)))))

    def test_a_short_streak_does_not(self):
        self.assertNotIn("week", game.newly_earned(store_with(("Read", range(3)))))

    def test_five_habits_earn_the_handful(self):
        s = store_with(*[(f"h{i}", [0]) for i in range(5)])
        self.assertIn("handful", game.newly_earned(s))

    def test_four_habits_do_not(self):
        s = store_with(*[(f"h{i}", [0]) for i in range(4)])
        self.assertNotIn("handful", game.newly_earned(s))

    def test_a_clean_sweep_needs_every_habit_on_one_day(self):
        both = store_with(("a", [0]), ("b", [0]))
        self.assertIn("perfect", game.newly_earned(both))
        split = store_with(("a", [0]), ("b", [1]))
        self.assertNotIn("perfect", game.newly_earned(split))

    def test_a_comeback_needs_a_gap_then_a_week(self):
        lapsed = store_with(("Read", [*range(20, 25), *range(7)]))
        self.assertIn("comeback", game.newly_earned(lapsed))

    def test_an_unbroken_run_is_not_a_comeback(self):
        steady = store_with(("Read", range(30)))
        self.assertNotIn("comeback", game.newly_earned(steady))

    def test_already_held_is_not_offered_again(self):
        s = store_with(("Read", [0]))
        self.assertIn("first", game.newly_earned(s))
        s.award("first")
        self.assertNotIn("first", game.newly_earned(s))

    def test_awarding_twice_reports_false(self):
        s = store_with(("Read", [0]))
        self.assertTrue(s.award("first"))
        self.assertFalse(s.award("first"))

    def test_every_key_has_a_test_and_a_description(self):
        """A key with no predicate is unreachable; one with no description is a
        blank tile. Both are silent failures."""
        for key in game.ACHIEVEMENT_KEYS:
            self.assertIn(key, game._TESTS, f"{key} has no predicate")
            name, blurb = game.describe(key)
            self.assertTrue(name and blurb, f"{key} has no description")


class TestPersistence(unittest.TestCase):
    def test_achievements_survive_a_round_trip(self):
        path = Path(tempfile.mkdtemp()) / "habits.json"
        s = Store(path)
        s.create("Read").set_value(TODAY, 1)
        s.award("first")
        s.save()
        again = Store(path)
        again.load()
        self.assertEqual(list(again.achievements), ["first"])

    def test_a_schema_1_file_loads_with_none_earned(self):
        import json

        path = Path(tempfile.mkdtemp()) / "habits.json"
        path.write_text(json.dumps({"schema": 1, "habits": []}), encoding="utf-8")
        s = Store(path)
        s.load()
        self.assertEqual(s.achievements, {})


if __name__ == "__main__":
    unittest.main()
