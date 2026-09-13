"""The rules of Breakout: a ball, a bat, and a wall written as art.

This is the only game in this repository with a *clock in it* rather than a
clock on it. Everywhere else a move is a discrete thing that either happened or
did not; here the state is continuous, the app advances it sixty times a second,
and the whole file is about making that advance correct rather than merely fast.

Two things carry most of the weight.

**The world is measured in widths, not pixels.** The field is one unit across
and `HEIGHT` units tall, so every speed, size and radius in here is a fraction
of the screen -- which means the game plays identically on a 360px phone and on
the same window dragged to 700px wide, and the widget's only job is to multiply
by one number. A physics engine in pixels is a physics engine that is a
different game on every screen.

**The ball is stepped in slices small enough that it cannot pass through
anything.** A ball moving at one width a second crosses a 0.03-unit brick in
thirty milliseconds, which is under two frames -- so a single step per frame
tunnels straight through the wall at exactly the moments that matter. `advance`
cuts the frame into slices no longer than it takes the ball to travel its own
radius, which is the cheapest rule that cannot miss.

The levels are art, the way Peg Solitaire's figures are: a digit is a brick and
how many hits it takes, a dot is a gap. Somebody adding a level should be able
to draw one.

Nothing here imports GTK.
"""

from __future__ import annotations

import math
import random
from dataclasses import dataclass, field

# The field, in widths. Taller than it is wide, because a phone is.
WIDTH = 1.0
HEIGHT = 1.62

COLUMNS = 7
ROWS = 8

# Everything below is a fraction of the field's width.
BRICK_W = WIDTH / COLUMNS
BRICK_H = 0.060
# Where the wall starts, leaving room for the score above it.
WALL_TOP = 0.11

BALL = 0.020
BAT_W = 0.20
BAT_H = 0.028
BAT_Y = HEIGHT - 0.075

# How fast the ball starts, and how much faster it gets for each brick broken --
# capped, because a ball that ends the level at four widths a second is a ball
# nobody can follow.
SPEED = 0.95
SPEED_STEP = 0.006
SPEED_MAX = 1.55

# How far from straight up the ball may leave the bat. Forty-five degrees short
# of horizontal at the very edge: a ball travelling more sideways than that
# spends its life crossing the field and never reaches the wall.
BAT_ANGLE = math.radians(62)
# ...and the shallowest it may ever travel. Without this the ball eventually
# finds a horizontal groove between two walls and stays there.
FLATTEST = math.radians(14)

LIVES = 3

# What a brick is worth: more for the ones that took more hitting.
SCORE = (0, 10, 25, 45)

# How long the ball waits on the bat before it may be launched. Long enough that
# the tap which ended the last life does not launch the next one.
SERVE_WAIT = 0.35


@dataclass(frozen=True)
class Level:
    """A wall, written as art, and what it is called."""

    key: str
    label: str
    art: str

    def bricks(self) -> list[int]:
        """The wall as one integer per cell: how many hits it has left."""
        out = [0] * (COLUMNS * ROWS)
        rows = [line for line in self.art.strip("\n").splitlines() if line.strip()]
        for row, line in enumerate(rows[:ROWS]):
            for column, glyph in enumerate(line[:COLUMNS]):
                if glyph.isdigit() and glyph != "0":
                    out[row * COLUMNS + column] = min(int(glyph), len(SCORE) - 1)
        return out


LEVELS = (
    Level(
        "opening",
        "Opening",
        """
1111111
1111111
1111111
.11111.
..111..
""",
    ),
    Level(
        "arch",
        "Arch",
        """
..222..
.22222.
2222222
1111111
1111111
1111111
""",
    ),
    Level(
        "gate",
        "Gate",
        """
2222222
2.....2
2.111.2
2.111.2
2.111.2
2.....2
2111112
""",
    ),
    Level(
        "chevron",
        "Chevron",
        """
3.....3
23...32
123.321
.12321.
..232..
...3...
""",
    ),
    Level(
        "keep",
        "Keep",
        """
3333333
3.....3
3.222.3
3.2.2.3
3.222.3
3.....3
3111113
""",
    ),
)
LEVEL_KEYS = tuple(level.key for level in LEVELS)


def level_at(number: int) -> Level:
    """The level for a round number, wrapping round for anybody who gets there.

    Five walls and then the first again, which is the honest arcade answer: the
    game gets harder because the ball gets faster and there is one more of it to
    clear, not because somebody wrote a hundred walls.
    """
    return LEVELS[max(number, 0) % len(LEVELS)]


def brick_rect(cell: int) -> tuple[float, float, float, float]:
    row, column = divmod(cell, COLUMNS)
    return (
        column * BRICK_W,
        WALL_TOP + row * BRICK_H,
        BRICK_W,
        BRICK_H,
    )


# What a step of the world did, for the window to make a noise about.
HIT_WALL = "wall"
HIT_BAT = "bat"
HIT_BRICK = "brick"
LOST_BALL = "lost"
CLEARED = "cleared"


@dataclass
class Bounce:
    """Everything that happened in one advance of the world."""

    events: list[str] = field(default_factory=list)
    broken: list[int] = field(default_factory=list)
    scored: int = 0

    def __bool__(self) -> bool:
        return bool(self.events)


class World:
    """One life's worth of ball, bat and wall.

    Mutable, which is the one place this repository's habit of frozen state does
    not fit: this is stepped sixty times a second and a new object per frame is
    a new object per frame. What is kept immutable is everything *around* it --
    the level art, the rectangles, the constants -- so the mutable part is four
    floats and a list of small integers.
    """

    def __init__(self, level: Level, lives: int = LIVES, rng=None) -> None:
        self.level = level
        # What is left of each brick, and what it started as. The first drives
        # what is drawn; the second decides what it is worth, because a brick
        # that took three hits is worth three hits' worth whichever hit ends it.
        self.bricks = level.bricks()
        self.strength = tuple(self.bricks)
        self.lives = lives
        self.score = 0
        self.bat = WIDTH / 2
        self.rng = rng or random.Random()
        self.speed = SPEED
        self.waiting = SERVE_WAIT
        self.ball_x = self.bat
        self.ball_y = BAT_Y - BALL - BAT_H / 2
        self.ball_vx = 0.0
        self.ball_vy = 0.0
        self.served = False

    # --- state -------------------------------------------------------------

    @property
    def standing(self) -> int:
        return sum(1 for brick in self.bricks if brick)

    @property
    def cleared(self) -> bool:
        return self.standing == 0

    @property
    def dead(self) -> bool:
        return self.lives <= 0

    @property
    def ready(self) -> bool:
        """Is the ball on the bat, waiting to be sent off?"""
        return not self.served and self.waiting <= 0

    def carry_on(self, level: Level) -> World:
        """The next wall, with the score, the lives and the speed brought over.

        A new World rather than a reset, because a level is a wall and the
        things that survive it are exactly the three named here -- writing that
        as a method is the difference between "what carries over" being a fact
        and being four assignments somebody will forget one of.
        """
        world = World(level, self.lives, self.rng)
        world.score = self.score
        world.speed = self.speed
        world.bat = self.bat
        world.ball_x = self.bat
        return world

    # --- the person's two controls -----------------------------------------

    def aim(self, x: float) -> None:
        """Put the middle of the bat here, clamped to the field.

        The bat follows a finger *absolutely* rather than by dragging, and it
        follows it from anywhere on the screen rather than only from on top of
        itself. Both are the same decision: a thumb covers a 72px bat
        completely, so the only playable arrangement is one where the thumb is
        somewhere else and the bat goes where it points.
        """
        half = BAT_W / 2
        self.bat = min(max(x, half), WIDTH - half)
        if not self.served:
            self.ball_x = self.bat

    def serve(self) -> bool:
        """Send the ball off the bat. Ignored until the pause has run out."""
        if self.served or self.waiting > 0:
            return False
        # Up and slightly towards the middle, so that the first shot is never
        # the one that goes straight up and comes straight back down forever.
        lean = (WIDTH / 2 - self.bat) * 0.8
        angle = math.atan2(lean, 1.0)
        self.ball_vx = math.sin(angle) * self.speed
        self.ball_vy = -math.cos(angle) * self.speed
        self.served = True
        return True

    # --- the clock ---------------------------------------------------------

    def advance(self, seconds: float) -> Bounce:
        """Move the world on by this much time.

        Cut into slices no longer than the ball's own radius takes, because a
        ball moving at a width a second crosses a brick in under two frames --
        and a single step per frame therefore passes through the wall at exactly
        the moments that decide the game.
        """
        bounce = Bounce()
        if self.dead:
            return bounce
        if not self.served:
            self.waiting = max(self.waiting - seconds, 0.0)
            self.ball_x = self.bat
            self.ball_y = BAT_Y - BALL - BAT_H / 2
            return bounce

        speed = math.hypot(self.ball_vx, self.ball_vy) or self.speed
        slice_length = BALL / max(speed, 1e-6)
        left = seconds
        # A hard cap on the number of slices, so that a frame the compositor
        # lost -- a phone waking up with two seconds of elapsed time on it --
        # cannot turn into a thousand steps of physics in one repaint.
        for _ in range(240):
            if left <= 0:
                break
            step = min(left, slice_length)
            self._step(step, bounce)
            left -= step
            if LOST_BALL in bounce.events or CLEARED in bounce.events:
                break
        return bounce

    def _step(self, seconds: float, bounce: Bounce) -> None:
        self.ball_x += self.ball_vx * seconds
        self.ball_y += self.ball_vy * seconds

        if self.ball_x < BALL:
            self.ball_x = BALL
            self.ball_vx = abs(self.ball_vx)
            bounce.events.append(HIT_WALL)
        elif self.ball_x > WIDTH - BALL:
            self.ball_x = WIDTH - BALL
            self.ball_vx = -abs(self.ball_vx)
            bounce.events.append(HIT_WALL)
        if self.ball_y < BALL:
            self.ball_y = BALL
            self.ball_vy = abs(self.ball_vy)
            bounce.events.append(HIT_WALL)

        self._bricks(bounce)
        self._bat(bounce)

        if self.ball_y > HEIGHT + BALL:
            self.lives -= 1
            self.served = False
            self.waiting = SERVE_WAIT
            self.ball_x, self.ball_y = self.bat, BAT_Y - BALL - BAT_H / 2
            self.ball_vx = self.ball_vy = 0.0
            bounce.events.append(LOST_BALL)

    def _bat(self, bounce: Bounce) -> None:
        if self.ball_vy <= 0:
            return  # going up: the bat is behind it
        top = BAT_Y - BAT_H / 2
        if not (top - BALL <= self.ball_y <= BAT_Y + BAT_H / 2 + BALL):
            return
        half = BAT_W / 2
        if not (self.bat - half - BALL <= self.ball_x <= self.bat + half + BALL):
            return
        # Where on the bat it landed decides where it goes, which is the whole
        # of what makes this a game of skill rather than of waiting. The middle
        # sends it back up; the ends send it out at an angle.
        offset = max(min((self.ball_x - self.bat) / half, 1.0), -1.0)
        angle = offset * BAT_ANGLE
        self.speed = min(self.speed, SPEED_MAX)
        self.ball_vx = math.sin(angle) * self.speed
        self.ball_vy = -math.cos(angle) * self.speed
        self.ball_y = top - BALL
        self._unflatten()
        bounce.events.append(HIT_BAT)

    def _bricks(self, bounce: Bounce) -> None:
        cell = self._brick_at(self.ball_x, self.ball_y)
        if cell < 0:
            return
        x, y, w, h = brick_rect(cell)
        # Which way to bounce is decided by which face the ball is least far
        # through, which is the cheap version of "where did it come from" and is
        # right whenever the ball is not arriving exactly at a corner.
        from_left = abs(self.ball_x - x)
        from_right = abs(x + w - self.ball_x)
        from_top = abs(self.ball_y - y)
        from_bottom = abs(y + h - self.ball_y)
        if min(from_left, from_right) < min(from_top, from_bottom):
            self.ball_vx = -self.ball_vx
            self.ball_x += self.ball_vx * 1e-3
        else:
            self.ball_vy = -self.ball_vy
            self.ball_y += self.ball_vy * 1e-3

        self.bricks[cell] -= 1
        bounce.events.append(HIT_BRICK)
        if self.bricks[cell] <= 0:
            self.bricks[cell] = 0
            bounce.broken.append(cell)
            gained = SCORE[self.strength[cell]]
            self.score += gained
            bounce.scored += gained
            self.speed = min(self.speed + SPEED_STEP, SPEED_MAX)
            self._rescale()
        if self.cleared:
            bounce.events.append(CLEARED)

    def _brick_at(self, x: float, y: float) -> int:
        if y < WALL_TOP or y > WALL_TOP + ROWS * BRICK_H:
            return -1
        column = int(x // BRICK_W)
        row = int((y - WALL_TOP) // BRICK_H)
        if not (0 <= column < COLUMNS and 0 <= row < ROWS):
            return -1
        cell = row * COLUMNS + column
        return cell if self.bricks[cell] else -1

    def _rescale(self) -> None:
        """Keep the ball's direction and give it the current speed."""
        length = math.hypot(self.ball_vx, self.ball_vy)
        if length <= 0:
            return
        self.ball_vx = self.ball_vx / length * self.speed
        self.ball_vy = self.ball_vy / length * self.speed

    def _unflatten(self) -> None:
        """Refuse to travel too close to horizontal.

        A guard rather than a fix for something observed: the bat's own limit
        keeps the ball a good deal steeper than this, so in the shipped game
        this never fires. It is here because BAT_ANGLE is a constant somebody
        will raise one day, and the failure it prevents is the ball finding a
        groove between two walls and crossing the screen for a minute at a time,
        which is not a rally, it is a screensaver.
        """
        angle = math.atan2(self.ball_vy, self.ball_vx)
        flat = abs(math.sin(angle))
        if flat >= math.sin(FLATTEST):
            return
        sign = -1.0 if self.ball_vy <= 0 else 1.0
        lean = math.copysign(math.cos(FLATTEST), self.ball_vx or 1.0)
        self.ball_vx = lean * self.speed
        self.ball_vy = sign * math.sin(FLATTEST) * self.speed
