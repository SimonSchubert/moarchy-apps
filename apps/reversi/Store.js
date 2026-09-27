// The game in progress and the record of games played, in the one JSON file
// the GTK version wrote: ~/.local/share/moarchy-reversi/reversi.json. A game
// left in 0.1.0 is the game found here.
//
// What is stored is the move list, not the board. Sixty small integers replay
// to exactly one position, so a file that has been truncated or edited by hand
// cannot describe a board legal play could not reach: loading it is playing
// it, and a bad tail is dropped.
//
// Every function here returns a new state and leaves its argument alone.
.pragma library

.import "Reversi.js" as R
.import "Ai.js" as Ai

var SCHEMA = 1

// Who the other player is. Against the computer there is a "you", so a result
// is a win or a loss; across a table there is not, and nothing is recorded.
var SOLO = "solo"
var HOTSEAT = "hotseat"
var MODES = [SOLO, HOTSEAT]

var WON = "won"
var LOST = "lost"
var DRAWN = "drawn"
var RESULTS = [WON, LOST, DRAWN]

var LEVEL_KEYS = ["easy", "medium", "hard"]

function int(value, fallback) {
  return typeof value === "number" && isFinite(value) ? Math.trunc(value) : fallback
}

function emptyRecord() { return { played: 0, won: 0, lost: 0, drawn: 0, best: 0 } }

function fresh() {
  return { mode: SOLO, level: Ai.DEFAULT_LEVEL, human: R.DARK, finished: false, moves: [], stats: ({}) }
}

// The file, read as leniently as store.py read it: anything out of range falls
// back to its default rather than refusing the whole file.
function parse(data) {
  var out = fresh()
  if (!data || typeof data !== "object" || data.constructor === Array) return out
  var game = data.game
  if (game && typeof game === "object") {
    var list = []
    if (game.moves && game.moves.constructor === Array)
      for (var i = 0; i < game.moves.length; i++)
        if (typeof game.moves[i] !== "boolean") list.push(int(game.moves[i], 0))
    out.moves = R.resume(list)
    if (MODES.indexOf(game.mode) >= 0) out.mode = game.mode
    if (LEVEL_KEYS.indexOf(game.level) >= 0) out.level = game.level
    out.human = game.human === "light" ? R.LIGHT : R.DARK
    out.finished = !!game.finished
  }
  var stats = data.stats
  if (stats && typeof stats === "object") {
    for (var level in stats) {
      if (LEVEL_KEYS.indexOf(level) < 0 || !stats[level] || typeof stats[level] !== "object") continue
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
      mode: state.mode,
      level: state.level,
      human: state.human === R.LIGHT ? "light" : "dark",
      finished: !!state.finished,
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

function begin(state, mode, level, human) {
  var out = copy(state)
  out.mode = MODES.indexOf(mode) >= 0 ? mode : SOLO
  out.level = LEVEL_KEYS.indexOf(level) >= 0 ? level : Ai.DEFAULT_LEVEL
  out.human = human === R.LIGHT ? R.LIGHT : R.DARK
  out.moves = []
  out.finished = false
  return out
}

function withMoves(state, moves) {
  var out = copy(state)
  out.moves = moves.slice()
  out.finished = R.isOver(R.replay(moves).position)
  return out
}

// One finished game against the computer, into its level's record. Two people
// passing a phone across a table are not in it: the tally answers "how am I
// doing against Medium". `best` is the biggest winning margin, not the last.
function record(state, result, margin) {
  if (state.mode !== SOLO || RESULTS.indexOf(result) < 0) return state
  var out = copy(state)
  var entry = out.stats[out.level] || emptyRecord()
  entry.played += 1
  entry[result] += 1
  if (result === WON) entry.best = Math.max(entry.best, margin || 0)
  out.stats[out.level] = entry
  return out
}

// The result on the board, for the person: won, lost or drawn, and the margin.
function resultOf(state) {
  var p = R.replay(state.moves).position
  var c = R.counts(p)
  var w = R.winner(p)
  return { result: w === null ? DRAWN : w === state.human ? WON : LOST, margin: Math.abs(c[0] - c[1]) }
}

function recordFor(state, level) { return state.stats[level] || emptyRecord() }

function totals(state) {
  var out = emptyRecord()
  for (var level in state.stats) {
    var e = state.stats[level]
    out.played += e.played
    out.won += e.won
    out.lost += e.lost
    out.drawn += e.drawn
    out.best = Math.max(out.best, e.best)
  }
  return out
}
