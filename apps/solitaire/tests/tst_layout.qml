// Where a card is drawn is where a tap on it lands: 0.1.0's layout tests, and
// the hit test the window used, as arithmetic -- a widget is not needed to
// answer it and a phone is not needed to get it wrong.
import QtQuick
import QtTest
import "../Klondike.js" as K
import "../Layout.js" as L

TestCase {
  name: "SolitaireLayout"

  function ordered() { var d = []; for (var i = 0; i < K.DECK; i++) d.push(i); return d }
  function none(n) { var out = []; for (var i = 0; i < n; i++) out.push([]); return out }
  function bare(changes) {
    var t = K.copy(K.deal(ordered(), 1))
    t.stock = []; t.waste = []; t.piles = none(7); t.down = [0, 0, 0, 0, 0, 0, 0]
    for (var k in changes) t[k] = changes[k]
    return t
  }

  function test_seven_columns_fit_across_a_phone() {
    var t = K.deal(K.shuffled(K.seeded(1)), 1)
    var l = L.layoutFor(360, 640, t)
    verify(l.cardW > 40)
    verify(L.slotX(l, 6) + l.cardW <= 360)
    verify(l.left >= 0)
  }
  function test_the_top_row_and_the_tableau_do_not_touch() {
    var l = L.layoutFor(360, 640, K.deal(K.shuffled(K.seeded(2)), 1))
    verify(l.tableauY > l.top + l.cardH)
  }
  function test_the_waste_fans_into_the_slot_that_is_left_empty() {
    var t = bare({ waste: [1, 2, 3], draw: 3 })
    var l = L.layoutFor(360, 640, t)
    var first = L.cardAt(l, t, K.WASTE, 0)
    var last = L.cardAt(l, t, K.WASTE, 2)
    verify(last.x > first.x)
    verify(last.x + last.w < L.slotX(l, 3))
  }
  function test_a_face_down_card_shows_less_than_a_face_up_one() {
    var l = L.layoutFor(360, 640, K.deal(K.shuffled(K.seeded(3)), 1))
    verify(l.downStep < l.upStep)
  }
  function test_the_tallest_column_a_game_can_have_still_fits() {
    var col = []
    for (var i = 0; i < 19; i++) col.push(i)
    var t = bare({ piles: [col].concat(none(6)), down: [6, 0, 0, 0, 0, 0, 0] })
    var l = L.layoutFor(360, 612, t)
    var r = L.cardAt(l, t, K.TABLEAU, 18)
    verify(r.y + r.h <= 612)
  }
  function test_a_desktop_window_does_not_draw_posters() {
    var t = K.deal(K.shuffled(K.seeded(4)), 1)
    var l = L.layoutFor(900, 760, t)
    verify(l.cardW <= L.LARGEST)
    // Centred in the width it has.
    compare(Math.round(l.left), Math.round(900 - (L.slotX(l, 6) + l.cardW)))
  }

  function test_a_tap_lands_on_the_card_that_is_drawn_there() {
    var t = K.deal(K.shuffled(K.seeded(5)), 1)
    var l = L.layoutFor(360, 640, t)
    for (var c = 0; c < 7; c++) {
      var pile = K.TABLEAU + c
      var last = K.column(t, pile).length - 1
      var r = L.cardAt(l, t, pile, last)
      compare(L.pileAt(l, t, r.x + r.w / 2, r.y + r.h - 2), [pile, last])
    }
    var stock = L.cardAt(l, t, K.STOCK, 0)
    compare(L.pileAt(l, t, stock.x + 3, stock.y + 3)[0], K.STOCK)
  }
  function test_the_gap_between_two_columns_is_not_dead_ground() {
    var t = K.deal(K.shuffled(K.seeded(6)), 1)
    var l = L.layoutFor(360, 640, t)
    var r = L.cardAt(l, t, K.TABLEAU, 0)
    var hit = L.pileAt(l, t, r.x + r.w + L.GAP / 2 - 0.5, r.y + 4)
    compare(hit[0], K.TABLEAU)
  }
  function test_below_a_column_is_nothing() {
    var t = K.deal(K.shuffled(K.seeded(7)), 1)
    var l = L.layoutFor(360, 640, t)
    compare(L.pileAt(l, t, L.slotX(l, 0) + 5, 630), null)
  }
  function test_the_empty_slot_means_the_waste_lying_in_it() {
    var t = bare({ waste: [1, 2, 3], draw: 3 })
    var l = L.layoutFor(360, 640, t)
    compare(L.pileAt(l, t, L.slotX(l, 2) + 5, l.top + 5), [K.WASTE, 2])
  }
}
