"""The figure in progress, and how every figure has gone before it.

One JSON file, for the reasons every app here has one. What is stored is the
**jump list**, not the board: a line of small integers replays to exactly one
position, and a file that has been truncated, edited or half-written cannot
describe a board that legal play could not reach, because loading it is playing
it. A bad tail is dropped and the game resumes at the last jump that made sense.

The record is per figure and its headline is **the fewest pegs left**, not a
number of wins. Peg solitaire is a puzzle rather than a contest, and the thing
somebody actually gets better at is finishing with three instead of five. A
win column alone would be a column of zeroes for a week and then a one.

Nothing is recorded for a figure somebody restarts halfway through. Backing up
and trying a different third jump is how this game is played, not a defeat, and
an app that counted it would be counting thinking.
"""

from __future__ import annotations

import json
import os
import time
from pathlib import Path

from .pegs import DEFAULT_FIGURE, FIGURE_KEYS, Game, figure_for

SCHEMA = 1


def data_dir() -> Path:
    """Where the game lives. Overridable, which is what makes the tests and the
    screenshot harness possible without touching a real game."""
    override = os.environ.get("MOARCHY_PEGSOLITAIRE_DIR")
    if override:
        return Path(override)
    base = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return Path(base) / "moarchy-pegsolitaire"


def _int(value, fallback: int) -> int:
    return (
        int(value)
        if isinstance(value, (int, float)) and not isinstance(value, bool)
        else fallback
    )


def _record() -> dict[str, int]:
    # "best" is a minimum, so zero means "none finished yet" rather than a
    # perfect score. A sentinel that has to be remembered in five places is
    # worse than a zero that means nothing has happened.
    return {"played": 0, "best": 0, "solved": 0, "perfect": 0}


class Store:
    """The saved game, the figure it is on, and the record for every figure."""

    def __init__(self, path: Path | str | None = None) -> None:
        self.path = Path(path) if path else data_dir() / "pegsolitaire.json"
        self.figure: str = DEFAULT_FIGURE
        self.moves: list[int] = []
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
            key = game.get("figure")
            self.figure = key if key in FIGURE_KEYS else DEFAULT_FIGURE
            moves = game.get("moves")
            self.moves = (
                [_int(m, -1) for m in moves if not isinstance(m, bool)]
                if isinstance(moves, list)
                else []
            )
            self.finished = bool(game.get("finished"))
            self.recorded = bool(game.get("recorded"))

        stats = data.get("stats")
        if isinstance(stats, dict):
            for key, value in stats.items():
                if key in FIGURE_KEYS and isinstance(value, dict):
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
                "figure": self.figure,
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
        game = Game.resume(self.figure, self.moves)
        self.moves = list(game.moves)
        return game

    def begin(self, figure: str) -> Game:
        self.figure = figure if figure in FIGURE_KEYS else DEFAULT_FIGURE
        self.moves = []
        self.finished = False
        self.recorded = False
        return Game(self.figure)

    def again(self) -> Game:
        """The same figure, from the top."""
        return self.begin(self.figure)

    def remember(self, game: Game, *, finished: bool = False) -> None:
        self.figure = game.figure.key
        self.moves = list(game.moves)
        self.finished = finished

    # --- the record ------------------------------------------------------

    def record(self, left: int, *, perfect: bool = False) -> None:
        """One figure played until it would not move again."""
        if left < 1:
            return
        self.recorded = True
        entry = self.stats.setdefault(self.figure, _record())
        entry["played"] += 1
        if not entry["best"] or left < entry["best"]:
            entry["best"] = left
        if left == 1:
            entry["solved"] += 1
            if perfect:
                entry["perfect"] += 1

    def record_for(self, key: str) -> dict[str, int]:
        return self.stats.get(key) or _record()

    def totals(self) -> dict[str, int]:
        out = _record()
        for entry in self.stats.values():
            out["played"] += entry.get("played", 0)
            out["solved"] += entry.get("solved", 0)
            out["perfect"] += entry.get("perfect", 0)
        # "best" across figures is meaningless -- one peg left on the Cross and
        # one on the whole board are not the same achievement -- so the total is
        # how many figures have been finished at all.
        out["best"] = sum(1 for entry in self.stats.values() if entry.get("solved"))
        return out


def figure_label(key: str) -> str:
    return figure_for(key).label
