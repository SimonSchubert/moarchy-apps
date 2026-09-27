// The two word lists, and which word today is.
//
// A word game is its word list, and this one has two: the words that may be
// the secret, filtered hard, and the words that may be a guess, barely
// filtered at all -- being told "not in word list" for a real word is the most
// annoying thing this kind of game does. Both are in Lists.js.
//
// Ported from the GTK version's words.py (0.1.0): the same lists, and the same
// arithmetic for the day's word, so a day has the same word in both.
.pragma library

.import "Game.js" as G
.import "Lists.js" as L

// The last resort, if the lists are ever empty: enough for the window to open
// and say so, not a game.
var SPARE = ["ABOUT", "ALERT", "BRAVE", "CHAIR", "CRANE", "DREAM",
             "FLINT", "GHOST", "LIGHT", "MONTH", "PLUMB", "STORM"]

// Only the well-formed words out of whatever this is, upper-cased.
function clean(list) {
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (typeof list[i] !== "string") continue
    var w = list[i].trim().toUpperCase()
    if (G.WORD.test(w)) out.push(w)
  }
  return out
}

// The lists: { answers: [...], guesses: {WORD: true}, complete }. Every answer
// is a legal guess whatever the lists say: a secret the keyboard will not
// accept is a game nobody can finish.
function make(answers, guesses) {
  var a = clean(answers)
  var complete = a.length > SPARE.length
  if (!a.length) a = SPARE.slice()
  var set = ({})
  var g = clean(guesses)
  for (var i = 0; i < g.length; i++) set[g[i]] = true
  for (var j = 0; j < a.length; j++) set[a[j]] = true
  return { answers: a, guesses: set, complete: complete }
}

var cached = null
function all() {
  if (!cached) cached = make(L.ANSWERS.split("\n"), L.GUESSES.split("\n"))
  return cached
}

function allows(words, word) { return words.guesses[String(word).toUpperCase()] === true }

// Python's date.toordinal() for "YYYY-MM-DD": 1 for 0001-01-01.
function ordinal(iso) {
  var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(iso))
  if (!m) return NaN
  var t = Date.UTC(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10))
  return Math.round(t / 86400000) + 719163
}

// A multiply-and-add rather than the day number: the list is sorted, and
// `days % n` would walk the alphabet. Exact in a double: the product is under
// 2^53 for any date this side of the year 20000.
function index(words, iso) {
  return (ordinal(iso) * 1103515245 + 12345) % words.answers.length
}

function daily(words, iso) { return words.answers[index(words, iso)] }
function practice(words, seed) { return words.answers[seed % words.answers.length] }

function iso(d) {
  function two(n) { return (n < 10 ? "0" : "") + n }
  return d.getFullYear() + "-" + two(d.getMonth() + 1) + "-" + two(d.getDate())
}

// Today, or the day the harness pinned (MOARCHY_FIVELETTERS_TODAY), so a
// picture taken on a Sunday and one taken on a Monday agree about the word.
function today(pinned) {
  if (pinned && !isNaN(ordinal(pinned))) return pinned
  return iso(new Date())
}

function addDays(isoDay, n) {
  var o = ordinal(isoDay) + n - 719163
  var d = new Date(o * 86400000)
  function two(x) { return (x < 10 ? "0" : "") + x }
  return d.getUTCFullYear() + "-" + two(d.getUTCMonth() + 1) + "-" + two(d.getUTCDate())
}
