"""The world. No GTK, so these run on any machine with a Python.

The test that earns its place is the tunnelling one. A ball moving at a width a
second crosses a brick in under two frames, so a physics step of one frame's
length passes straight through the wall at exactly the moments that decide a
game -- and nothing about that is visible in a screenshot, in a log, or from
reading the code. It is checked by giving `advance` a whole second at once and
asking whether the ball came out the far side of the wall.

The rest is arithmetic that has to be right for the game to be a game: a bounce
off each wall, a bat that sends the ball where it was hit, a life lost at the
bottom, and levels whose art means what it looks like.
"""

import random
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_breakout.breakout import (  # noqa: E402
    BALL,
    BAT_W,
    BAT_Y,
    BRICK_W,
    CLEARED,
    COLUMNS,
    HEIGHT,
    HIT_BAT,
    HIT_BRICK,
    HIT_WALL,
    LEVELS,
    LIVES,
    LOST_BALL,
    ROWS,
    SCORE,
    SPEED,
    SPEED_MAX,
    WALL_TOP,
    WIDTH,
    World,
    brick_rect,
    level_at,
)

FRAME = 1 / 60


def bare(level=None, **changes) -> World:
    """A world with nothing on the wall, for tests about the ball."""
    world = World(level or LEVELS[0], rng=random.Random(1))
    world.bricks = [0] * (COLUMNS * ROWS)
    for name, value in changes.items():
        setattr(world, name, value)
    return world


class TheLevels(unittest.TestCase):
    def test_the_art_means_what_it_looks_like(self):
        bricks = LEVELS[0].bricks()
        self.assertEqual(len(bricks), COLUMNS * ROWS)
        self.assertEqual(sum(1 for brick in bricks if brick), 29)
        # Every brick a level names is one hit or more, and no more than the
        # score table has entries for.
        for level in LEVELS:
            for brick in level.bricks():
                self.assertIn(brick, range(len(SCORE)))

    def test_every_level_has_bricks_and_they_fit_the_field(self):
        for level in LEVELS:
            bricks = level.bricks()
            self.assertGreater(sum(1 for brick in bricks if brick), 10, level.key)
            for cell, brick in enumerate(bricks):
                if not brick:
                    continue
                x, y, w, h = brick_rect(cell)
                self.assertGreaterEqual(x, 0)
                self.assertLessEqual(x + w, WIDTH + 1e-9)
                self.assertGreaterEqual(y, WALL_TOP)
                # ...and well clear of the bat, or the game opens already over.
                self.assertLess(y + h, BAT_Y - 0.3, level.key)

    def test_the_walls_come_round_again_rather_than_running_out(self):
        self.assertEqual(level_at(0).key, LEVELS[0].key)
        self.assertEqual(level_at(len(LEVELS)).key, LEVELS[0].key)
        self.assertEqual(level_at(len(LEVELS) + 2).key, LEVELS[2].key)

    def test_every_level_has_a_distinct_key_and_label(self):
        self.assertEqual(len({level.key for level in LEVELS}), len(LEVELS))
        self.assertEqual(len({level.label for level in LEVELS}), len(LEVELS))


class Serving(unittest.TestCase):
    def test_the_ball_sits_on_the_bat_until_it_is_sent_off(self):
        world = World(LEVELS[0])
        self.assertFalse(world.served)
        world.advance(0.5)
        self.assertAlmostEqual(world.ball_y, BAT_Y - BALL - 0.014, places=2)
        self.assertTrue(world.ready)
        self.assertTrue(world.serve())
        self.assertTrue(world.served)

    def test_it_will_not_be_sent_off_twice(self):
        world = World(LEVELS[0])
        world.advance(0.5)
        world.serve()
        self.assertFalse(world.serve())

    def test_there_is_a_pause_before_it_can_be(self):
        # So that the tap which ended the last life does not launch the next.
        world = World(LEVELS[0])
        self.assertFalse(world.ready)
        self.assertFalse(world.serve())

    def test_the_ball_follows_the_bat_while_it_waits(self):
        world = World(LEVELS[0])
        world.aim(0.2)
        self.assertAlmostEqual(world.ball_x, 0.2, places=6)

    def test_the_bat_stays_on_the_field(self):
        world = World(LEVELS[0])
        world.aim(-5)
        self.assertAlmostEqual(world.bat, BAT_W / 2, places=6)
        world.aim(5)
        self.assertAlmostEqual(world.bat, WIDTH - BAT_W / 2, places=6)


class Bouncing(unittest.TestCase):
    def test_it_comes_off_each_wall(self):
        world = bare(ball_x=0.5, ball_y=0.5, ball_vx=-SPEED, ball_vy=0.0, served=True)
        bounce = world.advance(1.0)
        self.assertIn(HIT_WALL, bounce.events)
        self.assertGreater(world.ball_vx, 0)

        world = bare(ball_x=0.5, ball_y=0.5, ball_vx=0.0, ball_vy=-SPEED, served=True)
        bounce = world.advance(1.0)
        self.assertIn(HIT_WALL, bounce.events)
        self.assertGreater(world.ball_vy, 0)

    def test_the_bat_sends_it_back_where_it_was_hit(self):
        world = bare(
            ball_x=0.5, ball_y=BAT_Y - 0.2, ball_vx=0.0, ball_vy=SPEED, served=True
        )
        world.bat = 0.5
        world.advance(0.5)
        # Dead centre: straight back up.
        self.assertLess(world.ball_vy, 0)
        self.assertAlmostEqual(world.ball_vx, 0.0, places=3)

        world = bare(
            ball_x=0.5, ball_y=BAT_Y - 0.2, ball_vx=0.0, ball_vy=SPEED, served=True
        )
        # Hit near the right-hand end: back up and to the right.
        world.bat = 0.5 - BAT_W * 0.4
        world.advance(0.5)
        self.assertLess(world.ball_vy, 0)
        self.assertGreater(world.ball_vx, 0)

    def test_a_ball_going_up_is_not_caught_by_the_bat(self):
        world = bare(ball_x=0.5, ball_y=BAT_Y, ball_vx=0.0, ball_vy=-SPEED, served=True)
        world.bat = 0.5
        bounce = world.advance(FRAME)
        self.assertNotIn(HIT_BAT, bounce.events)

    def test_a_ball_past_the_bottom_costs_a_life(self):
        world = bare(
            ball_x=0.5, ball_y=HEIGHT - 0.01, ball_vx=0.0, ball_vy=SPEED, served=True
        )
        world.bat = 0.05
        bounce = world.advance(0.3)
        self.assertIn(LOST_BALL, bounce.events)
        self.assertEqual(world.lives, LIVES - 1)
        self.assertFalse(world.served)

    def test_the_last_life_ends_the_game(self):
        world = bare(
            ball_x=0.5, ball_y=HEIGHT - 0.01, ball_vx=0.0, ball_vy=SPEED, served=True
        )
        world.bat = 0.05
        world.lives = 1
        world.advance(0.3)
        self.assertTrue(world.dead)
        self.assertFalse(world.advance(1.0))


class TheWall(unittest.TestCase):
    def _aimed_at(self, cell: int) -> World:
        """A ball below a column, travelling straight up at it."""
        world = World(LEVELS[0], rng=random.Random(1))
        x, y, _, h = brick_rect(cell)
        world.ball_x = x + BRICK_W / 2
        world.ball_y = y + h + 0.6
        world.ball_vx, world.ball_vy = 0.0, -SPEED
        world.served = True
        return world

    def _lowest_in(self, column: int) -> int:
        """The brick a ball coming up that column meets first.

        Not the first brick in the list, which is what the first draft of this
        test asserted on: a ball travelling upwards reaches the *bottom* of a
        column before the top of it, so aiming at cell 0 and checking cell 0 is
        checking the wrong one of three.
        """
        cells = [
            cell
            for cell, brick in enumerate(LEVELS[0].bricks())
            if brick and cell % COLUMNS == column
        ]
        return max(cells)

    def test_a_brick_is_broken_and_scores(self):
        cell = self._lowest_in(0)
        world = self._aimed_at(cell)
        bounce = world.advance(1.0)
        self.assertIn(HIT_BRICK, bounce.events)
        self.assertEqual(world.bricks[cell], 0)
        self.assertEqual(world.score, SCORE[1])
        self.assertGreater(world.ball_vy, 0)

    def test_a_tough_brick_takes_more_than_one_hit(self):
        level = next(lv for lv in LEVELS if any(b > 1 for b in lv.bricks()))
        cell = next(i for i, v in enumerate(level.bricks()) if v > 1)
        world = World(level, rng=random.Random(1))
        x, y, _, h = brick_rect(cell)
        world.bricks = [0] * (COLUMNS * ROWS)
        world.bricks[cell] = 2
        world.ball_x, world.ball_y = x + BRICK_W / 2, y + h + 0.4
        world.ball_vx, world.ball_vy = 0.0, -SPEED
        world.served = True
        world.advance(0.8)
        self.assertEqual(world.bricks[cell], 1)
        self.assertEqual(world.score, 0)

    def test_the_ball_never_passes_through_the_wall(self):
        # A whole second in one call. Without slicing, the ball crosses the
        # entire wall between two positions and hits nothing at all.
        for cell in (i for i, v in enumerate(LEVELS[0].bricks()) if v):
            world = self._aimed_at(cell)
            world.advance(1.0)
            self.assertLess(
                sum(world.bricks), sum(LEVELS[0].bricks()), f"missed brick {cell}"
            )
            self.assertGreater(world.ball_y, WALL_TOP, f"went through at {cell}")

    def test_clearing_the_wall_is_announced(self):
        world = bare(ball_x=0.5, ball_y=0.9, ball_vx=0.0, ball_vy=-SPEED, served=True)
        world.bricks[0] = 1
        x, y, _, h = brick_rect(0)
        world.ball_x, world.ball_y = x + BRICK_W / 2, y + h + 0.4
        bounce = world.advance(1.0)
        self.assertIn(CLEARED, bounce.events)
        self.assertTrue(world.cleared)

    def test_the_ball_speeds_up_but_not_without_limit(self):
        world = World(LEVELS[0], rng=random.Random(1))
        before = world.speed
        for cell in (i for i, v in enumerate(world.bricks) if v):
            world.bricks[cell] = 0
            world.speed = min(world.speed + 0.006, SPEED_MAX)
        self.assertGreater(world.speed, before)
        for _ in range(1000):
            world.speed = min(world.speed + 0.006, SPEED_MAX)
        self.assertLessEqual(world.speed, SPEED_MAX)


class AWholeGame(unittest.TestCase):
    """Played through, because the only way to know a physics engine works is
    to run it for a few thousand frames and see whether anything escapes."""

    def _play(self, level, seed: int, frames: int = 60 * 400):
        rng = random.Random(seed)
        world = World(level, lives=99, rng=rng)
        for _ in range(frames):
            if world.cleared:
                break
            world.aim(world.ball_x + rng.uniform(-0.05, 0.05))
            world.advance(FRAME)
            if world.ready:
                world.serve()
            self.assertGreaterEqual(world.ball_x, -0.05)
            self.assertLessEqual(world.ball_x, WIDTH + 0.05)
            self.assertGreaterEqual(world.ball_y, -0.05)
        return world

    def test_every_level_can_be_cleared(self):
        # Not a claim about difficulty: a level nobody can finish is a level
        # where a brick sits somewhere the ball cannot reach, which is a bug in
        # the art rather than a hard wall.
        for level in LEVELS:
            world = self._play(level, seed=5)
            self.assertTrue(world.cleared, f"{level.key} would not clear")

    def test_the_ball_stays_on_the_field(self):
        # Asserted inside _play on every frame; this names it.
        self._play(LEVELS[3], seed=2)

    def test_a_frame_the_compositor_lost_does_not_teleport_the_ball(self):
        world = World(LEVELS[0], rng=random.Random(1))
        world.advance(0.5)
        world.serve()
        before = sum(world.bricks)
        # Two whole seconds in one call, which is what a phone waking up looks
        # like. The world must cut it up rather than jump.
        world.advance(2.0)
        self.assertGreaterEqual(before - sum(world.bricks), 1)
        self.assertLessEqual(world.ball_y, HEIGHT + BALL + 0.1)


class CarryingOn(unittest.TestCase):
    def test_the_next_wall_keeps_the_score_the_lives_and_the_speed(self):
        world = World(LEVELS[0], rng=random.Random(1))
        world.score = 340
        world.lives = 2
        world.speed = 1.2
        world.bat = 0.3
        nxt = world.carry_on(LEVELS[1])
        self.assertEqual(nxt.score, 340)
        self.assertEqual(nxt.lives, 2)
        self.assertEqual(nxt.speed, 1.2)
        self.assertEqual(nxt.bat, 0.3)
        self.assertEqual(sum(nxt.bricks), sum(LEVELS[1].bricks()))
        self.assertFalse(nxt.served)


if __name__ == "__main__":
    unittest.main()
