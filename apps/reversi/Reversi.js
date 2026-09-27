// The rules, as bitboards.
//
// Ported from the GTK version's reversi.py (0.1.0). Every line of it reads
// the way the Python reads, because Bits.js already took the difficulty: there
// are no 64-bit integers on this engine, and pretending otherwise is a board
// that silently loses its top half.
//
// A Position is a plain object, not a class: it crosses a WorkerScript message
// to reach the search, and only plain values survive that.
.pragma library
.import "Bits.js" as Bits

var SIZE = 8
var CELLS = SIZE * SIZE
var PASS = -1

var DARK = 0
var LIGHT = 1
var NAMES = { 0: "Dark", 1: "Light" }

function other(colour) { return colour === DARK ? LIGHT : DARK }

// Every square but the first column, and every square but the last: a shift
// that steps sideways must not wrap onto the opposite edge.
var NOT_A_FILE = Bits.fromHex("FEFEFEFEFEFEFEFE")
var NOT_H_FILE = Bits.fromHex("7F7F7F7F7F7F7F7F")

var CORNERS = Bits.fromHex("8100000000000081")

// The longest run of enemy discs a single move can turn: six, between the two
// discs that bracket it on an eight-square line.
var MAX_RUN = SIZE - 2

// (shift, mask). A positive shift is up the board.
var DIRECTIONS = [
  [1, NOT_A_FILE], [-1, NOT_H_FILE],
  [8, Bits.FULL], [-8, Bits.FULL],
  [9, NOT_A_FILE], [-9, NOT_H_FILE],
  [7, NOT_H_FILE], [-7, NOT_A_FILE]
]

function index(row, column) { return row * SIZE + column }
function rowOf(cell) { return Math.floor(cell / SIZE) }
function columnOf(cell) { return cell % SIZE }

// a1 is square 0, drawn at the top-left, as reversi.py numbers and drew it.
function notation(cell) {
  if (cell === PASS) return "--"
  return "abcdefgh".charAt(columnOf(cell)) + String(rowOf(cell) + 1)
}

function slide(board, shift, mask) {
  return Bits.and(shift > 0 ? Bits.shl(board, shift) : Bits.shr(board, -shift), mask)
}

// Every square the side holding `own` may play, as a bitboard.
//
// One direction at a time: step off our own discs onto theirs, keep stepping
// while theirs continue, and the empty square after that run is a move. The run
// is grown for the whole board at once, which is why this is six iterations of
// eight directions rather than sixty-four separate walks.
function legalMoves(own, opp) {
  var empty = Bits.andNot(Bits.FULL, Bits.or(own, opp))
  var moves = Bits.ZERO
  for (var d = 0; d < DIRECTIONS.length; d++) {
    var shift = DIRECTIONS[d][0], mask = DIRECTIONS[d][1]
    var run = Bits.and(slide(own, shift, mask), opp)
    for (var i = 0; i < MAX_RUN - 1; i++)
      run = Bits.or(run, Bits.and(slide(run, shift, mask), opp))
    moves = Bits.or(moves, Bits.and(slide(run, shift, mask), empty))
  }
  return moves
}

// The discs that playing `cell` turns over.
//
// The mirror image of the scan above, walked out from the square played: a run
// of enemy discs flips only if one of ours is sitting at the end of it. A run
// that reaches an empty square or the edge flips nothing, which is the rule.
function flips(own, opp, cell) {
  var played = Bits.bit(cell)
  var turned = Bits.ZERO
  for (var d = 0; d < DIRECTIONS.length; d++) {
    var shift = DIRECTIONS[d][0], mask = DIRECTIONS[d][1]
    var run = Bits.and(slide(played, shift, mask), opp)
    for (var i = 0; i < MAX_RUN - 1; i++)
      run = Bits.or(run, Bits.and(slide(run, shift, mask), opp))
    if (!Bits.isZero(Bits.and(slide(run, shift, mask), own)))
      turned = Bits.or(turned, run)
  }
  return turned
}

// --- a position -------------------------------------------------------------

function position(dark, light, turn) {
  return { dark: dark, light: light, turn: turn }
}

var OPENING = position(Bits.or(Bits.bit(28), Bits.bit(35)),
                       Bits.or(Bits.bit(27), Bits.bit(36)), DARK)

function own(p) { return p.turn === DARK ? p.dark : p.light }
function opp(p) { return p.turn === DARK ? p.light : p.dark }
function discs(p, colour) { return colour === DARK ? p.dark : p.light }

function moves(p) { return legalMoves(own(p), opp(p)) }
function legal(p) { return Bits.cells(moves(p)) }
function isLegal(p, cell) { return cell >= 0 && Bits.test(moves(p), cell) }

function play(p, cell) {
  var mine = own(p), theirs = opp(p)
  var turned = flips(mine, theirs, cell)
  var next = Bits.or(Bits.or(mine, turned), Bits.bit(cell))
  var other = Bits.andNot(theirs, turned)
  return p.turn === DARK ? position(next, other, LIGHT) : position(other, next, DARK)
}

function flippedBy(p, cell) { return Bits.cells(flips(own(p), opp(p), cell)) }

function passed(p) {
  return position(p.dark, p.light, p.turn === DARK ? LIGHT : DARK)
}

// A pass is forced, never chosen: a player with a move must take it.
function mustPass(p) {
  return Bits.isZero(moves(p)) && !Bits.isZero(legalMoves(opp(p), own(p)))
}

function isOver(p) {
  return Bits.isZero(moves(p)) && Bits.isZero(legalMoves(opp(p), own(p)))
}

function count(p, colour) { return Bits.popcount(discs(p, colour)) }
function counts(p) { return [count(p, DARK), count(p, LIGHT)] }
function empties(p) { return CELLS - Bits.popcount(Bits.or(p.dark, p.light)) }

// The winner, or null for a draw. Only meaningful once the game is over.
function winner(p) {
  var d = count(p, DARK), l = count(p, LIGHT)
  if (d === l) return null
  return d > l ? DARK : LIGHT
}

// --- a game -----------------------------------------------------------------

// The move list is the game: the board is replayed from it rather than stored,
// which is what makes a saved game a list of small numbers and makes undo one
// subtraction. The same reason store.py keeps the taps rather than the board.
function replay(moveList) {
  var p = OPENING
  var history = [p]
  for (var i = 0; i < moveList.length; i++) {
    var cell = moveList[i]
    p = cell === PASS ? passed(p) : play(p, cell)
    history.push(p)
  }
  return { position: p, history: history }
}

// --- a game, as the GTK version's Game class played it ------------------------

// As much of a recorded game as will legally play: a pass only where one is
// forced, a move only where it is legal. Where a file stops making sense is
// where the game stops -- anything else is a guess, and a guess here is a
// board somebody never played. Returns the moves kept.
function resume(moveList) {
  var p = OPENING
  var kept = []
  for (var i = 0; i < moveList.length; i++) {
    var cell = moveList[i]
    if (cell === PASS) {
      if (!mustPass(p)) break
      p = passed(p)
    } else {
      if (!isLegal(p, cell)) break
      p = play(p, cell)
    }
    kept.push(cell)
  }
  return kept
}

// A move, then a pass for whoever cannot answer it: a position where the side
// to move has nothing to do is not a state the board should ever show.
// Returns { moves, passes, flipped }.
function playTurn(moveList, cell) {
  var p = replay(moveList).position
  var flipped = flippedBy(p, cell)
  p = play(p, cell)
  var out = moveList.concat([cell])
  var passes = 0
  while (mustPass(p)) {
    p = passed(p)
    out.push(PASS)
    passes += 1
  }
  return { moves: out, passes: passes, flipped: flipped }
}

// One move taken back, and any passes that followed it. null at the opening.
function undo(moveList) {
  var out = moveList.slice()
  while (out.length && out[out.length - 1] === PASS) out.pop()
  if (!out.length) return null
  out.pop()
  return out
}

// Rewind until `colour` is on move again with something to play, and with
// something undone -- one thumb on a bus lands one square off, and undoing a
// single ply would hand the board back with the computer's reply still on it.
// null when there was nothing to take back.
function takeback(moveList, colour) {
  var out = moveList
  var undone = false
  while (out.length) {
    var next = undo(out)
    if (next === null) break
    out = next
    undone = true
    var p = replay(out).position
    if (p.turn === colour && !mustPass(p)) break
  }
  return undone ? out : null
}

// The last square played, skipping passes, or -1.
function lastMove(moveList) {
  for (var i = moveList.length - 1; i >= 0; i--) if (moveList[i] !== PASS) return moveList[i]
  return -1
}
