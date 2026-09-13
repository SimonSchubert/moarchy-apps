"""The word lists, checked as word lists.

This is the test that runs in the build chroot, and it is the one that matters
for a word game: the lists are data, they were produced by a script in another
repository, and one blank line or one four-letter word among thirteen thousand
is a guess nobody can type or a secret nobody can reach. Nothing about that is
visible from reading the code.
"""

import sys
import unittest
from datetime import date, timedelta
from itertools import pairwise
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_fiveletters.words import (  # noqa: E402
    ALPHABET,
    GUESSES,
    KEYBOARD,
    LENGTH,
    SPARE,
    WORD,
    Words,
    today,
)

WORDS = Words()


class TheLists(unittest.TestCase):
    def test_they_are_actually_there(self):
        # A checkout has them in data/. If this fails the app still runs, on a
        # dozen built-in words -- but it is not the app anybody wanted.
        self.assertTrue(WORDS.complete, "the word lists did not load")
        self.assertGreater(len(WORDS.answers), 500)
        self.assertGreater(len(WORDS.guesses), 5000)

    def test_every_word_is_five_letters_of_the_alphabet(self):
        for word in WORDS.answers:
            self.assertTrue(WORD.match(word), word)
        for word in WORDS.guesses:
            self.assertTrue(WORD.match(word), word)

    def test_every_answer_is_a_word_the_keyboard_will_accept(self):
        # A secret that is not in the guess list is a game that cannot be won by
        # typing it, which is the one bug in this arrangement that would take a
        # person six guesses to discover.
        for word in WORDS.answers:
            self.assertIn(word, WORDS.guesses, word)

    def test_the_answers_are_a_smaller_and_different_list(self):
        # Two lists rather than one, because they answer two questions: what may
        # be the secret, and what may be typed at it.
        self.assertLess(len(WORDS.answers), len(WORDS.guesses) // 4)

    def test_there_are_no_duplicates_among_the_answers(self):
        self.assertEqual(len(set(WORDS.answers)), len(WORDS.answers))

    def test_the_keyboard_has_every_letter_once(self):
        letters = "".join(KEYBOARD)
        self.assertEqual(sorted(letters), sorted(ALPHABET))
        self.assertEqual(len(set(letters)), len(ALPHABET))


class TheDay(unittest.TestCase):
    def test_the_same_day_is_the_same_word(self):
        day = date(2026, 9, 12)
        self.assertEqual(WORDS.daily(day), WORDS.daily(day))

    def test_consecutive_days_do_not_walk_the_alphabet(self):
        # The list is sorted, so `days % len` would give a week of secrets
        # beginning A, A, A, B, B -- a pattern somebody notices on the fourth
        # day and never unsees. Tested on the index rather than on the letter,
        # because the index is what the mixing is for: two days running must
        # land a long way apart in the list.
        start = date(2026, 1, 1)
        indices = [WORDS.index(start + timedelta(days=step)) for step in range(60)]
        steps = [abs(b - a) for a, b in pairwise(indices)]
        self.assertGreater(min(steps), len(WORDS.answers) // 30, sorted(steps)[:3])
        self.assertEqual(len(set(indices)), len(indices))

    def test_every_day_of_a_year_has_a_word(self):
        start = date(2026, 1, 1)
        for step in range(366):
            word = WORDS.daily(start + timedelta(days=step))
            self.assertIn(word, WORDS.answers)

    def test_the_harness_can_pin_today(self):
        import os

        os.environ["MOARCHY_FIVELETTERS_TODAY"] = "2026-09-12"
        try:
            self.assertEqual(today(), date(2026, 9, 12))
            os.environ["MOARCHY_FIVELETTERS_TODAY"] = "not a date"
            self.assertEqual(today(), date.today())
        finally:
            del os.environ["MOARCHY_FIVELETTERS_TODAY"]


class WithoutTheLists(unittest.TestCase):
    """The app has to open even when its data is missing."""

    def test_it_falls_back_to_a_handful_of_words(self):
        words = Words(answers=[], guesses=[])
        self.assertFalse(words.complete)
        self.assertEqual(set(words.answers), set(SPARE))
        self.assertTrue(words.allows("CRANE"))

    def test_a_short_or_odd_word_never_gets_in(self):
        words = Words(answers=["CRANE", "OK", "", "SÉANCE", "toast"], guesses=[])
        # Filtered wherever it came from: a file, or a caller. "toast" comes
        # back as TOAST because case is the app's business; the rest are not
        # five letters of the alphabet and are simply gone.
        self.assertEqual(set(words.answers), {"CRANE", "TOAST"})
        self.assertTrue(words.allows("crane"))
        self.assertFalse(words.allows("SÉANCE"))

    def test_the_shape_of_the_game_is_five_and_six(self):
        self.assertEqual(LENGTH, 5)
        self.assertEqual(GUESSES, 6)


if __name__ == "__main__":
    unittest.main()
