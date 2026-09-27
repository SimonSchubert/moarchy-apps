// The rules of peg solitaire, on a board that is a number.
//
// A board is a 7x7 grid with the corners cut off, so a whole position is one
// 49-bit set of holes -- which is past what JavaScript's bitwise operators
// reach (32 bits) and well inside what a double holds exactly (53). So a mask
// here is a plain Number, the sum of 2^cell for every cell in it, and the bit
// arithmetic is done with powers of two rather than shifts. The file is the
// same one 0.1.0's pegs.py described: cell (row, column) is row * 7 + column,
// and a jump is `cell * 4 + direction`, directions up, down, left, right.
//
// The figures at the bottom are the app's content: the same board with
// different pegs standing on it is a different puzzle, for the cost of a
// picture. Every one of them is solved by tests/tst_solver.qml on every run.
//
// Ported from the GTK version's pegs.py (0.1.0), case for case.
.pragma library

var SIZE = 7
var CELLS = SIZE * SIZE
var CENTRE = 3 * SIZE + 3

var UP = 0, DOWN = 1, LEFT = 2, RIGHT = 3
var DIRECTIONS = [UP, DOWN, LEFT, RIGHT]
var STEPS = [[-1, 0], [1, 0], [0, -1], [0, 1]]
var ARROWS = ["up", "down", "left", "right"]

var POW = (function () {
  var out = []
  for (var i = 0; i < CELLS; i++) out.push(Math.pow(2, i))
  return out
})()

function index(row, column) { return row * SIZE + column }
function rowOf(cell) { return Math.floor(cell / SIZE) }
function columnOf(cell) { return cell % SIZE }

// Whether a cell is in a mask.
function has(mask, cell) {
  if (cell < 0 || cell >= CELLS) return false
  return Math.floor(mask / POW[cell]) % 2 === 1
}
function withCell(mask, cell) { return has(mask, cell) ? mask : mask + POW[cell] }
function without(mask, cell) { return has(mask, cell) ? mask - POW[cell] : mask }

// The cells set in a mask, lowest first.
function cells(mask) {
  var out = []
  var m = mask
  for (var i = 0; i < CELLS && m > 0; i++) {
    if (m % 2 === 1) out.push(i)
    m = Math.floor(m / 2)
  }
  return out
}
function count(mask) { return cells(mask).length }

// A picture of a board, as { holes, pegs }: `o` a peg, `.` an empty hole,
// anything else not part of the board.
function parse(art) {
  var holes = 0, pegs = 0
  var rows = String(art).replace(/^\n+|\n+$/g, "").split("\n")
    .filter(function (l) { return l.trim() !== "" })
  for (var r = 0; r < Math.min(rows.length, SIZE); r++) {
    var line = rows[r]
    for (var c = 0; c < Math.min(line.length, SIZE); c++) {
      var g = line[c]
      if (g !== "o" && g !== ".") continue
      holes += POW[index(r, c)]
      if (g === "o") pegs += POW[index(r, c)]
    }
  }
  return { holes: holes, pegs: pegs }
}

function encode(cell, direction) { return cell * DIRECTIONS.length + direction }
function decode(move) { return [Math.floor(move / DIRECTIONS.length), move % DIRECTIONS.length] }

// `d4 up`, for the tests and the screen reader.
function notation(move) {
  var d = decode(move)
  return String.fromCharCode(97 + columnOf(d[0])) + (rowOf(d[0]) + 1) + " " + ARROWS[d[1]]
}

// The cell `distance` steps from `cell`, or -1 off the grid. The edge is what
// stops a peg on the right of one row jumping onto the left of the next.
function step(cell, direction, distance) {
  var r = rowOf(cell) + STEPS[direction][0] * distance
  var c = columnOf(cell) + STEPS[direction][1] * distance
  if (r < 0 || r >= SIZE || c < 0 || c >= SIZE) return -1
  return index(r, c)
}

function position(holes, pegs) { return { holes: holes, pegs: pegs } }
function isEmpty(p, cell) { return has(p.holes, cell) && !has(p.pegs, cell) }
function pegCount(p) { return count(p.pegs) }

function isLegal(p, move) {
  if (typeof move !== "number" || !isFinite(move) || Math.floor(move) !== move) return false
  var d = decode(move)
  var cell = d[0], dir = d[1]
  if (cell < 0 || cell >= CELLS || DIRECTIONS.indexOf(dir) < 0) return false
  if (!has(p.pegs, cell)) return false
  var over = step(cell, dir, 1), land = step(cell, dir, 2)
  if (over < 0 || land < 0) return false
  return has(p.pegs, over) && isEmpty(p, land)
}

// Every legal jump, as encoded integers, in ascending order -- the order the
// solver tries them in, so a hint is the same hint every time.
function moves(p) {
  var out = []
  var pegs = cells(p.pegs)
  for (var i = 0; i < pegs.length; i++)
    for (var d = 0; d < DIRECTIONS.length; d++) {
      var m = encode(pegs[i], d)
      if (isLegal(p, m)) out.push(m)
    }
  out.sort(function (a, b) { return a - b })
  return out
}

// The jumps this one peg can make: what a tap needs.
function jumpsFrom(p, cell) {
  return moves(p).filter(function (m) { return decode(m)[0] === cell })
}

// [the peg jumped over, the hole landed in].
function landing(move) {
  var d = decode(move)
  return [step(d[0], d[1], 1), step(d[0], d[1], 2)]
}

// The position after a jump, or null for one that is not legal.
function play(p, move) {
  if (!isLegal(p, move)) return null
  var cell = decode(move)[0]
  var l = landing(move)
  var pegs = without(without(p.pegs, cell), l[0])
  return position(p.holes, withCell(pegs, l[1]))
}

function stuck(p) { return moves(p).length === 0 }
function solved(p) { return pegCount(p) === 1 }
// One peg, and it is the middle one.
function perfectAt(p, target) { return pegCount(p) === 1 && has(p.pegs, target) }

// `centre` is a claim about the figure -- that its last peg can be made to land
// in the middle -- and it is checked, not asserted: tst_solver.qml solves every
// figure both ways and fails if a claim is wrong.
var FIGURES = [
  { key: "english", label: "English board", centre: true,
    blurb: "Thirty-two pegs, the middle empty. The one everybody means.",
    art: "\n  ooo\n  ooo\nooooooo\nooo.ooo\nooooooo\n  ooo\n  ooo\n" },
  { key: "cross", label: "Cross", centre: false,
    blurb: "Six pegs. The gentlest way in.",
    art: "\n  ...\n  .o.\n...o...\n..ooo..\n...o...\n  ...\n  ...\n" },
  { key: "plus", label: "Plus", centre: true,
    blurb: "Nine pegs, and eight jumps if you find them.",
    art: "\n  ...\n  .o.\n...o...\n.ooooo.\n...o...\n  .o.\n  ...\n" },
  { key: "pyramid", label: "Pyramid", centre: true,
    blurb: "Nine pegs stacked three deep, finishing in the middle.",
    art: "\n  ...\n  ...\n...o...\n..ooo..\n.ooooo.\n  ...\n  ...\n" },
  { key: "hearth", label: "Hearth", centre: false,
    blurb: "Twelve pegs. It looks easier than it is.",
    art: "\n  ...\n  ...\n..ooo..\n.ooooo.\noo...oo\n  ...\n  ...\n" },
  { key: "diamond", label: "Diamond", centre: true,
    blurb: "Twelve pegs, symmetrical every way you look at it.",
    art: "\n  ...\n  .o.\n..ooo..\n.oo.oo.\n..ooo..\n  .o.\n  ...\n" },
  { key: "arrow", label: "Arrow", centre: false,
    blurb: "Thirteen pegs pointing the way out.",
    art: "\n  .o.\n  ooo\n.ooooo.\n...o...\n...o...\n  .o.\n  .o.\n" },
  { key: "wall", label: "Wall", centre: false,
    blurb: "Fourteen pegs in two rows, and nothing else on the board.",
    art: "\n  ...\n  ...\nooooooo\nooooooo\n.......\n  ...\n  ...\n" },
  { key: "goblet", label: "Goblet", centre: true,
    blurb: "Sixteen pegs, fifteen jumps, and it ends in the middle.",
    art: "\n  ...\n  ...\nooooooo\n.ooooo.\n..ooo..\n  .o.\n  ...\n" }
]
var FIGURE_KEYS = FIGURES.map(function (f) { return f.key })
var DEFAULT_FIGURE = "english"

function figureFor(key) {
  for (var i = 0; i < FIGURES.length; i++) if (FIGURES[i].key === key) return FIGURES[i]
  return FIGURES[0]
}

function start(figure) {
  var b = parse(figure.art)
  return position(b.holes, b.pegs)
}

// A figure and the jumps made on it: { figure, moves, position }. The list is
// the state and the board is derived by replaying it, so a board that could
// not have arisen from legal play cannot be loaded -- loading is playing. A bad
// tail is dropped.
function resume(key, list) {
  var figure = figureFor(key)
  var p = start(figure)
  var kept = []
  var src = list && list.constructor === Array ? list : []
  for (var i = 0; i < src.length; i++) {
    var next = play(p, src[i])
    if (next === null) break
    p = next
    kept.push(src[i])
  }
  return { figure: figure, moves: kept, position: p }
}

function over(game) { return stuck(game.position) }
// One peg in the middle, on a figure where that can happen at all: the Cross
// finishes with one peg that can never be the middle one, and a game that said
// "nearly" there would be setting a task with no answer.
function perfect(game) { return game.figure.centre && perfectAt(game.position, CENTRE) }
