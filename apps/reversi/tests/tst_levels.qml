// The levels are meant to differ in strength, not only in patience -- which
// cannot be asserted about a position and has to be played out. 0.1.0's
// test_ai.py case: a four-ply Hard beats Easy from either side.
//
// The clock is held still, so the depth is the level's ceiling and not how
// fast this machine is, and the dice are seeded, so a failure repeats.
import QtQuick
import QtTest
import "../Reversi.js" as R
import "../Ai.js" as Ai

TestCase {
  name: "ReversiLevels"

  function rng(seed) {
    var a = seed >>> 0
    return function () {
      a = (a + 0x6D2B79F5) >>> 0
      var t = a
      t = Math.imul(t ^ (t >>> 15), t | 1)
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296
    }
  }

  function test_hard_beats_easy_from_either_side() {
    var still = function () { return 0 }
    var hard = { key: "h", name: "Hard", blurb: "", depth: 4, seconds: 1, slack: 0, exact: false }
    var easy = Ai.levelFor("easy")
    var sides = [[0, R.DARK], [1, R.LIGHT]]
    for (var s = 0; s < sides.length; s++) {
      var dice = rng(sides[s][0])
      var pick = function (list) { return list[Math.floor(dice() * list.length)] }
      var strong = sides[s][1]
      var moves = []
      var p = R.OPENING
      while (!R.isOver(p)) {
        var level = p.turn === strong ? hard : easy
        var cell = Ai.think(p, level, still, pick).cell
        moves = R.playTurn(moves, cell).moves
        p = R.replay(moves).position
      }
      compare(R.winner(p), strong, "easy won game " + sides[s][0] + ": " + R.counts(p))
    }
  }
}
