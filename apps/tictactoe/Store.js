// The game in progress, the series it belongs to, and the lifetime record, in
// the one JSON file the GTK version wrote: ~/.local/share/moarchy-tictactoe/
// tictactoe.json. A game left in 0.1.0 is the game found here.
//
// What is stored is the move list, not the board. Nine digits replay to exactly
// one position, so a file that was truncated or edited by hand cannot describe
// a board legal play could not reach: loading it is playing it, and a bad tail
// is dropped.
//
// The part that is this game's own is the **series**. A game lasts about
// fifteen seconds, so the unit somebody plays is a sitting -- five or six games
// one tap apart. The file keeps a running score across it; Play again keeps it
// and New game starts a fresh one. The two seats are "a" and "b", not X and O,
// because **a rematch swaps who plays X**: X moves first, first is worth
// something against anybody short of perfect, and a series scored by mark
// would be scoring the advantage rather than the players.
//
// Every function here returns a new state and leaves its argument alone.
.pragma library

.import "Tictactoe.js" as T

var SCHEMA = 1

var SOLO = "solo"
var HOTSEAT = "hotseat"
var MODES = [SOLO, HOTSEAT]

// Every result is from seat A's point of view. Seat A is you in a solo game
// and player one in a hotseat one, whichever mark it holds this game.
var WON = "won"
var LOST = "lost"
var DRAWN = "drawn"
var RESULTS = [WON, LOST, DRAWN]

var SEATS = { a: "One", b: "Two" }

function int(value, fallback) {
  return typeof value === "number" && isFinite(value) ? Math.trunc(value) : fallback
}

// "unbeaten" is the run of games in a row that were not lost, and "best" the
// longest such run. Wins are the wrong headline in this game: against Perfect
// there are none to be had, and a hundred draws is a person who has learnt it.
function emptyRecord() { return { played: 0, won: 0, lost: 0, drawn: 0, unbeaten: 0, best: 0 } }
function emptySeries() { return { a: 0, b: 0, drawn: 0 } }

function fresh() {
  return {
    mode: SOLO, level: T.DEFAULT_LEVEL, mark: T.CROSS,
    finished: false,
    // Whether the finished game's result is in the tallies yet. Not the same
    // as `finished`: the last move is saved the instant it is played and the
    // result counted a moment later, and a phone killed between the two would
    // otherwise come back to a result nothing ever counted.
    recorded: false,
    moves: [], series: emptySeries(), stats: ({})
  }
}

// The file, read as leniently as store.py read it: anything out of range falls
// back to its default rather than refusing the whole file.
function parse(data) {
  var out = fresh()
  if (!data || typeof data !== "object") return out
  var game = data.game
  if (game && typeof game === "object") {
    if (MODES.indexOf(game.mode) >= 0) out.mode = game.mode
    if (T.LEVEL_KEYS.indexOf(game.level) >= 0) out.level = game.level
    // "x"/"o", as store.py wrote it, so the file stays readable by a person.
    out.mark = game.mark === "o" ? T.NOUGHT : T.CROSS
    out.finished = !!game.finished
    out.recorded = !!game.recorded
    var list = []
    if (game.moves && game.moves.constructor === Array)
      for (var i = 0; i < game.moves.length; i++)
        if (typeof game.moves[i] !== "boolean") list.push(int(game.moves[i], -1))
    // Replayed, and cut at the first move that will not play.
    var kept = []
    var p = T.EMPTY
    for (var j = 0; j < list.length; j++) {
      if (T.isOver(p) || !T.isLegal(p, list[j])) break
      p = T.play(p, list[j])
      kept.push(list[j])
    }
    out.moves = kept
  }
  var series = data.series
  if (series && typeof series === "object") {
    var s = emptySeries()
    for (var key in s) s[key] = Math.max(int(series[key], 0), 0)
    out.series = s
  }
  var stats = data.stats
  if (stats && typeof stats === "object") {
    for (var level in stats) {
      if (T.LEVEL_KEYS.indexOf(level) < 0 || !stats[level] || typeof stats[level] !== "object") continue
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
      mark: state.mark === T.NOUGHT ? "o" : "x",
      finished: !!state.finished,
      recorded: !!state.recorded,
      moves: state.moves
    },
    series: state.series,
    stats: state.stats
  }, null, 1) + "\n"
}

function copy(state) {
  var out = ({})
  for (var k in state) out[k] = state[k]
  out.moves = state.moves.slice()
  out.series = Object.assign({}, state.series)
  var stats = ({})
  for (var level in state.stats) stats[level] = Object.assign({}, state.stats[level])
  out.stats = stats
  return out
}

// A new game, and a new series with it. A score of 4-2 across a change of
// difficulty is two different questions added together.
function begin(state, mode, level, mark) {
  var out = copy(state)
  out.mode = MODES.indexOf(mode) >= 0 ? mode : SOLO
  out.level = T.LEVEL_KEYS.indexOf(level) >= 0 ? level : T.DEFAULT_LEVEL
  out.mark = mark === T.NOUGHT ? T.NOUGHT : T.CROSS
  out.moves = []
  out.finished = false
  out.recorded = false
  out.series = emptySeries()
  return out
}

// Another game on the same terms, with the marks swapped -- which is the
// whole point of the button, and why two people with a pencil take turns.
function rematch(state) {
  var out = copy(state)
  out.mark = T.other(state.mark)
  out.moves = []
  out.finished = false
  out.recorded = false
  return out
}

function withMoves(state, moves) {
  var out = copy(state)
  out.moves = moves.slice()
  out.finished = T.isOver(T.replay(moves))
  if (!out.finished) out.recorded = false
  return out
}

// One finished game, from seat A's point of view. The series counts both
// modes: two people across a table keep score too. The lifetime record counts
// only games against the computer -- it answers "how do I do against Fair".
function record(state, result) {
  if (RESULTS.indexOf(result) < 0) return state
  var out = copy(state)
  out.recorded = true
  out.series[result === WON ? "a" : result === LOST ? "b" : DRAWN] += 1
  if (out.mode !== SOLO) return out
  var entry = out.stats[out.level] || emptyRecord()
  entry.played += 1
  entry[result] += 1
  if (result === LOST) {
    entry.unbeaten = 0
  } else {
    entry.unbeaten += 1
    entry.best = Math.max(entry.best, entry.unbeaten)
  }
  out.stats[out.level] = entry
  return out
}

// The result of the game on the board, for seat A: won, lost or drawn.
function resultOf(state) {
  var w = T.winner(T.replay(state.moves))
  if (w === null) return DRAWN
  return w === state.mark ? WON : LOST
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
