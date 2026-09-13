"""The window, driven by calling it rather than by tapping it.

This is the only app here with a frame loop, so most of this is about when the
loop runs and when it does not: it stops when the window stops being the active
one, it stops when the game is over, and it is capped so that a frame the
compositor lost cannot fast-forward a rally nobody saw.

Needs a display. Skipped where there is none, so `python3 -m unittest` on a
machine without GTK still runs the physics and the file.
"""

from __future__ import annotations

import os
import sys
import time
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

REASON = ""
try:
    import gi

    gi.require_version("Gtk", "4.0")
    gi.require_version("Adw", "1")
    from gi.repository import Adw, GLib, Gtk

    if not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        REASON = "no display"
    elif not Gtk.init_check():
        REASON = "GTK could not open the display"
except (ImportError, ValueError) as exc:  # pragma: no cover - depends on host
    REASON = f"no GTK: {exc}"

if not REASON:
    Adw.init()
    from moarchy_breakout.theme import fallback
    from moarchy_breakout.widgets import FieldView, Lives
    from moarchy_breakout.window import BreakoutWindow, RecordPage

from moarchy_breakout.breakout import (  # noqa: E402
    BAT_W,
    HEIGHT,
    LEVELS,
    LIVES,
    SPEED,
    WIDTH,
)
from moarchy_breakout.store import Store  # noqa: E402


def pump(until=None, seconds: float = 4.0) -> bool:
    context = GLib.MainContext.default()
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        while context.pending():
            context.iteration(False)
        if until is None or until():
            return True
        time.sleep(0.01)
    return until is None or until()


@unittest.skipIf(REASON, REASON)
class WindowBase(unittest.TestCase):
    def setUp(self):
        self.dir = TemporaryDirectory()
        self.store = Store(Path(self.dir.name) / "breakout.json")

    def open(self) -> BreakoutWindow:
        self.window = BreakoutWindow(self.store)
        self.addCleanup(self.window.destroy)
        return self.window

    def tearDown(self):
        pump(seconds=0.05)
        self.dir.cleanup()


class TheField(WindowBase):
    def test_a_new_game_opens_on_the_first_wall_with_the_ball_on_the_bat(self):
        window = self.open()
        self.assertEqual(sum(window.world.bricks), sum(LEVELS[0].bricks()))
        self.assertFalse(window.world.served)
        self.assertEqual(window.world.lives, LIVES)

    def test_a_saved_wall_is_picked_back_up(self):
        world = self.store.begin()
        world.bricks[0] = 0
        world.score = 40
        self.store.remember(world)
        window = self.open()
        self.assertEqual(window.world.score, 40)
        self.assertEqual(window.world.bricks[0], 0)

    def test_it_describes_itself_for_a_screen_reader(self):
        view = FieldView()
        view.set_colours(fallback(dark=True))
        view.show(self.store.begin())
        self.assertIn("bricks left", view.describe())

    def test_the_lives_build_and_empty(self):
        lives = Lives(LIVES)
        lives.refresh(1)
        self.assertTrue(lives._dots[1].has_css_class("spent"))
        self.assertFalse(lives._dots[0].has_css_class("spent"))


class Aiming(WindowBase):
    def test_the_bat_goes_where_it_is_pointed(self):
        window = self.open()
        window._on_aimed(None, 0.25)
        self.assertAlmostEqual(window.world.bat, 0.25, places=5)

    def test_it_is_clamped_to_the_field(self):
        window = self.open()
        window._on_aimed(None, -3.0)
        self.assertAlmostEqual(window.world.bat, BAT_W / 2, places=5)
        window._on_aimed(None, 9.0)
        self.assertAlmostEqual(window.world.bat, WIDTH - BAT_W / 2, places=5)

    def test_a_press_serves_as_well_as_aims(self):
        window = self.open()
        window.world.waiting = 0.0
        window._on_aimed(None, 0.5)
        window.serve()
        self.assertTrue(window.world.served)

    def test_nothing_is_aimed_once_the_game_is_over(self):
        window = self.open()
        window.world.lives = 0
        window._on_aimed(None, 0.1)
        self.assertNotAlmostEqual(window.world.bat, 0.1, places=3)


class TheLoop(WindowBase):
    def test_it_is_not_running_once_the_game_is_over(self):
        window = self.open()
        window.world.lives = 0
        window.refresh()
        self.assertFalse(window._running)
        self.assertEqual(window._tick, 0)

    def test_it_agrees_with_the_window_about_being_active(self):
        window = self.open()
        window.present()
        pump(seconds=0.2)
        # Whether a headless window is ever "active" is the compositor's
        # business, so what is tested is that the loop and the window agree.
        self.assertEqual(bool(window._tick), window.is_active())

    def test_a_frozen_window_does_not_step(self):
        window = self.open()
        window._frozen = True
        window.refresh()
        self.assertFalse(window._running)

    def test_the_status_says_paused_when_it_is(self):
        window = self.open()
        if not window.is_active():
            self.assertEqual(window._status_text(), "Paused")


class TheGame(WindowBase):
    def test_clearing_a_wall_moves_on_and_keeps_the_score(self):
        window = self.open()
        window.world.score = 120
        window.world.bricks = [0] * len(window.world.bricks)
        window.world.bricks[0] = 1
        # One brick left, and a ball about to take it.
        from moarchy_breakout.breakout import BRICK_W, brick_rect

        x, y, _, h = brick_rect(0)
        window.world.ball_x = x + BRICK_W / 2
        window.world.ball_y = y + h + 0.3
        window.world.ball_vx, window.world.ball_vy = 0.0, -SPEED
        window.world.served = True
        bounce = window.world.advance(0.6)
        window._react(bounce)
        self.assertEqual(self.store.level, 1)
        self.assertEqual(window.world.score, 130)
        self.assertEqual(self.store.stats["cleared"], 1)

    def test_the_last_ball_ends_the_game_and_is_recorded_once(self):
        window = self.open()
        window.world.lives = 1
        window.world.score = 300
        window.world.ball_x, window.world.ball_y = 0.5, HEIGHT - 0.005
        window.world.ball_vx, window.world.ball_vy = 0.0, SPEED
        window.world.served = True
        window.world.bat = 0.05
        bounce = window.world.advance(0.3)
        window._react(bounce)
        self.assertTrue(window.world.dead)
        self.assertEqual(self.store.stats["played"], 1)
        self.assertEqual(self.store.stats["best"], 300)
        window._finish()
        self.assertEqual(self.store.stats["played"], 1)

    def test_a_game_given_up_is_still_a_game_played(self):
        window = self.open()
        window.world.score = 150
        window.new_game()
        self.assertEqual(self.store.stats["played"], 1)
        self.assertEqual(self.store.stats["best"], 150)
        self.assertEqual(window.world.score, 0)

    def test_a_game_never_started_is_not_counted(self):
        window = self.open()
        window.new_game()
        self.assertEqual(self.store.stats["played"], 0)


class TheOtherScreens(WindowBase):
    def test_the_record_builds_with_nothing_in_it(self):
        RecordPage(self.store)

    def test_the_record_builds_with_a_record(self):
        self.store.stats.update(
            {"played": 9, "best": 1400, "furthest": 3, "cleared": 12}
        )
        RecordPage(self.store)

    def test_the_window_can_push_it(self):
        window = self.open()
        window.show_record()
        pump(seconds=0.2)


if __name__ == "__main__":
    unittest.main()
