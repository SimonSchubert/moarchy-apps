// The rules: 0.1.0's test_klondike.py, case for case.
//
// Two of these are property tests over a lot of random play, and they are the
// two that matter. Every card exists exactly once, and the face-up part of a
// column is always a run -- the second is why a tap can pick up a run without
// validating it, the first is what a card game gets wrong in a way nobody
// notices until there are two aces of spades on the table.
import QtQuick
import QtTest
import "../Klondike.js" as K

TestCase {
  name: "Klondike"

  function card(r, s) { return r * K.SUITS + s }
  function none(n) { var out = []; for (var i = 0; i < n; i++) out.push([]); return out }
  function zeros(n) { var out = []; for (var i = 0; i < n; i++) out.push(0); return out }
  function ordered() { var d = []; for (var i = 0; i < K.DECK; i++) d.push(i); return d }
  function withT(t, changes) {
    var out = K.copy(t)
    for (var k in changes) out[k] = changes[k]
    return out
  }
  function bare(changes) {
    return withT(withT(K.deal(ordered(), 1), { stock: [], waste: [], piles: none(7), down: zeros(7) }), changes || {})
  }
  function table(stock, piles, draw) {
    return { stock: stock, waste: [], up: [0, 0, 0, 0], piles: piles, down: zeros(7), draw: draw }
  }

  function everyCard(t) {
    var out = t.stock.concat(t.waste)
    for (var i = 0; i < t.piles.length; i++) out = out.concat(t.piles[i])
    for (var s = 0; s < 4; s++) for (var r = 0; r < t.up[s]; r++) out.push(card(r, s))
    return out.sort(function (a, b) { return a - b })
  }
  function runsHold(t) {
    for (var i = 0; i < K.COLUMNS; i++) {
      var shown = K.faceUp(t, K.TABLEAU + i)
      for (var j = 1; j < shown.length; j++)
        if (K.rank(shown[j - 1]) !== K.rank(shown[j]) + 1 || K.isRed(shown[j - 1]) === K.isRed(shown[j])) return false
    }
    return true
  }
  function pick(random, list) { return list[Math.floor(random() * list.length)] }

  // --- the deal
  function test_it_puts_twenty_eight_cards_out_and_twenty_four_away() {
    var t = K.deal(K.shuffled(K.seeded(1)), 1)
    var out = 0
    for (var i = 0; i < 7; i++) out += t.piles[i].length
    compare(out, 28)
    compare(t.stock.length, 24)
    compare(t.down, [0, 1, 2, 3, 4, 5, 6])
    compare(t.up, [0, 0, 0, 0])
  }
  function test_one_card_of_each_column_is_face_up() {
    var t = K.deal(K.shuffled(K.seeded(2)), 1)
    for (var i = 0; i < 7; i++) compare(K.faceUp(t, K.TABLEAU + i).length, 1)
  }
  function test_it_refuses_anything_that_is_not_a_deck() {
    var short = ordered().slice(0, 51)
    var same = []
    for (var i = 0; i < K.DECK; i++) same.push(0)
    compare(K.deal([], 1), null)
    compare(K.deal(short, 1), null)
    compare(K.deal(same, 1), null)
  }
  function test_every_card_is_dealt_exactly_once() {
    compare(everyCard(K.deal(K.shuffled(K.seeded(3)), 1)), ordered())
  }

  // --- what a landing needs
  function test_a_foundation_takes_the_ace_first_and_then_in_order() {
    var t = bare()
    verify(K.accepts(t, K.FOUNDATION + 3, card(K.ACE, 3)))
    verify(!K.accepts(t, K.FOUNDATION + 3, card(1, 3)))
    verify(!K.accepts(t, K.FOUNDATION + 3, card(K.ACE, 0)))
    t = withT(t, { up: [0, 0, 0, 1] })
    verify(K.accepts(t, K.FOUNDATION + 3, card(1, 3)))
  }
  function test_an_empty_column_takes_a_king_and_nothing_else() {
    for (var r = 0; r < 13; r++) compare(K.accepts(bare(), K.TABLEAU, card(r, 0)), r === K.KING)
  }
  function test_a_column_builds_down_in_alternating_colours() {
    var t = bare({ piles: [[card(7, 3)]].concat(none(6)) })
    verify(K.accepts(t, K.TABLEAU, card(6, 1)))
    verify(!K.accepts(t, K.TABLEAU, card(6, 0)))
    verify(!K.accepts(t, K.TABLEAU, card(5, 1)))
  }
  function test_nothing_lands_on_the_stock_or_the_waste_by_accepting() {
    verify(!K.accepts(bare(), K.STOCK, 0))
    verify(!K.accepts(bare(), K.WASTE, 0))
  }

  // --- where a tap can go
  function test_an_ace_only_ever_goes_home() {
    var t = bare({ piles: [[card(1, 1)], [card(K.ACE, 0)]].concat(none(5)) })
    compare(K.destinations(t, K.TABLEAU + 1, 0), [K.FOUNDATION])
  }
  function test_three_empty_columns_are_one_decision() {
    var t = bare({ piles: [[card(5, 0), card(K.KING, 3)]].concat(none(6)), down: [1, 0, 0, 0, 0, 0, 0] })
    compare(K.destinations(t, K.TABLEAU, 1), [K.TABLEAU + 1])
  }
  function test_a_whole_column_does_not_move_to_an_empty_one() {
    var t = bare({ piles: [[card(K.KING, 3)]].concat(none(6)) })
    compare(K.destinations(t, K.TABLEAU, 0), [])
    compare(K.moves(t), [])
  }
  function test_a_face_down_card_picks_up_nothing() {
    var t = K.deal(K.shuffled(K.seeded(4)), 1)
    compare(K.runFrom(t, K.TABLEAU + 6, 0), [])
    compare(K.destinations(t, K.TABLEAU + 6, 0), [])
  }
  function test_a_run_picks_up_from_where_it_was_tapped() {
    var col = [card(7, 3), card(6, 1), card(5, 0)]
    var t = bare({ piles: [col].concat(none(6)) })
    compare(K.runFrom(t, K.TABLEAU, 1), col.slice(1))
    compare(K.runFrom(t, K.TABLEAU, 0), col)
  }

  // --- doing it
  function test_a_deal_turns_them_over_one_at_a_time() {
    var t = K.deal(ordered(), 3)
    var topCard = t.stock[t.stock.length - 1]
    t = K.apply(t, K.move(K.STOCK, K.WASTE, 3))
    compare(t.waste.length, 3)
    compare(t.waste[2], topCard)
    compare(K.top(t, K.WASTE), topCard)
  }
  function test_turning_the_waste_back_over_reverses_it() {
    var t = K.deal(ordered(), 1)
    for (var i = 0; i < 24; i++) t = K.apply(t, K.move(K.STOCK, K.WASTE, 1))
    var was = t.waste.slice()
    t = K.apply(t, K.move(K.WASTE, K.STOCK, was.length))
    compare(t.waste, [])
    compare(t.stock, was.slice().reverse())
    compare(t.stock[0], was[was.length - 1])
  }
  function test_the_card_under_the_one_that_left_turns_over() {
    var t = bare({ piles: [[card(5, 1), card(K.ACE, 3)]].concat(none(6)), down: [1, 0, 0, 0, 0, 0, 0] })
    compare(K.hidden(t, K.TABLEAU), 1)
    t = K.apply(t, K.move(K.TABLEAU, K.FOUNDATION + 3, 1))
    compare(K.hidden(t, K.TABLEAU), 0)
    compare(K.faceUp(t, K.TABLEAU), [card(5, 1)])
  }
  function test_an_illegal_move_is_refused() {
    var t = K.deal(ordered(), 1)
    compare(K.apply(t, K.move(K.TABLEAU, K.FOUNDATION + 1, 1)), null)
    compare(K.apply(t, K.move(K.WASTE, K.TABLEAU, 1)), null)
    compare(K.apply(t, K.move(K.TABLEAU + 6, K.TABLEAU, 7)), null)
  }
  function test_only_a_column_can_move_more_than_one_card() {
    var t = K.deal(ordered(), 1)
    verify(!K.isLegal(t, K.move(K.WASTE, K.TABLEAU, 2)))
    verify(!K.isLegal(t, K.move(K.TABLEAU, K.FOUNDATION, 2)))
  }

  // --- the invariants, over a lot of random play
  function test_every_card_exists_exactly_once_all_the_way_through() {
    var r = K.seeded(20260913)
    for (var seed = 0; seed < 12; seed++) {
      var g = K.resume(K.shuffled(K.seeded(seed)), seed % 2 ? 1 : 3, [])
      for (var i = 0; i < 300; i++) {
        var ms = K.moves(g.table)
        if (!ms.length) break
        g = K.play(g, pick(r, ms))
        compare(everyCard(g.table), ordered(), "seed " + seed + " after " + g.moves.length + " moves")
      }
    }
  }
  function test_the_face_up_part_of_a_column_is_always_a_run() {
    var r = K.seeded(11)
    for (var seed = 0; seed < 12; seed++) {
      var g = K.resume(K.shuffled(K.seeded(seed)), 1, [])
      for (var i = 0; i < 300; i++) {
        var ms = K.moves(g.table)
        if (!ms.length) break
        g = K.play(g, pick(r, ms))
        verify(runsHold(g.table), "seed " + seed)
      }
    }
  }
  function test_replaying_a_game_gives_back_the_same_table() {
    var r = K.seeded(7)
    var g = K.resume(K.shuffled(K.seeded(3)), 1, [])
    for (var i = 0; i < 80; i++) {
      var ms = K.moves(g.table)
      if (!ms.length) break
      g = K.play(g, pick(r, ms))
    }
    verify(K.sameTable(K.resume(g.deck, 1, g.moves).table, g.table))
  }

  // --- finishing
  function laidOut() {
    var runs = []
    var pairs = [[3, 2], [2, 3], [0, 1], [1, 0]]
    for (var p = 0; p < 4; p++) {
      var run = []
      for (var i = 0, r = K.KING; r >= 0; r--, i++) run.push(card(r, i % 2 === 0 ? pairs[p][0] : pairs[p][1]))
      runs.push(run)
    }
    return table([], runs.concat(none(3)), 1)
  }
  function test_a_table_with_nothing_face_down_can_be_finished() {
    var t = laidOut()
    verify(K.finishable(t))
    var ms = K.homeward(t)
    for (var i = 0; i < ms.length; i++) t = K.apply(t, ms[i])
    verify(K.won(t))
  }
  function test_it_finishes_a_stock_full_of_cards_too() {
    var t = table(ordered(), none(7), 3)
    var ms = K.homeward(t)
    for (var i = 0; i < ms.length; i++) t = K.apply(t, ms[i])
    verify(K.won(t))
  }
  function test_a_won_table_is_not_finishable_and_a_fresh_one_is_not_either() {
    var t = laidOut()
    var ms = K.homeward(t)
    for (var i = 0; i < ms.length; i++) t = K.apply(t, ms[i])
    verify(!K.finishable(t))
    verify(!K.finishable(K.deal(K.shuffled(K.seeded(1)), 1)))
  }

  // --- being stuck
  function test_a_table_where_nothing_moves_is_stuck() {
    var ranks = [K.KING, K.KING - 1, 10, 9, 8, 7, 6]
    var piles = ranks.map(function (r, i) { return [card(r, i % 2 ? 3 : 0)] })
    verify(K.stuck(table([], piles, 1)))
  }
  function test_a_card_in_the_stock_that_can_be_played_is_not_stuck() {
    verify(!K.stuck(table([card(K.ACE, 0)], [[card(K.KING, 3)]].concat(none(6)), 1)))
  }
  function test_a_fresh_deal_is_never_stuck() {
    for (var seed = 0; seed < 20; seed++) verify(!K.stuck(K.deal(K.shuffled(K.seeded(seed)), 1)))
  }

  // --- the move list
  function test_resume_keeps_what_will_play_and_drops_the_rest() {
    var deck = K.shuffled(K.seeded(9))
    var g = K.resume(deck, 1, [])
    var good = []
    for (var i = 0; i < 12; i++) {
      var ms = K.moves(g.table)
      if (!ms.length) break
      g = K.play(g, ms[0])
      good.push(ms[0])
    }
    var back = K.resume(deck, 1, good.concat([[K.TABLEAU, K.FOUNDATION, 9]]))
    compare(back.moves.length, good.length)
    verify(K.sameTable(back.table, g.table))
  }
  function test_resume_from_a_deck_that_is_not_one_deals_a_fresh_game() {
    var g = K.resume([1, 2, 3], 1, [])
    compare(g.deck.length, K.DECK)
    compare(g.moves, [])
  }
  function test_junk_in_the_move_list_ends_the_game_there() {
    compare(K.resume(K.shuffled(K.seeded(10)), 1, [["deal"], null, 7]).moves, [])
  }
  function test_undo_pops_one_and_nothing_from_a_fresh_deal() {
    var g = K.play(K.resume(K.shuffled(K.seeded(6)), 1, []), K.move(K.STOCK, K.WASTE, 1))
    var back = K.undo(g)
    verify(K.sameTable(back.table, back.start))
    compare(K.undo(back), null)
  }
  function test_a_move_survives_the_round_trip_through_a_list() {
    var m = K.move(K.TABLEAU + 2, K.FOUNDATION + 1, 1)
    compare(K.moveOf(JSON.parse(JSON.stringify(m))), m)
    var bad = [null, [1, 2], [1, 2, "3"], [true, 2, 3], "abc", [1.5, 2, 3]]
    for (var i = 0; i < bad.length; i++) compare(K.moveOf(bad[i]), null)
  }

  // --- naming
  function test_a_card_says_what_it_is() {
    compare(K.name(card(K.ACE, 3)), "A of spades")
    compare(K.name(card(9, 2)), "10 of hearts")
  }
  function test_the_piles_are_numbered_the_way_the_file_says_they_are() {
    compare([K.STOCK, K.WASTE, K.FOUNDATION, K.TABLEAU, K.PILES], [0, 1, 2, 6, 13])
    verify(K.isRed(card(0, 1)) && K.isRed(card(0, 2)))
    verify(!(K.isRed(card(0, 0)) || K.isRed(card(0, 3))))
    compare(K.suit(card(4, 2)), 2)
  }

  // --- the screenshot hook
  function test_something_to_pick_has_a_choice_to_make() {
    var t = bare({ piles: [[card(7, 3)], [card(7, 0)], [card(6, 1)]].concat(none(4)) })
    compare(K.somethingToPick(t), [K.TABLEAU + 2, 0])
  }
}
