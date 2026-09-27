// The game in progress, and the best there has been, in the one JSON file the
// GTK version wrote: ~/.local/share/moarchy-breakout/breakout.json. A wall
// left half-broken in 0.1.0 is the wall found here.
//
// What is stored is **the wall, the score, the lives and which level it is**,
// and deliberately not the ball. A ball has a position and a velocity in the
// middle of a physics step, and an app that saved them would come back with a
// ball frozen above the bat travelling left -- which is not where anybody left
// it and not a state anybody can take over. So a game picked up again comes
// back with the ball on the bat, waiting to be sent off.
//
// Saving happens when something discrete happens -- a brick falls, a life
// goes, a level is cleared, the window closes -- never once a frame.
//
// A store is a plain object; every function here returns a new one.
.pragma library

.import "Breakout.js" as B

var SCHEMA = 1

function int(value, fallback) {
  return typeof value === "number" && isFinite(value) ? Math.trunc(value) : fallback
}

function emptyRecord() { return { played: 0, best: 0, furthest: 0, cleared: 0 } }

function fresh() {
  return { level: 0, score: 0, lives: B.LIVES, speed: 0, bricks: [], stats: emptyRecord() }
}

// A wall of the right shape, or [] for one that is not.
function wall(value) {
  if (!value || value.constructor !== Array || value.length !== B.COLUMNS * B.ROWS) return []
  var out = []
  for (var i = 0; i < value.length; i++) {
    var v = value[i]
    if (typeof v !== "number" || v !== Math.floor(v) || v < 0) return []
    out.push(v)
  }
  return out
}

// The file, read as leniently as store.py read it: anything out of range
// falls back rather than refusing the whole file.
function parse(data) {
  var out = fresh()
  if (!data || typeof data !== "object" || data.constructor === Array) return out
  var game = data.game
  if (game && typeof game === "object") {
    out.level = Math.max(int(game.level, 0), 0)
    out.score = Math.max(int(game.score, 0), 0)
    out.lives = Math.min(Math.max(int(game.lives, B.LIVES), 0), B.LIVES)
    out.speed = typeof game.speed === "number" && isFinite(game.speed) ? game.speed : 0
    out.bricks = wall(game.bricks)
  }
  var stats = data.stats
  if (stats && typeof stats === "object") {
    var entry = emptyRecord()
    for (var k in entry) entry[k] = Math.max(int(stats[k], 0), 0)
    out.stats = entry
  }
  return out
}

function serialize(store) {
  return JSON.stringify({
    schema: SCHEMA,
    game: {
      level: store.level,
      score: store.score,
      lives: store.lives,
      speed: Math.round(store.speed * 10000) / 10000,
      bricks: store.bricks
    },
    stats: store.stats
  }, null, 1) + "\n"
}

function copy(store) {
  return {
    level: store.level, score: store.score, lives: store.lives, speed: store.speed,
    bricks: store.bricks.slice(), stats: Object.assign({}, store.stats)
  }
}

// Is every saved brick one this level actually has, and no stronger?
function fits(bricks, w) {
  for (var i = 0; i < bricks.length; i++)
    if (!(bricks[i] >= 0 && bricks[i] <= w.strength[i])) return false
  return true
}

// A new game from this wall: { store, world }.
function begin(store, level) {
  var out = copy(store)
  out.level = Math.max(level || 0, 0)
  out.score = 0
  out.lives = B.LIVES
  out.speed = 0
  var w = B.world(B.levelAt(out.level), B.LIVES)
  out.bricks = w.bricks.slice()
  return { store: out, world: w }
}

// Put the saved wall back, with the ball on the bat: { store, world }. A
// wall that does not fit the level it claims is dealt fresh -- the bricks on
// the screen and the bricks in the rules must be one set -- and a wall already
// down or a game already lost starts the game again.
function resume(store) {
  var w = B.world(B.levelAt(store.level), store.lives || B.LIVES)
  w.score = store.score
  if (store.speed) w.speed = Math.max(store.speed, w.speed)
  if (store.bricks.length === B.COLUMNS * B.ROWS && fits(store.bricks, w)) w.bricks = store.bricks.slice()
  if (B.cleared(w) || B.dead(w)) return begin(store, 0)
  return { store: copy(store), world: w }
}

function remember(store, w) {
  var out = copy(store)
  out.score = w.score
  out.lives = w.lives
  out.speed = w.speed
  out.bricks = w.bricks.slice()
  return out
}

// The next wall, with what survives a level brought over: { store, world }.
function nextLevel(store, w) {
  var out = copy(store)
  out.level += 1
  out.stats.cleared += 1
  var next = B.carryOn(w, B.levelAt(out.level))
  return { store: remember(out, next), world: next }
}

// One game that ran out of lives -- or was given up with points on it.
function record(store, w) {
  var out = copy(store)
  out.stats.played += 1
  out.stats.best = Math.max(out.stats.best, w.score)
  out.stats.furthest = Math.max(out.stats.furthest, out.level + 1)
  return out
}

function levelName(number) { return B.levelAt(number).label }
function levelCount() { return B.LEVELS.length }
