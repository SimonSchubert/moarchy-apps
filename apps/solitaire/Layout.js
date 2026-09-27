// Where every card on the table is, as arithmetic -- and, from the same
// numbers, which card a tap landed on. The GTK version's layout.py (0.1.0),
// with one addition: a desktop window is wider than a phone is tall, so a card
// is also capped by the height it has, and the table is centred.
//
// Kept out of QML for the reason it was kept out of the widget in Python:
// where a card is drawn and where a tap lands are the same function, and a bug
// in it is a game that plays the wrong card. It is tested without a display.
.pragma library

.import "Klondike.js" as K

// A card, as a ratio: a little squarer than a poker card, because seven
// columns across a 360 px screen fix the width and the height pays for rows.
var ASPECT = 1.45
var MARGIN = 5.0
var GAP = 4.0
// Between the top row and the tableau.
var SPLIT = 12.0
// How much of a covered card shows. Fixed rather than fitted to the tallest
// column, so a column growing does not move every card on the table under a
// thumb; squeezed only when a column would run off the bottom.
var UP_SHARE = 0.42
var DOWN_SHARE = 0.14
var SQUEEZE = 0.45
// How far the three cards of a draw-three deal fan across the waste, into the
// empty slot between it and the first foundation.
var FAN = 0.34
// The smallest table worth drawing.
var MINIMUM = 290
// The largest card, for a desktop window: past this a card is a poster.
var LARGEST = 120

// Which of the seven slots across a pile sits in. The third is left empty on
// purpose: it is where a three-card deal fans out to.
function columnOf(pile) {
  if (pile === K.STOCK) return 0
  if (pile === K.WASTE) return 1
  if (K.isFoundation(pile)) return 3 + (pile - K.FOUNDATION)
  return pile - K.TABLEAU
}

function layoutFor(width, height, table) {
  var w = Math.max(width, MINIMUM)
  var cardW = (w - 2 * MARGIN - (K.COLUMNS - 1) * GAP) / K.COLUMNS
  // On a window wider than it is tall the height decides: a card no taller
  // than a sixth of it, which leaves a column of a dozen room to show every
  // index without being squeezed under the card in front.
  cardW = Math.min(cardW, LARGEST, height / 6.2 / ASPECT)
  cardW = Math.max(cardW, (MINIMUM - 2 * MARGIN - (K.COLUMNS - 1) * GAP) / K.COLUMNS)
  var cardH = cardW * ASPECT
  var stride = cardW + GAP
  var left = (w - (K.COLUMNS * cardW + (K.COLUMNS - 1) * GAP)) / 2
  var tableauY = MARGIN + cardH + SPLIT
  var upStep = cardH * UP_SHARE
  var downStep = cardH * DOWN_SHARE
  // The tallest column decides the squeeze for all seven, so a card is the
  // same size everywhere on the table.
  var tallest = 0
  for (var i = 0; i < K.COLUMNS; i++) {
    var hid = table.down[i]
    var shown = Math.max(table.piles[i].length - hid, 0)
    tallest = Math.max(tallest, hid * downStep + Math.max(shown - 1, 0) * upStep)
  }
  var room = height - tableauY - cardH - MARGIN
  if (tallest > room && room > 0) {
    var shrink = Math.max(room / tallest, SQUEEZE)
    upStep *= shrink
    downStep *= shrink
  }
  return {
    cardW: cardW, cardH: cardH, stride: stride, left: left, top: MARGIN,
    tableauY: tableauY, upStep: upStep, downStep: downStep
  }
}

function slotX(layout, index) { return layout.left + index * layout.stride }

// The rectangle a card in a pile occupies: {x, y, w, h}.
function cardAt(layout, table, pile, position) {
  var x = slotX(layout, columnOf(pile))
  if (K.isTableau(pile)) {
    var hid = K.hidden(table, pile)
    var offset = position < hid ? position * layout.downStep
      : hid * layout.downStep + (position - hid) * layout.upStep
    return { x: x, y: layout.tableauY + offset, w: layout.cardW, h: layout.cardH }
  }
  if (pile === K.WASTE) {
    // Only the last few are drawn, fanned right.
    var shownW = Math.min(table.waste.length, table.draw)
    var place = position - (table.waste.length - shownW)
    return { x: x + Math.max(place, 0) * layout.cardW * FAN, y: layout.top, w: layout.cardW, h: layout.cardH }
  }
  return { x: x, y: layout.top, w: layout.cardW, h: layout.cardH }
}

// Which pile and which card is under a point: [pile, position], or null.
// Generous sideways -- the stride is the hit area, so there is no dead ground
// between two columns -- and strict downwards, because a column is a stack of
// strips and guessing would pick up the wrong run.
function pileAt(layout, table, x, y) {
  var index = Math.floor((x - layout.left + GAP / 2) / layout.stride)
  if (index < 0 || index >= K.COLUMNS) return null
  if (y < layout.tableauY - SPLIT / 2) {
    var tops = [K.STOCK, K.WASTE, K.FOUNDATION, K.FOUNDATION + 1, K.FOUNDATION + 2, K.FOUNDATION + 3]
    for (var i = 0; i < tops.length; i++)
      if (columnOf(tops[i]) === index) return [tops[i], Math.max(K.cardsIn(table, tops[i]) - 1, 0)]
    // The empty slot the waste fans into means the card lying in it.
    if (index === 2 && table.waste.length) return [K.WASTE, table.waste.length - 1]
    return null
  }
  var pile = K.TABLEAU + index
  var col = K.column(table, pile)
  if (!col.length) return [pile, 0]
  for (var p = col.length - 1; p >= 0; p--) {
    var r = cardAt(layout, table, pile, p)
    if (y >= r.y) return y <= r.y + r.h ? [pile, p] : null
  }
  return [pile, 0]
}

// Where a run dragged to this point would be put down: a pile, or -1. Kinder
// than pileAt -- anywhere over a column is that column, however far below its
// last card, because a run is dropped on a column rather than on a card.
function dropAt(layout, x, y) {
  var index = Math.floor((x - layout.left + GAP / 2) / layout.stride)
  if (index < 0 || index >= K.COLUMNS) return -1
  if (y < layout.tableauY - SPLIT / 2) return index >= 3 ? K.FOUNDATION + index - 3 : -1
  return K.TABLEAU + index
}

// How tall the table is, for a Flickable when it runs past the window.
function heightOf(layout, table) {
  var bottom = layout.tableauY + layout.cardH
  for (var i = 0; i < K.COLUMNS; i++) {
    var pile = K.TABLEAU + i
    var n = K.column(table, pile).length
    if (n) {
      var r = cardAt(layout, table, pile, n - 1)
      bottom = Math.max(bottom, r.y + r.h)
    }
  }
  return bottom + MARGIN
}
