// The two games in progress, and the record behind them, in the one JSON file
// the GTK version wrote: ~/.local/share/moarchy-fiveletters/fiveletters.json.
// A streak kept in 0.1.0 is the streak found here.
//
// What is stored is the guesses, not the board: loading is playing, so a file
// that was truncated or edited cannot describe a board play could not reach.
// Neither secret is in the file -- the day's word is a function of the date
// and a practice word of a seed -- so the answer is not sitting in a text file
// waiting to be read at two in the morning.
//
// **A streak is consecutive days solved, and the day you skip is the day it
// ends** -- as surely as the day you miss. That is why `last` is a date.
//
// Every function returns a new state and leaves its argument alone.
.pragma library

.import "Game.js" as G
.import "Words.js" as W

var SCHEMA = 1
var DAILY = "daily"
var PRACTICE = "practice"
var MODES = [DAILY, PRACTICE]
var SEED_MAX = 2147483647

function int(value, fallback) {
  return typeof value === "number" && isFinite(value) ? Math.trunc(value) : fallback
}

function randomSeed() { return Math.floor(Math.random() * SEED_MAX) }

function emptyStats() {
  // spread: days solved in one guess, two, ... six.
  return { played: 0, won: 0, streak: 0, best: 0, spread: [0, 0, 0, 0, 0, 0], last: "" }
}

function fresh(seed) {
  return { mode: DAILY, day: "", daily: [], seed: seed === undefined ? randomSeed() : seed,
           practice: [], stats: emptyStats() }
}

function wordsOf(value) {
  if (!value || value.constructor !== Array) return []
  var out = []
  for (var i = 0; i < value.length; i++) {
    if (typeof value[i] !== "string") continue
    var w = value[i].trim().toUpperCase()
    if (G.WORD.test(w)) out.push(w)
  }
  return out.slice(0, G.GUESSES)
}

// The file, read as leniently as store.py read it.
function parse(data, seed) {
  var s = fresh(seed)
  if (!data || typeof data !== "object" || data.constructor === Array) return s
  if (MODES.indexOf(data.mode) >= 0) s.mode = data.mode
  var d = data.daily
  if (d && typeof d === "object") {
    s.day = typeof d.day === "string" ? d.day : ""
    s.daily = wordsOf(d.guesses)
  }
  var p = data.practice
  if (p && typeof p === "object") {
    s.seed = ((int(p.seed, s.seed) % SEED_MAX) + SEED_MAX) % SEED_MAX
    s.practice = wordsOf(p.guesses)
  }
  var st = data.stats
  if (st && typeof st === "object") {
    var e = emptyStats()
    var fields = ["played", "won", "streak", "best"]
    for (var i = 0; i < fields.length; i++) e[fields[i]] = Math.max(int(st[fields[i]], 0), 0)
    if (st.spread && st.spread.constructor === Array) {
      for (var j = 0; j < G.GUESSES; j++) e.spread[j] = Math.max(int(st.spread[j], 0), 0)
    }
    e.last = typeof st.last === "string" ? st.last : ""
    s.stats = e
  }
  return s
}

function serialize(s) {
  return JSON.stringify({
    schema: SCHEMA,
    mode: s.mode,
    daily: { day: s.day, guesses: s.daily },
    practice: { seed: s.seed, guesses: s.practice },
    stats: s.stats
  }, null, 1) + "\n"
}

function copy(s) {
  var o = ({})
  for (var k in s) o[k] = s[k]
  o.daily = s.daily.slice()
  o.practice = s.practice.slice()
  o.stats = Object.assign({}, s.stats)
  o.stats.spread = s.stats.spread.slice()
  return o
}

// Has the day changed under the saved game? Then yesterday's board goes: with
// today's word on it, it would be green squares that mean nothing.
function rollOver(s, day) {
  if (s.day === day) return s
  var o = copy(s)
  o.day = day
  o.daily = []
  return o
}

// The game the app is showing, replayed from its guesses. Call rollOver first.
function game(s, words, day) {
  if (s.mode === PRACTICE) return G.make(W.practice(words, s.seed), words.guesses, s.practice)
  return G.make(W.daily(words, day), words.guesses, s.daily)
}

function remember(s, g) {
  var o = copy(s)
  if (o.mode === PRACTICE) o.practice = G.words(g)
  else o.daily = G.words(g)
  return o
}

function beginPractice(s, seed) {
  var o = copy(s)
  o.mode = PRACTICE
  o.seed = seed === undefined ? randomSeed() : ((seed % SEED_MAX) + SEED_MAX) % SEED_MAX
  o.practice = []
  return o
}

function showDaily(s) {
  var o = copy(s)
  o.mode = DAILY
  return o
}

function broken(s, day) {
  var last = s.stats.last || ""
  if (!last) return true
  var a = W.ordinal(day), b = W.ordinal(last)
  if (isNaN(a) || isNaN(b)) return true
  return a - b > 1
}

function counted(s, day) { return s.stats.last === day }

// One finished day. Practice is not recorded at all: a streak is a statement
// about days, not about how many goes somebody had.
function record(s, g, day) {
  if (s.mode !== DAILY || !G.over(g)) return s
  if (s.stats.last === day) return s
  var o = copy(s)
  var gap = broken(s, day)
  o.stats.played += 1
  o.stats.last = day
  if (G.solved(g)) {
    o.stats.won += 1
    o.stats.spread[G.used(g) - 1] += 1
    o.stats.streak = gap ? 1 : o.stats.streak + 1
    o.stats.best = Math.max(o.stats.best, o.stats.streak)
  } else {
    o.stats.streak = 0
  }
  return o
}

function rate(s) {
  return s.stats.played ? Math.round(100 * s.stats.won / s.stats.played) : 0
}

// The board as squares: spoiler-free by construction, for the clipboard.
function share(g, number) {
  var marks = [String.fromCodePoint(0x2B1B), String.fromCodePoint(0x1F7E8), String.fromCodePoint(0x1F7E9)]
  var score = G.solved(g) ? String(G.used(g)) : "X"
  var lines = ["Five Letters " + number + " " + score + "/" + G.GUESSES, ""]
  for (var i = 0; i < g.guesses.length; i++)
    lines.push(g.guesses[i].marks.map(function (m) { return marks[m] }).join(""))
  return lines.join("\n") + "\n"
}
