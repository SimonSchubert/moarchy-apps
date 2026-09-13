#!/usr/bin/python3
"""Fill a data directory with a game worth photographing.

A full wall with the ball sitting on the bat says what the app is and nothing
about playing it. So this plays a real game -- the world this app ships, stepped
at sixty frames a second by a bat that follows the ball with a deliberate lean
-- and stops it with a third of the wall down.

Playing it rather than rubbing bricks out matters for one reason: the wall in
the picture is then one the physics can actually produce. A hand-emptied wall is
easy to spot, because a real one is eaten from the middle outwards along the
lines the ball has taken, and an invented one is not.

    demo.py          a third of the wall down, a life gone
    demo.py late     deep into the second wall, one life left

The record is invented and says so.
"""

from __future__ import annotations

import os
import random
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_breakout.breakout import LOST_BALL, World, level_at  # noqa: E402
from moarchy_breakout.store import Store  # noqa: E402

# A bat that plays well but not perfectly: it follows the ball with a lean that
# changes, so the ball comes off at a different angle each time and the wall is
# eaten unevenly. Two other bats were tried and neither works. One that tracks
# the ball exactly sends it straight up and down a single column forever; one
# that leans by a *fixed* amount falls into a cycle and spends four hundred
# seconds missing the same four bricks. A little noise is what a person is.
LEAN = 0.05
FRAME = 1 / 60

STATS = {"played": 23, "best": 2140, "furthest": 4, "cleared": 41}


def _play(level_number: int, down_to: float, lives: int, seed: int) -> World:
    """Play a wall until the share of it left falls below `down_to`."""
    rng = random.Random(seed)
    world = World(level_at(level_number), lives, rng)
    standing = world.standing
    for _ in range(60 * 600):
        if world.standing <= standing * down_to or world.dead:
            break
        world.aim(world.ball_x + rng.uniform(-LEAN, LEAN))
        bounce = world.advance(FRAME)
        if LOST_BALL in bounce.events:
            # Serve again at once: the demo is not trying to lose, it is trying
            # to produce a wall with holes in it.
            pass
        if world.ready:
            world.serve()
    return world


def main() -> int:
    target = os.environ.get("MOARCHY_BREAKOUT_DIR")
    if not target:
        print(
            "set MOARCHY_BREAKOUT_DIR first -- refusing to touch a real game",
            file=sys.stderr,
        )
        return 2

    stage = sys.argv[1] if len(sys.argv) > 1 else "board"
    level = 1 if stage == "late" else 0
    world = _play(
        level, 0.3 if stage == "late" else 0.62, 2 if stage == "late" else 3, 9
    )

    store = Store(Path(target) / "breakout.json")
    store.begin(level=level)
    store.remember(world)
    store.stats.update(STATS)
    store.save()

    print(
        f"wrote level {level + 1} with {world.standing} bricks left, "
        f"{world.score} points, {world.lives} lives to {store.path}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
