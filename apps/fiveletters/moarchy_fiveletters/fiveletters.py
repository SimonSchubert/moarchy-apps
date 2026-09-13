"""The rules: six guesses, five letters, and the two-pass colouring.

There is one thing in this file that is not obvious, and it is the only thing in
this game that implementations get wrong: **duplicate letters**.

The colouring is two passes. The first marks every letter that is in the right
place and *consumes* that letter from the secret; the second marks a letter
present only while an unconsumed instance of it remains, and absent otherwise.
The consumption is the whole rule. Guess ALLOY against LOYAL and only two of the
three Ls may light up, because the secret has two. A single pass that asked "is
this letter in the word" would light all three and tell the player something
untrue about a word they are about to spend a guess on.

The same logic is in Braincup's `WordleGame.kt`, which is where the word lists
in `data/` come from, and it is written the same way here so that the two stay
wrong in the same places if they are wrong at all.

Nothing here imports GTK.
"""

from __future__ import annotations

from dataclasses import dataclass

from .words import GUESSES, LENGTH, WORD

# What a letter turned out to be. The order is the precedence: a key on the
# keyboard never goes backwards, so a letter known to be CORRECT stays correct
# even when a later guess puts it somewhere it is not.
ABSENT = 0
PRESENT = 1
CORRECT = 2
MARKS = (ABSENT, PRESENT, CORRECT)


def evaluate(guess: str, secret: str) -> tuple[int, ...]:
    """What each letter of `guess` turned out to be, against `secret`."""
    marks = [ABSENT] * len(guess)
    left: dict[str, int] = {}
    for letter in secret:
        left[letter] = left.get(letter, 0) + 1

    for index, letter in enumerate(guess):
        if index < len(secret) and letter == secret[index]:
            marks[index] = CORRECT
            left[letter] -= 1
    for index, letter in enumerate(guess):
        if marks[index] == CORRECT:
            continue
        if left.get(letter, 0) > 0:
            marks[index] = PRESENT
            left[letter] -= 1
    return tuple(marks)


@dataclass(frozen=True)
class Guess:
    """One row of the board: the word and what each of its letters turned out
    to be. Frozen, because a row that has been submitted never changes again."""

    word: str
    marks: tuple[int, ...]

    @classmethod
    def of(cls, word: str, secret: str) -> Guess:
        return cls(word, evaluate(word, secret))

    @property
    def right(self) -> bool:
        return all(mark == CORRECT for mark in self.marks)


class Game:
    """One secret and the guesses made at it.

    The guesses are the state, and the board is derived from them -- the same
    shape every other game in this repository has, and here it costs five
    comparisons a row. A file that has been truncated or edited cannot describe
    a board that play could not reach, because loading it is playing it: a word
    that is not five letters, or that is not in the guess list, is where the
    file stops being a game.
    """

    def __init__(self, secret: str, allowed=None, words=()) -> None:
        self.secret = secret.upper()
        self.allowed = allowed
        self.guesses: list[Guess] = []
        for word in words:
            if not self.submit(word):
                break

    # --- playing -----------------------------------------------------------

    def accepts(self, word: str) -> bool:
        """Is this a word this game will take? Length first, then the list."""
        word = word.upper()
        if not WORD.match(word):
            return False
        if self.allowed is None:
            return True
        return word in self.allowed

    def submit(self, word: str) -> bool:
        if self.over or not self.accepts(word):
            return False
        self.guesses.append(Guess.of(word.upper(), self.secret))
        return True

    @property
    def solved(self) -> bool:
        return bool(self.guesses) and self.guesses[-1].right

    @property
    def out(self) -> bool:
        return len(self.guesses) >= GUESSES and not self.solved

    @property
    def over(self) -> bool:
        return self.solved or self.out

    @property
    def used(self) -> int:
        return len(self.guesses)

    @property
    def left(self) -> int:
        return max(GUESSES - len(self.guesses), 0)

    @property
    def words(self) -> list[str]:
        return [guess.word for guess in self.guesses]

    # --- what the keyboard shows -------------------------------------------

    def keys(self) -> dict[str, int]:
        """The best thing known about each letter, for colouring the keyboard.

        Best, not latest. A letter shown correct in one guess and absent in the
        next -- which happens the moment somebody puts a known letter in the
        wrong place -- must stay correct, or the keyboard un-learns things the
        player already knows.
        """
        out: dict[str, int] = {}
        for guess in self.guesses:
            for letter, mark in zip(guess.word, guess.marks, strict=False):
                if mark > out.get(letter, -1):
                    out[letter] = mark
        return out

    def known(self) -> str:
        """The letters placed so far, as a pattern like `C R _ N _`.

        Not shown anywhere in the app -- it is what the tests use to say what a
        board looks like without spelling out thirty tiles.
        """
        placed = ["_"] * LENGTH
        for guess in self.guesses:
            for index, mark in enumerate(guess.marks):
                if mark == CORRECT:
                    placed[index] = guess.word[index]
        return "".join(placed)
