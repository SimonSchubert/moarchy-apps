"""The deal, the moves played on it, and what has been played before.

One JSON file, for the reasons every app here has one: a person plays a few
thousand games, not a million, and a file can be read by anything, diffed,
synced with rsync and repaired by hand on a device with no keyboard.

What is stored is **the deck and the move list**, not the table. Fifty-two
integers and a few hundred triples replay to exactly one table in a millisecond,
and that has a property a stored table cannot have: a file that has been
truncated, edited or half-written cannot describe a table that legal play could
not reach, because loading it is playing it. A bad tail is dropped and the game
resumes at the last move that made sense -- which for a game of patience is a
much better outcome than the alternative, since the alternative is a table with
two aces of spades on it.

It also means the deal survives everything. A game that is lost is lost on a
deal somebody can look at, and `moves: []` is the same deal again.

Saving happens on every move rather than on a timer. A move here is a tap, and
taps come in fast runs -- but on a phone the app is not closed, it is killed,
and a run of taps that is not on disk is a column somebody has to work out
again.
"""

from __future__ import annotations

import json
import os
import time
from pathlib import Path

from .klondike import DECK, DEFAULT_DRAW, DRAWS, Game, Move, shuffled

SCHEMA = 1

WON = "won"
LOST = "lost"
RESULTS = (WON, LOST)


def data_dir() -> Path:
    """Where the game lives. Overridable, which is what makes the tests and the
    screenshot harness possible without touching a real game."""
    override = os.environ.get("MOARCHY_SOLITAIRE_DIR")
    if override:
        return Path(override)
    base = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return Path(base) / "moarchy-solitaire"


def _int(value, fallback: int) -> int:
    return (
        int(value)
        if isinstance(value, (int, float)) and not isinstance(value, bool)
        else fallback
    )


def _record() -> dict[str, int]:
    # "best" is the fewest moves a game has been won in, which is zero until
    # there has been one -- there is no sensible starting value for a minimum,
    # and a sentinel that has to be remembered everywhere is worse than a zero
    # that means "none yet".
    return {"played": 0, WON: 0, "best": 0, "streak": 0, "longest": 0}


def _deck(value) -> tuple[int, ...] | None:
    """A deck out of whatever was in the file, or None if it is not one."""
    if not isinstance(value, list) or len(value) != DECK:
        return None
    if any(isinstance(v, bool) or not isinstance(v, int) for v in value):
        return None
    if sorted(value) != list(range(DECK)):
        # Fifty-two cards, each exactly once. A file with two aces of spades in
        # it is not a deck that lost some of its meaning, it is not a deck.
        return None
    return tuple(value)


class Store:
    """The saved game, the setting it was dealt at, and the tally."""

    def __init__(self, path: Path | str | None = None) -> None:
        self.path = Path(path) if path else data_dir() / "solitaire.json"
        self.deck: tuple[int, ...] = shuffled()
        self.draw: int = DEFAULT_DRAW
        self.moves: list[list[int]] = []
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
            deck = _deck(game.get("deck"))
            if deck is not None:
                self.deck = deck
            self.draw = game.get("draw") if game.get("draw") in DRAWS else DEFAULT_DRAW
            moves = game.get("moves")
            self.moves = (
                [list(m) for m in moves if Move.of(m) is not None]
                if isinstance(moves, list)
                else []
            )
            self.finished = bool(game.get("finished"))
            self.recorded = bool(game.get("recorded"))

        stats = data.get("stats")
        if isinstance(stats, dict):
            for key, value in stats.items():
                if key in _keys() and isinstance(value, dict):
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
                "draw": self.draw,
                "finished": self.finished,
                "recorded": self.recorded,
                "deck": list(self.deck),
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
        game = Game.resume(self.deck, self.draw, self.moves)
        self.deck = game.deck
        self.moves = [move.as_list() for move in game.moves]
        return game

    def begin(self, *, draw: int, deck: tuple[int, ...] | None = None) -> Game:
        self.draw = draw if draw in DRAWS else DEFAULT_DRAW
        self.deck = tuple(deck) if deck else shuffled()
        self.moves = []
        self.finished = False
        self.recorded = False
        return Game(self.deck, self.draw)

    def again(self) -> Game:
        """The same deal, from the top.

        Worth its own verb rather than being a new game with the old deck passed
        in: a deal you have just lost is the one you want another go at, and the
        alternative is somebody writing fifty-two numbers down.
        """
        self.moves = []
        self.finished = False
        self.recorded = False
        return Game(self.deck, self.draw)

    def remember(self, game: Game, *, finished: bool = False) -> None:
        self.deck = game.deck
        self.moves = [move.as_list() for move in game.moves]
        self.finished = finished

    # --- the tally -------------------------------------------------------

    def key(self) -> str:
        return _key(self.draw)

    def record(self, result: str, moves: int = 0) -> None:
        """One finished game against this deal, at the setting it was dealt at.

        Kept per draw setting because they are two different games: draw one is
        winnable about four times in five and draw three is not, so one tally
        across both would report a number that is mostly about which setting was
        in use that month.
        """
        if result not in RESULTS:
            return
        self.recorded = True
        entry = self.stats.setdefault(self.key(), _record())
        entry["played"] += 1
        if result == WON:
            entry[WON] += 1
            entry["streak"] += 1
            entry["longest"] = max(entry["longest"], entry["streak"])
            if moves and (not entry["best"] or moves < entry["best"]):
                entry["best"] = moves
        else:
            entry["streak"] = 0

    def record_for(self, draw: int) -> dict[str, int]:
        return self.stats.get(_key(draw)) or _record()

    def totals(self) -> dict[str, int]:
        out = _record()
        for entry in self.stats.values():
            out["played"] += entry.get("played", 0)
            out[WON] += entry.get(WON, 0)
            out["longest"] = max(out["longest"], entry.get("longest", 0))
            best = entry.get("best", 0)
            if best and (not out["best"] or best < out["best"]):
                out["best"] = best
        return out


def _key(draw: int) -> str:
    return f"draw{draw}"


def _keys() -> tuple[str, ...]:
    return tuple(_key(draw) for draw in DRAWS)
