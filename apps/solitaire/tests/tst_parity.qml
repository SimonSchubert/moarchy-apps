// Klondike.js against the Python it was ported from: two games 0.1.0's engine
// played, replayed here, and compared card by card -- so a deal left in the GTK
// app is the same table in this one.
import QtQuick
import QtTest
import "../Klondike.js" as K
import "Golden.js" as G

TestCase {
  name: "SolitaireParity"

  function check(which) {
    var g = G.GAMES[which]
    var game = K.resume(g.deck, g.draw, g.moves)
    compare(game.moves.length, g.moves.length, which + ": every recorded move plays")
    compare(game.table.stock, g.table.stock)
    compare(game.table.waste, g.table.waste)
    compare(game.table.up, g.table.up)
    compare(game.table.piles, g.table.piles)
    compare(game.table.down, g.table.down)
    compare(K.finishable(game.table), g.finishable)
    compare(K.isStuck(game), g.stuck)
    compare(K.moves(game.table), g.moves_now, which + ": the same legal moves, in the same order")
    if (g.finishable) compare(K.homeward(game.table), g.homeward)
  }

  function test_a_game_in_progress_replays_to_pythons_table() { check("table") }
  function test_a_game_ready_to_finish_replays_and_runs_home_as_python_did() { check("home") }
}
