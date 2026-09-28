// Somebody else's JSON, and every figure on screen.
//
// Nothing here touches the network: the failures worth testing -- a refused
// key, the demo key's one sample, a body that is not JSON -- are exactly the
// ones a real request will not produce on demand, so `answer()` is handed
// what curl would have printed.
import QtQuick
import QtTest
import "../Countries.js" as C
import "Fixture.js" as F

TestCase {
  name: "Countries"

  function curl(body, status) { return JSON.stringify(body) + "\n" + status }
  function page() { return C.parsePage(JSON.stringify(F.PAGE)) }
  function byCode(list, code) {
    for (var i = 0; i < list.length; i++) if (list[i].code === code) return list[i]
    return null
  }

  // --- the wire -----------------------------------------------------------

  function test_a_page_keeps_what_can_be_drawn() {
    var p = page()
    compare(p.error, "")
    compare(p.more, true)
    compare(p.total, 249)
    // Canada, Bolivia, Bouvet Island, and the record whose figures are wrong
    // but whose name and code are right. Not the ones with no code or name.
    compare(p.countries.map(function (c) { return c.code }).join(","), "CA,BO,BV,ZZ")
  }

  function test_canada_comes_through_whole() {
    var ca = byCode(page().countries, "CA")
    compare(ca.id, "CA")
    compare(ca.a3, "CAN")
    compare(ca.name, "Canada")
    compare(ca.official, "Canada")
    compare(ca.capitals, ["Ottawa"])
    compare(ca.region, "Americas")
    compare(ca.subregion, "North America")
    compare(ca.population, 41798407)
    compare(ca.area, 9984670)
    compare(ca.languages, ["English", "French"])
    compare(ca.currencies[0].code, "CAD")
    compare(ca.calling, ["1"])
    compare(ca.tlds, [".ca"])
    compare(ca.timezones.length, 6)
    compare(ca.borders, ["USA"])
    compare(ca.drives, "right")
    compare(ca.landlocked, false)
    compare(ca.sovereign, true)
    compare(ca.un, true)
    compare(ca.memberships, ["NATO", "G7", "G20", "OECD", "Commonwealth"])
    compare(ca.demonym, "Canadian")
    compare(ca.tint, "#ff181b")
    compare(ca.weekStarts, "sunday")
    verify(ca.about.indexOf("Commonwealth realm") >= 0)
    verify(ca.flagAbout.indexOf("maple leaf") >= 0)
    // Its native names are the same word as its name, so there are none to show.
    compare(ca["native"], [])
  }

  function test_the_primary_capital_comes_first() {
    var bo = byCode(page().countries, "BO")
    compare(bo.capitals, ["Sucre", "La Paz"])
    compare(bo.capitalAt.lat, -19.02)
    compare(bo.code, "BO")
    compare(bo["native"], ["Wuliwya"])
    // `prominent` is not a colour, so the dominant one is used.
    compare(bo.tint, "#007a33")
    compare(bo.landlocked, true)
  }

  function test_a_territory_is_a_territory() {
    var bv = byCode(page().countries, "BV")
    compare(bv.sovereign, false)
    compare(bv.un, false)
    compare(bv.population, 0)
    compare(bv.capitals, [])
    compare(bv.drives, "")
    compare(C.tags(bv), ["Antarctic", "Territory"])
    compare(C.people(bv.population), "No permanent population")
  }

  function test_figures_of_the_wrong_type_are_dropped() {
    var zz = byCode(page().countries, "ZZ")
    compare(zz.population, null)
    compare(zz.area, null)
    compare(zz.landlocked, false)
    compare(zz.borders, [])
    compare(C.facts(zz), [])
  }

  function test_curl_answers() {
    var ok = C.answer(0, curl(F.PAGE, 200), "")
    compare(ok.error, "")
    compare(ok.countries.length, 4)
    compare(ok.more, true)

    var refused = C.answer(0, curl(F.REFUSED, 401), "")
    compare(refused.auth, true)
    compare(refused.countries.length, 0)
    verify(refused.error.indexOf("key") >= 0)

    var slow = C.answer(0, curl({}, 429), "HTTP/2 429\r\nretry-after: 12\r\n")
    compare(slow.retry, 12)
    compare(slow.auth, false)
    compare(C.answer(0, curl({}, 429), "").retry, C.RATE_LIMIT_S)

    verify(C.answer(0, curl({}, 403), "").error.indexOf("month") >= 0)
    verify(C.answer(0, curl({}, 410), "").error.indexOf("retired") >= 0)
    verify(C.answer(0, curl({}, 503), "").error !== "")
    verify(C.answer(6, "", "").error.indexOf("No answer") >= 0)
    verify(C.answer(63, "", "").error.indexOf("more than") >= 0)
    verify(C.answer(0, "<html>\n200", "").error.indexOf("not JSON") >= 0)
  }

  function test_the_demo_key_is_not_the_world() {
    var d = C.answer(0, curl(F.DEMO, 200), "")
    compare(d.countries.length, 0)
    verify(d.error.indexOf("demo key") >= 0)
  }

  function test_the_request() {
    var argv = C.command("rc_live_abc", 200)
    var url = argv[argv.length - 1]
    verify(url.indexOf(C.API + "?limit=100&offset=200&response_fields=") === 0)
    verify(url.indexOf("names.common") > 0)
    verify(argv.indexOf("Authorization: Bearer rc_live_abc") > 0)
  }

  function test_pages_merge_by_code_in_name_order() {
    var p = page().countries
    var merged = C.merge([p, [p[0]], []])
    compare(merged.map(function (c) { return c.code }).join(","), "ZZ,BO,BV,CA")
  }

  function test_a_saved_record_comes_back_the_same() {
    var ca = byCode(page().countries, "CA")
    compare(JSON.stringify(C.restore(JSON.parse(JSON.stringify(ca)))), JSON.stringify(ca))
    compare(C.restore({ code: "ca", name: "Canada", population: "lots", borders: [1, "USA"] }).population, null)
    compare(C.restore({ code: "ca", name: "Canada" }).code, "CA")
    compare(C.restore({ code: "CAN", name: "Canada" }), null)
  }

  // --- looking things up --------------------------------------------------

  function test_search_folds_accents_and_finds_capitals_and_codes() {
    var list = page().countries
    var bo = byCode(list, "BO")
    verify(C.matches(bo, "sucre"))
    verify(C.matches(bo, "la paz"))
    verify(C.matches(bo, "WULI"))
    verify(C.matches(bo, "bol"))
    verify(C.matches({ code: "CI", a3: "CIV", name: "Côte d'Ivoire", official: "", "native": [], capitals: ["Yamoussoukro"] }, "cote"))
    verify(C.matches({ code: "IS", a3: "ISL", name: "Iceland", official: "", "native": ["Ísland"], capitals: ["Reykjavík"] }, "reykjavik"))
    verify(!C.matches(bo, "ottawa"))
    // In name order because the list is kept in name order: merge() sorts it.
    compare(C.shown(C.merge([list]), "Americas", "", "name").map(function (c) { return c.code }), ["BO", "CA"])
    compare(C.shown(list, "all", "", "population")[0].code, "CA")
    compare(C.shown(list, "all", "", "area").map(function (c) { return c.code }), ["CA", "BO", "BV", "ZZ"])
  }

  function test_ranks_and_neighbours() {
    var list = page().countries
    var idx = C.index(list)
    compare(idx.popRank.CA, 1)
    compare(idx.popRank.BO, 2)
    compare(idx.popRank.ZZ, undefined)
    compare(idx.areaRank.BV, 3)
    compare(idx.byA3.BOL.code, "BO")
    // Canada's one neighbour is not in this list, so there is no chip for it.
    compare(C.neighbours(byCode(list, "CA"), idx), [])
    compare(C.regionsIn(list), ["Americas", "Antarctic"])
  }

  // --- saying it ----------------------------------------------------------

  function test_numbers() {
    compare(C.grouped(83491249), "83,491,249")
    compare(C.grouped(999), "999")
    compare(C.grouped(null), C.DASH)
    compare(C.compact(83491249), "83.5 M")
    compare(C.compact(1411750000), "1.4 B")
    compare(C.compact(146028325), "146 M")
    compare(C.compact(38423), "38.4 K")
    compare(C.compact(9999), "9,999")
    compare(C.people(1), "1 person")
    compare(C.people(null), "Population not known")
    compare(C.areaText(2.02), "2.02 km²")
    compare(C.areaText(357114), "357,114 km²")
    compare(C.density({ population: 83577140, area: 357114 }), "234 per km²")
    compare(C.density({ population: 2359609, area: 582000 }), "4.1 per km²")
    compare(C.degrees(51, 9), "51°N 9°E")
    compare(C.degrees(-19.02, -65.26), "19°S 65°W")
    compare(C.degrees(null, 1), "")
  }

  function test_the_facts_card() {
    var ca = byCode(page().countries, "CA")
    var labels = C.facts(ca).map(function (f) { return f.label })
    compare(labels, ["Capital", "Languages", "Currency", "Calling code", "Internet", "Time",
                     "People are", "Drives on the", "Week starts", "Centre"])
    var f = {}
    C.facts(ca).forEach(function (x) { f[x.label] = x.value })
    compare(f["Currency"], "Canadian dollar (CAD, $)")
    compare(f["Calling code"], "+1")
    compare(f["Time"], "UTC-08:00 to UTC-03:30 (6 zones)")
    compare(f["Week starts"], "Sunday")
    compare(C.facts(null), [])
  }

  function test_freshness() {
    compare(C.freshness(20), "just now")
    compare(C.freshness(3 * 86400), "3 days ago")
    compare(C.freshness(86400), "yesterday")
  }

  // --- flags --------------------------------------------------------------

  function test_flags() {
    compare(C.flagUrl("DE"), "https://flags.restcountries.com/v5/w320/de.png")
    compare(C.flagFile("/d/flags", "DE"), "/d/flags/de.png")
    var have = C.flagsIn("de.png\nfr.png\nfr.png.part\nREADME\nxyz.png\n")
    compare(Object.keys(have).sort(), ["DE", "FR"])
    compare(C.missingFlags([{ code: "DE" }, { code: "JP" }], have), ["JP"])
    var argv = C.flagCommand("/d/flags", ["JP", "CA"])
    verify(argv.indexOf("--remove-on-error") > 0)
    compare(argv.slice(-6), ["-o", "/d/flags/jp.png", C.flagUrl("JP"), "-o", "/d/flags/ca.png", C.flagUrl("CA")])
  }
}
