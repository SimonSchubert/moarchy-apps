// The rules of Nine Men's Morris, as two 24-bit integers.
//
// Ported from the GTK version's mill.py (0.1.0), and checked against its tests
// case for case. Twenty-four points fit in a JavaScript int, so unlike Reversi
// this needs no 64-bit workaround.
//
// The numbering is a ring and a place on it. Point `ring * 8 + place`, with the
// rings running outer, middle, inner and the places running clockwise from the
// top-left corner -- so the even places are corners and the odd ones are the
// midpoints of the sides. Within a ring a point touches `place ± 1`; between
// rings only the odd places connect, straight through. The sixteen mills are
// the same shape: four to a ring, and four across the rings at each odd place.
//
// A turn is not always one move. Closing a mill earns a removal, and the
// removal is a move in its own right with the same side still on turn:
// `removing` says so, and the move list records it like anything else.
//
// A position is a plain object -- {white, black, turn, placed: [w, b],
// removing} -- and nothing here changes one: play() returns a new position.
.pragma library

var RINGS = 3
var PLACES = 8
var POINTS = RINGS * PLACES
var FULL = (1 << POINTS) - 1

var WHITE = 0
var BLACK = 1
var NAMES = { 0: "White", 1: "Black" }

// Nine pieces each, which is the name of the game.
var PIECES = 9
// Below this a side has lost; at this a side may fly.
var DEAD = 2
var FLYING = 3

// How many moves may pass in the moving phase with nothing taken before the
// game is called a draw. The tournament figure is fifty; two people shuffling
// pieces on a phone reach that in a minute, and a game that cannot end is
// worse than one that ends level.
var QUIET_LIMIT = 50

function other(colour) { return colour === WHITE ? BLACK : WHITE }

function point(ring, place) { return ring * PLACES + ((place % PLACES) + PLACES) % PLACES }
function ringOf(spot) { return Math.floor(spot / PLACES) }
function placeOf(spot) { return spot % PLACES }

function popcount(x) {
  var n = 0
  while (x) { x &= x - 1; n += 1 }
  return n
}

// The point indices set in a bitboard, lowest first.
function spots(board) {
  var out = []
  for (var i = 0; i < POINTS; i++) if ((board >> i) & 1) out.push(i)
  return out
}

var NEIGHBOURS = (function () {
  var out = []
  for (var spot = 0; spot < POINTS; spot++) {
    var ring = ringOf(spot), place = placeOf(spot)
    var near = [point(ring, place - 1), point(ring, place + 1)]
    if (place % 2 === 1) {
      // Only the midpoints are joined between rings, straight through.
      if (ring > 0) near.push(point(ring - 1, place))
      if (ring < RINGS - 1) near.push(point(ring + 1, place))
    }
    near.sort(function (a, b) { return a - b })
    out.push(near)
  }
  return out
})()

var MILLS = (function () {
  var out = []
  for (var ring = 0; ring < RINGS; ring++)
    for (var corner = 0; corner < 8; corner += 2)
      out.push([point(ring, corner), point(ring, corner + 1), point(ring, corner + 2)])
  var across = [1, 3, 5, 7]
  for (var i = 0; i < across.length; i++)
    out.push([point(0, across[i]), point(1, across[i]), point(2, across[i])])
  return out
})()

function maskOf(list) {
  var m = 0
  for (var i = 0; i < list.length; i++) m |= 1 << list[i]
  return m
}

var MILL_MASKS = MILLS.map(maskOf)
// Which mills a point belongs to: two each.
var MILLS_AT = (function () {
  var out = []
  for (var spot = 0; spot < POINTS; spot++) {
    var here = []
    for (var i = 0; i < MILLS.length; i++) if (MILLS[i].indexOf(spot) >= 0) here.push(i)
    out.push(here)
  }
  return out
})()
var NEIGHBOUR_MASKS = NEIGHBOURS.map(maskOf)

// A move is one integer. A placement or a removal is the point itself; a
// movement is the pair, offset past them so the two cannot be confused. That
// offset is the whole encoding, and it is what goes in the file.
var MOVE_BASE = POINTS

function placeMove(spot) { return spot }
function travel(src, dst) { return MOVE_BASE + src * POINTS + dst }
function isTravel(move) { return move >= MOVE_BASE }

// [from, to] for a movement, or [-1, point] for a placement or removal.
function unpack(move) {
  if (move < MOVE_BASE) return [-1, move]
  var n = move - MOVE_BASE
  return [Math.floor(n / POINTS), n % POINTS]
}

function spotName(spot) { return "abc"[ringOf(spot)] + (placeOf(spot) + 1) }

// `c2` or `c2-b2`: rings lettered from the outside in, places numbered
// clockwise from the top-left corner.
function notation(move) {
  var u = unpack(move)
  return u[0] < 0 ? spotName(u[1]) : spotName(u[0]) + "-" + spotName(u[1])
}

// ------------------------------------------------------------ positions

function position(white, black, turn, placed, removing) {
  return {
    white: white || 0, black: black || 0,
    turn: turn === BLACK ? BLACK : WHITE,
    placed: placed ? [placed[0], placed[1]] : [0, 0],
    removing: !!removing
  }
}

var OPENING = position(0, 0, WHITE, [0, 0], false)

function same(a, b) {
  return a.white === b.white && a.black === b.black && a.turn === b.turn
    && a.placed[0] === b.placed[0] && a.placed[1] === b.placed[1] && a.removing === b.removing
}

function men(p, colour) { return colour === WHITE ? p.white : p.black }
function own(p) { return men(p, p.turn) }
function opp(p) { return men(p, other(p.turn)) }
function count(p, colour) { return popcount(men(p, colour)) }
// Pieces still to place: what the score strip shows after the plus.
function left(p, colour) { return PIECES - p.placed[colour] }
function empty(p) { return FULL & ~(p.white | p.black) }
function placing(p, colour) { return p.placed[colour] < PIECES }

// Down to three, and allowed to move anywhere -- only once the placing phase
// is over. Three on the board because three have been placed is the third
// turn, not the endgame.
function flying(p, colour) { return !placing(p, colour) && count(p, colour) === FLYING }

// Would `colour` holding `spot` complete a mill? `without` is the point it is
// moving off, which comes out first: a piece that slides along its own mill
// and back closes nothing.
function closes(p, colour, spot, without) {
  var m = men(p, colour) | (1 << spot)
  if (without !== undefined && without >= 0) m &= ~(1 << without)
  var at = MILLS_AT[spot]
  for (var i = 0; i < at.length; i++) if ((m & MILL_MASKS[at[i]]) === MILL_MASKS[at[i]]) return true
  return false
}

function inMill(p, colour, spot) {
  var m = men(p, colour)
  var at = MILLS_AT[spot]
  for (var i = 0; i < at.length; i++) if ((m & MILL_MASKS[at[i]]) === MILL_MASKS[at[i]]) return true
  return false
}

function millsOf(board) {
  var n = 0
  for (var i = 0; i < MILL_MASKS.length; i++) if ((board & MILL_MASKS[i]) === MILL_MASKS[i]) n += 1
  return n
}

// Which of the other side's pieces may be taken: not one in a mill -- unless
// every one of them is. That is the rule everybody forgets, and without it a
// side that has walled itself into mills can never be touched.
function removable(p) {
  var them = other(p.turn)
  var theirs = spots(men(p, them))
  var loose = theirs.filter(function (s) { return !inMill(p, them, s) })
  return loose.length ? loose : theirs
}

function moves(p) {
  var out = [], i, j
  if (p.removing) return removable(p)
  if (placing(p, p.turn)) return spots(empty(p))
  var free = empty(p)
  var mine = spots(own(p))
  if (flying(p, p.turn)) {
    var to = spots(free)
    for (i = 0; i < mine.length; i++)
      for (j = 0; j < to.length; j++) out.push(travel(mine[i], to[j]))
    return out
  }
  for (i = 0; i < mine.length; i++) {
    var near = spots(free & NEIGHBOUR_MASKS[mine[i]])
    for (j = 0; j < near.length; j++) out.push(travel(mine[i], near[j]))
  }
  return out
}

function isLegal(p, move) {
  return typeof move === "number" && moves(p).indexOf(move) >= 0
}

// Where this piece may go: what a tap on it lights up.
function destinations(p, src) {
  if (p.removing || placing(p, p.turn)) return []
  if (!((own(p) >> src) & 1)) return []
  if (flying(p, p.turn)) return spots(empty(p))
  return spots(empty(p) & NEIGHBOUR_MASKS[src])
}

// The position after this move. Throws on an illegal one.
function play(p, move) {
  if (!isLegal(p, move)) throw new Error(notation(move) + " is not a legal move")
  var them = other(p.turn)
  var u = unpack(move), src = u[0], dst = u[1]

  if (p.removing) {
    var theirs = men(p, them) & ~(1 << dst)
    return p.turn === WHITE
      ? position(p.white, theirs, them, p.placed, false)
      : position(theirs, p.black, them, p.placed, false)
  }

  var mine = own(p)
  var placed = [p.placed[0], p.placed[1]]
  if (src < 0) {
    mine |= 1 << dst
    placed[p.turn] += 1
  } else {
    mine = (mine & ~(1 << src)) | (1 << dst)
  }
  var white = p.turn === WHITE ? mine : p.white
  var black = p.turn === WHITE ? p.black : mine
  var made = closes(p, p.turn, dst, src)
  var after = position(white, black, p.turn, placed, true)
  if (made && removable(after).length) return after
  return position(white, black, them, placed, false)
}

// Has this side lost? Two pieces, or nowhere to go -- and only once its
// placing phase is done. "Nowhere to go" is only asked of the side on move.
function lost(p, colour) {
  if (placing(p, colour)) return false
  if (count(p, colour) < FLYING) return true
  if (p.turn !== colour || p.removing) return false
  return moves(p).length === 0
}

function isOver(p) { return lost(p, WHITE) || lost(p, BLACK) }

function winner(p) {
  if (lost(p, WHITE)) return BLACK
  if (lost(p, BLACK)) return WHITE
  return null
}

// ------------------------------------------------------------ games

// A game is its move list, and everything else is replayed from it: undo is
// a pop, the file is small integers, and a board legal play could not reach
// cannot be loaded, because loading is playing.
//
// {moves, position, quiet}: `quiet` counts moves in the moving phase since
// anything was taken, for the fifty-move draw.
function apply(g, move) {
  if (!isLegal(g.position, move)) return false
  var before = g.position
  g.position = play(before, move)
  g.moves.push(move)
  if (before.removing || placing(before, before.turn)) g.quiet = 0
  else g.quiet += 1
  return true
}

function newGame() { return { moves: [], position: OPENING, quiet: 0 } }

// As much of a recorded game as will legally play.
function resume(list) {
  var g = newGame()
  for (var i = 0; i < list.length; i++) {
    var m = list[i]
    if (typeof m !== "number" || m !== Math.floor(m)) break
    if (!apply(g, m)) break
  }
  return g
}

function drawn(g) { return !isOver(g.position) && g.quiet >= QUIET_LIMIT }
function gameOver(g) { return isOver(g.position) || drawn(g) }

function lastMove(list) { return list.length ? list[list.length - 1] : null }

// What one move did, for the board to show: the mover, where from and to, a
// piece taken, and the mill that earned it.
function describe(before, move) {
  var u = unpack(move)
  var colour = before.turn
  if (before.removing) return { move: move, colour: colour, src: -1, dst: -1, removed: u[1], mill: [] }
  var after = play(before, move)
  var mill = []
  if (after.removing) {
    var m = men(after, colour)
    var at = MILLS_AT[u[1]]
    for (var i = 0; i < at.length; i++)
      if ((m & MILL_MASKS[at[i]]) === MILL_MASKS[at[i]]) { mill = MILLS[at[i]].slice(); break }
  }
  return { move: move, colour: colour, src: u[0], dst: u[1], removed: -1, mill: mill }
}

// One ply back, or null with nothing to take.
function undo(list) { return list.length ? list.slice(0, -1) : null }

// Rewind until `colour` is on move again, not owing a removal, with something
// undone -- or null. A single ply is sometimes half a turn, because a mill owes
// a removal, and the computer's reply would still be on the board.
function takeback(list, colour) {
  var out = list.slice()
  var undone = false
  while (out.length) {
    out.pop()
    undone = true
    var p = resume(out).position
    if (p.turn === colour && !p.removing) break
  }
  return undone ? out : null
}
