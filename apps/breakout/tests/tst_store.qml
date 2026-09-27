// The file, against the GTK version's test_store.py (0.1.0), case for case:
// what is written, what is read back, and what a bad one does.
//
// The case that is this app's own is what is *not* stored: the ball. The wall,
// the score and the lives come back, and the ball comes back on the bat.
import QtQuick
import QtTest
import "../Breakout.js" as B
import "../Store.js" as S

TestCase {
  name: "BreakoutStore"

  function sum(list) { var s = 0; for (var i = 0; i < list.length; i++) s += list[i]; return s }
  function roundTrip(store) { return S.parse(JSON.parse(S.serialize(store))) }

  // A third of the wall down, a life gone and the ball faster: { store, world }.
  function partPlayed() {
    var g = S.begin(S.fresh(), 0)
    var w = g.world
    for (var cell = 0; cell < w.bricks.length; cell++) {
      if (w.bricks[cell] && cell % 3 === 0) { w.bricks[cell] = 0; w.score += 10 }
    }
    w.lives = 2
    w.speed = 1.1
    return { store: S.remember(g.store, w), world: w }
  }

  function test_a_missing_file_is_the_first_wall_and_not_an_error() {
    var g = S.resume(S.parse(null))
    compare(g.store.level, 0)
    compare(g.world.lives, B.LIVES)
    compare(g.world.score, 0)
    compare(sum(g.world.bricks), sum(B.bricksOf(B.LEVELS[0])))
  }

  function test_a_new_game_starts_from_the_first_wall() {
    var p = partPlayed()
    var store = p.store
    store.level = 3
    var g = S.begin(store, 0)
    compare(g.store.level, 0)
    compare(g.world.score, 0)
    compare(g.world.lives, B.LIVES)
  }

  function test_the_wall_the_score_and_the_lives_come_back() {
    var p = partPlayed()
    var g = S.resume(roundTrip(p.store))
    compare(g.world.bricks, p.world.bricks)
    compare(g.world.score, p.world.score)
    compare(g.world.lives, p.world.lives)
    verify(g.world.speed >= p.world.speed)
  }

  function test_the_file_is_the_shape_store_py_wrote() {
    var raw = JSON.parse(S.serialize(partPlayed().store))
    compare(raw.schema, 1)
    compare(raw.game.level, 0)
    compare(raw.game.lives, 2)
    compare(raw.game.speed, 1.1)
    compare(raw.game.bricks.length, B.COLUMNS * B.ROWS)
    compare(Object.keys(raw.stats).sort(), ["best", "cleared", "furthest", "played"])
  }

  function test_the_ball_comes_back_on_the_bat() {
    var p = partPlayed()
    var w = p.world
    B.advance(w, 0.5)
    B.serve(w)
    B.advance(w, 0.4)
    var g = S.resume(roundTrip(S.remember(p.store, w)))
    verify(!g.world.served)
    verify(!B.ready(g.world))  // and it waits before it can be sent off
  }

  function test_a_wall_of_the_wrong_shape_is_dealt_fresh() {
    var store = S.parse({ game: { bricks: [1, 1, 1] } })
    compare(store.bricks, [])
    compare(sum(S.resume(store).world.bricks), sum(B.bricksOf(B.LEVELS[0])))
  }

  // A wall that does not fit the level it claims would put bricks on the
  // screen that the rules do not have.
  function test_a_brick_stronger_than_the_level_has_is_dealt_fresh() {
    var store = S.fresh()
    store.bricks = []
    for (var i = 0; i < B.COLUMNS * B.ROWS; i++) store.bricks.push(9)
    compare(S.resume(store).world.bricks, B.bricksOf(B.LEVELS[0]))
  }

  function test_an_already_cleared_wall_is_dealt_again() {
    var store = S.fresh()
    for (var i = 0; i < B.COLUMNS * B.ROWS; i++) store.bricks.push(0)
    verify(!B.cleared(S.resume(store).world))
  }

  function test_junk_in_the_fields_falls_back_rather_than_raising() {
    var store = S.parse({
      game: { level: "three", score: -5, lives: 99, speed: "fast", bricks: "wall" },
      stats: { best: "lots" }
    })
    compare(store.level, 0)
    compare(store.score, 0)
    compare(store.lives, B.LIVES)
    compare(store.speed, 0)
    compare(store.bricks, [])
    compare(store.stats.best, 0)
  }

  function test_a_file_that_is_not_an_object_is_ignored() {
    compare(S.parse([1, 2, 3]).bricks, [])
    compare(S.parse("x").bricks, [])
  }

  function test_clearing_one_carries_the_score_over() {
    var p = partPlayed()
    var g = S.nextLevel(p.store, p.world)
    compare(g.store.level, 1)
    compare(g.world.score, p.world.score)
    compare(g.world.lives, p.world.lives)
    compare(g.store.stats.cleared, 1)
    compare(g.store.bricks, B.bricksOf(B.LEVELS[1]))
  }

  function test_the_walls_have_names_and_come_round_again() {
    compare(S.levelCount(), B.LEVELS.length)
    compare(S.levelName(0), B.LEVELS[0].label)
    compare(S.levelName(S.levelCount()), B.LEVELS[0].label)
  }

  function test_a_game_that_ran_out_is_counted() {
    var p = partPlayed()
    p.world.lives = 0
    var store = S.record(p.store, p.world)
    compare(store.stats.played, 1)
    compare(store.stats.best, p.world.score)
    compare(store.stats.furthest, 1)
  }

  function test_the_best_score_only_goes_up() {
    var p = partPlayed()
    var store = p.store
    p.world.score = 500
    store = S.record(store, p.world)
    p.world.score = 200
    store = S.record(store, p.world)
    compare(store.stats.best, 500)
    p.world.score = 900
    store = S.record(store, p.world)
    compare(store.stats.best, 900)
  }

  function test_the_furthest_wall_is_how_many_were_reached() {
    var p = partPlayed()
    var store = p.store
    store.level = 3
    compare(S.record(store, p.world).stats.furthest, 4)
  }

  function test_nothing_changes_the_store_it_was_given() {
    var p = partPlayed()
    S.record(p.store, p.world)
    S.nextLevel(p.store, p.world)
    compare(p.store.stats.played, 0)
    compare(p.store.level, 0)
  }
}
