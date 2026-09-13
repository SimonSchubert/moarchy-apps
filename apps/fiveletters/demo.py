#!/usr/bin/python3
"""Fill a data directory with a game worth photographing.

An untouched board is thirty empty squares and says nothing about the app: no
colours, no marks, no keyboard states. So this plays a real one -- guesses a
person would actually make, against the word the app would actually set for the
day the screenshot harness pins.

Playing it rather than colouring tiles matters for one reason: the tiles in the
picture then say what the rules say. A hand-coloured board is the app telling a
lie about its own two-pass matching, and duplicate letters are exactly where
somebody who knows the game will look.

    demo.py          four guesses in, with the fifth half typed
    demo.py solved   the same word, got on the fifth

The record is invented and says so.
"""

from __future__ import annotations

import os
import sys
from datetime import date
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_fiveletters.fiveletters import CORRECT, PRESENT, Game  # noqa: E402
from moarchy_fiveletters.store import DAILY, Store  # noqa: E402
from moarchy_fiveletters.words import GUESSES, Words, today  # noqa: E402

# Openers a real player uses: common letters, no repeats, spread across the
# alphabet. The rest of the guesses are chosen against what those turn up.
OPENERS = ("CRANE", "SLOTH", "PUDGY", "BEFIT", "WHOMP", "GAMUT", "VIXEN")

# A plausible record: a hundred-odd days, most of them solved, most of those in
# four. The shape of somebody who plays every morning and is quite good at it.
SPREAD = [1, 9, 31, 44, 22, 7]
STATS = {
    "played": 121,
    "won": sum(SPREAD),
    "streak": 12,
    "best": 34,
    "spread": SPREAD,
}


def _plays(words: Words, secret: str, stop_at: int) -> Game:
    """Guesses that narrow the word down, the way a person narrows it down.

    Not a solver: it takes the openers in order, keeps any that are still
    possible given everything seen so far, and stops when it has made enough
    guesses. What it produces is a board with greens, ambers and greys on it in
    the places the rules put them.
    """
    game = Game(secret, words.guesses)
    for opener in OPENERS:
        if game.used >= stop_at or game.over:
            break
        if game.accepts(opener):
            game.submit(opener)
    while game.used < stop_at and not game.over:
        for word in words.answers:
            if _fits(word, game) and word not in game.words:
                game.submit(word)
                break
        else:
            break
    return game


def _fits(word: str, game: Game) -> bool:
    """Is this word still possible, given every guess made so far?"""
    for guess in game.guesses:
        for index, mark in enumerate(guess.marks):
            letter = guess.word[index]
            if mark == CORRECT and word[index] != letter:
                return False
            if mark == PRESENT and (letter not in word or word[index] == letter):
                return False
            if mark not in (CORRECT, PRESENT) and letter in word:
                return False
    return True


def main() -> int:
    target = os.environ.get("MOARCHY_FIVELETTERS_DIR")
    if not target:
        print(
            "set MOARCHY_FIVELETTERS_DIR first -- refusing to touch a real game",
            file=sys.stderr,
        )
        return 2

    stage = sys.argv[1] if len(sys.argv) > 1 else "board"
    words = Words()
    day = today()
    secret = words.daily(day)
    game = _plays(words, secret, GUESSES if stage == "solved" else 4)

    store = Store(Path(target) / "fiveletters.json")
    store.mode = DAILY
    store.day = day.isoformat()
    store.daily = game.words
    store.stats.update(STATS)
    # The invented record stops the day before the one on screen, so that the
    # board in the picture is a day that has not been counted yet -- which is
    # what an unfinished board is, and what a just-finished one has to be for
    # the app to count it while somebody is watching.
    store.stats["last"] = date.fromordinal(day.toordinal() - 1).isoformat()
    store.save()

    print(
        f"wrote {game.used} guesses at {secret} "
        f"({'solved' if game.solved else 'in progress'}) to {store.path}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
