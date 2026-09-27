// Somebody else's JSON, our own files, and every figure on screen -- the
// cases 0.1.0's test_launches.py had, against the same fixture.
//
// Nothing here touches the network: the failures worth testing -- a 429, a
// body that is not JSON -- are exactly the ones a real request will not
// produce on demand, so `answer()` is handed what curl would have printed.
import QtQuick
import QtTest
import "../Launches.js" as L
import "../Store.js" as S
import "Fixture.js" as F

TestCase {
  name: "Launches"

  readonly property var fixture: F.ANSWER
  readonly property real now: Date.parse("2026-09-14T18:00:00Z")

  readonly property var listMode: ({
    id: "electron-capella",
    name: "Electron | Capella 17",
    status: { id: 8, name: "To Be Confirmed", abbrev: "TBC" },
    net: "2026-09-16T18:00:00Z",
    net_precision: { abbrev: "MIN" },
    lsp_name: "Rocket Lab",
    mission: "Capella 17",
    mission_type: "Earth Observation",
    pad: "Launch Complex 1A",
    location: "Mahia Peninsula, New Zealand",
    orbit: "SSO",
    type: "list"
  })

  function launch(over) {
    var item = {
      id: "vega-sentinel", name: "Sentinel-3C & FLEX", vehicle: "Vega-C", agency: "Arianespace",
      status_id: L.STATUS_GO, status: "Go", net: Date.parse("2026-09-15T01:21:07Z"), precision: "SEC",
      window_start: 0, window_end: 0, pad: "Ensemble de Lancement Vega",
      location: "Guiana Space Centre, French Guiana", orbit: "SSO", mission_type: "Earth Science",
      probability: 75, weather: "", hold: "", description: ""
    }
    for (var k in (over || {})) item[k] = over[k]
    return item
  }
  function copy(o) { return JSON.parse(JSON.stringify(o)) }
  function ids(list) { return list.map(function (i) { return i.id }) }
  function curl(body, status) { return body + "\n" + status }

  // --- parsing ------------------------------------------------------------

  function test_a_normal_result_comes_through_whole() {
    var p = L.parse(fixture.results[0])
    compare(p.id, "vega-sentinel")
    compare(p.name, "Sentinel-3C & FLEX")
    compare(p.vehicle, "Vega-C")
    compare(p.agency, "Arianespace")
    compare(p.status_id, L.STATUS_GO)
    compare(p.orbit, "SSO")
    compare(p.probability, 75)
    compare(p.weather, "Cumulus Cloud Rule")
    compare(p.pad, "Ensemble de Lancement Vega")
  }

  function test_a_list_mode_row_still_parses() {
    var p = L.parse(listMode)
    compare(p.agency, "Rocket Lab")
    compare(p.name, "Capella 17")
    compare(p.vehicle, "Electron")
    compare(p.pad, "Launch Complex 1A")
    compare(p.location, "Mahia Peninsula, New Zealand")
  }

  function test_a_launch_with_no_net_is_not_a_row() {
    var r = copy(fixture.results[0])
    r.net = null
    compare(L.parse(r), null)
  }

  function test_a_minus_one_probability_is_missing_rather_than_negative() {
    compare(L.parse(fixture.results[1]).probability, null)
  }

  function test_a_bool_is_not_a_number() {
    var r = copy(fixture.results[0])
    r.probability = true
    compare(L.parse(r).probability, null)
  }

  function test_one_bad_row_does_not_take_the_list_with_it() {
    var got = L.parsePayload({ results: [fixture.results[0], { id: "broken" }, fixture.results[1]] })
    compare(ids(got.launches), ["vega-sentinel", "falcon-o3b"])
    compare(got.error, "")
  }

  function test_an_answer_that_is_not_a_list_is_an_error() {
    verify(L.parsePayload({ error: "nope" }).error !== "")
  }

  function test_an_answer_where_nothing_is_usable_is_an_error() {
    verify(L.parsePayload({ results: [{ nope: 1 }, { nope: 2 }] }).error !== "")
  }

  function test_an_empty_list_is_not_an_error() {
    var got = L.parsePayload({ results: [] })
    compare(got.launches, [])
    compare(got.error, "")
  }

  function test_a_fixture_round_trips_through_our_own_shape() {
    var p = L.parse(fixture.results[0])
    var again = S.launchFrom(copy(S.launchTo(p)))
    compare(again.id, p.id)
    compare(again.net, p.net)
    compare(again.probability, p.probability)
  }

  function test_the_cache_is_the_shape_store_py_wrote() {
    var raw = JSON.parse(S.serializeUpcoming([launch()], 1000000))
    compare(raw.schema, 1)
    compare(raw.fetched, 1000000)
    compare(raw.launches[0].net, "2026-09-15T01:21:07Z")
    compare(raw.launches[0].window_start, null)
  }

  // --- the countdown ------------------------------------------------------

  function test_a_fine_net_ticks() {
    compare(L.headline(launch({ net: Date.parse("2026-09-14T18:12:00Z") }), now), "T-00:12:00")
  }

  function test_a_net_more_than_a_day_away_drops_the_seconds() {
    compare(L.headline(launch({ net: Date.parse("2026-09-16T22:00:00Z") }), now), "T-2d 04h")
  }

  function test_a_go_that_has_passed_counts_up() {
    compare(L.headline(launch({ net: Date.parse("2026-09-14T17:56:48Z") }), now), "T+00:03:12")
  }

  function test_a_success_is_an_age_not_a_countdown() {
    var item = launch({ status_id: L.STATUS_SUCCESS, status: "Success", net: Date.parse("2026-09-14T04:00:00Z") })
    compare(L.headline(item, now), "14 hours ago")
  }

  function test_a_tbc_is_a_date_even_when_the_precision_is_a_minute() {
    var drawn = L.headline(launch({ status_id: L.STATUS_TBC, status: "TBC", precision: "MIN",
                                    net: Date.parse("2026-09-16T18:00:00Z") }), now)
    verify(drawn.indexOf("T-") < 0 && drawn.indexOf("T+") < 0, drawn)
  }

  function test_a_quarter_does_not_tick() {
    compare(L.headline(launch({ precision: "Q3", net: Date.parse("2026-09-16T18:00:00Z") }), now), "Q3 2026")
  }

  function test_a_pinned_clock_is_an_iso_time_or_epoch_seconds() {
    compare(L.pinned("2026-09-14T18:00:00Z"), now)
    compare(L.pinned(String(now / 1000)), now)
    compare(L.pinned(""), 0)
    compare(L.pinned("soon"), 0)
  }

  function test_a_go_in_the_next_hour_is_soon() {
    compare(L.tone(launch({ net: Date.parse("2026-09-14T18:12:00Z") }), now), "soon")
  }

  function test_a_go_that_has_passed_is_late() {
    compare(L.tone(launch({ net: Date.parse("2026-09-14T17:50:00Z") }), now), "late")
  }

  function test_a_tbc_is_wait() {
    compare(L.tone(launch({ status_id: L.STATUS_TBC, status: "TBC" }), now), "wait")
  }

  // --- refreshing ---------------------------------------------------------

  function test_a_quiet_list_waits_fifteen_minutes() {
    compare(L.refreshAfter([launch({ net: Date.parse("2026-09-20T00:00:00Z") })], now), L.REFRESH_S)
  }

  function test_a_go_in_the_next_hour_shortens_that() {
    compare(L.refreshAfter([launch({ net: Date.parse("2026-09-14T18:40:00Z") })], now), L.NEAR_REFRESH_S)
  }

  function test_a_go_in_the_next_ten_minutes_shortens_it_again() {
    compare(L.refreshAfter([launch({ net: Date.parse("2026-09-14T18:08:00Z") })], now), L.IMMINENT_REFRESH_S)
  }

  function test_a_success_does_not_hurry_the_clock() {
    var item = launch({ status_id: L.STATUS_SUCCESS, status: "Success", net: Date.parse("2026-09-14T18:05:00Z") })
    compare(L.refreshAfter([item], now), L.REFRESH_S)
  }

  // --- searching ----------------------------------------------------------

  function test_a_query_matches_the_front_of_any_word() {
    verify(L.matches(launch(), "sen"))
    verify(L.matches(launch(), "vega"))
    verify(L.matches(launch(), "ariane"))
    verify(!L.matches(launch(), "canaveral"))
    verify(L.matches(launch({ location: "Cape Canaveral SFS, FL, USA" }), "canaveral"))
  }

  function test_a_query_does_not_match_the_middle_of_a_word() {
    verify(!L.matches(launch(), "ega"))
    verify(!L.matches(launch(), "entin"))
  }

  function test_the_badge_is_short_enough_for_the_disc() {
    compare(L.disc(launch()), "GO")
    compare(L.disc(launch({ status_id: L.STATUS_IN_FLIGHT, status: "In Flight" })), "FLY")
    verify(L.disc(launch({ status_id: L.STATUS_FAILURE })).length <= 4)
  }

  // --- the network, as curl reports it -------------------------------------

  function test_the_url_asks_for_twenty_and_does_not_paginate() {
    var u = L.url(L.LIMIT)
    verify(u.indexOf("limit=20") >= 0)
    verify(u.indexOf("offset") < 0)
    verify(u.indexOf("mode=") < 0)
  }

  function test_a_count_past_the_endpoints_ceiling_is_clamped() {
    verify(L.url(9999).indexOf("limit=100") >= 0)
  }

  function test_a_good_answer_becomes_launches() {
    var got = L.answer(0, curl(JSON.stringify(fixture), 200), "")
    compare(ids(got.launches), ["vega-sentinel", "falcon-o3b"])
    compare(got.error, "")
  }

  function test_a_token_is_sent_as_authorization() {
    verify(L.command("secret-token").indexOf("Authorization: Token secret-token") >= 0)
    verify(L.command("").join(" ").indexOf("Authorization") < 0)
  }

  function test_a_rate_limit_says_so_and_says_when() {
    var got = L.answer(0, curl("", 429), "HTTP/2 429\r\nretry-after: 90\r\n")
    compare(got.retry, 90)
    verify(got.error.indexOf("rate-limit") >= 0)
  }

  function test_a_rate_limit_with_no_advice_still_says_when() {
    compare(L.answer(0, curl("", 429), "").retry, L.RATE_LIMIT_S)
  }

  function test_a_body_that_is_not_json_is_a_sentence() {
    verify(L.answer(0, curl("<html>maintenance</html>", 200), "").error.indexOf("JSON") >= 0)
  }

  function test_no_network_is_one_sentence_whichever_way_it_failed() {
    var codes = [6, 7, 28, 35, 56]
    for (var i = 0; i < codes.length; i++)
      verify(L.answer(codes[i], "", "").error.indexOf("No answer") >= 0)
  }

  function test_an_oversize_body_is_refused_unread() {
    verify(L.answer(63, "", "").error.indexOf("more than this app will read") >= 0)
  }

  function test_a_server_error_and_a_refusal_are_different_sentences() {
    verify(L.answer(0, curl("", 503), "").error.indexOf("trouble") >= 0)
    verify(L.answer(0, curl("", 404), "").error.indexOf("404") >= 0)
  }

  // --- the stars ----------------------------------------------------------

  function test_a_star_survives_the_file() {
    var t = S.toggle([], "vega-sentinel")
    verify(t.starred)
    compare(S.parseFavourites(JSON.parse(S.serializeFavourites(t.favourites))), ["vega-sentinel"])
  }

  function test_toggling_twice_leaves_nothing_behind() {
    var t = S.toggle(S.toggle([], "vega-sentinel").favourites, "vega-sentinel")
    verify(!t.starred)
    compare(t.favourites, [])
  }

  function test_the_starred_page_is_in_the_order_things_were_starred() {
    var list = [launch({ id: "a" }), launch({ id: "b" }), launch({ id: "c" })]
    compare(ids(L.starred(list, ["b", "a", "c"], "")), ["b", "a", "c"])
  }

  function test_a_star_with_no_launch_behind_it_is_not_drawn() {
    compare(L.starred([], ["missing"], ""), [])
  }

  function test_a_duplicated_file_does_not_draw_a_launch_twice() {
    compare(S.parseFavourites({ favourites: ["vega-sentinel", "vega-sentinel", 7, ""] }), ["vega-sentinel"])
  }

  function test_a_full_list_of_stars_says_so() {
    var many = []
    for (var i = 0; i < S.MAX_FAVOURITES; i++) many.push("l" + i)
    var t = S.toggle(many, "one-more")
    verify(t.full)
    verify(!t.starred)
  }

  // --- the cache ----------------------------------------------------------

  function test_launches_survive_a_launch_with_no_signal() {
    var back = S.parseUpcoming(JSON.parse(S.serializeUpcoming([launch()], 1000000)))
    compare(ids(back.launches), ["vega-sentinel"])
    compare(back.fetched, 1000000)
  }

  function test_a_duplicate_id_keeps_the_later_record_and_the_first_place() {
    var got = S.dedupe([launch({ probability: 10 }), launch({ id: "other" }), launch({ probability: 90 })])
    compare(ids(got), ["vega-sentinel", "other"])
    compare(got[0].probability, 90)
  }

  function test_launches_that_were_never_fetched_are_infinitely_old() {
    compare(S.age(0, 1000), Infinity)
  }

  function test_a_clock_that_went_backwards_does_not_make_launches_from_the_future() {
    compare(S.age(2000, 1000), 0)
  }

  function test_a_cache_row_that_cannot_be_read_is_left_out() {
    var got = S.parseUpcoming({ fetched: 5, launches: [{ id: "x" }, S.launchTo(launch()), "nope"] })
    compare(ids(got.launches), ["vega-sentinel"])
  }
}
