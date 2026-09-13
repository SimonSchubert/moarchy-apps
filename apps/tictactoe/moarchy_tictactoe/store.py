"""The game in progress, the series it belongs to, and the lifetime record.

One JSON file, for the reasons Keep, Habits and Reversi have one: a person plays
a few thousand of these, not a million, and a file can be read by anything,
diffed, synced with rsync and repaired by hand on a device with no keyboard.

What is stored is the move list, not the board. Nine digits replay to exactly
one position, and that has a property a stored board cannot have: a file that
has been truncated, edited or half-written cannot describe a board that legal
play could not reach, because loading it is playing it. A bad tail is dropped
and the game resumes at the last move that made sense.

The part that is this game's own is the **series**. A game here lasts about
fifteen seconds, so the unit somebody actually plays is not a game, it is a
sitting -- five or six of them, one tap apart, until the bus arrives. So the
file keeps a running score across the sitting, and the rematch button keeps it;
only choosing New game from the menu starts a fresh one. Reversi has no
equivalent because nobody plays six games of Reversi between two stops.

The two seats are stored as "a" and "b" rather than as X and O, and that is
deliberate: **the rematch swaps who plays X**, the way two people taking turns
on paper do, because X moves first and first is worth something against anybody
who is not perfect. A series scored by mark would be scoring the advantage
rather than the players.

Saving happens on every move. It costs one fsync a turn, and on a phone the app
is not usually closed -- it is killed, backgrounded, by a compositor reclaiming
memory while somebody reads a message.
"""

from __future__ import annotations

import json
import os
import time
from pathlib import Path

from .ai import DEFAULT_LEVEL, LEVEL_KEYS
from .tictactoe import O, X, Game

SCHEMA = 1

# Who the other player is. Against the computer there is a "you", so a result is
# a win or a loss and goes into the record; across a table there is not, and
# only the series is kept.
SOLO = "solo"
HOTSEAT = "hotseat"
MODES = (SOLO, HOTSEAT)

# Every result in this file is from seat A's point of view. Seat A is you in a
# solo game and player one in a hotseat one, and it is the same seat all series
# whichever mark it is holding this game.
WON = "won"
LOST = "lost"
DRAWN = "drawn"
RESULTS = (WON, LOST, DRAWN)


def data_dir() -> Path:
    """Where the game lives. Overridable, which is what makes the tests and the
    screenshot harness possible without touching a real game."""
    override = os.environ.get("MOARCHY_TICTACTOE_DIR")
    if override:
        return Path(override)
    base = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return Path(base) / "moarchy-tictactoe"


def _int(value, fallback: int) -> int:
    return (
        int(value)
        if isinstance(value, (int, float)) and not isinstance(value, bool)
        else fallback
    )


def _record() -> dict[str, int]:
    # "unbeaten" is the run of games in a row that were not lost, and "best" is
    # the longest such run there has been. Wins are the wrong headline figure in
    # this game: against Perfect there are none to be had, and a hundred draws
    # is a person who has learnt it rather than a person who keeps failing.
    return {"played": 0, WON: 0, LOST: 0, DRAWN: 0, "unbeaten": 0, "best": 0}


def _series() -> dict[str, int]:
    return {"a": 0, "b": 0, DRAWN: 0}


class Store:
    """The saved game, the settings it was started with, and both tallies."""

    def __init__(self, path: Path | str | None = None) -> None:
        self.path = Path(path) if path else data_dir() / "tictactoe.json"
        self.moves: list[int] = []
        self.mode: str = SOLO
        self.level: str = DEFAULT_LEVEL
        # The mark seat A is holding *this* game. It swaps on every rematch.
        self.mark: int = X
        self.finished: bool = False
        # Whether the result of the finished game has already gone into the
        # tallies. Deliberately not the same flag as `finished`: the move that
        # ends a game is written to the file the instant it is played, and the
        # result is counted a fraction of a second later when the mark has
        # finished being drawn. A phone killed between the two would otherwise
        # come back to a finished board whose result nothing ever counted.
        self.recorded: bool = False
        self.series: dict[str, int] = _series()
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
                [_int(m, -1) for m in moves if not isinstance(m, bool)]
                if isinstance(moves, list)
                else []
            )
            self.mode = game.get("mode") if game.get("mode") in MODES else SOLO
            self.level = (
                game.get("level") if game.get("level") in LEVEL_KEYS else DEFAULT_LEVEL
            )
            self.mark = O if game.get("mark") == "o" else X
            self.finished = bool(game.get("finished"))
            self.recorded = bool(game.get("recorded"))

        series = data.get("series")
        if isinstance(series, dict):
            self.series = {key: max(_int(series.get(key), 0), 0) for key in _series()}

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
                "mark": "x" if self.mark == X else "o",
                "finished": self.finished,
                "recorded": self.recorded,
                "moves": self.moves,
            },
            "series": self.series,
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
        game = Game.resume(self.moves)
        self.moves = list(game.moves)
        return game

    def begin(self, *, mode: str, level: str, mark: int) -> Game:
        """A new game, and a new series with it.

        Changing the opponent or the difficulty ends the sitting: a score line
        reading 4-2 across a change of difficulty is two different questions
        added together.
        """
        self.mode = mode if mode in MODES else SOLO
        self.level = level if level in LEVEL_KEYS else DEFAULT_LEVEL
        self.mark = mark if mark in (X, O) else X
        self.moves = []
        self.finished = False
        self.recorded = False
        self.series = _series()
        return Game()

    def rematch(self) -> Game:
        """Another game on the same terms, with the marks swapped.

        Swapping is the whole point of the button. X moves first and first is
        worth something against anybody short of perfect, so a series where one
        seat holds X every game is a series decided before it starts -- which is
        exactly why two people with a pencil take turns going first.
        """
        self.mark = O if self.mark == X else X
        self.moves = []
        self.finished = False
        self.recorded = False
        return Game()

    def remember(self, game: Game, *, finished: bool = False) -> None:
        self.moves = list(game.moves)
        self.finished = finished

    # --- the tallies -----------------------------------------------------

    def record(self, result: str) -> None:
        """One finished game, from seat A's point of view.

        The series counts both modes, because two people across a table are
        keeping score whether or not a computer is involved. The lifetime record
        counts only games against the computer: it answers "how do I do against
        Fair", and two people passing a phone have no answer to put in it.
        """
        if result not in RESULTS:
            return
        self.recorded = True
        self.series["a" if result == WON else "b" if result == LOST else DRAWN] += 1

        if self.mode != SOLO:
            return
        entry = self.stats.setdefault(self.level, _record())
        entry["played"] += 1
        entry[result] += 1
        if result == LOST:
            entry["unbeaten"] = 0
        else:
            entry["unbeaten"] += 1
            entry["best"] = max(entry["best"], entry["unbeaten"])

    def record_for(self, key: str) -> dict[str, int]:
        return self.stats.get(key) or _record()

    def totals(self) -> dict[str, int]:
        out = _record()
        for entry in self.stats.values():
            for field in ("played", WON, LOST, DRAWN):
                out[field] += entry.get(field, 0)
            out["best"] = max(out["best"], entry.get("best", 0))
            out["unbeaten"] = max(out["unbeaten"], entry.get("unbeaten", 0))
        return out
