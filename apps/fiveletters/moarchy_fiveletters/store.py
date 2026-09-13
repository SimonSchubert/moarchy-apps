"""The two games in progress, and the record behind them.

One JSON file. What is stored is **the guesses**, not the board: five words
replay to exactly one board, and a file that has been truncated, edited or
half-written cannot describe a board that play could not reach, because loading
it is playing it -- a word that is not five letters, or is not in the guess
list, is where the file stops being a game.

Neither secret is in the file. The day's word is a function of the date, and a
practice word is a function of a seed, so both come back from four bytes and
neither is sitting in a text file in somebody's home directory waiting to be
read at two in the morning. It is the same argument Minesweeper's seed makes,
and it is a stronger one here: a minefield is hard to read off a list of taps,
and a five-letter word is not hard to read off anything.

The record is the one thing in this app that has to survive a change of day, and
the rule is the one everybody expects: **a streak is consecutive days solved,
and the day you skip is the day it ends** -- not the day you fail, which also
ends it, but the day you simply do not play. That is why `last` is stored as a
date rather than as a counter.
"""

from __future__ import annotations

import json
import os
import random
import time
from datetime import date, timedelta
from pathlib import Path

from .fiveletters import Game
from .words import GUESSES, WORD, Words, today

SCHEMA = 1

DAILY = "daily"
PRACTICE = "practice"
MODES = (DAILY, PRACTICE)

SEED_MAX = 2**31 - 1


def data_dir() -> Path:
    """Where the game lives. Overridable, which is what makes the tests and the
    screenshot harness possible without touching a real game."""
    override = os.environ.get("MOARCHY_FIVELETTERS_DIR")
    if override:
        return Path(override)
    base = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return Path(base) / "moarchy-fiveletters"


def _int(value, fallback: int) -> int:
    return (
        int(value)
        if isinstance(value, (int, float)) and not isinstance(value, bool)
        else fallback
    )


def _words(value) -> list[str]:
    if not isinstance(value, list):
        return []
    out = []
    for item in value:
        if isinstance(item, str) and WORD.match(item.strip().upper()):
            out.append(item.strip().upper())
    return out[:GUESSES]


def _record() -> dict:
    return {
        "played": 0,
        "won": 0,
        "streak": 0,
        "best": 0,
        # How many days were solved in one guess, two, three... six. The bar
        # chart everybody knows, and the only statistic in this app that says
        # anything about how somebody plays rather than how often.
        "spread": [0] * GUESSES,
        "last": "",
    }


class Store:
    """The daily game, the practice game, and the record."""

    def __init__(self, path: Path | str | None = None) -> None:
        self.path = Path(path) if path else data_dir() / "fiveletters.json"
        self.mode: str = DAILY
        self.day: str = ""
        self.daily: list[str] = []
        self.seed: int = random.randrange(SEED_MAX)
        self.practice: list[str] = []
        self.stats: dict = _record()

    # --- file ------------------------------------------------------------

    def load(self) -> None:
        try:
            raw = self.path.read_text(encoding="utf-8")
        except OSError:
            return
        try:
            data = json.loads(raw)
        except ValueError:
            # Moved aside rather than overwritten: the next save would otherwise
            # destroy whatever the person actually had.
            self._rescue()
            return
        if not isinstance(data, dict):
            return

        self.mode = data.get("mode") if data.get("mode") in MODES else DAILY
        game = data.get("daily")
        if isinstance(game, dict):
            self.day = game.get("day") if isinstance(game.get("day"), str) else ""
            self.daily = _words(game.get("guesses"))
        game = data.get("practice")
        if isinstance(game, dict):
            self.seed = _int(game.get("seed"), self.seed) % SEED_MAX
            self.practice = _words(game.get("guesses"))

        stats = data.get("stats")
        if isinstance(stats, dict):
            entry = _record()
            for field in ("played", "won", "streak", "best"):
                entry[field] = max(_int(stats.get(field), 0), 0)
            spread = stats.get("spread")
            if isinstance(spread, list):
                entry["spread"] = [
                    max(_int(value, 0), 0) for value in spread[:GUESSES]
                ] + [0] * max(GUESSES - len(spread), 0)
            last = stats.get("last")
            entry["last"] = last if isinstance(last, str) else ""
            self.stats = entry

    def _rescue(self) -> Path | None:
        spare = self.path.with_suffix(f".broken-{int(time.time())}.json")
        try:
            self.path.rename(spare)
            return spare
        except OSError:
            return None

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "schema": SCHEMA,
            "mode": self.mode,
            "daily": {"day": self.day, "guesses": self.daily},
            "practice": {"seed": self.seed, "guesses": self.practice},
            "stats": self.stats,
        }
        tmp = self.path.with_suffix(".tmp")
        with tmp.open("w", encoding="utf-8") as fh:
            json.dump(payload, fh, ensure_ascii=False, indent=1)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, self.path)

    # --- the games -------------------------------------------------------

    def roll_over(self, day: date) -> bool:
        """Has the day changed under the saved game? Clears it if so.

        A phone left open overnight comes back to yesterday's board, and
        yesterday's board with today's word on it would be a game that says
        three letters are green and means nothing by it.
        """
        stamp = day.isoformat()
        if self.day == stamp:
            return False
        self.day = stamp
        self.daily = []
        return True

    def game(self, words: Words, day: date | None = None) -> Game:
        """The game the app is currently showing, replayed from its guesses."""
        day = day or today()
        self.roll_over(day)
        if self.mode == PRACTICE:
            game = Game(words.practice(self.seed), words.guesses, self.practice)
            self.practice = game.words
            return game
        game = Game(words.daily(day), words.guesses, self.daily)
        self.daily = game.words
        return game

    def remember(self, game: Game) -> None:
        if self.mode == PRACTICE:
            self.practice = game.words
        else:
            self.daily = game.words

    def begin_practice(self, words: Words, seed: int | None = None) -> Game:
        self.mode = PRACTICE
        self.seed = random.randrange(SEED_MAX) if seed is None else seed % SEED_MAX
        self.practice = []
        return Game(words.practice(self.seed), words.guesses)

    def show_daily(self, words: Words, day: date | None = None) -> Game:
        self.mode = DAILY
        return self.game(words, day)

    # --- the record ------------------------------------------------------

    def record(self, game: Game, day: date) -> None:
        """One finished day. Practice is not recorded at all.

        Practice exists so that somebody who has done today's word has something
        to play, and counting it would turn a streak -- which is a statement
        about days -- into a statement about how many goes they had.
        """
        if self.mode != DAILY or not game.over:
            return
        stamp = day.isoformat()
        if self.stats.get("last") == stamp:
            return  # already counted today
        broken = self._broken(stamp)
        self.stats["played"] += 1
        self.stats["last"] = stamp
        if game.solved:
            self.stats["won"] += 1
            self.stats["spread"][game.used - 1] += 1
            self.stats["streak"] = 1 if broken else self.stats["streak"] + 1
            self.stats["best"] = max(self.stats["best"], self.stats["streak"])
        else:
            self.stats["streak"] = 0

    def _broken(self, stamp: str) -> bool:
        """Was there a gap between the last day counted and this one?"""
        last = self.stats.get("last") or ""
        if not last:
            return True
        try:
            return date.fromisoformat(stamp) - date.fromisoformat(last) > timedelta(
                days=1
            )
        except ValueError:
            return True

    def counted(self, day: date) -> bool:
        return self.stats.get("last") == day.isoformat()

    def rate(self) -> int:
        played = self.stats.get("played", 0)
        return round(100 * self.stats.get("won", 0) / played) if played else 0


def share(game: Game, day: date, number: int) -> str:
    """The board as squares, which is the one thing this game is famous for.

    Not posted anywhere -- there is no network code in this app -- but put on
    the clipboard, because that is where it is wanted and because a row of
    coloured squares is the only spoiler-free way anybody has found to say how
    a word went.
    """
    marks = {0: "⬛", 1: "🟨", 2: "🟩"}
    score = str(game.used) if game.solved else "X"
    lines = [f"Five Letters {number} {score}/{GUESSES}", ""]
    lines.extend("".join(marks[mark] for mark in guess.marks) for guess in game.guesses)
    return "\n".join(lines) + "\n"
