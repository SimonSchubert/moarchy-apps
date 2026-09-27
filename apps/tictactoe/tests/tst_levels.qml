// The three levels have to stay ordered by strength. It is the only property
// of an opponent a person can feel, it is the one a tweak to any number in
// Tictactoe.js can quietly break, and no amount of reading the code says
// whether it still holds. The cases 0.1.0's test_ai.py had.
//
// The dice are seeded, so a failure is reproducible and a pass is not luck.
import QtQuick
import QtTest
import "../Tictactoe.js" as T

TestCase {
  name: "TictactoeLevels"

  // mulberry32: small, and the same numbers on every run.
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

  // One game: `computer` plays `level`; the other side plays `opponent`, or
  // taps at random -- somebody not paying attention on a bus, and the only
  // opponent an easy level is meant to be able to lose to.
  function play(computer, level, dice, opponent) {
    var pick = function (list) { return list[Math.floor(dice() * list.length)] }
    var p = T.EMPTY
    while (!T.isOver(p)) {
      var cell
      if (p.turn === computer) cell = T.choose(p, level, pick, dice)
      else if (!opponent) cell = pick(T.legal(p))
      else cell = T.choose(p, opponent, pick, dice)
      p = T.play(p, cell)
    }
    return p
  }

  function outcomes(level, dice, games, opponent) {
    var tally = { won: 0, lost: 0, drawn: 0 }
    for (var n = 0; n < (games || 240); n++) {
      var computer = n % 2 ? T.CROSS : T.NOUGHT
      var w = T.winner(play(computer, level, dice, opponent))
      if (w === null) tally.drawn += 1
      else if (w === computer) tally.won += 1
      else tally.lost += 1
    }
    return tally
  }

  function test_perfect_never_loses() {
    compare(outcomes(T.levelFor("perfect"), rng(7), 400).lost, 0)
  }

  function test_perfect_against_perfect_is_always_a_draw() {
    var perfect = T.levelFor("perfect")
    var dice = rng(11)
    for (var i = 0; i < 30; i++) compare(T.winner(play(T.CROSS, perfect, dice, perfect)), null)
  }

  function test_each_level_loses_more_often_than_the_one_above_it() {
    var easy = outcomes(T.levelFor("easy"), rng(3))
    var fair = outcomes(T.levelFor("fair"), rng(3))
    verify(easy.lost > fair.lost, JSON.stringify([easy, fair]))
    verify(fair.lost > 0, "Fair never loses, which is not fair")
  }

  function test_easy_still_wins_most_of_its_games_against_a_random_player() {
    var easy = outcomes(T.levelFor("easy"), rng(5))
    verify(easy.won > easy.lost, JSON.stringify(easy))
  }
}
