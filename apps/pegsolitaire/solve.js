// The worker thread's program: one hint, off the UI thread.
//
// A WorkerScript source is not a QML document, so a `.import` in it does
// nothing; `Qt.include()` runs Solver.js in this scope instead, which is why
// Solver.js imports nothing and its functions arrive here as globals.
// Reversi's search.js found that out, and says how.
Qt.include("Solver.js")

WorkerScript.onMessage = function (msg) {
  var answer
  try {
    answer = search(msg.holes, msg.pegs, msg.target, msg.seconds)
  } catch (e) {
    // A hint that dies must not take the game with it: the board is still
    // playable, and the honest report is that there is no answer.
    answer = { verdict: UNKNOWN, line: [], nodes: 0, trouble: String(e) }
  }
  answer.generation = msg.generation
  WorkerScript.sendMessage(answer)
}
