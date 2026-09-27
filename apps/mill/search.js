// The worker thread's program: one search, off the UI thread.
//
// Reversi's search.js found the three facts this file is shaped by: a
// WorkerScript source is not a QML document, so `.import` in it -- or in a file
// it includes -- does nothing, while `Qt.include()` runs a file in this scope.
// So Mill.js is included and its namespace rebuilt by hand, before Ai.js, which
// refers to `M.*`, is included after it. The files stay unchanged and work the
// ordinary way from QML: one copy of the rules, not a worker's own.
Qt.include("Mill.js")

var M = {
  RINGS: RINGS, PLACES: PLACES, POINTS: POINTS, FULL: FULL, WHITE: WHITE, BLACK: BLACK,
  PIECES: PIECES, FLYING: FLYING, QUIET_LIMIT: QUIET_LIMIT,
  other: other, popcount: popcount, spots: spots, NEIGHBOURS: NEIGHBOURS,
  MILLS: MILLS, MILL_MASKS: MILL_MASKS, MILLS_AT: MILLS_AT, NEIGHBOUR_MASKS: NEIGHBOUR_MASKS,
  unpack: unpack, travel: travel, placeMove: placeMove,
  men: men, own: own, opp: opp, count: count, left: left, empty: empty,
  placing: placing, flying: flying, closes: closes, inMill: inMill, millsOf: millsOf,
  removable: removable, moves: moves, isLegal: isLegal, play: play,
  lost: lost, isOver: isOver, winner: winner
}

Qt.include("Ai.js")

WorkerScript.onMessage = function (msg) {
  var answer
  try {
    var move = choose(msg.position, levelFor(msg.level), function () { return Date.now() / 1000 }, null)
    answer = { move: move }
  } catch (e) {
    // A search that dies takes the game with it: this thread is the only thing
    // that will ever move for this side, so it answers with a legal move.
    var legal = []
    try { legal = M.moves(msg.position) } catch (inner) { legal = [] }
    answer = { move: legal.length ? legal[0] : -1, trouble: String(e) }
  }
  answer.generation = msg.generation
  WorkerScript.sendMessage(answer)
}
