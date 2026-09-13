"""The game in progress, and the best there has been.

One JSON file. What is stored is **the wall, the score, the lives and which
level it is** -- and deliberately not the ball.

That last part is the decision. A ball has a position and a velocity and both
are floats in the middle of a physics step, and an app that saved them would
come back with a ball frozen three inches above the bat travelling left, which
is not where anybody left it and is not a state anybody can take over. So a game
put down and picked up again comes back with **the ball on the bat**, waiting to
be sent off. The wall is exactly as it was, the score is exactly as it was, and
the one thing given back is the rally that was in the air -- which is the only
honest thing to do with something nobody was holding.

Saving happens when something discrete happens: a brick falls, a life goes, a
level is cleared, the window stops being the active one. Not every frame, which
would be sixty fsyncs a second, and not on a timer, which would be a save in the
middle of a rally for no reason.
"""

from __future__ import annotations

import json
import os
import time
from pathlib import Path

from .breakout import COLUMNS, LEVELS, LIVES, ROWS, World, level_at

SCHEMA = 1


def data_dir() -> Path:
    """Where the game lives. Overridable, which is what makes the tests and the
    screenshot harness possible without touching a real game."""
    override = os.environ.get("MOARCHY_BREAKOUT_DIR")
    if override:
        return Path(override)
    base = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return Path(base) / "moarchy-breakout"


def _int(value, fallback: int) -> int:
    return (
        int(value)
        if isinstance(value, (int, float)) and not isinstance(value, bool)
        else fallback
    )


def _record() -> dict[str, int]:
    return {"played": 0, "best": 0, "furthest": 0, "cleared": 0}


class Store:
    """The saved wall, and the record."""

    def __init__(self, path: Path | str | None = None) -> None:
        self.path = Path(path) if path else data_dir() / "breakout.json"
        self.level: int = 0
        self.score: int = 0
        self.lives: int = LIVES
        self.speed: float = 0.0
        self.bricks: list[int] = []
        self.stats: dict[str, int] = _record()

    # --- file ------------------------------------------------------------

    def load(self) -> None:
        try:
            raw = self.path.read_text(encoding="utf-8")
        except OSError:
            return
        try:
            data = json.loads(raw)
        except ValueError:
            self._rescue()
            return
        if not isinstance(data, dict):
            return

        game = data.get("game")
        if isinstance(game, dict):
            self.level = max(_int(game.get("level"), 0), 0)
            self.score = max(_int(game.get("score"), 0), 0)
            self.lives = min(max(_int(game.get("lives"), LIVES), 0), LIVES)
            speed = game.get("speed")
            self.speed = float(speed) if isinstance(speed, (int, float)) else 0.0
            self.bricks = _wall(game.get("bricks"))

        stats = data.get("stats")
        if isinstance(stats, dict):
            entry = _record()
            for name in entry:
                entry[name] = max(_int(stats.get(name), 0), 0)
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
            "game": {
                "level": self.level,
                "score": self.score,
                "lives": self.lives,
                "speed": round(self.speed, 4),
                "bricks": self.bricks,
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

    def world(self, rng=None) -> World:
        """Put the saved wall back, with the ball on the bat.

        A wall that does not fit the level it claims to be is thrown away and
        the level is dealt fresh: the alternative is a game where the bricks on
        the screen and the bricks in the rules are different sets, which nobody
        can be expected to notice and everybody would notice eventually.
        """
        level = level_at(self.level)
        world = World(level, self.lives or LIVES, rng)
        world.score = self.score
        if self.speed:
            world.speed = max(self.speed, world.speed)
        if len(self.bricks) == COLUMNS * ROWS and self._fits(self.bricks, world):
            world.bricks = list(self.bricks)
        if world.cleared or world.dead:
            # Nothing to come back to. Start the level again rather than opening
            # on a wall that is already down or a game that is already lost.
            return self.begin(rng)
        return world

    def _fits(self, bricks: list[int], world: World) -> bool:
        """Is every saved brick one this level actually has, and no stronger?"""
        return all(
            0 <= saved <= original
            for saved, original in zip(bricks, world.strength, strict=False)
        )

    def begin(self, rng=None, level: int = 0) -> World:
        self.level = max(level, 0)
        self.score = 0
        self.lives = LIVES
        self.speed = 0.0
        self.bricks = []
        world = World(level_at(self.level), LIVES, rng)
        self.bricks = list(world.bricks)
        return world

    def remember(self, world: World) -> None:
        self.score = world.score
        self.lives = world.lives
        self.speed = world.speed
        self.bricks = list(world.bricks)

    def advance(self, world: World) -> World:
        """The next wall, with what survives a level brought over."""
        self.level += 1
        self.stats["cleared"] += 1
        nxt = world.carry_on(level_at(self.level))
        self.remember(nxt)
        return nxt

    # --- the record ------------------------------------------------------

    def record(self, world: World) -> None:
        """One game that ran out of lives."""
        self.stats["played"] += 1
        self.stats["best"] = max(self.stats["best"], world.score)
        self.stats["furthest"] = max(self.stats["furthest"], self.level + 1)

    def record_for(self) -> dict[str, int]:
        return dict(self.stats)


def _wall(value) -> list[int]:
    if not isinstance(value, list) or len(value) != COLUMNS * ROWS:
        return []
    out = []
    for item in value:
        if isinstance(item, bool) or not isinstance(item, int) or item < 0:
            return []
        out.append(item)
    return out


def level_name(number: int) -> str:
    return level_at(number).label


def level_count() -> int:
    return len(LEVELS)
