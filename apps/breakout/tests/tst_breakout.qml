// The world, against the GTK version's test_breakout.py (0.1.0), case for case.
//
// The test that earns its place is the tunnelling one. A ball at a width a
// second crosses a brick in under two frames, so one step per frame passes
// straight through the wall at the moments that decide a game -- and nothing
// about that shows in a screenshot or a log. It is checked by giving advance()
// a whole second at once and asking whether the ball came out the far side.
import QtQuick
import QtTest
import "../Breakout.js" as B

TestCase {
  name: "BreakoutWorld"

  readonly property real frame: 1 / 60

  // mulberry32: the same numbers on every run.
  function rng(seed) {
    var a = seed >>> 0
    return function () {
      a = (a + 0x6D2B79F5) >>> 0
      var t = a
      t = Math.imul(t ^ (t >>> 15), t | 1)
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296
    }
  }
  function uniform(r, lo, hi) { return lo + (hi - lo) * r() }
  function sum(list) { var s = 0; for (var i = 0; i < list.length; i++) s += list[i]; return s }
  function has(b, e) { return b.events.indexOf(e) >= 0 }

  // A world with nothing on the wall, for tests about the ball.
  function bare(changes) {
    var w = B.world(B.LEVELS[0])
    for (var i = 0; i < w.bricks.length; i++) w.bricks[i] = 0
    for (var k in changes) w[k] = changes[k]
    return w
  }

  // --- the levels

  function test_the_art_means_what_it_looks_like() {
    var bricks = B.bricksOf(B.LEVELS[0])
    compare(bricks.length, B.COLUMNS * B.ROWS)
    compare(bricks.filter(function (b) { return b > 0 }).length, 29)
    for (var l = 0; l < B.LEVELS.length; l++) {
      var all = B.bricksOf(B.LEVELS[l])
      for (var i = 0; i < all.length; i++) verify(all[i] >= 0 && all[i] < B.SCORE.length)
    }
  }

  function test_every_level_has_bricks_and_they_fit_the_field() {
    for (var l = 0; l < B.LEVELS.length; l++) {
      var level = B.LEVELS[l]
      var bricks = B.bricksOf(level)
      verify(bricks.filter(function (b) { return b > 0 }).length > 10, level.key)
      for (var cell = 0; cell < bricks.length; cell++) {
        if (!bricks[cell]) continue
        var r = B.brickRect(cell)
        verify(r.x >= 0)
        verify(r.x + r.w <= B.WIDTH + 1e-9)
        verify(r.y >= B.WALL_TOP)
        // ...and well clear of the bat, or the game opens already over.
        verify(r.y + r.h < B.BAT_Y - 0.3, level.key)
      }
    }
  }

  function test_the_walls_come_round_again_rather_than_running_out() {
    compare(B.levelAt(0).key, B.LEVELS[0].key)
    compare(B.levelAt(B.LEVELS.length).key, B.LEVELS[0].key)
    compare(B.levelAt(B.LEVELS.length + 2).key, B.LEVELS[2].key)
  }

  function test_every_level_has_a_distinct_key_and_label() {
    var keys = ({}), labels = ({})
    for (var l = 0; l < B.LEVELS.length; l++) { keys[B.LEVELS[l].key] = 1; labels[B.LEVELS[l].label] = 1 }
    compare(Object.keys(keys).length, B.LEVELS.length)
    compare(Object.keys(labels).length, B.LEVELS.length)
  }

  // --- serving

  function test_the_ball_sits_on_the_bat_until_it_is_sent_off() {
    var w = B.world(B.LEVELS[0])
    verify(!w.served)
    B.advance(w, 0.5)
    fuzzyCompare(w.ballY, B.BAT_Y - B.BALL - 0.014, 0.005)
    verify(B.ready(w))
    verify(B.serve(w))
    verify(w.served)
  }

  function test_it_will_not_be_sent_off_twice() {
    var w = B.world(B.LEVELS[0])
    B.advance(w, 0.5)
    B.serve(w)
    verify(!B.serve(w))
  }

  // So that the tap which ended the last life does not launch the next.
  function test_there_is_a_pause_before_it_can_be() {
    var w = B.world(B.LEVELS[0])
    verify(!B.ready(w))
    verify(!B.serve(w))
  }

  function test_the_ball_follows_the_bat_while_it_waits() {
    var w = B.world(B.LEVELS[0])
    B.aim(w, 0.2)
    fuzzyCompare(w.ballX, 0.2, 1e-6)
  }

  function test_the_bat_stays_on_the_field() {
    var w = B.world(B.LEVELS[0])
    B.aim(w, -5)
    fuzzyCompare(w.bat, B.BAT_W / 2, 1e-6)
    B.aim(w, 5)
    fuzzyCompare(w.bat, B.WIDTH - B.BAT_W / 2, 1e-6)
  }

  // --- bouncing

  function test_it_comes_off_each_wall() {
    var w = bare({ ballX: 0.5, ballY: 0.5, ballVx: -B.SPEED, ballVy: 0, served: true })
    verify(has(B.advance(w, 1.0), B.HIT_WALL))
    verify(w.ballVx > 0)

    w = bare({ ballX: 0.5, ballY: 0.5, ballVx: 0, ballVy: -B.SPEED, served: true })
    verify(has(B.advance(w, 1.0), B.HIT_WALL))
    verify(w.ballVy > 0)
  }

  function test_the_bat_sends_it_back_where_it_was_hit() {
    // Dead centre: straight back up.
    var w = bare({ ballX: 0.5, ballY: B.BAT_Y - 0.2, ballVx: 0, ballVy: B.SPEED, served: true, bat: 0.5 })
    B.advance(w, 0.5)
    verify(w.ballVy < 0)
    fuzzyCompare(w.ballVx, 0, 1e-3)

    // Hit near the right-hand end: back up and to the right.
    w = bare({ ballX: 0.5, ballY: B.BAT_Y - 0.2, ballVx: 0, ballVy: B.SPEED, served: true, bat: 0.5 - B.BAT_W * 0.4 })
    B.advance(w, 0.5)
    verify(w.ballVy < 0)
    verify(w.ballVx > 0)
  }

  function test_a_ball_going_up_is_not_caught_by_the_bat() {
    var w = bare({ ballX: 0.5, ballY: B.BAT_Y, ballVx: 0, ballVy: -B.SPEED, served: true, bat: 0.5 })
    verify(!has(B.advance(w, frame), B.HIT_BAT))
  }

  function test_a_ball_past_the_bottom_costs_a_life() {
    var w = bare({ ballX: 0.5, ballY: B.HEIGHT - 0.01, ballVx: 0, ballVy: B.SPEED, served: true, bat: 0.05 })
    verify(has(B.advance(w, 0.3), B.LOST_BALL))
    compare(w.lives, B.LIVES - 1)
    verify(!w.served)
  }

  function test_the_last_life_ends_the_game() {
    var w = bare({ ballX: 0.5, ballY: B.HEIGHT - 0.01, ballVx: 0, ballVy: B.SPEED, served: true, bat: 0.05, lives: 1 })
    B.advance(w, 0.3)
    verify(B.dead(w))
    compare(B.advance(w, 1.0).events.length, 0)
  }

  // --- the wall

  // A ball below a brick, travelling straight up at it.
  function aimedAt(cell) {
    var w = B.world(B.LEVELS[0])
    var r = B.brickRect(cell)
    w.ballX = r.x + B.BRICK_W / 2
    w.ballY = r.y + r.h + 0.6
    w.ballVx = 0
    w.ballVy = -B.SPEED
    w.served = true
    return w
  }

  // The brick a ball coming up this column meets first: the lowest one, not
  // the first in the list -- a ball going up reaches the bottom of a column
  // before its top.
  function lowestIn(column) {
    var bricks = B.bricksOf(B.LEVELS[0]), best = -1
    for (var c = 0; c < bricks.length; c++) if (bricks[c] && c % B.COLUMNS === column) best = c
    return best
  }

  function test_a_brick_is_broken_and_scores() {
    var cell = lowestIn(0)
    var w = aimedAt(cell)
    verify(has(B.advance(w, 1.0), B.HIT_BRICK))
    compare(w.bricks[cell], 0)
    compare(w.score, B.SCORE[1])
    verify(w.ballVy > 0)
  }

  function test_a_tough_brick_takes_more_than_one_hit() {
    var level = B.LEVELS.filter(function (l) { return B.bricksOf(l).some(function (b) { return b > 1 }) })[0]
    var cell = B.bricksOf(level).findIndex(function (b) { return b > 1 })
    var w = B.world(level)
    var r = B.brickRect(cell)
    for (var i = 0; i < w.bricks.length; i++) w.bricks[i] = 0
    w.bricks[cell] = 2
    w.ballX = r.x + B.BRICK_W / 2
    w.ballY = r.y + r.h + 0.4
    w.ballVx = 0
    w.ballVy = -B.SPEED
    w.served = true
    B.advance(w, 0.8)
    compare(w.bricks[cell], 1)
    compare(w.score, 0)
  }

  // A whole second in one call. Without slicing, the ball crosses the entire
  // wall between two positions and hits nothing at all.
  function test_the_ball_never_passes_through_the_wall() {
    var original = B.bricksOf(B.LEVELS[0])
    for (var cell = 0; cell < original.length; cell++) {
      if (!original[cell]) continue
      var w = aimedAt(cell)
      B.advance(w, 1.0)
      verify(sum(w.bricks) < sum(original), "missed brick " + cell)
      verify(w.ballY > B.WALL_TOP, "went through at " + cell)
    }
  }

  function test_clearing_the_wall_is_announced() {
    var w = bare({ ballVx: 0, ballVy: -B.SPEED, served: true })
    w.bricks[0] = 1
    var r = B.brickRect(0)
    w.ballX = r.x + B.BRICK_W / 2
    w.ballY = r.y + r.h + 0.4
    verify(has(B.advance(w, 1.0), B.CLEARED))
    verify(B.cleared(w))
  }

  // Through the real code rather than by setting the speed: a brick broken
  // makes the ball faster, and a brick broken at the cap does not.
  function test_the_ball_speeds_up_but_not_without_limit() {
    function breakOne(w, cell, speed) {
      w.bricks[cell] = 1
      var r = B.brickRect(cell)
      w.ballX = r.x + B.BRICK_W / 2
      w.ballY = r.y + r.h + 0.3
      w.ballVx = 0
      w.ballVy = -speed
      B.advance(w, 1.0)
    }
    var w = bare({ served: true })
    var before = w.speed
    breakOne(w, 0, B.SPEED)
    verify(w.speed > before)
    w.speed = B.SPEED_MAX
    breakOne(w, 1, B.SPEED_MAX)
    verify(w.speed <= B.SPEED_MAX)
  }

  // --- a whole game, played: the only way to know a physics engine works is
  // to run it for a few thousand frames and see whether anything escapes.

  function play(level, seed, frames) {
    var r = rng(seed)
    var w = B.world(level, 99)
    for (var i = 0; i < (frames || 60 * 400); i++) {
      if (B.cleared(w)) break
      B.aim(w, w.ballX + uniform(r, -0.05, 0.05))
      B.advance(w, frame)
      if (B.ready(w)) B.serve(w)
      if (w.ballX < -0.05 || w.ballX > B.WIDTH + 0.05 || w.ballY < -0.05)
        fail("the ball left the field at frame " + i)
    }
    return w
  }

  // A level nobody can finish has a brick where the ball cannot reach, which
  // is a bug in the art rather than a hard wall.
  function test_every_level_can_be_cleared() {
    for (var l = 0; l < B.LEVELS.length; l++)
      verify(B.cleared(play(B.LEVELS[l], 5)), B.LEVELS[l].key + " would not clear")
  }

  function test_the_ball_stays_on_the_field() {
    play(B.LEVELS[3], 2)
  }

  // Two seconds in one call, which is what a phone waking up looks like.
  function test_a_frame_the_compositor_lost_does_not_teleport_the_ball() {
    var w = B.world(B.LEVELS[0])
    B.advance(w, 0.5)
    B.serve(w)
    var before = sum(w.bricks)
    B.advance(w, 2.0)
    verify(before - sum(w.bricks) >= 1)
    verify(w.ballY <= B.HEIGHT + B.BALL + 0.1)
  }

  // --- carrying on

  function test_the_next_wall_keeps_the_score_the_lives_and_the_speed() {
    var w = B.world(B.LEVELS[0])
    w.score = 340
    w.lives = 2
    w.speed = 1.2
    w.bat = 0.3
    var next = B.carryOn(w, B.LEVELS[1])
    compare(next.score, 340)
    compare(next.lives, 2)
    compare(next.speed, 1.2)
    compare(next.bat, 0.3)
    compare(sum(next.bricks), sum(B.bricksOf(B.LEVELS[1])))
    verify(!next.served)
  }
}
