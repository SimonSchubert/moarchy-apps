// The rules of chess, on an array of sixty-four small integers.
//
// Ported from 0.1.0's chess.py, rule for rule, and checked against the same
// perft counts. One flat array of 64 squares, every table precomputed once,
// and make/unmake on the array itself rather than a new board per move: a
// search at depth four visits tens of thousands of nodes, and on the A53 in a
// PinePhone copying a board per node would be the whole time budget. `make`
// returns what the move did (the `made` record), which is what `unmake`, the
// evaluation in Ai.js and the captured-pieces row all read.
//
// Squares run a1 = 0 to h8 = 63, so `square = rank * 8 + file` and the other
// side's point of view is `square ^ 56`. A piece is `colour * 8 + kind`:
// white 1..6, black 9..14, `piece & 7` what it is and `piece >> 3` whose. A
// move is one int, `from | to << 6 | promotion << 12`, and the file holds it
// as long algebraic, "e2e4" or "e7e8q".
//
// The Zobrist keys differ from Python's (V4 has no 64-bit integers, so a key
// is two 32-bit halves from a seeded generator); they are only ever compared
// with each other, for repetition, and never leave the process.
.pragma library

var SIZE = 8
var CELLS = 64

var WHITE = 0
var BLACK = 1
var COLOUR_NAMES = { 0: "White", 1: "Black" }

var EMPTY = 0
var PAWN = 1
var KNIGHT = 2
var BISHOP = 3
var ROOK = 4
var QUEEN = 5
var KING = 6
var KINDS = [PAWN, KNIGHT, BISHOP, ROOK, QUEEN, KING]
var KIND_NAMES = { 1: "pawn", 2: "knight", 3: "bishop", 4: "rook", 5: "queen", 6: "king" }
var LETTERS = { 1: "p", 2: "n", 3: "b", 4: "r", 5: "q", 6: "k" }
var KIND_OF_LETTER = { p: PAWN, n: KNIGHT, b: BISHOP, r: ROOK, q: QUEEN, k: KING }
// What a piece is worth when a person counts. Ai.js has its own table.
var POINTS = { 1: 1, 2: 3, 3: 3, 4: 5, 5: 9, 6: 0 }

var WHITE_KINGSIDE = 1
var WHITE_QUEENSIDE = 2
var BLACK_KINGSIDE = 4
var BLACK_QUEENSIDE = 8
var ALL_CASTLING = 15

var NO_SQUARE = -1

var ONGOING = "ongoing"
var CHECKMATE = "checkmate"
var STALEMATE = "stalemate"
var FIFTY_MOVE = "fifty-move"
var INSUFFICIENT = "insufficient"
var REPETITION = "repetition"

var START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

function piece(colour, kind) { return (colour << 3) | kind }
function kindOf(code) { return code & 7 }
function colourOf(code) { return code >> 3 }
function square(file, rank) { return rank * SIZE + file }
function fileOf(cell) { return cell & 7 }
function rankOf(cell) { return cell >> 3 }

// e4: the notation a person reads, and the one the saved file is in.
function name(cell) { return String.fromCharCode(97 + (cell & 7)) + ((cell >> 3) + 1) }

// A square by name, or -1 for anything that is not one.
function parseSquare(text) {
  if (typeof text !== "string" || text.length !== 2) return NO_SQUARE
  var file = text.charCodeAt(0) - 97
  var rank = text.charCodeAt(1) - 49
  if (file < 0 || file >= SIZE || rank < 0 || rank >= SIZE) return NO_SQUARE
  return rank * SIZE + file
}

function move(frm, to, promotion) { return frm | (to << 6) | ((promotion || 0) << 12) }
function moveFrom(code) { return code & 63 }
function moveTo(code) { return (code >> 6) & 63 }
function movePromotion(code) { return code >> 12 }

function uci(code) {
  var p = code >> 12
  return name(code & 63) + name((code >> 6) & 63) + (p ? LETTERS[p] : "")
}

// A move as written, or -1. Says nothing about whether it is legal here.
function parseUci(text) {
  if (typeof text !== "string" || (text.length !== 4 && text.length !== 5)) return -1
  var frm = parseSquare(text.slice(0, 2))
  var to = parseSquare(text.slice(2, 4))
  if (frm < 0 || to < 0) return -1
  var promotion = 0
  if (text.length === 5) {
    promotion = KIND_OF_LETTER[text[4].toLowerCase()] || 0
    if (promotion !== KNIGHT && promotion !== BISHOP && promotion !== ROOK && promotion !== QUEEN) return -1
  }
  return move(frm, to, promotion)
}

// --- the tables, built once ---------------------------------------------

// Rook directions first, then bishop directions: a slide along ray i is a
// rook's if i < 4 and a bishop's otherwise, and a queen's either way.
var STEPS = [[0, 1], [0, -1], [1, 0], [-1, 0], [1, 1], [-1, 1], [1, -1], [-1, -1]]
var ROOK_RAYS = [0, 1, 2, 3]
var BISHOP_RAYS = [4, 5, 6, 7]
var KNIGHT_STEPS = [[1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2]]

function step(cell, s) {
  var f = fileOf(cell) + s[0], r = rankOf(cell) + s[1]
  return f >= 0 && f < SIZE && r >= 0 && r < SIZE ? square(f, r) : NO_SQUARE
}
function walk(cell, s) {
  var out = []
  var f = fileOf(cell) + s[0], r = rankOf(cell) + s[1]
  while (f >= 0 && f < SIZE && r >= 0 && r < SIZE) {
    out.push(square(f, r))
    f += s[0]
    r += s[1]
  }
  return out
}

var RAYS = []
var KNIGHT_MOVES = []
var KING_MOVES = []
var PAWN_ATTACKS = [[], []]
var PAWN_ATTACKERS = [[], []]
;(function () {
  for (var cell = 0; cell < CELLS; cell++) {
    var rays = []
    for (var i = 0; i < 8; i++) rays.push(walk(cell, STEPS[i]))
    RAYS.push(rays)
    var kn = [], kg = []
    for (var j = 0; j < 8; j++) {
      var a = step(cell, KNIGHT_STEPS[j]); if (a >= 0) kn.push(a)
      var b = step(cell, STEPS[j]); if (b >= 0) kg.push(b)
    }
    KNIGHT_MOVES.push(kn)
    KING_MOVES.push(kg)
    for (var colour = 0; colour < 2; colour++) {
      var dr = colour === WHITE ? 1 : -1
      var at = []
      var l = step(cell, [-1, dr]); if (l >= 0) at.push(l)
      var r = step(cell, [1, dr]); if (r >= 0) at.push(r)
      PAWN_ATTACKS[colour].push(at)
    }
  }
  // Read backwards: where a pawn of this colour would stand to attack here.
  for (var c = 0; c < 2; c++)
    for (var to = 0; to < CELLS; to++) {
      var from = []
      for (var f = 0; f < CELLS; f++) if (PAWN_ATTACKS[c][f].indexOf(to) >= 0) from.push(f)
      PAWN_ATTACKERS[c].push(from)
    }
})()

// Rights that survive a piece leaving or arriving on a square. AND-ing both
// ends of every move into the rights is the whole rule, including capturing
// a rook on its own corner.
var CASTLE_MASK = (function () {
  var m = []
  for (var i = 0; i < CELLS; i++) m.push(ALL_CASTLING)
  m[square(0, 0)] &= ~WHITE_QUEENSIDE
  m[square(7, 0)] &= ~WHITE_KINGSIDE
  m[square(4, 0)] &= ~(WHITE_KINGSIDE | WHITE_QUEENSIDE)
  m[square(0, 7)] &= ~BLACK_QUEENSIDE
  m[square(7, 7)] &= ~BLACK_KINGSIDE
  m[square(4, 7)] &= ~(BLACK_KINGSIDE | BLACK_QUEENSIDE)
  return m
})()

// Zobrist keys, two 32-bit halves each, from a fixed seed (mulberry32).
var Z = (function () {
  var a = 0x52455645
  function next() {
    a = (a + 0x6D2B79F5) | 0
    var t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return (t ^ (t >>> 14)) | 0
  }
  var pieceH = [], pieceL = []
  for (var p = 0; p < 15; p++) {
    var h = [], l = []
    for (var c = 0; c < CELLS; c++) { h.push(next()); l.push(next()) }
    pieceH.push(h); pieceL.push(l)
  }
  var castH = [], castL = [], epH = [], epL = []
  for (var i = 0; i < 16; i++) { castH.push(next()); castL.push(next()) }
  for (var j = 0; j < 8; j++) { epH.push(next()); epL.push(next()) }
  return { pieceH: pieceH, pieceL: pieceL, sideH: next(), sideL: next(),
           castH: castH, castL: castL, epH: epH, epL: epL }
})()

// --- positions ------------------------------------------------------------

function hashOf(p) {
  var h = 0, l = 0
  for (var cell = 0; cell < CELLS; cell++) {
    var code = p.squares[cell]
    if (code) { h ^= Z.pieceH[code][cell]; l ^= Z.pieceL[code][cell] }
  }
  if (p.turn === BLACK) { h ^= Z.sideH; l ^= Z.sideL }
  h ^= Z.castH[p.castling]; l ^= Z.castL[p.castling]
  if (p.ep !== NO_SQUARE) { h ^= Z.epH[p.ep & 7]; l ^= Z.epL[p.ep & 7] }
  return [h, l]
}

function makePosition(squares, turn, castling, ep, halfmove, fullmove) {
  var p = {
    squares: squares, turn: turn || WHITE, castling: castling || 0,
    ep: ep === undefined ? NO_SQUARE : ep, halfmove: halfmove || 0,
    fullmove: fullmove || 1, kings: [NO_SQUARE, NO_SQUARE], kh: 0, kl: 0,
    keysH: [], keysL: []
  }
  for (var cell = 0; cell < CELLS; cell++) {
    var code = squares[cell]
    if (code && (code & 7) === KING) p.kings[code >> 3] = cell
  }
  var k = hashOf(p)
  p.kh = k[0]; p.kl = k[1]
  p.keysH.push(p.kh); p.keysL.push(p.kl)
  return p
}

function start() { return fromFen(START_FEN) }

// A position as Forsyth-Edwards writes it, or null for text that is not one.
function fromFen(text) {
  var parts = String(text || "").trim().split(/\s+/)
  if (parts.length < 4) return null
  var squares = []
  for (var i = 0; i < CELLS; i++) squares.push(EMPTY)
  var rank = SIZE - 1, file = 0
  for (var j = 0; j < parts[0].length; j++) {
    var ch = parts[0][j]
    if (ch === "/") { rank -= 1; file = 0 }
    else if (ch >= "0" && ch <= "9") file += parseInt(ch, 10)
    else {
      var kind = KIND_OF_LETTER[ch.toLowerCase()]
      if (!kind || file < 0 || file >= SIZE || rank < 0 || rank >= SIZE) return null
      squares[square(file, rank)] = piece(ch === ch.toUpperCase() ? WHITE : BLACK, kind)
      file += 1
    }
  }
  var castling = 0
  if (parts[2].indexOf("K") >= 0) castling |= WHITE_KINGSIDE
  if (parts[2].indexOf("Q") >= 0) castling |= WHITE_QUEENSIDE
  if (parts[2].indexOf("k") >= 0) castling |= BLACK_KINGSIDE
  if (parts[2].indexOf("q") >= 0) castling |= BLACK_QUEENSIDE
  var ep = parts[3] !== "-" ? parseSquare(parts[3]) : NO_SQUARE
  var half = parts.length > 4 && /^\d+$/.test(parts[4]) ? parseInt(parts[4], 10) : 0
  var full = parts.length > 5 && /^\d+$/.test(parts[5]) ? parseInt(parts[5], 10) : 1
  return makePosition(squares, parts[1] === "b" ? BLACK : WHITE, castling, ep, half, full)
}

function fen(p) {
  var rows = []
  for (var rank = SIZE - 1; rank >= 0; rank--) {
    var row = "", gap = 0
    for (var file = 0; file < SIZE; file++) {
      var code = p.squares[square(file, rank)]
      if (!code) { gap += 1; continue }
      if (gap) { row += gap; gap = 0 }
      var letter = LETTERS[code & 7]
      row += (code >> 3) === WHITE ? letter.toUpperCase() : letter
    }
    rows.push(row + (gap ? gap : ""))
  }
  var rights = (p.castling & WHITE_KINGSIDE ? "K" : "") + (p.castling & WHITE_QUEENSIDE ? "Q" : "")
    + (p.castling & BLACK_KINGSIDE ? "k" : "") + (p.castling & BLACK_QUEENSIDE ? "q" : "")
  return [rows.join("/"), p.turn === WHITE ? "w" : "b", rights || "-",
          p.ep !== NO_SQUARE ? name(p.ep) : "-", String(p.halfmove), String(p.fullmove)].join(" ")
}

function copy(p) {
  return {
    squares: p.squares.slice(), turn: p.turn, castling: p.castling, ep: p.ep,
    halfmove: p.halfmove, fullmove: p.fullmove, kings: p.kings.slice(),
    kh: p.kh, kl: p.kl, keysH: p.keysH.slice(), keysL: p.keysL.slice()
  }
}

// --- playing ----------------------------------------------------------------

// Play a pseudo-legal move into this board, and say what it did.
function make(p, code) {
  var squares = p.squares
  var frm = code & 63
  var to = (code >> 6) & 63
  var promotion = code >> 12
  var mover = squares[frm]
  var kind = mover & 7
  var us = mover >> 3
  var h = p.kh ^ Z.sideH ^ Z.castH[p.castling]
  var l = p.kl ^ Z.sideL ^ Z.castL[p.castling]
  if (p.ep !== NO_SQUARE) { h ^= Z.epH[p.ep & 7]; l ^= Z.epL[p.ep & 7] }

  var captured = squares[to]
  var capturedSquare = to
  if (kind === PAWN && to === p.ep && !captured) {
    // The only capture that does not happen where the capturer lands.
    capturedSquare = us === WHITE ? to - SIZE : to + SIZE
    captured = squares[capturedSquare]
  }
  if (captured) {
    squares[capturedSquare] = EMPTY
    h ^= Z.pieceH[captured][capturedSquare]; l ^= Z.pieceL[captured][capturedSquare]
  }

  var placed = promotion ? piece(us, promotion) : mover
  squares[frm] = EMPTY
  squares[to] = placed
  h ^= Z.pieceH[mover][frm] ^ Z.pieceH[placed][to]
  l ^= Z.pieceL[mover][frm] ^ Z.pieceL[placed][to]

  var rookFrom = NO_SQUARE, rookTo = NO_SQUARE
  if (kind === KING) {
    p.kings[us] = to
    if (to - frm === 2 || frm - to === 2) {
      if (to > frm) { rookFrom = frm + 3; rookTo = frm + 1 } else { rookFrom = frm - 4; rookTo = frm - 1 }
      var rook = squares[rookFrom]
      squares[rookFrom] = EMPTY
      squares[rookTo] = rook
      h ^= Z.pieceH[rook][rookFrom] ^ Z.pieceH[rook][rookTo]
      l ^= Z.pieceL[rook][rookFrom] ^ Z.pieceL[rook][rookTo]
    }
  }

  var made = {
    move: code, piece: mover, placed: placed, captured: captured,
    capturedSquare: captured ? capturedSquare : NO_SQUARE,
    rookFrom: rookFrom, rookTo: rookTo,
    castling: p.castling, ep: p.ep, halfmove: p.halfmove, kh: p.kh, kl: p.kl
  }

  p.castling &= CASTLE_MASK[frm] & CASTLE_MASK[to]
  p.ep = kind === PAWN && (to - frm === 16 || frm - to === 16) ? (frm + to) >> 1 : NO_SQUARE
  p.halfmove = kind === PAWN || captured ? 0 : p.halfmove + 1
  if (us === BLACK) p.fullmove += 1
  p.turn = us ^ 1
  h ^= Z.castH[p.castling]; l ^= Z.castL[p.castling]
  if (p.ep !== NO_SQUARE) { h ^= Z.epH[p.ep & 7]; l ^= Z.epL[p.ep & 7] }
  p.kh = h; p.kl = l
  p.keysH.push(h); p.keysL.push(l)
  return made
}

function unmake(p, made) {
  var squares = p.squares
  var frm = made.move & 63
  var to = (made.move >> 6) & 63
  var us = made.piece >> 3
  squares[to] = EMPTY
  squares[frm] = made.piece
  if (made.captured) squares[made.capturedSquare] = made.captured
  if (made.rookFrom !== NO_SQUARE) {
    squares[made.rookFrom] = squares[made.rookTo]
    squares[made.rookTo] = EMPTY
  }
  if ((made.piece & 7) === KING) p.kings[us] = frm
  p.castling = made.castling
  p.ep = made.ep
  p.halfmove = made.halfmove
  if (us === BLACK) p.fullmove -= 1
  p.turn = us
  p.kh = made.kh; p.kl = made.kl
  p.keysH.pop(); p.keysL.pop()
}

// --- what is attacking what -----------------------------------------------

// Is this square attacked by that colour? Asked from the square outwards: the
// hottest function in the file.
function attacked(p, cell, by) {
  // No king on the board (a study, a test) has nothing to attack. Python's
  // negative indexing answered this by accident, reading square 63.
  if (cell < 0) return false
  var squares = p.squares
  var base = by << 3
  var i, list, frm, found
  list = PAWN_ATTACKERS[by][cell]
  for (i = 0; i < list.length; i++) if (squares[list[i]] === (base | PAWN)) return true
  list = KNIGHT_MOVES[cell]
  for (i = 0; i < list.length; i++) if (squares[list[i]] === (base | KNIGHT)) return true
  list = KING_MOVES[cell]
  for (i = 0; i < list.length; i++) if (squares[list[i]] === (base | KING)) return true
  var rays = RAYS[cell]
  for (var r = 0; r < 4; r++) {
    var ray = rays[r]
    for (i = 0; i < ray.length; i++) {
      found = squares[ray[i]]
      if (found) {
        if (found === (base | ROOK) || found === (base | QUEEN)) return true
        break
      }
    }
  }
  for (var b = 4; b < 8; b++) {
    var bray = rays[b]
    for (i = 0; i < bray.length; i++) {
      found = squares[bray[i]]
      if (found) {
        if (found === (base | BISHOP) || found === (base | QUEEN)) return true
        break
      }
    }
  }
  return false
}

function inCheck(p, colour) {
  var c = colour === undefined ? p.turn : colour
  var king = p.kings[c]
  return king !== NO_SQUARE && attacked(p, king, c ^ 1)
}

// --- generating moves ------------------------------------------------------

// Every move the pieces allow, before the king is considered. `tactical`
// narrows it to captures and queen promotions, for the quiescence search.
function pseudoMoves(p, tactical) {
  var out = []
  var squares = p.squares
  var us = p.turn
  for (var frm = 0; frm < CELLS; frm++) {
    var code = squares[frm]
    if (!code || (code >> 3) !== us) continue
    var kind = code & 7
    if (kind === PAWN) pawnMoves(p, frm, us, out, tactical)
    else if (kind === KNIGHT) stepMoves(p, frm, us, KNIGHT_MOVES[frm], out, tactical)
    else if (kind === KING) {
      stepMoves(p, frm, us, KING_MOVES[frm], out, tactical)
      if (!tactical) castles(p, frm, us, out)
    } else {
      var rays = RAYS[frm]
      if (kind !== BISHOP) slide(p, frm, us, rays, 0, out, tactical)
      if (kind !== ROOK) slide(p, frm, us, rays, 4, out, tactical)
    }
  }
  return out
}

function stepMoves(p, frm, us, targets, out, tactical) {
  var squares = p.squares
  for (var i = 0; i < targets.length; i++) {
    var to = targets[i]
    var found = squares[to]
    if (found) { if ((found >> 3) !== us) out.push(frm | (to << 6)) }
    else if (!tactical) out.push(frm | (to << 6))
  }
}

function slide(p, frm, us, rays, first, out, tactical) {
  var squares = p.squares
  for (var r = first; r < first + 4; r++) {
    var ray = rays[r]
    for (var i = 0; i < ray.length; i++) {
      var to = ray[i]
      var found = squares[to]
      if (found) {
        if ((found >> 3) !== us) out.push(frm | (to << 6))
        break
      }
      if (!tactical) out.push(frm | (to << 6))
    }
  }
}

function pawnMoves(p, frm, us, out, tactical) {
  var squares = p.squares
  var ahead = us === WHITE ? frm + SIZE : frm - SIZE
  var last = us === WHITE ? SIZE - 1 : 0
  // A promotion is four moves; the quiescence search wants only the queen.
  var promotions = rankOf(ahead) === last ? (tactical ? [QUEEN] : [QUEEN, ROOK, BISHOP, KNIGHT]) : [0]
  var i
  if (!squares[ahead] && (!tactical || promotions[0]))
    for (i = 0; i < promotions.length; i++) out.push(frm | (ahead << 6) | (promotions[i] << 12))
  if (!tactical && !squares[ahead] && rankOf(frm) === (us === WHITE ? 1 : 6)) {
    var dbl = us === WHITE ? ahead + SIZE : ahead - SIZE
    if (!squares[dbl]) out.push(frm | (dbl << 6))
  }
  var targets = PAWN_ATTACKS[us][frm]
  for (var t = 0; t < targets.length; t++) {
    var to = targets[t]
    var found = squares[to]
    if ((found && (found >> 3) !== us) || (!found && to === p.ep))
      for (i = 0; i < promotions.length; i++) out.push(frm | (to << 6) | (promotions[i] << 12))
  }
}

function castles(p, frm, us, out) {
  var home = us === WHITE ? 0 : 7
  if (frm !== square(4, home)) return
  var rights = p.castling >> (us === WHITE ? 0 : 2)
  if (!(rights & 3)) return
  var squares = p.squares
  var them = us ^ 1
  var rook = piece(us, ROOK)
  // Not out of check, not through an attacked square; landing on one is left
  // to the legality filter.
  if ((rights & 1) && !(squares[frm + 1] || squares[frm + 2]) && squares[frm + 3] === rook
      && !attacked(p, frm, them) && !attacked(p, frm + 1, them))
    out.push(frm | ((frm + 2) << 6))
  if ((rights & 2) && !(squares[frm - 1] || squares[frm - 2] || squares[frm - 3]) && squares[frm - 4] === rook
      && !attacked(p, frm, them) && !attacked(p, frm - 1, them))
    out.push(frm | ((frm - 2) << 6))
}

// The legal moves: every one of them playable, right now, here.
function moves(p) {
  var us = p.turn
  var out = []
  var list = pseudoMoves(p, false)
  for (var i = 0; i < list.length; i++) {
    var made = make(p, list[i])
    if (!attacked(p, p.kings[us], p.turn)) out.push(list[i])
    unmake(p, made)
  }
  return out
}

function movesFrom(p, cell) {
  return moves(p).filter(function (code) { return (code & 63) === cell })
}

function isLegal(p, code) { return moves(p).indexOf(code) >= 0 }

// --- endings ------------------------------------------------------------------

// How many times this exact position has stood on the board, back as far as
// the last capture or pawn move, two plies at a time.
function repetitions(p) {
  var count = 1
  var n = p.keysH.length
  var index = n - 3
  var floor = Math.max(n - 1 - p.halfmove, 0)
  while (index >= floor) {
    if (p.keysH[index] === p.kh && p.keysL[index] === p.kl) count += 1
    index -= 2
  }
  return count
}

// Neither side could deliver mate with what is left: bare kings, a king and
// one minor, or bishops that never meet. Two knights is not in here -- mate
// is possible, it just cannot be forced.
function insufficientMaterial(p) {
  var minors = [0, 0]
  var bishops = [NO_SQUARE, NO_SQUARE]
  for (var cell = 0; cell < CELLS; cell++) {
    var code = p.squares[cell]
    if (!code) continue
    var kind = code & 7
    if (kind === PAWN || kind === ROOK || kind === QUEEN) return false
    if (kind === KING) continue
    minors[code >> 3] += 1
    if (kind === BISHOP) bishops[code >> 3] = cell
  }
  if (minors[0] > 1 || minors[1] > 1) return false
  if (minors[0] + minors[1] <= 1) return true
  if (bishops[0] === NO_SQUARE || bishops[1] === NO_SQUARE) return false
  return (fileOf(bishops[0]) + rankOf(bishops[0])) % 2 === (fileOf(bishops[1]) + rankOf(bishops[1])) % 2
}

// How the game stands: { state, winner }. Mate first -- a mated king is mated
// on the hundredth quiet move as well.
function outcome(p) {
  if (!moves(p).length) {
    if (inCheck(p)) return { state: CHECKMATE, winner: p.turn ^ 1 }
    return { state: STALEMATE, winner: null }
  }
  if (p.halfmove >= 100) return { state: FIFTY_MOVE, winner: null }
  if (insufficientMaterial(p)) return { state: INSUFFICIENT, winner: null }
  if (repetitions(p) >= 3) return { state: REPETITION, winner: null }
  return { state: ONGOING, winner: null }
}

// --- games --------------------------------------------------------------------

// A game is the list of moves that made it: { position, moves, made }.
// Loading is playing, so a file cannot describe a board legal play could
// not reach, and where it stops making sense is where the game stops.
function game(position) {
  return { position: position ? copy(position) : start(), moves: [], made: [] }
}

function apply(g, code) {
  if (moves(g.position).indexOf(code) < 0) return false
  g.made.push(make(g.position, code))
  g.moves.push(code)
  return true
}

function resume(codes, position) {
  var g = game(position)
  for (var i = 0; i < codes.length; i++) if (!apply(g, codes[i])) break
  return g
}

// Long algebraic strings to a game, as far as they parse and play.
function resumeUci(texts, position) {
  var codes = []
  for (var i = 0; i < texts.length; i++) {
    var c = parseUci(texts[i])
    if (c < 0) break
    codes.push(c)
  }
  return resume(codes, position)
}

function gameUci(g) { return g.moves.map(uci) }

function undo(g) {
  if (!g.made.length) return false
  unmake(g.position, g.made.pop())
  g.moves.pop()
  return true
}

// Rewind until `colour` is on move again, with something undone: undoing one
// ply would leave the computer's reply on the board.
function takeback(g, colour) {
  var undone = false
  while (g.moves.length) {
    if (!undo(g)) break
    undone = true
    if (g.position.turn === colour) break
  }
  return undone
}

// Everything taken so far, in the order it went: from the moves, not the
// board, because a promotion is not a capture.
function captured(g) {
  var out = []
  for (var i = 0; i < g.made.length; i++) if (g.made[i].captured) out.push(g.made[i].captured)
  return out
}

// Material on the board, in points, from White's side.
function balance(p) {
  var total = 0
  for (var cell = 0; cell < CELLS; cell++) {
    var code = p.squares[cell]
    if (code) total += POINTS[code & 7] * ((code >> 3) === WHITE ? 1 : -1)
  }
  return total
}

// The last move played, or -1.
function lastMove(g) { return g.moves.length ? g.moves[g.moves.length - 1] : -1 }

// The moves in the form a person writes them: "Nf3", "exd5", "O-O", "e8=Q+".
function san(p, code) {
  var frm = code & 63, to = (code >> 6) & 63, promo = code >> 12
  var mover = p.squares[frm]
  var kind = mover & 7
  var out
  if (kind === KING && Math.abs(to - frm) === 2) out = to > frm ? "O-O" : "O-O-O"
  else {
    var capture = !!p.squares[to] || (kind === PAWN && to === p.ep)
    if (kind === PAWN) {
      out = (capture ? String.fromCharCode(97 + (frm & 7)) + "x" : "") + name(to)
      if (promo) out += "=" + LETTERS[promo].toUpperCase()
    } else {
      out = LETTERS[kind].toUpperCase()
      // Disambiguate by file, then rank, then both, as the rules of notation say.
      var others = moves(p).filter(function (m) {
        return (m & 63) !== frm && ((m >> 6) & 63) === to && (p.squares[m & 63] & 7) === kind
      })
      if (others.length) {
        var sameFile = others.some(function (m) { return ((m & 63) & 7) === (frm & 7) })
        var sameRank = others.some(function (m) { return ((m & 63) >> 3) === (frm >> 3) })
        if (!sameFile) out += String.fromCharCode(97 + (frm & 7))
        else if (!sameRank) out += String((frm >> 3) + 1)
        else out += name(frm)
      }
      out += (capture ? "x" : "") + name(to)
    }
  }
  var made = make(p, code)
  if (inCheck(p)) out += moves(p).length ? "+" : "#"
  unmake(p, made)
  return out
}

// The whole game in SAN, one string a ply.
function sanList(g) {
  var out = []
  // Walked back to where the game began, then forward, naming each move on
  // the board it was played on.
  var q = copy(g.position)
  for (var i = g.made.length - 1; i >= 0; i--) unmake(q, g.made[i])
  for (var j = 0; j < g.moves.length; j++) {
    out.push(san(q, g.moves[j]))
    make(q, g.moves[j])
  }
  return out
}

// The whole of the API, as one object, for the search worker, which cannot
// use `.import` (see search.js).
var API = {
  SIZE: SIZE, CELLS: CELLS, WHITE: WHITE, BLACK: BLACK, EMPTY: EMPTY,
  PAWN: PAWN, KNIGHT: KNIGHT, BISHOP: BISHOP, ROOK: ROOK, QUEEN: QUEEN, KING: KING,
  KINDS: KINDS, NO_SQUARE: NO_SQUARE, piece: piece, fileOf: fileOf, rankOf: rankOf,
  make: make, unmake: unmake, attacked: attacked, inCheck: inCheck,
  pseudoMoves: pseudoMoves, moves: moves, copy: copy, repetitions: repetitions,
  insufficientMaterial: insufficientMaterial, uci: uci
}
