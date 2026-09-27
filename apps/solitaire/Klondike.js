// The rules of Klondike, as five arrays and a list of moves.
//
// Ported from the GTK version's klondike.py (0.1.0), and checked against it:
// tests/tst_parity.qml replays two games that engine played and compares every
// card. A game left in either is the same table in the other.
//
// A card is an integer from 0 to 51: `card / 4` is its rank, ace as 0 and king
// as 12, and `card % 4` its suit in the order clubs, diamonds, hearts, spades --
// so the two red suits are the two in the middle. Fifty-two small integers is a
// whole deck a person can read in a JSON file.
//
// A table is {stock, waste, up, piles, down, draw}. `down` is the number of
// face-down cards at the *bottom* of each column: face-down cards in Klondike
// are always at the bottom and always contiguous, so a count says everything a
// flag per card would.
//
// The invariant the whole file leans on: **the face-up part of a column is
// always a legal run.** Cards only ever land on a column as a descending
// alternating sequence, so every suffix of the face-up part is movable and a
// run is validated when it is put down, never when it is picked up.
//
// A game is a deck and a list of moves; the table is derived by replaying
// them. Undo is a pop, the file is small integers, and a table legal play could
// not reach cannot be loaded, because loading is playing.
.pragma library

var SUITS = 4
var RANKS = 13
var DECK = SUITS * RANKS

var CLUB = 0, DIAMOND = 1, HEART = 2, SPADE = 3
var SUIT_NAMES = ["clubs", "diamonds", "hearts", "spades"]
var RANK_NAMES = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]

var ACE = 0
var KING = RANKS - 1
var COLUMNS = 7

// Where a card can be. The numbering is what goes in the file, so it is fixed:
// 0 the stock, 1 the waste, 2 to 5 the foundations in suit order, 6 to 12 the
// seven columns left to right.
var STOCK = 0
var WASTE = 1
var FOUNDATION = 2
var TABLEAU = FOUNDATION + SUITS
var PILES = TABLEAU + COLUMNS

// How many cards a tap on the stock turns over. Three is the game as it is
// printed on the box; one is the game people actually play on a bus.
var DRAWS = [1, 3]
var DEFAULT_DRAW = 1

function rank(card) { return Math.floor(card / SUITS) }
function suit(card) { return card % SUITS }
function isRed(card) { var s = suit(card); return s === DIAMOND || s === HEART }
function name(card) { return RANK_NAMES[rank(card)] + " of " + SUIT_NAMES[suit(card)] }
function foundationOf(card) { return FOUNDATION + suit(card) }
function isFoundation(pile) { return pile >= FOUNDATION && pile < TABLEAU }
function isTableau(pile) { return pile >= TABLEAU && pile < PILES }

// Fisher-Yates with the given random() -- Math.random by default. The deck is
// what is saved, not a seed, so a deal survives any change to this function.
function shuffled(random) {
  var r = random || Math.random
  var deck = []
  for (var i = 0; i < DECK; i++) deck.push(i)
  for (var j = DECK - 1; j > 0; j--) {
    var k = Math.floor(r() * (j + 1))
    var t = deck[j]; deck[j] = deck[k]; deck[k] = t
  }
  return deck
}

// A seeded random(), for the tests: the same numbers every run.
function seeded(seed) {
  var a = seed >>> 0
  return function () {
    a = (a + 0x6D2B79F5) >>> 0
    var t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

// ------------------------------------------------------------ moves

// [src, dst, count]. `count` is recorded rather than worked out on replay, so
// a deal means what it meant when it was played whatever the file's draw says.
function move(src, dst, count) { return [src, dst, count === undefined ? 1 : count] }

// One move out of whatever a JSON file actually had in it, or null.
function moveOf(raw) {
  if (!raw || raw.constructor !== Array || raw.length !== 3) return null
  for (var i = 0; i < 3; i++)
    if (typeof raw[i] !== "number" || raw[i] !== Math.floor(raw[i])) return null
  return [raw[0], raw[1], raw[2]]
}

function sameMove(a, b) { return a[0] === b[0] && a[1] === b[1] && a[2] === b[2] }

// ------------------------------------------------------------ the table

function isDeck(deck) {
  if (!deck || deck.constructor !== Array || deck.length !== DECK) return false
  var seen = []
  for (var i = 0; i < DECK; i++) {
    var c = deck[i]
    if (typeof c !== "number" || c !== Math.floor(c) || c < 0 || c >= DECK || seen[c]) return false
    seen[c] = true
  }
  return true
}

// Seven columns of one to seven cards, the rest face down in the stock.
// Null for anything that is not a deck.
function deal(deck, draw) {
  if (!isDeck(deck)) return null
  var piles = []
  var at = 0
  for (var c = 0; c < COLUMNS; c++) {
    piles.push(deck.slice(at, at + c + 1))
    at += c + 1
  }
  var down = []
  for (var d = 0; d < COLUMNS; d++) down.push(d)
  return {
    stock: deck.slice(at), waste: [], up: [0, 0, 0, 0],
    piles: piles, down: down,
    draw: DRAWS.indexOf(draw) >= 0 ? draw : DEFAULT_DRAW
  }
}

function copy(t) {
  return {
    stock: t.stock.slice(), waste: t.waste.slice(), up: t.up.slice(),
    piles: t.piles.map(function (p) { return p.slice() }), down: t.down.slice(), draw: t.draw
  }
}

function column(t, pile) { return t.piles[pile - TABLEAU] }
function hidden(t, pile) { return t.down[pile - TABLEAU] }
function faceUp(t, pile) { return column(t, pile).slice(hidden(t, pile)) }

// The card that can be taken off this pile, or -1 if there is none.
function top(t, pile) {
  if (pile === STOCK) return t.stock.length ? t.stock[t.stock.length - 1] : -1
  if (pile === WASTE) return t.waste.length ? t.waste[t.waste.length - 1] : -1
  if (isFoundation(pile)) {
    var n = t.up[pile - FOUNDATION]
    return n ? (n - 1) * SUITS + (pile - FOUNDATION) : -1
  }
  var col = column(t, pile)
  return col.length ? col[col.length - 1] : -1
}

function cardsIn(t, pile) {
  if (pile === STOCK) return t.stock.length
  if (pile === WASTE) return t.waste.length
  if (isFoundation(pile)) return t.up[pile - FOUNDATION]
  return column(t, pile).length
}

function won(t) { for (var i = 0; i < SUITS; i++) if (t.up[i] !== RANKS) return false; return true }
function home(t) { return t.up[0] + t.up[1] + t.up[2] + t.up[3] }
function anyDown(t) { for (var i = 0; i < COLUMNS; i++) if (t.down[i]) return true; return false }

// Is there nothing left to find out -- and does playing it out win? Checked by
// doing it rather than by trusting the argument: a banner offering to finish a
// game that then does not finish is worse than no banner.
function finishable(t) {
  if (won(t) || anyDown(t) || home(t) >= DECK) return false
  var ms = homeward(t)
  var table = t
  for (var i = 0; i < ms.length; i++) table = apply(table, ms[i])
  return won(table)
}

// May this card land here? Asked of the bottom card of a run.
function accepts(t, pile, card) {
  if (isFoundation(pile)) {
    var index = pile - FOUNDATION
    return suit(card) === index && rank(card) === t.up[index]
  }
  if (!isTableau(pile)) return false
  var col = column(t, pile)
  if (!col.length) return rank(card) === KING
  var under = col[col.length - 1]
  return rank(under) === rank(card) + 1 && isRed(under) !== isRed(card)
}

// The cards a tap at this position picks up. Only a column has positions;
// everywhere else there is one card to take and it is the top one. A face-down
// card picks up nothing: it is not a card yet, it is the back of one.
function runFrom(t, pile, position) {
  if (!isTableau(pile)) {
    var c = top(t, pile)
    return c < 0 ? [] : [c]
  }
  var col = column(t, pile)
  if (position < 0 || position >= col.length || position < hidden(t, pile)) return []
  return col.slice(position)
}

// Everywhere the run picked up here could legally be put down.
//
// An ace never goes to a column: the rules allow a black ace on a red two and
// nobody has ever wanted it. Empty columns count once: three empty columns
// are one decision. And a whole column does not move to an empty one: it
// changes nothing, and it would make a lost game undetectable.
function destinations(t, pile, position) {
  var run = runFrom(t, pile, position)
  if (!run.length) return []
  var card = run[0]
  var out = []
  if (run.length === 1 && accepts(t, foundationOf(card), card)) out.push(foundationOf(card))
  if (run.length === 1 && rank(card) === ACE) return out
  var whole = isTableau(pile) && position === 0
  var empty = -1
  for (var c = TABLEAU; c < PILES; c++) {
    if (c === pile || !accepts(t, c, card)) continue
    if (column(t, c).length) out.push(c)
    else if (empty < 0 && !whole) empty = c
  }
  if (empty >= 0) out.push(empty)
  return out
}

// Every legal move. For the tests and for "is this game stuck".
function moves(t) {
  var out = []
  if (t.stock.length) out.push(move(STOCK, WASTE, Math.min(t.draw, t.stock.length)))
  else if (t.waste.length) out.push(move(WASTE, STOCK, t.waste.length))
  var piles = [WASTE]
  for (var p = FOUNDATION; p < PILES; p++) piles.push(p)
  for (var i = 0; i < piles.length; i++) {
    var pile = piles[i]
    var positions = []
    if (pile === WASTE || isFoundation(pile)) positions.push(Math.max(cardsIn(t, pile) - 1, 0))
    else for (var at = hidden(t, pile); at < column(t, pile).length; at++) positions.push(at)
    for (var j = 0; j < positions.length; j++) {
      var run = runFrom(t, pile, positions[j])
      if (!run.length) continue
      var ds = destinations(t, pile, positions[j])
      for (var k = 0; k < ds.length; k++) out.push(move(pile, ds[k], run.length))
    }
  }
  return out
}

function isLegal(t, m) {
  var src = m[0], dst = m[1], count = m[2]
  if (src === STOCK) return dst === WASTE && count > 0 && count <= t.stock.length && count <= t.draw
  if (dst === STOCK) return src === WASTE && !t.stock.length && count === t.waste.length && count > 0
  if (src < 0 || src >= PILES || dst < 0 || dst >= PILES) return false
  if (count < 1 || src === dst) return false
  var held = cardsIn(t, src)
  if (count > held) return false
  if (!isTableau(src) && count !== 1) return false
  var run = runFrom(t, src, held - count)
  if (run.length !== count) return false
  if (isFoundation(dst) && count !== 1) return false
  return accepts(t, dst, run[0])
}

// The table after this move, or null for an illegal one.
function apply(t, m) {
  if (!isLegal(t, m)) return null
  var out = copy(t)
  var src = m[0], dst = m[1], count = m[2]
  if (src === STOCK) {
    // Dealt one at a time onto the waste, so the last one turned over is on
    // top -- the order a hand does it in.
    var taken = out.stock.splice(out.stock.length - count, count)
    out.waste = out.waste.concat(taken)
    return out
  }
  if (dst === STOCK) {
    // Turned face down as one block, which reverses it. Getting this backwards
    // makes a game that is trivially winnable and takes a while to notice.
    out.stock = t.waste.slice().reverse()
    out.waste = []
    return out
  }
  var held = cardsIn(t, src)
  var run = runFrom(t, src, held - count)
  // Take.
  if (src === WASTE) {
    out.waste.splice(out.waste.length - count, count)
  } else if (isFoundation(src)) {
    out.up[src - FOUNDATION] -= count
  } else {
    var index = src - TABLEAU
    out.piles[index].splice(out.piles[index].length - count, count)
    // The card under the one that left turns over. This is the whole rule.
    if (out.down[index] && out.piles[index].length === out.down[index]) out.down[index] -= 1
  }
  // Put.
  if (isFoundation(dst)) out.up[dst - FOUNDATION] += run.length
  else out.piles[dst - TABLEAU] = out.piles[dst - TABLEAU].concat(run)
  return out
}

function sameTable(a, b) { return JSON.stringify(a) === JSON.stringify(b) }

// The moves that finish a table nothing is hidden in. Greedy and exact: send
// home whatever will go, turn the stock over when nothing will, and stop when
// the table is won or a whole pass round the stock changed nothing.
function homeward(t) {
  var out = []
  var table = t
  var stuckFor = 0
  while (!won(table) && stuckFor <= DECK * 2) {
    var played = false
    var piles = [WASTE]
    for (var p = TABLEAU; p < PILES; p++) piles.push(p)
    for (var i = 0; i < piles.length; i++) {
      var card = top(table, piles[i])
      if (card >= 0 && accepts(table, foundationOf(card), card)) {
        var m = move(piles[i], foundationOf(card), 1)
        out.push(m)
        table = apply(table, m)
        stuckFor = 0
        played = true
        break
      }
    }
    if (played) continue
    var turn
    if (table.stock.length) turn = move(STOCK, WASTE, Math.min(table.draw, table.stock.length))
    else if (table.waste.length) turn = move(WASTE, STOCK, table.waste.length)
    else break
    out.push(turn)
    table = apply(table, turn)
    stuckFor += 1
  }
  return out
}

// Is there nothing left but turning the stock over, round and round? Klondike
// has no rule that ends a lost game, so this turns the stock over as many times
// as it takes to come back round and asks each time whether any move exists
// that is not itself turning the stock over.
function stuck(t) {
  var table = t
  for (var steps = 0; steps <= DECK * 2; steps++) {
    var ms = moves(table)
    for (var i = 0; i < ms.length; i++)
      if (ms[i][0] !== STOCK && ms[i][1] !== STOCK) return false
    if (table.stock.length) table = apply(table, move(STOCK, WASTE, Math.min(table.draw, table.stock.length)))
    else if (table.waste.length) table = apply(table, move(WASTE, STOCK, table.waste.length))
    else return true
  }
  return true
}

// ------------------------------------------------------------ a game

// {deck, draw, moves, start, table}. As much of a recorded game as will
// legally play: where a list stops making sense is where the game stops. A
// deck that is not a deck is a fresh deal.
function resume(deck, draw, list, random) {
  var d = DRAWS.indexOf(draw) >= 0 ? draw : DEFAULT_DRAW
  var cards = isDeck(deck) ? deck.slice() : shuffled(random)
  var start = deal(cards, d)
  var game = { deck: cards, draw: d, moves: [], start: start, table: start }
  if (!isDeck(deck) || !list || list.constructor !== Array) return game
  for (var i = 0; i < list.length; i++) {
    var m = moveOf(list[i])
    if (!m) break
    var next = apply(game.table, m)
    if (!next) break
    game.table = next
    game.moves.push(m)
  }
  return game
}

function play(game, m) {
  var next = apply(game.table, m)
  if (!next) return null
  return { deck: game.deck, draw: game.draw, start: game.start, table: next, moves: game.moves.concat([m]) }
}

function undo(game) {
  if (!game.moves.length) return null
  return resume(game.deck, game.draw, game.moves.slice(0, -1))
}

function isStuck(game) { return !won(game.table) && stuck(game.table) }

// The first run on the table with a choice to make, for the screenshots.
function somethingToPick(t) {
  for (var pile = TABLEAU; pile < PILES; pile++)
    for (var at = hidden(t, pile); at < column(t, pile).length; at++)
      if (destinations(t, pile, at).length > 1) return [pile, at]
  if (t.waste.length && destinations(t, WASTE, t.waste.length - 1).length > 1) return [WASTE, t.waste.length - 1]
  return null
}
