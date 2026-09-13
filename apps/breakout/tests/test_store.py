"""The file: what is written, what is read back, and what a bad one does.

The case that is this app's own is what is *not* stored. A ball has a position
and a velocity, both floats in the middle of a physics step, and an app that
saved them would come back with a ball frozen three inches above the bat
travelling left -- which is not where anybody left it and is not a state anybody
can take over. So the wall, the score and the lives come back, and the ball
comes back on the bat.
"""

import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_breakout.breakout import (  # noqa: E402
    COLUMNS,
    LEVELS,
    LIVES,
    ROWS,
    World,
)
from moarchy_breakout.store import Store, level_count, level_name  # noqa: E402


def fresh() -> Store:
    return Store(Path(tempfile.mkdtemp()) / "breakout.json")


def part_played(store: Store) -> World:
    world = store.begin()
    for cell, brick in enumerate(world.bricks):
        if brick and cell % 3 == 0:
            world.bricks[cell] = 0
            world.score += 10
    world.lives = 2
    world.speed = 1.1
    store.remember(world)
    return world


class TestDefaults(unittest.TestCase):
    def test_a_missing_file_is_the_first_wall_and_not_an_error(self):
        store = fresh()
        store.load()
        world = store.world()
        self.assertEqual(store.level, 0)
        self.assertEqual(world.lives, LIVES)
        self.assertEqual(world.score, 0)
        self.assertEqual(sum(world.bricks), sum(LEVELS[0].bricks()))

    def test_a_new_game_starts_from_the_first_wall(self):
        store = fresh()
        part_played(store)
        store.level = 3
        world = store.begin()
        self.assertEqual(store.level, 0)
        self.assertEqual(world.score, 0)
        self.assertEqual(world.lives, LIVES)


class TestRoundTrip(unittest.TestCase):
    def test_the_wall_the_score_and_the_lives_come_back(self):
        store = fresh()
        world = part_played(store)
        store.save()

        back = Store(store.path)
        back.load()
        resumed = back.world()
        self.assertEqual(resumed.bricks, world.bricks)
        self.assertEqual(resumed.score, world.score)
        self.assertEqual(resumed.lives, world.lives)
        self.assertGreaterEqual(resumed.speed, world.speed)

    def test_the_ball_comes_back_on_the_bat(self):
        store = fresh()
        world = part_played(store)
        world.advance(0.5)
        world.serve()
        world.advance(0.4)
        store.remember(world)
        store.save()

        back = Store(store.path)
        back.load()
        resumed = back.world()
        self.assertFalse(resumed.served)
        self.assertFalse(resumed.ready)  # and it waits before it can be sent off

    def test_a_save_leaves_no_temporary_file_behind(self):
        store = fresh()
        store.save()
        self.assertEqual(
            [p.name for p in store.path.parent.iterdir()], [store.path.name]
        )


class TestABadFile(unittest.TestCase):
    def test_nonsense_is_moved_aside_rather_than_overwritten(self):
        store = fresh()
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text("{not json", encoding="utf-8")
        store.load()
        self.assertEqual(len(list(store.path.parent.glob("*.broken-*.json"))), 1)

    def test_a_wall_of_the_wrong_shape_is_dealt_fresh(self):
        store = fresh()
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text(
            json.dumps({"game": {"bricks": [1, 1, 1]}}), encoding="utf-8"
        )
        store.load()
        self.assertEqual(store.bricks, [])
        self.assertEqual(sum(store.world().bricks), sum(LEVELS[0].bricks()))

    def test_a_brick_stronger_than_the_level_has_is_dealt_fresh(self):
        # A wall that does not fit the level it claims to be would put bricks on
        # the screen that the rules do not have, which nobody can be expected to
        # notice and everybody would notice eventually.
        store = fresh()
        store.level = 0
        store.bricks = [9] * (COLUMNS * ROWS)
        world = store.world()
        self.assertEqual(world.bricks, LEVELS[0].bricks())

    def test_an_already_cleared_wall_is_dealt_again(self):
        store = fresh()
        store.bricks = [0] * (COLUMNS * ROWS)
        world = store.world()
        self.assertFalse(world.cleared)

    def test_junk_in_the_fields_falls_back_rather_than_raising(self):
        store = fresh()
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text(
            json.dumps(
                {
                    "game": {
                        "level": "three",
                        "score": -5,
                        "lives": 99,
                        "speed": "fast",
                        "bricks": "wall",
                    },
                    "stats": {"best": "lots"},
                }
            ),
            encoding="utf-8",
        )
        store.load()
        self.assertEqual(store.level, 0)
        self.assertEqual(store.score, 0)
        self.assertEqual(store.lives, LIVES)
        self.assertEqual(store.speed, 0.0)
        self.assertEqual(store.bricks, [])
        self.assertEqual(store.stats["best"], 0)

    def test_a_file_that_is_not_an_object_is_ignored(self):
        store = fresh()
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text("[1, 2, 3]", encoding="utf-8")
        store.load()
        self.assertEqual(store.bricks, [])


class TestLevels(unittest.TestCase):
    def test_clearing_one_carries_the_score_over(self):
        store = fresh()
        world = part_played(store)
        nxt = store.advance(world)
        self.assertEqual(store.level, 1)
        self.assertEqual(nxt.score, world.score)
        self.assertEqual(nxt.lives, world.lives)
        self.assertEqual(store.stats["cleared"], 1)

    def test_the_walls_have_names_and_come_round_again(self):
        self.assertEqual(level_count(), len(LEVELS))
        self.assertEqual(level_name(0), LEVELS[0].label)
        self.assertEqual(level_name(level_count()), LEVELS[0].label)


class TestTheRecord(unittest.TestCase):
    def test_a_game_that_ran_out_is_counted(self):
        store = fresh()
        world = part_played(store)
        world.lives = 0
        store.record(world)
        self.assertEqual(store.stats["played"], 1)
        self.assertEqual(store.stats["best"], world.score)
        self.assertEqual(store.stats["furthest"], 1)

    def test_the_best_score_only_goes_up(self):
        store = fresh()
        world = part_played(store)
        world.score = 500
        store.record(world)
        world.score = 200
        store.record(world)
        self.assertEqual(store.stats["best"], 500)
        world.score = 900
        store.record(world)
        self.assertEqual(store.stats["best"], 900)

    def test_the_furthest_wall_is_how_many_were_reached(self):
        store = fresh()
        world = part_played(store)
        store.level = 3
        store.record(world)
        self.assertEqual(store.stats["furthest"], 4)


if __name__ == "__main__":
    unittest.main()
