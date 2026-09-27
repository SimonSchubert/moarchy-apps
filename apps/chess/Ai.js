// The computer player: alpha-beta with a quiescence search, on a clock.
//
// Ported from 0.1.0's ai.py, which took its shape from Braincup's
// NormalChessAi: the same piece-square tables, MVV/LVA ordering, captures-only
// search past the horizon, and the deliberate beginner's blunder that makes
// Easy easy. A level names a number of seconds and a depth it will not exceed,
// and the search deepens one ply at a time until one of them runs out -- so
// Hard is a five-ply opponent on a laptop and a three-ply one on a PinePhone,
// and neither leaves somebody holding a device that has stopped answering.
//
// Nothing here builds a board: the search plays moves into one position and
// takes them back out, and carries the evaluation as a running total adjusted
// by what each move did (Chess.make's record).
//
// Runs in the search worker (search.js), where `.import` is not processed and
// `C` is set by hand before this file is included.
.pragma library

.import "Chess.js" as C

var VALUES = { 1: 100, 2: 300, 3: 320, 4: 500, 5: 900, 6: 0 }

// Piece-square tables, white's point of view, index 0 = a1.
var PAWN_PST = [
    0,   0,   0,   0,   0,   0,   0,   0,
    5,  10,  10, -20, -20,  10,  10,   5,
    5,  -5, -10,   0,   0, -10,  -5,   5,
    0,   0,   0,  20,  20,   0,   0,   0,
    5,   5,  10,  25,  25,  10,   5,   5,
   10,  10,  20,  30,  30,  20,  10,  10,
   50,  50,  50,  50,  50,  50,  50,  50,
    0,   0,   0,   0,   0,   0,   0,   0]
var KNIGHT_PST = [
  -50, -40, -30, -30, -30, -30, -40, -50,
  -40, -20,   0,   5,   5,   0, -20, -40,
  -30,   5,  10,  15,  15,  10,   5, -30,
  -30,   0,  15,  20,  20,  15,   0, -30,
  -30,   5,  15,  20,  20,  15,   5, -30,
  -30,   0,  10,  15,  15,  10,   0, -30,
  -40, -20,   0,   0,   0,   0, -20, -40,
  -50, -40, -30, -30, -30, -30, -40, -50]
var BISHOP_PST = [
  -20, -10, -10, -10, -10, -10, -10, -20,
  -10,   5,   0,   0,   0,   0,   5, -10,
  -10,  10,  10,  10,  10,  10,  10, -10,
  -10,   0,  10,  10,  10,  10,   0, -10,
  -10,   5,   5,  10,  10,   5,   5, -10,
  -10,   0,   5,  10,  10,   5,   0, -10,
  -10,   0,   0,   0,   0,   0,   0, -10,
  -20, -10, -10, -10, -10, -10, -10, -20]
var ROOK_PST = [
    0,   0,   0,   5,   5,   0,   0,   0,
   -5,   0,   0,   0,   0,   0,   0,  -5,
   -5,   0,   0,   0,   0,   0,   0,  -5,
   -5,   0,   0,   0,   0,   0,   0,  -5,
   -5,   0,   0,   0,   0,   0,   0,  -5,
   -5,   0,   0,   0,   0,   0,   0,  -5,
    5,  10,  10,  10,  10,  10,  10,   5,
    0,   0,   0,   0,   0,   0,   0,   0]
var QUEEN_PST = [
  -20, -10, -10,  -5,  -5, -10, -10, -20,
  -10,   0,   0,   0,   0,   0,   0, -10,
  -10,   5,   5,   5,   5,   5,   0, -10,
    0,   0,   5,   5,   5,   5,   0,  -5,
   -5,   0,   5,   5,   5,   5,   0,  -5,
  -10,   0,   5,   5,   5,   5,   0, -10,
  -10,   0,   0,   0,   0,   0,   0, -10,
  -20, -10, -10,  -5,  -5, -10, -10, -20]
// The middlegame king: the corner it castled into. What it wants once the
// board has emptied is the opposite, and that is not a table (see ending()).
var KING_PST = [
   20,  30,  10,   0,   0,  10,  30,  20,
   20,  20,   0,   0,   0,   0,  20,  20,
  -10, -20, -20, -20, -20, -20, -20, -10,
  -20, -30, -30, -40, -40, -30, -30, -20,
  -30, -40, -40, -50, -50, -40, -40, -30,
  -30, -40, -40, -50, -50, -40, -40, -30,
  -30, -40, -40, -50, -50, -40, -40, -30,
  -30, -40, -40, -50, -50, -40, -40, -30]

var TABLES = { 1: PAWN_PST, 2: KNIGHT_PST, 3: BISHOP_PST, 4: ROOK_PST, 5: QUEEN_PST, 6: KING_PST }

// What a piece of this colour on this square is worth to White, signed.
var VALUE_AT = (function () {
  var out = []
  for (var code = 0; code < 15; code++) {
    var row = []
    for (var c = 0; c < 64; c++) row.push(0)
    out.push(row)
  }
  for (var kind = 1; kind <= 6; kind++)
    for (var cell = 0; cell < 64; cell++) {
      var worth = VALUES[kind] + TABLES[kind][cell]
      out[kind][cell] = worth
      out[8 | kind][cell ^ 56] = -worth
    }
  return out
})()

// Nought in the four centre squares, six in the corners.
var CENTRE_DISTANCE = (function () {
  var out = []
  for (var cell = 0; cell < 64; cell++)
    out.push(Math.floor(Math.abs(2 * (cell & 7) - 7) / 2) + Math.floor(Math.abs(2 * (cell >> 3) - 7) / 2))
  return out
})()

var MATING = 6
var EDGE_WEIGHT = 12
var APPROACH_WEIGHT = 4
var MATE = 100000
var INFINITY = 1000000
var CHECK_MASK = 1023
var QUIET_PLIES = 8

var LEVELS = [
  { key: "easy", label: "Easy", blurb: "Misses recaptures, and sometimes just plays",
    depth: 2, seconds: 0.4, quiescence: false, blunder: 0.22 },
  { key: "medium", label: "Medium", blurb: "Looks three moves ahead and counts",
    depth: 3, seconds: 1.2, quiescence: true, blunder: 0 },
  { key: "hard", label: "Hard", blurb: "Thinks for a couple of seconds",
    depth: 5, seconds: 2.5, quiescence: true, blunder: 0 }
]
var LEVEL_KEYS = ["easy", "medium", "hard"]
var DEFAULT_LEVEL = "medium"

function levelFor(key) {
  for (var i = 0; i < LEVELS.length; i++) if (LEVELS[i].key === key) return LEVELS[i]
  return LEVELS[1]
}

// A level with some fields changed, for the tests' shorter clocks.
function withLevel(key, changes) {
  var out = Object.assign({}, levelFor(key))
  for (var k in changes) out[k] = changes[k]
  return out
}

function OutOfTime() {}

function advantage(p) {
  var total = 0
  for (var cell = 0; cell < 64; cell++) {
    var code = p.squares[cell]
    if (code) total += VALUE_AT[code][cell]
  }
  return total
}

function piecesOn(p) {
  var n = 0
  for (var cell = 0; cell < 64; cell++) if (p.squares[cell]) n += 1
  return n
}

// How much the move just played changed White's score by.
function delta(made) {
  var frm = made.move & 63
  var to = (made.move >> 6) & 63
  var change = VALUE_AT[made.placed][to] - VALUE_AT[made.piece][frm]
  if (made.captured) change -= VALUE_AT[made.captured][made.capturedSquare]
  if (made.rookFrom !== C.NO_SQUARE) {
    var rook = ((made.piece >> 3) << 3) | C.ROOK
    change += VALUE_AT[rook][made.rookTo] - VALUE_AT[rook][made.rookFrom]
  }
  return change
}

// The correction that turns a won ending into a mate: take the king table
// back off, then pay the side ahead for driving the other king to a corner
// and walking its own up to it.
function ending(p, score) {
  var white = p.kings[0], black = p.kings[1]
  if (white === C.NO_SQUARE || black === C.NO_SQUARE) return 0
  var correction = KING_PST[black ^ 56] - KING_PST[white]
  var material = score + correction
  var apart = Math.abs((white & 7) - (black & 7)) + Math.abs((white >> 3) - (black >> 3))
  if (material > 0) correction += EDGE_WEIGHT * CENTRE_DISTANCE[black] + APPROACH_WEIGHT * (14 - apart)
  else if (material < 0) correction -= EDGE_WEIGHT * CENTRE_DISTANCE[white] + APPROACH_WEIGHT * (14 - apart)
  return correction
}

// What the position is worth to the side to move.
function evaluate(p, score, pieces) {
  if (pieces <= MATING) score += ending(p, score)
  return p.turn === C.WHITE ? score : -score
}

// Captures first, richest victim by cheapest attacker, then the rest. A
// stable sort, as Python's is, so ties keep generation order.
function ordered(p, list) {
  if (list.length < 2) return list
  var squares = p.squares
  var keyed = list.map(function (code, i) {
    var victim = squares[(code >> 6) & 63]
    var promotion = code >> 12
    var s
    if (!victim && !promotion) s = -1
    else {
      s = victim ? 10 * VALUES[victim & 7] : 0
      if (promotion) s += VALUES[promotion]
      s -= VALUES[squares[code & 63] & 7]
    }
    return { code: code, s: s, i: i }
  })
  keyed.sort(function (a, b) { return (b.s - a.s) || (a.i - b.i) })
  return keyed.map(function (k) { return k.code })
}

// A draw the search stops at. Repetition counts at twice inside the search.
function drawn(p, pieces) {
  if (p.halfmove >= 100) return true
  if (pieces <= 4 && C.insufficientMaterial(p)) return true
  return C.repetitions(p) >= 2
}

function tick(state) {
  state.nodes += 1
  if (!(state.nodes & CHECK_MASK) && state.clock() > state.deadline) throw new OutOfTime()
}

function quiescence(p, alpha, beta, score, pieces, ply, state) {
  tick(state)
  var check = C.inCheck(p)
  if (!check) {
    var stand = evaluate(p, score, pieces)
    if (stand >= beta) return beta
    if (stand > alpha) alpha = stand
  } else if (ply >= QUIET_PLIES) {
    return evaluate(p, score, pieces)
  }
  // In check there is no standing pat: every move is looked at, or mate is
  // scored as merely uncomfortable.
  var list = ordered(p, C.pseudoMoves(p, !check))
  var us = p.turn
  var played = 0
  for (var i = 0; i < list.length; i++) {
    var made = C.make(p, list[i])
    if (C.attacked(p, p.kings[us], p.turn)) { C.unmake(p, made); continue }
    played += 1
    var value = -quiescence(p, -beta, -alpha, score + delta(made),
                            made.captured ? pieces - 1 : pieces, ply + 1, state)
    C.unmake(p, made)
    if (value >= beta) return beta
    if (value > alpha) alpha = value
  }
  if (check && !played) return -(MATE - ply)
  return alpha
}

function search(p, depth, alpha, beta, score, pieces, ply, state, level) {
  tick(state)
  if (ply && drawn(p, pieces)) return 0
  if (depth <= 0) {
    if (level.quiescence) return quiescence(p, alpha, beta, score, pieces, ply, state)
    return evaluate(p, score, pieces)
  }
  var us = p.turn
  var best = -INFINITY
  var played = 0
  var list = ordered(p, C.pseudoMoves(p, false))
  for (var i = 0; i < list.length; i++) {
    var made = C.make(p, list[i])
    if (C.attacked(p, p.kings[us], p.turn)) { C.unmake(p, made); continue }
    played += 1
    var value = -search(p, depth - 1, -beta, -alpha, score + delta(made),
                        made.captured ? pieces - 1 : pieces, ply + 1, state, level)
    C.unmake(p, made)
    if (value > best) {
      best = value
      if (best > alpha) {
        alpha = best
        if (alpha >= beta) break
      }
    }
  }
  // Mate is worth less the further away it is; stalemate is nothing.
  if (!played) return C.inCheck(p) ? -(MATE - ply) : 0
  return best
}

function root(p, list, depth, score, pieces, state, level) {
  var alpha = -INFINITY
  var scored = []
  for (var i = 0; i < list.length; i++) {
    var made = C.make(p, list[i])
    var value = -search(p, depth - 1, -INFINITY, -alpha, score + delta(made),
                        made.captured ? pieces - 1 : pieces, 1, state, level)
    C.unmake(p, made)
    scored.push({ code: list[i], value: value, i: i })
    if (value > alpha) alpha = value
  }
  scored.sort(function (a, b) { return (b.value - a.value) || (a.i - b.i) })
  return scored
}

// A move for the side to play, inside the level's budget:
// { move, depth, nodes, score }, or null with nothing to move. Works on a
// copy: a search abandoned part way unwinds with moves still on its board.
// `rng` is a function returning [0, 1); `clock` returns seconds.
function think(position, level, rng, clock) {
  var p = C.copy(position)
  var legal = C.moves(p)
  if (!legal.length) return null
  // Nothing to think about, and a pause here reads as pretending.
  if (legal.length === 1) return { move: legal[0], depth: 0, nodes: 0, score: 0 }
  var chance = rng || Math.random
  var now = clock || function () { return Date.now() / 1000 }
  // Not while in check: a random move there looks broken, not casual.
  if (level.blunder && !C.inCheck(p) && chance() < level.blunder)
    return { move: legal[Math.floor(chance() * legal.length)], depth: 0, nodes: 0, score: 0 }

  var score = advantage(p)
  var pieces = piecesOn(p)
  var state = { nodes: 0, deadline: now() + level.seconds, clock: now }
  var order = ordered(p, legal)
  var scored = order.map(function (code) { return { code: code, value: 0 } })
  var reached = 0
  for (var depth = 1; depth <= level.depth; depth++) {
    var found
    try {
      found = root(p, order, depth, score, pieces, state, level)
    } catch (e) {
      if (e instanceof OutOfTime) break
      throw e
    }
    scored = found
    // The best move from the depth just finished is tried first at the next.
    order = scored.map(function (s) { return s.code })
    reached = depth
    if (Math.abs(scored[0].value) >= MATE - 100) break
  }
  return { move: scored[0].code, depth: reached, nodes: state.nodes, score: scored[0].value }
}

function choose(position, level, rng, clock) {
  var t = think(position, level, rng, clock)
  return t ? t.move : null
}
