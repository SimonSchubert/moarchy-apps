// The rules on a board made by hand, so that a test about the rules is not
// also a test about where a seed put things. The cases 0.1.0's
// test_minesweeper.py had.
//
//   . . . . .      * is a mine, the rest are empty
//   . * . . .
//   . . . . .
//   . . . * .
//   . . . . .
import QtQuick
import QtTest
import "../Minesweeper.js" as M

TestCase {
  name: "MinesweeperRules"

  readonly property var tiny: ({ key: "tiny", label: "Tiny", width: 5, height: 5, mines: 2 })
  function at(r, c) { return M.index(r, c, 5) }
  function handMade() {
    var g = M.create(tiny, 0, [])
    g.mines = ({})
    g.mines[at(1, 1)] = true
    g.mines[at(3, 3)] = true
    return g
  }
  function openedList(g) {
    var out = []
    for (var k in g.opened) out.push(parseInt(k, 10))
    return out.sort(function (a, b) { return a - b })
  }

  function test_a_cell_counts_the_mines_touching_it() {
    var g = handMade()
    compare(M.count(g, at(0, 0)), 1)
    compare(M.count(g, at(2, 2)), 2)
    compare(M.count(g, at(0, 4)), 0)
  }

  function test_the_first_tap_always_floods_on_every_level() {
    for (var i = 0; i < M.LEVELS.length; i++) {
      var level = M.LEVELS[i]
      var g = M.create(level, 4, [])
      M.tap(g, M.index(Math.floor(level.height / 2), Math.floor(level.width / 2), level.width))
      verify(M.openedCount(g) > 9, level.key)
      verify(!M.lost(g))
    }
  }

  function test_the_first_tap_is_never_a_mine_and_never_a_number() {
    for (var i = 0; i < M.LEVELS.length; i++) {
      var level = M.LEVELS[i]
      for (var seed = 0; seed < 25; seed++) {
        var first = seed * 7 % M.cellCount(level)
        var mines = M.place(level, seed, first)
        verify(!mines[first])
        var near = M.around(first, level.width, level.height)
        for (var n = 0; n < near.length; n++) verify(!mines[near[n]], level.key + " " + seed)
      }
    }
  }

  function test_an_empty_cell_opens_everything_it_leads_to() {
    var g = handMade()
    M.tap(g, at(0, 4))
    verify(g.opened[at(0, 4)])
    verify(g.opened[at(0, 2)])
    verify(!g.opened[at(1, 1)])
  }

  function test_a_numbered_cell_opens_only_itself() {
    var g = handMade()
    M.tap(g, at(0, 0))
    compare(openedList(g), [at(0, 0)])
  }

  function test_nothing_happens_after_it_is_over() {
    var g = handMade()
    M.tap(g, at(1, 1))
    verify(M.lost(g))
    compare(g.boom, at(1, 1))
    verify(!M.tap(g, at(4, 4)))
    verify(!M.mark(g, at(4, 4)))
  }

  function test_the_mines_do_not_have_to_be_flagged_to_win() {
    var g = handMade()
    for (var c = 0; c < 25; c++) if (!g.mines[c]) M.tap(g, c)
    verify(M.won(g))
    compare(M.flagCount(g), 0)
  }

  function test_an_opened_cell_cannot_be_flagged() {
    var g = handMade()
    M.tap(g, at(0, 0))
    verify(!M.mark(g, at(0, 0)))
  }

  function test_a_flag_with_nothing_under_it_is_named() {
    var g = handMade()
    M.mark(g, at(0, 0))
    compare(M.wrongFlags(g), [at(0, 0)])
    M.mark(g, at(1, 1))
    compare(M.wrongFlags(g), [at(0, 0)])
  }

  function test_a_number_with_its_flags_opens_the_rest() {
    var g = handMade()
    M.tap(g, at(0, 0))
    M.mark(g, at(1, 1))
    verify(M.satisfied(g, at(0, 0)))
    verify(M.clearAround(g, at(0, 0)))
    verify(g.opened[at(0, 1)])
    verify(g.opened[at(1, 0)])
    verify(!M.lost(g))
  }

  function test_a_number_without_its_flags_opens_nothing() {
    var g = handMade()
    M.tap(g, at(0, 0))
    verify(!M.satisfied(g, at(0, 0)))
    verify(!M.clearAround(g, at(0, 0)))
    compare(openedList(g), [at(0, 0)])
  }

  function test_a_chord_on_a_wrongly_flagged_number_ends_it() {
    var g = handMade()
    M.tap(g, at(0, 0))
    M.mark(g, at(0, 1))
    verify(M.satisfied(g, at(0, 0)))
    M.clearAround(g, at(0, 0))
    verify(M.lost(g))
  }

  function test_a_zero_and_a_covered_cell_cannot_be_chorded() {
    var g = handMade()
    M.tap(g, at(0, 4))
    verify(!M.clearAround(g, at(0, 4)))
    verify(!M.clearAround(g, at(4, 0)))
  }

  function test_a_tap_that_changes_nothing_is_not_recorded() {
    var g = handMade()
    M.tap(g, at(0, 0))
    var before = g.moves.slice()
    M.tap(g, at(0, 0))
    compare(g.moves, before)
  }

  function test_junk_in_the_move_list_ends_the_game_there() {
    var level = M.levelFor("gentle")
    var g = M.create(level, 5, [])
    M.tap(g, M.index(4, 4, level.width))
    var good = g.moves.slice()
    compare(M.create(level, 5, good.concat([99999]).concat(good)).moves, good)
    compare(M.create(level, 5, good.concat([1.5])).moves, good)
  }

  function test_the_levels_get_harder_in_order() {
    for (var i = 1; i < M.LEVELS.length; i++) {
      var a = M.LEVELS[i - 1], b = M.LEVELS[i]
      verify(b.mines / M.cellCount(b) > a.mines / M.cellCount(a))
      verify(M.cellCount(b) > M.cellCount(a))
    }
    compare(M.levelFor("nonsense").key, "standard")
  }
}
