// The worker thread's program: one search, off the UI thread.
//
// Inside a WorkerScript `.import` is not processed and `Qt.include()` runs a
// file in this scope (see apps/reversi/search.js, where that was measured).
// So Chess.js is included, its `API` object stands in for the `C` namespace
// Ai.js imports, and then Ai.js is included on top.
Qt.include("Chess.js")

var C = API

Qt.include("Ai.js")

WorkerScript.onMessage = function (msg) {
  var thought
  try {
    var position = fromFen(msg.fen)
    // The history the repetition rule needs, which a FEN does not carry.
    position.keysH = msg.keysH.slice()
    position.keysL = msg.keysL.slice()
    var clock = function () { return Date.now() / 1000 }
    thought = think(position, levelFor(msg.level), null, clock)
    if (!thought) thought = { move: -1, depth: 0, nodes: 0 }
  } catch (e) {
    // A search that dies takes the game with it: this thread is the only thing
    // that will move for this side, so it answers with a legal move.
    var legal = []
    try { legal = moves(fromFen(msg.fen)) } catch (inner) { legal = [] }
    thought = { move: legal.length ? legal[0] : -1, depth: 0, nodes: 0, trouble: String(e) }
  }
  thought.generation = msg.generation
  WorkerScript.sendMessage(thought)
}
