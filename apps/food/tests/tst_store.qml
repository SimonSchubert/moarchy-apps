// The history and the cache, in the files 0.1.0 wrote: the cases its
// test_facts.py had for the store, and the shapes, so an upgrade keeps what a
// person scanned.
import QtQuick
import QtTest
import "../Facts.js" as F
import "../Store.js" as S

TestCase {
  name: "FoodStore"

  readonly property string nutella: "3017620422003"
  readonly property string cola: "5449000000996"

  function product(code, name) {
    return F.fromDict({ code: code, name: name, brand: "Brand", nutriscore: "e",
      nutrients: [{ key: "fat_100g", label: "Fat", value: 30.9, unit: "g" }] })
  }

  function roundTrip(state) {
    var history = S.parseHistory(JSON.parse(S.serializeHistory(state)))
    var cache = S.parseProducts(JSON.parse(S.serializeProducts(state)))
    return { history: history, products: cache.products, fetched: cache.fetched }
  }

  function test_a_scan_is_remembered_and_comes_back() {
    var s = S.remember(S.fresh(), product(nutella, "Nutella"), 100)
    var back = roundTrip(s)
    compare(back.history, [nutella])
    compare(back.products[nutella].name, "Nutella")
    compare(back.fetched[nutella], 100)
  }

  function test_the_files_are_the_shape_store_py_wrote() {
    var s = S.remember(S.fresh(), product(nutella, "Nutella"), 100)
    var h = JSON.parse(S.serializeHistory(s))
    compare(h.schema, 1)
    compare(h.codes, [nutella])
    var p = JSON.parse(S.serializeProducts(s))
    compare(p.products[nutella].nutriscore, "e")
    compare(p.products[nutella].nutrients[0].label, "Fat")
    compare(p.fetched[nutella], 100)
  }

  function test_scanning_the_same_packet_twice_moves_it_to_the_front() {
    var s = S.remember(S.fresh(), product(nutella, "Nutella"))
    s = S.remember(s, product(cola, "Coca-Cola"))
    s = S.remember(s, product(nutella, "Nutella"))
    compare(s.history, [nutella, cola])
  }

  function test_the_history_is_capped_and_the_cache_goes_with_it() {
    var s = S.fresh()
    for (var i = 0; i < S.MAX_HISTORY + 5; i++) s = S.remember(s, product(String(1000 + i), "P" + i))
    compare(s.history.length, S.MAX_HISTORY)
    compare(Object.keys(s.products).length, S.MAX_HISTORY)
    compare(s.products["1000"], undefined)
  }

  function test_forgetting_a_row_drops_its_cached_product() {
    var s = S.remember(S.remember(S.fresh(), product(nutella, "Nutella")), product(cola, "Coca-Cola"))
    s = S.forget(s, nutella)
    compare(s.history, [cola])
    compare(s.products[nutella], undefined)
  }

  function test_a_history_row_without_a_cached_product_is_skipped() {
    var s = { history: [nutella, cola], products: ({}), fetched: ({}) }
    s.products[cola] = product(cola, "Coca-Cola")
    compare(S.recent(s).length, 1)
    compare(S.recent(s)[0].code, cola)
  }

  function test_junk_in_the_files_falls_back_rather_than_raising() {
    compare(S.parseHistory({ codes: "nope" }), [])
    compare(S.parseHistory({ codes: [nutella, nutella, 7, "", cola] }), [nutella, cola])
    var cache = S.parseProducts({ products: { x: { code: "x" }, y: "z" }, fetched: { x: "soon" } })
    compare(Object.keys(cache.products).length, 0)
    compare(S.parseProducts(null).products, ({}))
  }

  function test_nothing_changes_the_state_it_was_given() {
    var s = S.remember(S.fresh(), product(nutella, "Nutella"))
    S.remember(s, product(cola, "Coca-Cola"))
    S.forget(s, nutella)
    compare(s.history, [nutella])
  }

  function test_the_history_is_searched_by_name_brand_or_barcode() {
    var rows = [product(nutella, "Nutella"), product(cola, "Coca-Cola")]
    compare(S.filter(rows, "cola").length, 1)
    compare(S.filter(rows, "brand").length, 2)
    compare(S.filter(rows, "30176").length, 1)
    compare(S.filter(rows, "").length, 2)
  }
}
