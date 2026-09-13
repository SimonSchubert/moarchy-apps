"""The file: what is written, what is read back, and what a bad one does.

Two cases here are this app's own. **The day turning over**, because a phone
left open overnight comes back to yesterday's board and yesterday's board with
today's word on it is a board claiming three letters are green and meaning
nothing by it. And **the streak**, which is a statement about days rather than
about games: the day you skip ends it as surely as the day you miss.
"""

import json
import sys
import tempfile
import unittest
from datetime import date, timedelta
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_fiveletters.fiveletters import Game  # noqa: E402
from moarchy_fiveletters.store import DAILY, PRACTICE, Store, share  # noqa: E402
from moarchy_fiveletters.words import GUESSES, Words  # noqa: E402

WORDS = Words()
DAY = date(2026, 9, 12)


def fresh() -> Store:
    return Store(Path(tempfile.mkdtemp()) / "fiveletters.json")


def solved(store: Store, day: date) -> Game:
    """A day finished on the second guess."""
    game = store.game(WORDS, day)
    game.submit("CRANE" if game.secret != "CRANE" else "SLOTH")
    game.submit(game.secret)
    store.remember(game)
    return game


class TestDefaults(unittest.TestCase):
    def test_a_missing_file_is_a_fresh_day_and_not_an_error(self):
        store = fresh()
        store.load()
        self.assertEqual(store.mode, DAILY)
        self.assertEqual(store.daily, [])
        self.assertEqual(store.stats["played"], 0)

    def test_the_game_it_hands_back_is_the_day_it_was_asked_for(self):
        store = fresh()
        game = store.game(WORDS, DAY)
        self.assertEqual(game.secret, WORDS.daily(DAY))
        self.assertEqual(store.day, DAY.isoformat())


class TestTheDayTurningOver(unittest.TestCase):
    def test_yesterdays_board_is_not_shown_against_todays_word(self):
        store = fresh()
        game = store.game(WORDS, DAY)
        game.submit("CRANE")
        store.remember(game)
        self.assertEqual(len(store.daily), 1)

        tomorrow = store.game(WORDS, DAY + timedelta(days=1))
        self.assertEqual(store.daily, [])
        self.assertEqual(tomorrow.used, 0)
        self.assertEqual(tomorrow.secret, WORDS.daily(DAY + timedelta(days=1)))

    def test_the_same_day_keeps_its_guesses(self):
        store = fresh()
        game = store.game(WORDS, DAY)
        game.submit("CRANE")
        store.remember(game)
        again = store.game(WORDS, DAY)
        self.assertEqual(again.words, ["CRANE"])

    def test_roll_over_says_whether_it_happened(self):
        store = fresh()
        self.assertTrue(store.roll_over(DAY))
        self.assertFalse(store.roll_over(DAY))
        self.assertTrue(store.roll_over(DAY + timedelta(days=1)))


class TestRoundTrip(unittest.TestCase):
    def test_everything_written_comes_back(self):
        store = fresh()
        game = solved(store, DAY)
        store.record(game, DAY)
        store.save()

        back = Store(store.path)
        back.load()
        self.assertEqual(back.day, DAY.isoformat())
        self.assertEqual(back.daily, game.words)
        self.assertEqual(back.stats["won"], 1)
        self.assertEqual(back.stats["spread"][1], 1)
        self.assertEqual(back.game(WORDS, DAY).words, game.words)

    def test_the_secret_is_not_in_the_file(self):
        # Neither secret is stored: the day's word is a function of the date and
        # a practice word is a function of a seed. A five-letter word sitting in
        # a text file is a great deal easier to read than a minefield.
        store = fresh()
        solved(store, DAY)
        store.save()
        text = store.path.read_text(encoding="utf-8")
        practice = store.begin_practice(WORDS, seed=7)
        self.assertNotIn(WORDS.daily(DAY), json.loads(text)["daily"]["guesses"][:1])
        store.save()
        self.assertNotIn(
            practice.secret, json.loads(store.path.read_text())["practice"]["guesses"]
        )

    def test_a_practice_word_comes_back_from_its_seed(self):
        store = fresh()
        game = store.begin_practice(WORDS, seed=4242)
        game.submit("CRANE")
        store.remember(game)
        store.save()
        back = Store(store.path)
        back.load()
        self.assertEqual(back.mode, PRACTICE)
        self.assertEqual(back.game(WORDS, DAY).secret, game.secret)

    def test_a_save_leaves_no_temporary_file_behind(self):
        store = fresh()
        store.save()
        self.assertEqual(
            [p.name for p in store.path.parent.iterdir()], [store.path.name]
        )


class TestABadFile(unittest.TestCase):
    def test_nonsense_is_moved_aside_rather_than_overwritten(self):
        store = fresh()
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text("{not json", encoding="utf-8")
        store.load()
        self.assertEqual(len(list(store.path.parent.glob("*.broken-*.json"))), 1)

    def test_junk_in_the_fields_falls_back_rather_than_raising(self):
        store = fresh()
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text(
            json.dumps(
                {
                    "mode": "telepathy",
                    "daily": {"day": 7, "guesses": ["CRANE", "NO", 5, None]},
                    "practice": {"seed": "cheese"},
                    "stats": {"played": "many", "spread": "none"},
                }
            ),
            encoding="utf-8",
        )
        store.load()
        self.assertEqual(store.mode, DAILY)
        self.assertEqual(store.day, "")
        self.assertEqual(store.daily, ["CRANE"])
        self.assertEqual(store.stats["played"], 0)
        self.assertEqual(store.stats["spread"], [0] * GUESSES)

    def test_more_guesses_than_the_game_allows_are_cut_off(self):
        store = fresh()
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text(
            json.dumps({"daily": {"guesses": ["CRANE"] * 20}}), encoding="utf-8"
        )
        store.load()
        self.assertEqual(len(store.daily), GUESSES)

    def test_a_file_that_is_not_an_object_is_ignored(self):
        store = fresh()
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text("[1, 2, 3]", encoding="utf-8")
        store.load()
        self.assertEqual(store.daily, [])


class TestTheStreak(unittest.TestCase):
    def test_days_in_a_row_build_it(self):
        store = fresh()
        for step in range(4):
            day = DAY + timedelta(days=step)
            store.record(solved(store, day), day)
        self.assertEqual(store.stats["streak"], 4)
        self.assertEqual(store.stats["best"], 4)
        self.assertEqual(store.stats["played"], 4)

    def test_a_day_skipped_ends_it(self):
        store = fresh()
        for step in (0, 1):
            day = DAY + timedelta(days=step)
            store.record(solved(store, day), day)
        self.assertEqual(store.stats["streak"], 2)
        later = DAY + timedelta(days=5)
        store.record(solved(store, later), later)
        self.assertEqual(store.stats["streak"], 1)
        self.assertEqual(store.stats["best"], 2)

    def test_a_day_missed_ends_it_too(self):
        store = fresh()
        store.record(solved(store, DAY), DAY)
        lost = DAY + timedelta(days=1)
        game = store.game(WORDS, lost)
        for _ in range(GUESSES):
            game.submit("CRANE" if game.secret != "CRANE" else "SLOTH")
        store.record(game, lost)
        self.assertEqual(store.stats["streak"], 0)
        self.assertEqual(store.stats["played"], 2)
        self.assertEqual(store.stats["won"], 1)

    def test_a_day_is_only_counted_once(self):
        store = fresh()
        game = solved(store, DAY)
        store.record(game, DAY)
        store.record(game, DAY)
        self.assertEqual(store.stats["played"], 1)
        self.assertTrue(store.counted(DAY))

    def test_practice_is_not_counted_at_all(self):
        store = fresh()
        game = store.begin_practice(WORDS, seed=1)
        game.submit(game.secret)
        store.record(game, DAY)
        self.assertEqual(store.stats["played"], 0)

    def test_an_unfinished_day_is_not_counted(self):
        store = fresh()
        game = store.game(WORDS, DAY)
        game.submit("CRANE" if game.secret != "CRANE" else "SLOTH")
        store.record(game, DAY)
        self.assertEqual(store.stats["played"], 0)

    def test_the_rate_is_a_percentage_and_not_a_crash(self):
        store = fresh()
        self.assertEqual(store.rate(), 0)
        store.record(solved(store, DAY), DAY)
        self.assertEqual(store.rate(), 100)


class TestTheShare(unittest.TestCase):
    def test_it_is_squares_and_a_score_and_nothing_else(self):
        store = fresh()
        game = solved(store, DAY)
        text = share(game, DAY, 51)
        self.assertIn("2/6", text)
        self.assertIn("🟩🟩🟩🟩🟩", text)
        # Spoiler-free by construction: no letter of the answer appears in it.
        for letter in set(game.secret):
            self.assertNotIn(letter, text)

    def test_an_unsolved_day_scores_an_x(self):
        store = fresh()
        game = store.game(WORDS, DAY)
        for _ in range(GUESSES):
            game.submit("CRANE" if game.secret != "CRANE" else "SLOTH")
        self.assertIn("X/6", share(game, DAY, 51))


if __name__ == "__main__":
    unittest.main()
