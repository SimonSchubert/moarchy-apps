// The game in progress and what has been played before it, in the one JSON
// file the GTK version wrote: ~/.local/share/moarchy-mill/mill.json. A game
// left in 0.1.0 is the game found here.
//
// What is stored is the move list, not the board: sixty small integers replay
// to exactly one position, so a truncated or hand-edited file cannot describe a
// board legal play could not reach. A bad tail is dropped.
//
// Every function here returns a new state and leaves its argument alone.
.pragma library

.import "Mill.js" as M
.import "Ai.js" as Ai

var SCHEMA = 1

// Against the computer there is a "you", so a result is a win or a loss;
// across a table there is not, and nothing is recorded.
var SOLO = "solo"
var HOTSEAT = "hotseat"
var MODES = [SOLO, HOTSEAT]

var WON = "won"
var LOST = "lost"
var DRAWN = "drawn"
var RESULTS = [WON, LOST, DRAWN]

function int(value, fallback) {
  return typeof value === "number" && isFinite(value) ? Math.trunc(value) : fallback
}

// `best` is the most pieces a win was won with: this game's version of a
// score. Winning with eight and winning with three are the same result and
// very different games.
function emptyRecord() { return { played: 0, won: 0, lost: 0, drawn: 0, best: 0 } }

function fresh() {
  return {
    mode: SOLO, level: Ai.DEFAULT_LEVEL, human: M.WHITE, finished: false,
    // Whether a finished game's result is in the record yet. Not `finished`:
    // the last move is saved the instant it is played and counted a moment
    // later, and a phone killed between the two comes back owed a result.
    recorded: false, moves: [], stats: ({})
  }
}

// The file, read as leniently as store.py read it.
function parse(data) {
  var out = fresh()
  if (!data || typeof data !== "object" || data.constructor === Array) return out
  var game = data.game
  if (game && typeof game === "object") {
    var list = []
    if (game.moves && game.moves.constructor === Array)
      for (var i = 0; i < game.moves.length; i++)
        if (typeof game.moves[i] !== "boolean") list.push(int(game.moves[i], 0))
    out.moves = M.resume(list).moves
    if (MODES.indexOf(game.mode) >= 0) out.mode = game.mode
    if (Ai.LEVEL_KEYS.indexOf(game.level) >= 0) out.level = game.level
    out.human = game.human === "black" ? M.BLACK : M.WHITE
    out.finished = !!game.finished
    out.recorded = !!game.recorded
  }
  var stats = data.stats
  if (stats && typeof stats === "object") {
    for (var level in stats) {
      if (Ai.LEVEL_KEYS.indexOf(level) < 0 || !stats[level] || typeof stats[level] !== "object") continue
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
      human: state.human === M.BLACK ? "black" : "white",
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

function begin(state, mode, level, human) {
  var out = copy(state)
  out.mode = MODES.indexOf(mode) >= 0 ? mode : SOLO
  out.level = Ai.LEVEL_KEYS.indexOf(level) >= 0 ? level : Ai.DEFAULT_LEVEL
  out.human = human === M.BLACK ? M.BLACK : M.WHITE
  out.moves = []
  out.finished = false
  out.recorded = false
  return out
}

function withMoves(state, moves) {
  var out = copy(state)
  out.moves = moves.slice()
  out.finished = M.gameOver(M.resume(moves))
  if (!out.finished) out.recorded = false
  return out
}

// One finished game against the computer, into its level's record. Hotseat
// games are not recorded: the tally answers "how am I doing against Medium".
function record(state, result, margin) {
  if (state.mode !== SOLO || RESULTS.indexOf(result) < 0) return state
  var out = copy(state)
  out.recorded = true
  var entry = out.stats[out.level] || emptyRecord()
  entry.played += 1
  entry[result] += 1
  if (result === WON) entry.best = Math.max(entry.best, margin || 0)
  out.stats[out.level] = entry
  return out
}

// A finished game whose result has been said, with nothing to count: a
// hotseat game, so reopening it does not announce it again.
function settled(state) {
  var out = copy(state)
  out.recorded = true
  return out
}

// The result on the board, for the person: won, lost or drawn, and how many
// pieces they won with.
function resultOf(state) {
  var g = M.resume(state.moves)
  if (M.drawn(g)) return { result: DRAWN, margin: 0 }
  var w = M.winner(g.position)
  if (w === null) return { result: DRAWN, margin: 0 }
  if (w === state.human) return { result: WON, margin: M.count(g.position, state.human) }
  return { result: LOST, margin: 0 }
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
