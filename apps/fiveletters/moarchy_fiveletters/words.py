"""The two word lists, and which word today is.

A word game is its word list, and this one has two of them for the reason
`data/NOTICE.md` gives at length: the words that may be the *secret* and the
words that may be a *guess* answer two different questions. A five-letter string
in a dictionary is not the same thing as a word somebody would guess, so the
answers are filtered hard and the guesses barely at all -- being told "not in
word list" for a real word is the most annoying thing this kind of game does.

The lists are found rather than imported. An installed copy has them in
/usr/share, a checkout has them next to the app, and a test has them wherever it
put them -- so the search is a short list of places and the first one that has a
file wins. Failing all of those the app still runs, on a handful of words baked
into this file: a word game with no word list is not a degraded word game, it is
a crash on startup, and an app that cannot find its data should say so from
inside a window rather than from a journal nobody reads.

Nothing here imports GTK.
"""

from __future__ import annotations

import os
import re
from datetime import date
from pathlib import Path

LENGTH = 5
GUESSES = 6
ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
WORD = re.compile(f"^[{ALPHABET}]{{{LENGTH}}}$")

# The rows of the keyboard the app draws for itself. QWERTY, because the list is
# English and the letters are the ones on an English keyboard.
KEYBOARD = ("QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM")

# Where the lists live, in the order they are looked for. The installed path
# comes last on purpose: a checkout being run from source should use its own
# copy rather than whichever version happens to be installed on the machine.
SHARE = Path("/usr/share/moarchy-fiveletters")

# The last resort. Twelve words is not a game, and it is not meant to be one --
# it is enough for the window to open, the record to load and the message that
# explains what is missing to be readable.
SPARE = (
    "ABOUT", "ALERT", "BRAVE", "CHAIR", "CRANE", "DREAM",
    "FLINT", "GHOST", "LIGHT", "MONTH", "PLUMB", "STORM",
)  # fmt: skip


def _places() -> list[Path]:
    override = os.environ.get("MOARCHY_FIVELETTERS_WORDS")
    here = Path(__file__).resolve().parent
    return [
        *([Path(override)] if override else []),
        here.parent / "data",
        here / "data",
        SHARE,
    ]


def _clean(words) -> list[str]:
    """Only the well-formed words out of whatever this is."""
    return [
        word.strip().upper()
        for word in words
        if isinstance(word, str) and WORD.match(word.strip().upper())
    ]


def _read(name: str) -> list[str]:
    """Every well-formed word in the first file of this name that exists.

    Filtered on the way in rather than trusted: these files are data, they are
    edited by scripts, and one blank line or one four-letter word in a list of
    twelve thousand would otherwise be a guess that can never be typed or a
    secret that can never be reached.
    """
    for place in _places():
        path = place / name
        try:
            text = path.read_text(encoding="utf-8")
        except OSError:
            continue
        good = _clean(text.splitlines())
        if good:
            return good
    return []


class Words:
    """The lists, loaded once, with the answer for any given day."""

    def __init__(self, answers=None, guesses=None) -> None:
        # `None` means "go and find the files"; a list means "use exactly this,
        # filtered". An empty list is therefore a way to ask for the fallback,
        # which is what the tests want and what the first cut of this got wrong
        # by writing `answers or _read(...)` -- an empty list is falsey, so the
        # test that asked for no words got all of them.
        self.answers: tuple[str, ...] = tuple(
            _clean(answers) if answers is not None else _read("answers.txt")
        )
        allowed = tuple(
            _clean(guesses) if guesses is not None else _read("guesses.txt")
        )
        if not self.answers:
            self.answers = SPARE
        # Every answer has to be a legal guess, whatever the files say. A secret
        # the keyboard will not accept is a game nobody can finish.
        self.guesses: frozenset[str] = frozenset(allowed) | frozenset(self.answers)

    @property
    def complete(self) -> bool:
        """Did the real lists load? The window says so when they did not."""
        return len(self.answers) > len(SPARE)

    def allows(self, word: str) -> bool:
        return word.upper() in self.guesses

    def daily(self, day: date) -> str:
        """The word for a given day.

        A multiply-and-add rather than the day number itself, because the list
        is sorted: `days % len` would walk the alphabet, and a week of secrets
        starting A, A, A, B, B would be the kind of pattern somebody notices on
        the fourth day and never unsees.
        """
        return self.answers[self.index(day)]

    def index(self, day: date) -> int:
        days = day.toordinal()
        return (days * 1103515245 + 12345) % len(self.answers)

    def practice(self, seed: int) -> str:
        return self.answers[seed % len(self.answers)]


def today() -> date:
    """Today, or whatever the screenshot harness has said today is.

    The same hook Keep and Habits have, for the same reason: a picture taken on
    a Sunday and one taken on a Monday would otherwise disagree about which word
    is the day's, for reasons that have nothing to do with the app.
    """
    stamp = os.environ.get("MOARCHY_FIVELETTERS_TODAY")
    if stamp:
        try:
            return date.fromisoformat(stamp)
        except ValueError:
            pass
    return date.today()
