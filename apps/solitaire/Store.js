// The deal, the moves played on it, and what has been played before, in the
// one JSON file the GTK version wrote: ~/.local/share/moarchy-solitaire/
// solitaire.json. A deal left in 0.1.0 is the deal found here.
//
// What is stored is the deck and the move list, not the table: fifty-two
// integers and a few hundred triples replay to exactly one table, so a file
// that was truncated or edited cannot describe a table legal play could not
// reach. A bad tail is dropped. And the deal survives everything: a lost game
// is lost on a deal somebody can look at, and `moves: []` is the same deal
// again.
//
// Every function returns a new state and leaves its argument alone.
.pragma library

.import "Klondike.js" as K

var SCHEMA = 1
var WON = "won"
var LOST = "lost"
var RESULTS = [WON, LOST]

function int(value, fallback) {
  return typeof value === "number" && isFinite(value) ? Math.trunc(value) : fallback
}

// "best" is the fewest moves a game has been won in, zero until there has been
// one: there is no sensible starting value for a minimum.
function emptyRecord() { return { played: 0, won: 0, best: 0, streak: 0, longest: 0 } }

function key(draw) { return "draw" + draw }
function keys() { return K.DRAWS.map(key) }

function fresh(random) {
  return {
    deck: K.shuffled(random), draw: K.DEFAULT_DRAW, moves: [],
    finished: false,
    // Whether the finished game's result is in the tally yet. Not the same
    // as `finished`: a phone killed between the last move and the count would
    // otherwise come back to a win nothing counted.
    recorded: false,
    stats: ({})
  }
}

// The file, read as leniently as store.py read it: anything out of range falls
// back to its default. A deck with a card twice, or one short, is not a deck.
function parse(data, random) {
  var out = fresh(random)
  if (!data || typeof data !== "object" || data.constructor === Array) return out
  var game = data.game
  if (game && typeof game === "object") {
    if (K.isDeck(game.deck)) out.deck = game.deck.slice()
    out.draw = K.DRAWS.indexOf(game.draw) >= 0 ? game.draw : K.DEFAULT_DRAW
    if (game.moves && game.moves.constructor === Array) {
      for (var i = 0; i < game.moves.length; i++) {
        var m = K.moveOf(game.moves[i])
        if (m) out.moves.push(m)
      }
    }
    out.finished = !!game.finished
    out.recorded = !!game.recorded
  }
  var stats = data.stats
  if (stats && typeof stats === "object") {
    var ks = keys()
    for (var k in stats) {
      if (ks.indexOf(k) < 0 || !stats[k] || typeof stats[k] !== "object") continue
      var entry = emptyRecord()
      for (var field in entry) entry[field] = Math.max(int(stats[k][field], 0), 0)
      out.stats[k] = entry
    }
  }
  return out
}

function serialize(state) {
  return JSON.stringify({
    schema: SCHEMA,
    game: {
      draw: state.draw,
      finished: !!state.finished,
      recorded: !!state.recorded,
      deck: state.deck,
      moves: state.moves
    },
    stats: state.stats
  }, null, 1) + "\n"
}

function copy(state) {
  var out = ({})
  for (var k in state) out[k] = state[k]
  out.deck = state.deck.slice()
  out.moves = state.moves.map(function (m) { return m.slice() })
  var stats = ({})
  for (var s in state.stats) stats[s] = Object.assign({}, state.stats[s])
  out.stats = stats
  return out
}

// The game this state describes, replayed as far as it legally goes.
function game(state) { return K.resume(state.deck, state.draw, state.moves) }

// The state after the game moved on: its deck and moves, and whether it is won.
function remember(state, g) {
  var out = copy(state)
  out.deck = g.deck.slice()
  out.moves = g.moves.map(function (m) { return m.slice() })
  out.finished = K.won(g.table)
  return out
}

// A new deal. A new deck unless one is given.
function begin(state, draw, deck, random) {
  var out = copy(state)
  out.draw = K.DRAWS.indexOf(draw) >= 0 ? draw : K.DEFAULT_DRAW
  out.deck = deck ? deck.slice() : K.shuffled(random)
  out.moves = []
  out.finished = false
  out.recorded = false
  return out
}

// The same deal, from the top: a deal you have just lost is the one you want
// another go at, and the alternative is writing fifty-two numbers down.
function again(state) {
  var out = copy(state)
  out.moves = []
  out.finished = false
  out.recorded = false
  return out
}

// One finished game against this deal, at the setting it was dealt at. Kept
// per draw: draw one is winnable about four times in five and draw three is
// not, so one tally across both would mostly report which setting was in use.
function record(state, result, count) {
  if (RESULTS.indexOf(result) < 0) return state
  var out = copy(state)
  out.recorded = true
  var k = key(out.draw)
  var entry = out.stats[k] || emptyRecord()
  entry.played += 1
  if (result === WON) {
    entry.won += 1
    entry.streak += 1
    entry.longest = Math.max(entry.longest, entry.streak)
    if (count && (!entry.best || count < entry.best)) entry.best = count
  } else {
    entry.streak = 0
  }
  out.stats[k] = entry
  return out
}

// A deal left unfinished counts as a loss -- if it was ever started. Dealing,
// looking at it and dealing again is not a game anybody played.
function abandon(state) {
  if (state.moves.length && !state.finished && !state.recorded) return record(state, LOST)
  return state
}

function recordFor(state, draw) { return state.stats[key(draw)] || emptyRecord() }

function totals(state) {
  var out = emptyRecord()
  for (var k in state.stats) {
    var e = state.stats[k]
    out.played += e.played || 0
    out.won += e.won || 0
    out.longest = Math.max(out.longest, e.longest || 0)
    var best = e.best || 0
    if (best && (!out.best || best < out.best)) out.best = best
  }
  return out
}
