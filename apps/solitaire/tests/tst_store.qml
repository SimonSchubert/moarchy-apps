// The deal, the moves and the tally: 0.1.0's test_store.py, case for case, so
// a file one version wrote reads the same in the other and a result is counted
// the same way in both.
import QtQuick
import QtTest
import "../Klondike.js" as K
import "../Store.js" as S

TestCase {
  name: "SolitaireStore"

  function ordered() { var d = []; for (var i = 0; i < K.DECK; i++) d.push(i); return d }
  function roundTrip(state) { return S.parse(JSON.parse(S.serialize(state))) }
  // Three turns of the stock, recorded.
  function played(state, deals) {
    var g = S.game(state)
    for (var i = 0; i < (deals || 3); i++) g = K.play(g, K.move(K.STOCK, K.WASTE, Math.min(g.draw, g.table.stock.length)))
    return { state: S.remember(state, g), game: g }
  }

  function test_a_missing_file_is_a_fresh_deal_and_not_an_error() {
    var s = S.parse(null)
    compare(s.moves, [])
    verify(K.isDeck(s.deck))
  }
  function test_a_new_game_deals_a_different_pack() {
    var s = S.fresh(K.seeded(1))
    var next = S.begin(s, 1, null, K.seeded(2))
    verify(K.isDeck(next.deck))
    verify(JSON.stringify(next.deck) !== JSON.stringify(s.deck))
  }
  function test_dealing_again_keeps_the_pack() {
    var s = played(S.fresh(K.seeded(3))).state
    var again = S.again(s)
    compare(again.deck, s.deck)
    compare(again.moves, [])
    verify(!again.recorded)
  }

  function test_everything_written_comes_back() {
    var s = S.begin(S.fresh(), 3)
    var p = played(s)
    var st = S.record(p.state, S.WON, 140)
    var back = roundTrip(st)
    compare(back.deck, st.deck)
    compare(back.draw, 3)
    compare(back.moves.length, p.game.moves.length)
    verify(K.sameTable(S.game(back).table, p.game.table))
    compare(S.recordFor(back, 3).won, 1)
    compare(S.recordFor(back, 3).best, 140)
  }
  function test_the_table_is_replayed_rather_than_stored() {
    var p = played(S.fresh(), 8)
    var raw = JSON.parse(S.serialize(p.state))
    compare(raw.game.table, undefined)
    verify(K.sameTable(S.game(S.parse(raw)).table, p.game.table))
  }
  function test_the_file_is_the_shape_store_py_wrote() {
    var raw = JSON.parse(S.serialize(S.begin(S.fresh(), 3, ordered())))
    compare(raw.schema, 1)
    compare(raw.game.draw, 3)
    compare(raw.game.deck, ordered())
    compare(raw.game.moves, [])
    compare(raw.stats, {})
  }

  function test_a_deck_with_a_card_twice_is_not_a_deck() {
    var bad = ordered()
    bad[0] = bad[1]
    verify(K.isDeck(S.parse({ game: { deck: bad } }).deck))
  }
  function test_a_short_deck_is_not_a_deck_either() {
    var deck = S.parse({ game: { deck: ordered().slice(0, 40) } }).deck
    compare(deck.length, K.DECK)
    verify(K.isDeck(deck))
  }
  function test_a_move_that_will_not_play_ends_the_game_there() {
    var p = played(S.fresh(), 4)
    var raw = JSON.parse(S.serialize(p.state))
    raw.game.moves.push([6, 2, 9])
    var back = S.parse(raw)
    var g = S.game(back)
    verify(K.sameTable(g.table, p.game.table))
    compare(g.moves.length, p.game.moves.length)
  }
  function test_junk_in_the_fields_falls_back_rather_than_raising() {
    var s = S.parse({ game: { draw: 7, moves: "lots", deck: "cards" }, stats: { draw1: { played: "many" } } })
    compare(s.draw, 1)
    compare(s.moves, [])
    compare(S.recordFor(s, 1).played, 0)
  }
  function test_a_file_that_is_not_an_object_is_ignored() {
    compare(S.parse([1, 2, 3]).moves, [])
  }

  function test_the_two_deals_are_counted_apart() {
    var s = S.record(S.begin(S.fresh(), 1), S.WON, 120)
    s = S.record(S.begin(s, 3), S.LOST)
    compare(S.recordFor(s, 1).won, 1)
    compare(S.recordFor(s, 3).won, 0)
    compare(S.recordFor(s, 3).played, 1)
  }
  function test_fewest_moves_only_ever_goes_down() {
    var s = S.record(S.begin(S.fresh(), 1), S.WON, 180)
    compare(S.recordFor(s, 1).best, 180)
    s = S.record(s, S.WON, 210)
    compare(S.recordFor(s, 1).best, 180)
    s = S.record(s, S.WON, 150)
    compare(S.recordFor(s, 1).best, 150)
  }
  function test_a_run_of_wins_grows_and_a_loss_ends_it() {
    var s = S.begin(S.fresh(), 1)
    for (var i = 0; i < 4; i++) s = S.record(s, S.WON, 200)
    compare(S.recordFor(s, 1).longest, 4)
    s = S.record(s, S.LOST)
    compare(S.recordFor(s, 1).streak, 0)
    compare(S.recordFor(s, 1).longest, 4)
  }
  function test_recording_marks_the_game_as_counted() {
    var s = S.fresh()
    verify(!s.recorded)
    s = S.record(s, S.WON, 100)
    verify(s.recorded)
    verify(!S.begin(s, 1).recorded)
  }
  function test_a_result_that_is_not_one_is_ignored() {
    compare(S.recordFor(S.record(S.fresh(), "abandoned"), 1).played, 0)
  }
  function test_totals_add_the_deals_up_and_take_the_fewest_moves() {
    var s = S.record(S.begin(S.fresh(), 1), S.WON, 175)
    s = S.record(S.begin(s, 3), S.WON, 240)
    s = S.record(s, S.LOST)
    var t = S.totals(s)
    compare(t.played, 3)
    compare(t.won, 2)
    compare(t.best, 175)
  }

  // The window's rule, from 0.1.0's _abandon: a deal walked away from is a
  // loss, one replaced without a move is nothing, a win is not counted twice.
  function test_a_deal_walked_away_from_counts_as_a_loss() {
    var s = S.abandon(played(S.fresh()).state)
    compare(S.recordFor(s, 1).played, 1)
    compare(S.recordFor(s, 1).won, 0)
  }
  function test_a_deal_replaced_without_being_played_counts_as_nothing() {
    compare(S.recordFor(S.abandon(S.fresh()), 1).played, 0)
  }
  function test_a_counted_game_is_not_counted_again_when_left() {
    var s = S.record(played(S.fresh()).state, S.WON, 90)
    compare(S.recordFor(S.abandon(s), 1).played, 1)
  }
  function test_nothing_changes_the_state_it_was_given() {
    var s = S.begin(S.fresh(), 1)
    S.record(s, S.WON, 10)
    S.again(s)
    compare(S.recordFor(s, 1).played, 0)
  }
}
