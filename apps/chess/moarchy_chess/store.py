"""The game in progress, and what has been played before it.

One JSON file, for the reasons Keep and Habits have one: a person plays a few
hundred games, not a million, and a file can be read by anything, diffed, synced
with rsync and repaired by hand on a device with no keyboard.

What is stored is the *move list*, not the board, and the moves are written the
way people write them:

    "moves": ["e2e4", "e7e5", "g1f3", "b8c6"]

That is the same argument Reversi's file makes and one more besides. The same
argument: a file that has been truncated, edited or half-written cannot describe
a board that legal play could not reach, because loading it is playing it, and a
move that will not play is where the file stops being a game. The one more is
that chess has a written form and Reversi does not -- anybody can read that
line, and a saved game that can be pasted into any other chess program is worth
more than four bytes saved per move.

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
from .chess import BLACK, WHITE, Game, parse_uci

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
    override = os.environ.get("MOARCHY_CHESS_DIR")
    if override:
        return Path(override)
    base = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return Path(base) / "moarchy-chess"


def _int(value, fallback: int) -> int:
    return (
        int(value)
        if isinstance(value, (int, float)) and not isinstance(value, bool)
        else fallback
    )


def _record() -> dict[str, int]:
    return {"played": 0, WON: 0, LOST: 0, DRAWN: 0, "quickest": 0}


class Store:
    """The saved game, the settings it was started with, and the tally."""

    def __init__(self, path: Path | str | None = None) -> None:
        self.path = Path(path) if path else data_dir() / "chess.json"
        self.moves: list[str] = []
        self.mode: str = SOLO
        self.level: str = DEFAULT_LEVEL
        self.human: int = WHITE
        self.finished: bool = False
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
                [m for m in moves if isinstance(m, str)]
                if isinstance(moves, list)
                else []
            )
            self.mode = game.get("mode") if game.get("mode") in MODES else SOLO
            self.level = (
                game.get("level") if game.get("level") in LEVEL_KEYS else DEFAULT_LEVEL
            )
            self.human = BLACK if game.get("human") == "black" else WHITE
            self.finished = bool(game.get("finished"))

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

        A move that will not play -- or will not even parse -- is where the file
        stops being a game, so the rest of it goes. See Game.resume, which is
        where that happens for the moves that are at least moves.
        """
        codes = []
        for text in self.moves:
            try:
                codes.append(parse_uci(text))
            except ValueError:
                break
        game = Game.resume(codes)
        self.moves = game.uci()
        return game

    def begin(self, *, mode: str, level: str, human: int) -> Game:
        self.mode = mode if mode in MODES else SOLO
        self.level = level if level in LEVEL_KEYS else DEFAULT_LEVEL
        self.human = human if human in (WHITE, BLACK) else WHITE
        self.moves = []
        self.finished = False
        return Game()

    def remember(self, game: Game, *, finished: bool = False) -> None:
        self.moves = game.uci()
        self.finished = finished

    # --- the tally -------------------------------------------------------

    def record(self, result: str, moves: int = 0) -> None:
        """Add one finished game against the computer to the level's record.

        Hotseat games are not recorded at all: the tally answers "how am I doing
        against Medium", and two people passing a phone across a table have no
        answer to put in it.
        """
        if self.mode != SOLO or result not in RESULTS:
            return
        entry = self.stats.setdefault(self.level, _record())
        entry["played"] += 1
        entry[result] += 1
        if result == WON and moves:
            # The shortest win rather than the longest: "mate in 18" is a thing
            # to be pleased about and "mate in 96" is a thing that happened.
            entry["quickest"] = (
                min(entry["quickest"], moves) if entry["quickest"] else moves
            )

    def record_for(self, key: str) -> dict[str, int]:
        return self.stats.get(key) or _record()

    def totals(self) -> dict[str, int]:
        out = _record()
        for entry in self.stats.values():
            for field in ("played", WON, LOST, DRAWN):
                out[field] += entry.get(field, 0)
            quickest = entry.get("quickest", 0)
            if quickest:
                out["quickest"] = (
                    min(out["quickest"], quickest) if out["quickest"] else quickest
                )
        return out
