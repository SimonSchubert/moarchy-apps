"""The game in progress, and what has been played before it.

One JSON file, for the reasons Keep and Habits have one: a person plays a few
hundred games, not a million, and a file can be read by anything, diffed, synced
with rsync and repaired by hand on a device with no keyboard.

What is stored is the *move list*, not the board. Sixty small integers replay to
exactly one position in microseconds, and that has a property a stored board
cannot have: a file that has been truncated, edited or half-written cannot
describe a board that legal play could not reach, because loading it is playing
it. A bad tail is dropped and the game resumes at the last move that made sense.

Saving happens on every move rather than on a timer. Habits debounces because a
thumb can tick five marks in a row and each one is one fsync; a move here is
seconds of thinking apart at the very least, and on a phone the app is not
usually closed -- it is killed, backgrounded, by a compositor reclaiming memory
while somebody reads a message. A game that loses its last move to that is a
game nobody finishes.
"""

from __future__ import annotations

import json
import os
import time
from pathlib import Path

from .ai import DEFAULT_LEVEL, LEVEL_KEYS
from .mill import BLACK, WHITE, Game

SCHEMA = 1

# Who the other player is. Against the computer there is a "you", so a result is
# a win or a loss; across a table there is not, and nothing is recorded.
SOLO = "solo"
HOTSEAT = "hotseat"
MODES = (SOLO, HOTSEAT)

WON = "won"
LOST = "lost"
DRAWN = "drawn"
RESULTS = (WON, LOST, DRAWN)


def data_dir() -> Path:
    """Where the game lives. Overridable, which is what makes the tests and the
    screenshot harness possible without touching a real game."""
    override = os.environ.get("MOARCHY_MILL_DIR")
    if override:
        return Path(override)
    base = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return Path(base) / "moarchy-mill"


def _int(value, fallback: int) -> int:
    return (
        int(value)
        if isinstance(value, (int, float)) and not isinstance(value, bool)
        else fallback
    )


def _record() -> dict[str, int]:
    return {"played": 0, WON: 0, LOST: 0, DRAWN: 0, "best": 0}


class Store:
    """The saved game, the settings it was started with, and the tally."""

    def __init__(self, path: Path | str | None = None) -> None:
        self.path = Path(path) if path else data_dir() / "mill.json"
        self.moves: list[int] = []
        self.mode: str = SOLO
        self.level: str = DEFAULT_LEVEL
        self.human: int = WHITE
        self.finished: bool = False
        # Whether the result of a finished game has already gone into the
        # record. Deliberately not the same flag as `finished`: the move that
        # ends a game is written the instant it is played and counted a moment
        # later, when the piece has finished sliding, so a phone killed between
        # the two comes back to a decided board with a result still owed to it.
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
            moves = game.get("moves")
            self.moves = (
                [_int(m, 0) for m in moves if not isinstance(m, bool)]
                if isinstance(moves, list)
                else []
            )
            self.mode = game.get("mode") if game.get("mode") in MODES else SOLO
            self.level = (
                game.get("level") if game.get("level") in LEVEL_KEYS else DEFAULT_LEVEL
            )
            self.human = BLACK if game.get("human") == "black" else WHITE
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
                "mode": self.mode,
                "level": self.level,
                "human": "white" if self.human == WHITE else "black",
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
        """Replay what was saved, keeping as much of it as is legal.

        A move that will not play is where the file stops being a game, so the
        rest of it goes -- see Game.resume, which is where that happens.
        """
        game = Game.resume(self.moves)
        self.moves = list(game.moves)
        return game

    def begin(self, *, mode: str, level: str, human: int) -> Game:
        self.mode = mode if mode in MODES else SOLO
        self.level = level if level in LEVEL_KEYS else DEFAULT_LEVEL
        self.human = human if human in (WHITE, BLACK) else WHITE
        self.moves = []
        self.finished = False
        self.recorded = False
        return Game()

    def remember(self, game: Game, *, finished: bool = False) -> None:
        self.moves = list(game.moves)
        self.finished = finished

    # --- the tally -------------------------------------------------------

    def record(self, result: str, margin: int = 0) -> None:
        """Add one finished game against the computer to the level's record.

        Hotseat games are not recorded at all: the tally answers "how am I doing
        against Medium", and two people passing a phone across a table have no
        answer to put in it.

        `margin` is how many pieces the winner had left, which is this game's
        version of a score. Winning with eight men on the board and winning with
        three are the same result and very different games.
        """
        if self.mode != SOLO or result not in RESULTS:
            return
        self.recorded = True
        entry = self.stats.setdefault(self.level, _record())
        entry["played"] += 1
        entry[result] += 1
        if result == WON:
            entry["best"] = max(entry["best"], margin)

    def record_for(self, key: str) -> dict[str, int]:
        return self.stats.get(key) or _record()

    def totals(self) -> dict[str, int]:
        out = _record()
        for entry in self.stats.values():
            for field in ("played", WON, LOST, DRAWN):
                out[field] += entry.get(field, 0)
            out["best"] = max(out["best"], entry.get("best", 0))
        return out
