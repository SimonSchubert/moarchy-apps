// The computer player: alpha-beta over the bitboards, on a clock.
//
// Ported from the GTK version's ai.py (0.1.0). Three things shape it:
//
// **The depth is not decided in advance.** Every level names a number of
// seconds and a ceiling, and the search deepens one ply at a time until one of
// the two runs out -- so the same Hard is deeper on a laptop than on a
// PinePhone, and neither leaves somebody holding a phone that has stopped
// answering.
//
// **Nobody waits for a move they had no choice about.** A position with one
// legal move is answered at once.
//
// **A turn is not always one ply.** Closing a mill earns a removal made by the
// same side, so a child position can have the same player to move as its
// parent, and negamax's flip-the-sign is wrong exactly there. Every recursion
// asks whose turn the child is before negating. Getting it wrong produces a
// search that plays well until it makes a mill and then throws a piece away.
//
// `clock` is a function returning seconds, and `rand` one returning [0, 1): a
// test that cannot hold the clock and the dice still is a test that fails one
// run in five. The search runs in a WorkerScript (search.js), off the UI.
.pragma library

.import "Mill.js" as M

// What a piece is worth, and everything else against it.
var MAN = 100
// A closed mill: not material, the machine that takes material.
var MILL = 32
// Two of a line with the third empty. Cheap, because most never close.
var NEARLY = 11
// Being able to move at all, which in the endgame is most of the game.
var MOBILITY = 3
// An enemy piece with nowhere to go.
var BLOCKED = 5

var WIN = 100000

var LEVELS = [
  { key: "easy", label: "Easy", blurb: "Looks one move ahead, and often not that far.",
    seconds: 0.20, depth: 2, slack: 0.55 },
  { key: "medium", label: "Medium", blurb: "A second of thought. Will see a mill coming.",
    seconds: 0.9, depth: 6, slack: 0.12 },
  { key: "hard", label: "Hard", blurb: "Two seconds, as deep as they go. Take the mills.",
    seconds: 2.2, depth: 12, slack: 0.0 }
]
var LEVEL_KEYS = ["easy", "medium", "hard"]
var DEFAULT_LEVEL = "medium"

function levelFor(key) {
  for (var i = 0; i < LEVELS.length; i++) if (LEVELS[i].key === key) return LEVELS[i]
  return LEVELS[1]
}

var TIMEOUT = { timeout: true }

function millCount(board) { return M.millsOf(board) }

// Lines holding two of mine and nothing of theirs.
function nearly(mine, theirs) {
  var n = 0
  for (var i = 0; i < M.MILL_MASKS.length; i++) {
    var mask = M.MILL_MASKS[i]
    if (theirs & mask) continue
    if (M.popcount(mine & mask) === 2) n += 1
  }
  return n
}

function room(mine, theirs) {
  var free = M.FULL & ~(mine | theirs)
  var n = 0
  var list = M.spots(mine)
  for (var i = 0; i < list.length; i++) n += M.popcount(M.NEIGHBOUR_MASKS[list[i]] & free)
  return n
}

function stuck(mine, theirs) {
  var free = M.FULL & ~(mine | theirs)
  var n = 0
  var list = M.spots(mine)
  for (var i = 0; i < list.length; i++) if (!(M.NEIGHBOUR_MASKS[list[i]] & free)) n += 1
  return n
}

// What this position is worth to `colour`, in hundredths of a piece.
// Deliberately flat: on an A53 every term is positions a second not searched.
function evaluate(p, colour) {
  var them = M.other(colour)
  if (M.lost(p, colour)) return -WIN
  if (M.lost(p, them)) return WIN
  var mine = M.men(p, colour), theirs = M.men(p, them)
  var score = (M.popcount(mine) - M.popcount(theirs)) * MAN
  score += (millCount(mine) - millCount(theirs)) * MILL
  score += (nearly(mine, theirs) - nearly(theirs, mine)) * NEARLY
  // Mobility means nothing while every empty point is open to both sides.
  if (!M.placing(p, colour) && !M.placing(p, them)) {
    score += (room(mine, theirs) - room(theirs, mine)) * MOBILITY
    score += stuck(theirs, mine) * BLOCKED
  }
  return score
}

// Moves, with the ones that close a mill first: most of what move ordering
// buys here, for one cheap test a move.
function ordered(p) {
  var list = M.moves(p)
  if (p.removing) return list
  var keyed = list.map(function (move, i) {
    var u = M.unpack(move)
    return { move: move, key: M.closes(p, p.turn, u[1], u[0]) ? 0 : 1, i: i }
  })
  keyed.sort(function (a, b) { return (a.key - b.key) || (a.i - b.i) })
  return keyed.map(function (k) { return k.move })
}

// A finished or exhausted position, from the mover's side. The depth left is
// added to a decided game, so a win found sooner is worth more.
function leaf(p, depth) {
  var value = evaluate(p, p.turn)
  if (value >= WIN) return value + depth
  if (value <= -WIN) return value - depth
  return value
}

// Negamax, except where a turn does not change hands: every value is from the
// point of view of the side to move in the position it describes.
function search(p, depth, alpha, beta, deadline, clock) {
  if (clock() > deadline) throw TIMEOUT
  if (M.isOver(p) || depth <= 0) return leaf(p, depth)
  var list = ordered(p)
  if (!list.length) return leaf(p, depth)
  var best = -WIN * 2
  for (var i = 0; i < list.length; i++) {
    var child = M.play(p, list[i])
    var score = child.turn === p.turn
      ? search(child, depth - 1, alpha, beta, deadline, clock)
      : -search(child, depth - 1, -beta, -alpha, deadline, clock)
    if (score > best) best = score
    if (best > alpha) alpha = best
    if (alpha >= beta) break
  }
  return best
}

// A move chosen from the decent ones rather than the best one: every move
// within a piece of the best, which is an opponent that misses things rather
// than one that gives pieces away. `scored` is [[score, move], ...].
function casual(scored, rand) {
  if (!scored.length) return -1
  var top = -Infinity
  for (var i = 0; i < scored.length; i++) if (scored[i][0] > top) top = scored[i][0]
  var pool = []
  for (var j = 0; j < scored.length; j++) if (scored[j][0] >= top - MAN) pool.push(scored[j][1])
  if (!pool.length) pool = [scored[0][1]]
  return pool[Math.floor(rand() * pool.length)]
}

// The computer's move, or -1 on a board with nothing to play.
//
// Iterative deepening, keeping the best move from the last depth that
// finished: a depth abandoned halfway has looked at some moves and not others,
// and the best of those is a bias, not a result.
function choose(p, level, clock, rand) {
  var list = ordered(p)
  if (!list.length) return -1
  if (list.length === 1) return list[0]
  var tick = clock || function () { return Date.now() / 1000 }
  var dice = rand || Math.random
  var deadline = tick() + level.seconds
  var best = list[0]
  var scored = list.map(function (m) { return [0, m] })

  for (var depth = 1; depth <= level.depth; depth++) {
    var here = []
    try {
      var alpha = -WIN * 2
      for (var i = 0; i < list.length; i++) {
        var child = M.play(p, list[i])
        var score = child.turn === p.turn
          ? search(child, depth - 1, alpha, WIN * 2, deadline, tick)
          : -search(child, depth - 1, -WIN * 2, -alpha, deadline, tick)
        here.push([score, list[i]])
        if (score > alpha) alpha = score
      }
    } catch (e) {
      if (e === TIMEOUT) break
      throw e
    }
    scored = here
    // Best first next time round: the previous depth is the ordering for the
    // next one. A stable sort, as Python's is.
    var byScore = here.map(function (pair, k) { return { s: pair[0], m: pair[1], k: k } })
    byScore.sort(function (a, b) { return (b.s - a.s) || (a.k - b.k) })
    list = byScore.map(function (x) { return x.m })
    best = list[0]
    if (byScore[0].s >= WIN) break
  }

  if (level.slack && dice() < level.slack) return casual(scored, dice)
  return best
}
