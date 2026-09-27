// The game in progress and what has been played before it, in the one JSON
// file 0.1.0 wrote: ~/.local/share/moarchy-chess/chess.json. A game left in
// the GTK app is the game found here.
//
// What is stored is the move list, written the way people write them:
//
//     "moves": ["e2e4", "e7e5", "g1f3", "b8c6"]
//
// Loading is playing, so a file that was truncated or edited cannot describe
// a board legal play could not reach, and a move that will not play is where
// the file stops being a game. Every function here returns a new state.
.pragma library

.import "Chess.js" as C
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

function emptyRecord() { return { played: 0, won: 0, lost: 0, drawn: 0, quickest: 0 } }

function fresh() {
  return { mode: SOLO, level: Ai.DEFAULT_LEVEL, human: C.WHITE, finished: false,
           moves: [], stats: ({}) }
}

// The file, read as leniently as store.py read it. `moves` are kept as far
// as they are strings; how far they play is the game's business (gameOf).
function parse(data) {
  var out = fresh()
  if (!data || typeof data !== "object" || data.constructor === Array) return out
  var g = data.game
  if (g && typeof g === "object") {
    if (g.moves && g.moves.constructor === Array)
      out.moves = g.moves.filter(function (m) { return typeof m === "string" })
    if (MODES.indexOf(g.mode) >= 0) out.mode = g.mode
    if (Ai.LEVEL_KEYS.indexOf(g.level) >= 0) out.level = g.level
    out.human = g.human === "black" ? C.BLACK : C.WHITE
    out.finished = !!g.finished
  }
  var stats = data.stats
  if (stats && typeof stats === "object") {
    for (var key in stats) {
      if (Ai.LEVEL_KEYS.indexOf(key) < 0 || !stats[key] || typeof stats[key] !== "object") continue
      var entry = emptyRecord()
      for (var field in entry) entry[field] = Math.max(int(stats[key][field], 0), 0)
      out.stats[key] = entry
    }
  }
  return out
}

function serialize(s) {
  return JSON.stringify({
    schema: SCHEMA,
    game: {
      mode: s.mode,
      level: s.level,
      human: s.human === C.BLACK ? "black" : "white",
      finished: !!s.finished,
      moves: s.moves
    },
    stats: s.stats
  }, null, 1) + "\n"
}

function copy(s) {
  var out = Object.assign({}, s)
  out.moves = s.moves.slice()
  var stats = ({})
  for (var k in s.stats) stats[k] = Object.assign({}, s.stats[k])
  out.stats = stats
  return out
}

// The game the moves play to, and the state trimmed to the part that played:
// { game, state }. What is kept is what gets saved back.
function gameOf(s) {
  var g = C.resumeUci(s.moves)
  var out = copy(s)
  out.moves = C.gameUci(g)
  return { game: g, state: out }
}

function remember(s, g, finished) {
  var out = copy(s)
  out.moves = C.gameUci(g)
  out.finished = !!finished
  return out
}

function begin(s, mode, level, human) {
  var out = copy(s)
  out.mode = MODES.indexOf(mode) >= 0 ? mode : SOLO
  out.level = Ai.LEVEL_KEYS.indexOf(level) >= 0 ? level : Ai.DEFAULT_LEVEL
  out.human = human === C.BLACK ? C.BLACK : C.WHITE
  out.moves = []
  out.finished = false
  return out
}

// One finished game against the computer into the level's record. Hotseat
// games are not recorded: two people at one phone have no answer to "how am
// I doing against Medium". `moves` is the winner's move count, and the
// quickest win is the shortest one.
function record(s, result, moves) {
  if (s.mode !== SOLO || RESULTS.indexOf(result) < 0) return s
  var out = copy(s)
  var entry = out.stats[out.level] || emptyRecord()
  entry.played += 1
  entry[result] += 1
  if (result === WON && moves) entry.quickest = entry.quickest ? Math.min(entry.quickest, moves) : moves
  out.stats[out.level] = entry
  return out
}

function recordFor(s, key) { return s.stats[key] || emptyRecord() }

function totals(s) {
  var out = emptyRecord()
  for (var k in s.stats) {
    var e = s.stats[k]
    out.played += e.played
    out.won += e.won
    out.lost += e.lost
    out.drawn += e.drawn
    if (e.quickest) out.quickest = out.quickest ? Math.min(out.quickest, e.quickest) : e.quickest
  }
  return out
}
