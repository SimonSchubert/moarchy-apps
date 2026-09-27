// The figure in progress and how every figure has gone before it, in the one
// JSON file the GTK version wrote: ~/.local/share/moarchy-pegsolitaire/
// pegsolitaire.json. A game left in 0.1.0 is the game found here.
//
// What is stored is the jump list, not the board: loading is playing, so a
// truncated or hand-edited file cannot describe a board legal play could not
// reach, and a bad tail is dropped.
//
// The record is per figure and its headline is the fewest pegs left, not a
// number of wins: peg solitaire is a puzzle, and what somebody gets better at
// is finishing with three instead of five. Nothing is recorded for a figure
// started over halfway -- backing up and trying a different third jump is how
// this game is played, and counting it would be counting thinking.
//
// Every function returns a new state and leaves its argument alone. Ported
// from the GTK version's store.py (0.1.0), case for case.
.pragma library

.import "Pegs.js" as P

var SCHEMA = 1

function int(value, fallback) {
  return typeof value === "number" && isFinite(value) ? Math.trunc(value) : fallback
}

// "best" is a minimum, so zero means "none finished yet".
function emptyRecord() { return { played: 0, best: 0, solved: 0, perfect: 0 } }

function fresh() {
  return { figure: P.DEFAULT_FIGURE, moves: [], finished: false, recorded: false, stats: ({}) }
}

function parse(data) {
  var out = fresh()
  if (!data || typeof data !== "object" || data.constructor === Array) return out
  var game = data.game
  if (game && typeof game === "object") {
    out.figure = P.FIGURE_KEYS.indexOf(game.figure) >= 0 ? game.figure : P.DEFAULT_FIGURE
    var list = []
    if (game.moves && game.moves.constructor === Array)
      for (var i = 0; i < game.moves.length; i++)
        if (typeof game.moves[i] !== "boolean") list.push(int(game.moves[i], -1))
    // Replayed, and cut at the first jump that will not play.
    out.moves = P.resume(out.figure, list).moves
    out.finished = !!game.finished
    out.recorded = !!game.recorded
  }
  var stats = data.stats
  if (stats && typeof stats === "object") {
    for (var key in stats) {
      if (P.FIGURE_KEYS.indexOf(key) < 0 || !stats[key] || typeof stats[key] !== "object") continue
      var entry = emptyRecord()
      for (var field in entry) entry[field] = Math.max(int(stats[key][field], 0), 0)
      out.stats[key] = entry
    }
  }
  return out
}

function serialize(state) {
  return JSON.stringify({
    schema: SCHEMA,
    game: {
      figure: state.figure,
      finished: !!state.finished,
      recorded: !!state.recorded,
      moves: state.moves
    },
    stats: state.stats
  }, null, 1) + "\n"
}

function copy(state) {
  var stats = ({})
  for (var k in state.stats) stats[k] = Object.assign({}, state.stats[k])
  return { figure: state.figure, moves: state.moves.slice(), finished: state.finished,
           recorded: state.recorded, stats: stats }
}

function begin(state, key) {
  var out = copy(state)
  out.figure = P.FIGURE_KEYS.indexOf(key) >= 0 ? key : P.DEFAULT_FIGURE
  out.moves = []
  out.finished = false
  out.recorded = false
  return out
}

// The same figure, from the top.
function again(state) { return begin(state, state.figure) }

function withMoves(state, moves) {
  var out = copy(state)
  out.moves = moves.slice()
  out.finished = P.over(P.resume(out.figure, out.moves))
  if (!out.finished) out.recorded = false
  return out
}

// One figure played until it would not move again.
function record(state, left, perfect) {
  if (!(left >= 1)) return state
  var out = copy(state)
  out.recorded = true
  var entry = out.stats[out.figure] || emptyRecord()
  entry.played += 1
  if (!entry.best || left < entry.best) entry.best = left
  if (left === 1) {
    entry.solved += 1
    if (perfect) entry.perfect += 1
  }
  out.stats[out.figure] = entry
  return out
}

function recordFor(state, key) { return state.stats[key] || emptyRecord() }

// "best" across figures means nothing -- one peg on the Cross and one on the
// whole board are not the same thing -- so the total's `best` is how many
// figures have been finished at all.
function totals(state) {
  var out = emptyRecord()
  var finished = 0
  for (var k in state.stats) {
    var e = state.stats[k]
    out.played += e.played || 0
    out.solved += e.solved || 0
    out.perfect += e.perfect || 0
    if (e.solved) finished += 1
  }
  out.best = finished
  return out
}

function figureLabel(key) { return P.figureFor(key).label }
