// The game in progress, the clock on it, and the record behind it, in the one
// JSON file the GTK version wrote: ~/.local/share/moarchy-minesweeper/
// minesweeper.json. A board left in 0.1.0 is the board found here.
//
// What is stored is the level, a **seed** and the list of taps -- not the board
// and not the mines. Minesweeper.js puts the same mines back from the seed and
// the first tap, which keeps the file small, makes it impossible for it to
// describe a board that could not have been played, and means a person stuck at
// two in the morning cannot read the answer out of their own home directory.
//
// The clock is accumulated seconds, not a start time, because what it measures
// stops and starts: it only runs while the window is on screen.
//
// Every function here returns a new state and leaves its argument alone.
.pragma library

.import "Minesweeper.js" as M

var SCHEMA = 1
var WON = "won"
var LOST = "lost"
var RESULTS = [WON, LOST]

// Wide enough that two games in a row are never the same board, narrow enough
// to read in a file.
var SEED_MAX = 2147483647

function int(value, fallback) {
  return typeof value === "number" && isFinite(value) ? Math.trunc(value) : fallback
}

// "best" is a minimum in seconds, so zero means "never cleared one" rather
// than an instantaneous victory.
function emptyRecord() { return { played: 0, won: 0, best: 0, streak: 0, longest: 0 } }

function newSeed() { return Math.floor(Math.random() * SEED_MAX) }

function fresh() {
  return {
    level: M.DEFAULT_LEVEL, seed: newSeed(), moves: [], seconds: 0,
    finished: false,
    // Whether the finished game's result is counted yet. Not `finished`: the
    // last tap is saved the instant it is made and the result counted a moment
    // later, and a phone killed between the two owes the result on the way in.
    recorded: false,
    stats: ({})
  }
}

function mod(n, m) { return ((n % m) + m) % m }

// The file, read as leniently as store.py read it: anything out of range falls
// back rather than refusing the whole file.
function parse(data) {
  var out = fresh()
  if (!data || typeof data !== "object" || data.constructor === Array) return out
  var game = data.game
  if (game && typeof game === "object") {
    if (M.LEVEL_KEYS.indexOf(game.level) >= 0) out.level = game.level
    out.seed = mod(int(game.seed, out.seed), SEED_MAX)
    var list = []
    if (game.moves && game.moves.constructor === Array)
      for (var i = 0; i < game.moves.length; i++)
        if (typeof game.moves[i] !== "boolean") list.push(int(game.moves[i], -1))
    // Replayed, and cut at the first move that will not play.
    out.moves = M.create(M.levelFor(out.level), out.seed, list).moves
    out.seconds = Math.max(int(game.seconds, 0), 0)
    out.finished = !!game.finished
    out.recorded = !!game.recorded
  }
  var stats = data.stats
  if (stats && typeof stats === "object") {
    for (var level in stats) {
      if (M.LEVEL_KEYS.indexOf(level) < 0 || !stats[level] || typeof stats[level] !== "object") continue
      var entry = emptyRecord()
      for (var field in entry) entry[field] = Math.max(int(stats[level][field], 0), 0)
      out.stats[level] = entry
    }
  }
  return out
}

function serialize(state) {
  return JSON.stringify({
    schema: SCHEMA,
    game: {
      level: state.level,
      seed: state.seed,
      seconds: state.seconds,
      finished: !!state.finished,
      recorded: !!state.recorded,
      moves: state.moves
    },
    stats: state.stats
  }, null, 1) + "\n"
}

function copy(state) {
  var out = ({})
  for (var k in state) out[k] = state[k]
  out.moves = state.moves.slice()
  var stats = ({})
  for (var level in state.stats) stats[level] = Object.assign({}, state.stats[level])
  out.stats = stats
  return out
}

// The game on the board, built from the file's seed and taps.
function game(state) { return M.create(M.levelFor(state.level), state.seed, state.moves) }

// A new board. `seed` is given for "this board again" -- the same mines, which
// is what everybody wants after losing one.
function begin(state, level, seed) {
  var out = copy(state)
  out.level = M.LEVEL_KEYS.indexOf(level) >= 0 ? level : M.DEFAULT_LEVEL
  out.seed = seed === undefined || seed === null ? newSeed() : mod(int(seed, 0), SEED_MAX)
  out.moves = []
  out.seconds = 0
  out.finished = false
  out.recorded = false
  return out
}

function withMoves(state, moves) {
  var out = copy(state)
  out.moves = moves.slice()
  out.finished = M.isOver(game(out))
  return out
}

function withSeconds(state, seconds) {
  var out = copy(state)
  out.seconds = Math.max(0, Math.floor(seconds))
  return out
}

// One finished game at the level it was played at. The fastest clear only
// ever goes down; a loss ends the run of clears.
function record(state, result, seconds) {
  if (RESULTS.indexOf(result) < 0) return state
  var out = copy(state)
  out.recorded = true
  var entry = out.stats[out.level] || emptyRecord()
  entry.played += 1
  if (result === WON) {
    entry.won += 1
    entry.streak += 1
    entry.longest = Math.max(entry.longest, entry.streak)
    if (seconds && (!entry.best || seconds < entry.best)) entry.best = seconds
  } else {
    entry.streak = 0
  }
  out.stats[out.level] = entry
  return out
}

function recordFor(state, level) { return state.stats[level] || emptyRecord() }

function totals(state) {
  var out = emptyRecord()
  for (var level in state.stats) {
    var e = state.stats[level]
    out.played += e.played
    out.won += e.won
    out.longest = Math.max(out.longest, e.longest)
  }
  return out
}
