"""The game in progress, the clock on it, and the record behind it.

One JSON file, for the reasons every app here has one. What is stored is the
level, a **seed**, and the list of taps -- not the board and not the mines. The
same few lines in `minesweeper.py` put the same mines back from the seed and the
first tap, which makes the file small, makes it impossible for it to describe a
board that could not have been played, and means a person who gets stuck at two
in the morning cannot simply read the answer out of their own home directory.

The clock is the part that is this app's own, and it is the only clock in this
repository. Solitaire refuses one on the grounds that a phone game is one you
are interrupted in the middle of, and a timer that counts through the
interruption is measuring the interruption. That argument is right and
Minesweeper cannot follow it, because a best time is most of what this game's
record has ever been. So the clock is kept and the argument is answered
directly: **it only runs while the window is on screen.** The seconds live here,
accumulated; the window adds to them a second at a time and stops the moment it
stops being the active window.
"""

from __future__ import annotations

import json
import os
import random
import time
from pathlib import Path

from .minesweeper import DEFAULT_LEVEL, LEVEL_KEYS, Game, level_for

SCHEMA = 1

WON = "won"
LOST = "lost"
RESULTS = (WON, LOST)

# A seed is only ever written by this app and only ever read back by it, so its
# range is arbitrary -- this one is wide enough that two games in a row are
# never the same board and narrow enough to read in a file.
SEED_MAX = 2**31 - 1


def data_dir() -> Path:
    """Where the game lives. Overridable, which is what makes the tests and the
    screenshot harness possible without touching a real game."""
    override = os.environ.get("MOARCHY_MINESWEEPER_DIR")
    if override:
        return Path(override)
    base = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return Path(base) / "moarchy-minesweeper"


def _int(value, fallback: int) -> int:
    return (
        int(value)
        if isinstance(value, (int, float)) and not isinstance(value, bool)
        else fallback
    )


def _record() -> dict[str, int]:
    # "best" is a minimum in seconds, so zero means "never won one" rather than
    # an instantaneous victory.
    return {"played": 0, WON: 0, "best": 0, "streak": 0, "longest": 0}


class Store:
    """The saved game, the clock on it, and the record for every level."""

    def __init__(self, path: Path | str | None = None) -> None:
        self.path = Path(path) if path else data_dir() / "minesweeper.json"
        self.level: str = DEFAULT_LEVEL
        self.seed: int = random.randrange(SEED_MAX)
        self.moves: list[int] = []
        self.seconds: int = 0
        self.finished: bool = False
        self.recorded: bool = False
        self.stats: dict[str, dict[str, int]] = {}

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

        game = data.get("game")
        if isinstance(game, dict):
            key = game.get("level")
            self.level = key if key in LEVEL_KEYS else DEFAULT_LEVEL
            self.seed = _int(game.get("seed"), self.seed) % SEED_MAX
            moves = game.get("moves")
            self.moves = (
                [_int(m, -1) for m in moves if not isinstance(m, bool)]
                if isinstance(moves, list)
                else []
            )
            self.seconds = max(_int(game.get("seconds"), 0), 0)
            self.finished = bool(game.get("finished"))
            self.recorded = bool(game.get("recorded"))

        stats = data.get("stats")
        if isinstance(stats, dict):
            for key, value in stats.items():
                if key in LEVEL_KEYS and isinstance(value, dict):
                    entry = _record()
                    for field in entry:
                        entry[field] = max(_int(value.get(field), 0), 0)
                    self.stats[key] = entry

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
            "game": {
                "level": self.level,
                "seed": self.seed,
                "seconds": self.seconds,
                "finished": self.finished,
                "recorded": self.recorded,
                "moves": self.moves,
            },
            "stats": self.stats,
        }
        tmp = self.path.with_suffix(".tmp")
        with tmp.open("w", encoding="utf-8") as fh:
            json.dump(payload, fh, ensure_ascii=False, indent=1)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, self.path)

    # --- the game --------------------------------------------------------

    def game(self) -> Game:
        """Replay what was saved, keeping as much of it as is legal."""
        game = Game.resume(level_for(self.level), self.seed, self.moves)
        self.moves = list(game.moves)
        return game

    def begin(self, level: str, seed: int | None = None) -> Game:
        self.level = level if level in LEVEL_KEYS else DEFAULT_LEVEL
        self.seed = random.randrange(SEED_MAX) if seed is None else seed % SEED_MAX
        self.moves = []
        self.seconds = 0
        self.finished = False
        self.recorded = False
        return Game(level_for(self.level), self.seed)

    def remember(self, game: Game, *, finished: bool = False) -> None:
        self.moves = list(game.moves)
        self.finished = finished

    # --- the record ------------------------------------------------------

    def record(self, result: str, seconds: int = 0) -> None:
        """One finished game at the level it was played at."""
        if result not in RESULTS:
            return
        self.recorded = True
        entry = self.stats.setdefault(self.level, _record())
        entry["played"] += 1
        if result == WON:
            entry[WON] += 1
            entry["streak"] += 1
            entry["longest"] = max(entry["longest"], entry["streak"])
            if seconds and (not entry["best"] or seconds < entry["best"]):
                entry["best"] = seconds
        else:
            entry["streak"] = 0

    def record_for(self, key: str) -> dict[str, int]:
        return self.stats.get(key) or _record()

    def totals(self) -> dict[str, int]:
        out = _record()
        for entry in self.stats.values():
            out["played"] += entry.get("played", 0)
            out[WON] += entry.get(WON, 0)
            out["longest"] = max(out["longest"], entry.get("longest", 0))
        return out


def clock(seconds: int) -> str:
    """Seconds as a clock. Minutes and seconds, and hours only if there are any.

    An hour on a Gentle board means the phone was in a pocket for most of it,
    which the clock is meant to prevent -- but a game left open over a lunch
    break and come back to is an ordinary thing and the display should not
    silently wrap round at sixty minutes.
    """
    seconds = max(int(seconds), 0)
    minutes, rest = divmod(seconds, 60)
    if minutes < 60:
        return f"{minutes}:{rest:02d}"
    hours, minutes = divmod(minutes, 60)
    return f"{hours}:{minutes:02d}:{rest:02d}"
