"""The rules, and mostly the one rule implementations get wrong.

Duplicate letters. The colouring is two passes with the secret's letters being
*consumed* as they are matched, and a single-pass version that asked "is this
letter in the word" would light three Ls when the secret has two -- telling a
player something untrue about a word they are about to spend a guess on.

Half of this file is that, with the examples everybody uses.
"""

import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_fiveletters.fiveletters import (  # noqa: E402
    ABSENT,
    CORRECT,
    PRESENT,
    Game,
    Guess,
    evaluate,
)
from moarchy_fiveletters.words import GUESSES  # noqa: E402

ALLOWED = frozenset(
    {"CRANE", "SLOTH", "ALLOY", "LOYAL", "SPEED", "ERASE", "ABBEY", "EERIE", "GEESE"}
)


class TheColouring(unittest.TestCase):
    def test_an_exact_match_is_correct_and_a_miss_is_absent(self):
        self.assertEqual(evaluate("CRANE", "CRANE"), (CORRECT,) * 5)
        self.assertEqual(evaluate("SLOTH", "BUMPY"), (ABSENT,) * 5)

    def test_a_letter_in_the_wrong_place_is_present(self):
        self.assertEqual(evaluate("ARC", "CAR"), (PRESENT, PRESENT, PRESENT))

    def test_an_anagram_is_five_yellows(self):
        # ALLOY and LOYAL are the same five letters in a different order, so
        # every one of them is present and none is correct.
        self.assertEqual(evaluate("ALLOY", "LOYAL"), (PRESENT,) * 5)

    def test_a_repeated_letter_only_lights_as_often_as_the_secret_has_it(self):
        # SPEED against ERASE: the secret has two Es. The first E of the guess
        # is present, the second is present, and there are none left over.
        self.assertEqual(
            evaluate("SPEED", "ERASE"),
            (PRESENT, ABSENT, PRESENT, PRESENT, ABSENT),
        )

    def test_an_exact_match_consumes_its_letter_first(self):
        # GEESE against EERIE. The third E of the guess sits under the third
        # letter of the secret... it does not, but the fifth does, and the pass
        # that finds it has to take that E out of circulation before the second
        # pass gets to the earlier ones.
        marks = evaluate("GEESE", "EERIE")
        self.assertEqual(marks[4], CORRECT)
        self.assertEqual(sum(1 for mark in marks if mark != ABSENT), 3)

    def test_a_letter_the_secret_has_once_lights_once(self):
        self.assertEqual(
            evaluate("ABBEY", "ABODE"),
            (CORRECT, CORRECT, ABSENT, PRESENT, ABSENT),
        )

    def test_the_marks_are_ordered_so_a_key_never_goes_backwards(self):
        self.assertLess(ABSENT, PRESENT)
        self.assertLess(PRESENT, CORRECT)


class TheGame(unittest.TestCase):
    def test_a_guess_is_taken_and_answered(self):
        game = Game("CRANE", ALLOWED)
        self.assertTrue(game.submit("SLOTH"))
        self.assertEqual(game.used, 1)
        self.assertEqual(game.left, GUESSES - 1)
        self.assertFalse(game.over)

    def test_the_right_word_ends_it(self):
        game = Game("CRANE", ALLOWED)
        game.submit("CRANE")
        self.assertTrue(game.solved)
        self.assertTrue(game.over)
        self.assertFalse(game.out)
        self.assertFalse(game.submit("SLOTH"))

    def test_six_wrong_ones_end_it_too(self):
        game = Game("CRANE", None)
        for _ in range(GUESSES):
            game.submit("SLOTH")
        self.assertTrue(game.out)
        self.assertTrue(game.over)
        self.assertFalse(game.solved)
        self.assertEqual(game.left, 0)

    def test_a_word_that_is_not_on_the_list_is_refused(self):
        game = Game("CRANE", ALLOWED)
        self.assertFalse(game.submit("ZZZZZ"))
        self.assertEqual(game.used, 0)

    def test_a_word_of_the_wrong_length_is_refused(self):
        game = Game("CRANE", None)
        for bad in ("CRAN", "CRANES", "", "CR4NE", "CRAN E"):
            self.assertFalse(game.accepts(bad), bad)

    def test_anything_goes_when_there_is_no_list(self):
        # Which is what the fallback word list amounts to, and what the tests
        # that are about the rules rather than the vocabulary want.
        game = Game("CRANE", None)
        self.assertTrue(game.submit("ZZZZZ"))

    def test_a_game_is_rebuilt_from_its_guesses(self):
        game = Game("CRANE", ALLOWED, ["SLOTH", "ALLOY"])
        self.assertEqual(game.words, ["SLOTH", "ALLOY"])
        again = Game("CRANE", ALLOWED, game.words)
        self.assertEqual(
            [guess.marks for guess in again.guesses],
            [guess.marks for guess in game.guesses],
        )

    def test_a_word_that_will_not_play_ends_the_replay_there(self):
        game = Game("CRANE", ALLOWED, ["SLOTH", "NOPE", "ALLOY"])
        self.assertEqual(game.words, ["SLOTH"])

    def test_the_lowercase_is_taken_and_kept_upper(self):
        game = Game("crane", ALLOWED)
        self.assertEqual(game.secret, "CRANE")
        game.submit("sloth")
        self.assertEqual(game.words, ["SLOTH"])


class TheKeyboard(unittest.TestCase):
    def test_a_letter_never_goes_backwards(self):
        # E is correct in the first guess and misplaced in the second. The key
        # has to stay green, or the keyboard un-learns what the player knows.
        game = Game("ABODE", None, ["ABBEY", "EERIE"])
        self.assertEqual(game.keys()["E"], CORRECT)

    def test_it_only_knows_letters_that_have_been_guessed(self):
        game = Game("CRANE", None, ["SLOTH"])
        self.assertEqual(set(game.keys()), set("SLOTH"))

    def test_what_is_known_reads_as_a_pattern(self):
        game = Game("CRANE", None, ["CRUMB"])
        self.assertEqual(game.known(), "CR___")


class TheRow(unittest.TestCase):
    def test_a_guess_knows_whether_it_was_right(self):
        self.assertTrue(Guess.of("CRANE", "CRANE").right)
        self.assertFalse(Guess.of("CRANE", "SLOTH").right)


if __name__ == "__main__":
    unittest.main()
