// Can this position still be finished, and what is the next jump if it can?
//
// Peg solitaire is the one game here where the hard question is not "what is
// a good move" but "have I already lost". A board with twenty pegs and no way
// to reach one looks exactly like a board with a way, so the hint is a search
// and not a heuristic, and it gives one of three answers:
//
//     solved       there is a way from here; `line` is one, first jump first
//     impossible   proved: every line from here ends with more than one peg
//     unknown      the clock ran out before either was established
//
// On a clock, not a node budget: the same count is a proof on a laptop and a
// shrug on a PinePhone. The dead set is the whole optimisation -- a position
// shown to lead nowhere leads nowhere however it was reached, and a great many
// orders of the same jumps reach the same position.
//
// Self-contained on purpose: it runs in a WorkerScript (solve.js), where a
// `.import` is not processed. The masks are Pegs.js's -- the sum of 2^cell --
// and inside the search a board is an array of booleans, played and unplayed
// in place, with the mask kept alongside as the dead set's key.
//
// Ported from the GTK version's solver.py (0.1.0).
.pragma library

var SOLVED = "solved"
var IMPOSSIBLE = "impossible"
var UNKNOWN = "unknown"

// How long a hint may take, and how often the clock is looked at.
var SECONDS = 2.0
var CHECK_EVERY = 512

var N = 7
var CELLS = 49
var P2 = (function () { var o = []; for (var i = 0; i < CELLS; i++) o.push(Math.pow(2, i)); return o })()

function bits(mask) {
  var out = []
  for (var i = 0; i < CELLS; i++) out.push(false)
  var m = mask
  for (var j = 0; j < CELLS && m > 0; j++) { out[j] = m % 2 === 1; m = Math.floor(m / 2) }
  return out
}

// Every jump the board allows, as [from, over, to, move], ascending by move --
// the order pegs.py's moves() returns, so the first line found is the same.
function jumpsOn(hole) {
  var steps = [[-1, 0], [1, 0], [0, -1], [0, 1]]
  var out = []
  for (var cell = 0; cell < CELLS; cell++) {
    if (!hole[cell]) continue
    var r = Math.floor(cell / N), c = cell % N
    for (var d = 0; d < 4; d++) {
      var r1 = r + steps[d][0], c1 = c + steps[d][1]
      var r2 = r + 2 * steps[d][0], c2 = c + 2 * steps[d][1]
      if (r2 < 0 || r2 >= N || c2 < 0 || c2 >= N) continue
      var over = r1 * N + c1, to = r2 * N + c2
      if (!hole[over] || !hole[to]) continue
      out.push([cell, over, to, cell * 4 + d])
    }
  }
  return out
}

// Look for a line that ends with one peg -- in `target` if it is >= 0.
// `clock` returns seconds; `seconds` is the budget.
function search(holes, pegs, target, seconds, clock) {
  var now = clock || function () { return Date.now() / 1000 }
  var budget = seconds === undefined ? SECONDS : seconds
  var peg = bits(pegs)
  var left = 0
  for (var i = 0; i < CELLS; i++) if (peg[i]) left++
  if (left === 1) {
    var ok = target < 0 || peg[target]
    return { verdict: ok ? SOLVED : IMPOSSIBLE, line: [], nodes: 0 }
  }
  if (budget <= 0) return { verdict: UNKNOWN, line: [], nodes: 0 }

  var jumps = jumpsOn(bits(holes))
  var dead = new Map()
  var line = []
  var nodes = 0
  var deadline = now() + budget
  var key = pegs
  var timedOut = false

  function walk() {
    nodes++
    if (nodes % CHECK_EVERY === 0 && now() > deadline) { timedOut = true; return false }
    if (left === 1) {
      if (target < 0) return true
      return peg[target] === true
    }
    if (dead.has(key)) return false
    for (var j = 0; j < jumps.length; j++) {
      var jp = jumps[j]
      if (!peg[jp[0]] || !peg[jp[1]] || peg[jp[2]]) continue
      peg[jp[0]] = false; peg[jp[1]] = false; peg[jp[2]] = true
      key = key - P2[jp[0]] - P2[jp[1]] + P2[jp[2]]
      left--
      line.push(jp[3])
      var found = walk()
      if (found) return true
      line.pop()
      left++
      key = key + P2[jp[0]] + P2[jp[1]] - P2[jp[2]]
      peg[jp[0]] = true; peg[jp[1]] = true; peg[jp[2]] = false
      if (timedOut) return false
    }
    // Only now: a position is dead when every jump out of it has been tried.
    dead.set(key, true)
    return false
  }

  var found = walk()
  if (timedOut) return { verdict: UNKNOWN, line: [], nodes: nodes }
  if (found) return { verdict: SOLVED, line: line.slice(), nodes: nodes }
  return { verdict: IMPOSSIBLE, line: [], nodes: nodes }
}

// The whole line, or null. For the tests: nothing in the app waits this long.
function solve(holes, pegs, target, seconds) {
  var a = search(holes, pegs, target, seconds === undefined ? 30 : seconds)
  return a.verdict === SOLVED ? a.line : null
}
