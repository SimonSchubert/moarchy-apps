// The quiz's rules: who is asked about, which wrong answers sit beside the
// right one, and what a finished round does to the record.
import QtQuick
import QtTest
import "../Quiz.js" as Q
import "../Store.js" as S

TestCase {
  name: "Quiz"

  function c(code, region, subregion, capital, sovereign) {
    return { code: code, region: region, subregion: subregion,
             capitals: capital ? [capital] : [], sovereign: sovereign !== false, un: sovereign !== false }
  }

  // Twelve countries in three regions, a territory, and a twin pair.
  function world() {
    return [
      c("DE", "Europe", "Western Europe", "Berlin"), c("FR", "Europe", "Western Europe", "Paris"),
      c("NL", "Europe", "Western Europe", "Amsterdam"), c("BE", "Europe", "Western Europe", "Brussels"),
      c("RO", "Europe", "Southeast Europe", "Bucharest"), c("BG", "Europe", "Southeast Europe", "Sofia"),
      c("TD", "Africa", "Middle Africa", "N'Djamena"), c("GA", "Africa", "Middle Africa", "Libreville"),
      c("NG", "Africa", "Western Africa", "Abuja"), c("ML", "Africa", "Western Africa", "Bamako"),
      c("JP", "Asia", "Eastern Asia", "Tokyo"), c("TH", "Asia", "South-Eastern Asia", "Bangkok"),
      c("BV", "Antarctic", "", "", false)
    ]
  }

  function find(list, code) {
    for (var i = 0; i < list.length; i++) if (list[i].code === code) return list[i]
    return null
  }

  function test_the_generator_is_seeded() {
    var a = Q.rng(7), b = Q.rng(7), d = Q.rng(8)
    var x = [a(), a(), a()], y = [b(), b(), b()]
    compare(x, y)
    verify(d() !== x[0])
    for (var i = 0; i < 100; i++) { var v = a(); verify(v >= 0 && v < 1) }
  }

  function test_territories_are_not_asked_about() {
    var p = Q.pool(world(), "world", "flags")
    compare(p.length, 12)
    verify(!find(p, "BV"))
    compare(Q.pool(world(), "Africa", "flags").length, 4)
    // A place with too few countries asks about whatever it has.
    compare(Q.pool(world(), "Antarctic", "flags").length, 1)
    verify(!Q.playable(world(), "Antarctic", "flags"))
    verify(Q.playable(world(), "Asia", "flags") === false)
    verify(Q.playable(world(), "Europe", "capitals"))
  }

  function test_a_round() {
    var r = Q.round(world(), "flags", "world", Q.rng(1))
    compare(r.mode, "flags")
    compare(r.scope, "world")
    compare(r.questions.length, 10)
    compare(r.picks, [])
    var asked = {}
    for (var i = 0; i < r.questions.length; i++) {
      var q = r.questions[i]
      verify(!asked[q.answer], "asked twice: " + q.answer)
      asked[q.answer] = true
      compare(q.options.length, 4)
      verify(q.options.indexOf(q.answer) >= 0)
      // Four different countries, and never Chad beside Romania.
      var seen = {}
      q.options.forEach(function (o) { verify(!seen[o]); seen[o] = true })
      verify(!(seen.TD && seen.RO), "twins offered together")
    }
    // The same seed, the same round.
    compare(JSON.stringify(Q.round(world(), "flags", "world", Q.rng(1))), JSON.stringify(r))
  }

  function test_wrong_answers_come_from_next_door() {
    var list = world()
    var de = find(list, "DE")
    var wrong = Q.distractors(de, Q.pool(list, "world", "flags"), "flags", Q.rng(3))
    compare(wrong.length, 3)
    // Western Europe has three others, so all three are from there.
    wrong.forEach(function (w) { compare(w.subregion, "Western Europe") })
    var ro = find(list, "RO")
    var near = Q.distractors(ro, Q.pool(list, "world", "flags"), "flags", Q.rng(3))
    verify(!near.some(function (w) { return w.code === "TD" }))
    // Bulgaria is its subregion; the rest are from Europe before anywhere else.
    compare(near[0].code, "BG")
    near.slice(1).forEach(function (w) { compare(w.region, "Europe") })
  }

  function test_a_round_in_a_region_is_shorter_when_it_has_to_be() {
    var r = Q.round(world(), "capitals", "Africa", Q.rng(5))
    compare(r.questions.length, 4)
    r.questions.forEach(function (q) { compare(q.options.sort().join(), "GA,ML,NG,TD") })
  }

  function test_answering() {
    var r = Q.round(world(), "flags", "world", Q.rng(2))
    var q0 = r.questions[0]
    var wrongOne = q0.options.filter(function (o) { return o !== q0.answer })[0]
    compare(Q.current(r), q0)
    r = Q.pick(r, q0.answer)
    compare(Q.score(r), 1)
    compare(Q.streak(r), 1)
    // Not one of the four: nothing happens.
    compare(Q.pick(r, "XX"), r)
    var q1 = Q.current(r)
    r = Q.pick(r, q1.options.filter(function (o) { return o !== q1.answer })[0])
    compare(Q.score(r), 1)
    compare(Q.streak(r), 0)
    compare(Q.misses(r), [q1.answer])
    verify(!Q.finished(r))
    while (Q.current(r)) r = Q.pick(r, Q.current(r).answer)
    verify(Q.finished(r))
    compare(Q.score(r), 9)
    compare(Q.streak(r), 8)
    compare(Q.pick(r, q0.answer), r)
    verify(wrongOne !== q0.answer)
  }

  function test_verdicts() {
    compare(Q.verdict(10, 10), "Flawless")
    compare(Q.verdict(8, 10), "Well travelled")
    compare(Q.verdict(5, 10), "Getting there")
    compare(Q.verdict(1, 10), "Back to the atlas")
    compare(Q.verdict(0, 10), "Every one a surprise")
  }

  function test_the_record() {
    var r = Q.round(world(), "capitals", "world", Q.rng(4))
    while (Q.current(r)) r = Q.pick(r, Q.current(r).answer)
    var first = Q.record(Q.emptyStats(), r)
    verify(first.record)
    compare(first.stats.rounds, 1)
    compare(first.stats.asked, 10)
    compare(first.stats.right, 10)
    compare(Q.best(first.stats, "capitals", "world"), "10/10")
    compare(Q.best(first.stats, "flags", "world"), "")
    // The same score again is not a new best.
    var second = Q.record(first.stats, r)
    verify(!second.record)
    compare(second.stats.rounds, 2)
    // An unfinished round changes nothing.
    compare(Q.record(second.stats, Q.round(world(), "flags", "world", Q.rng(1))).stats.rounds, 2)
  }

  function test_the_record_file() {
    var s = Q.parseStats(JSON.parse(Q.serializeStats({ rounds: 3, asked: 30, right: 21, best: { "flags:world": { score: 8, total: 10 } } })))
    compare(s.rounds, 3)
    compare(s.best["flags:world"].score, 8)
    var hand = Q.parseStats({ rounds: -2, asked: "x", right: 99, best: { "flags:world": { score: 12, total: 10 }, "bad key": { score: 1, total: 1 }, "find:Europe": 7 } })
    compare(hand.rounds, 0)
    compare(hand.right, 0)
    compare(hand.best["flags:world"].score, 10)
    compare(Object.keys(hand.best), ["flags:world"])
    compare(Q.parseStats(null).rounds, 0)
  }

  function test_keys() {
    compare(S.cleanKey("  rc_live_0123456789abcdef \n"), "rc_live_0123456789abcdef")
    compare(S.cleanKey("Bearer rc_live_0123456789abcdef"), "rc_live_0123456789abcdef")
    compare(S.cleanKey("rc live with spaces"), "")
    compare(S.cleanKey("short"), "")
    compare(S.cleanKey("rc_live_abc\r\nX-Evil: 1"), "")
    compare(S.parseAccount(JSON.parse(S.serializeAccount("rc_live_0123456789"))).key, "rc_live_0123456789")
    compare(S.parseAccount({ key: 12 }).key, "")
  }

  function test_the_cache_file() {
    var list = [{ code: "DE", name: "Germany", capitals: ["Berlin"] }, { code: "de", name: "Duplicate" }, { code: "FR", name: "France" }, { name: "No code" }]
    var back = S.parseCache(JSON.parse(S.serializeCache(list, 1790000000)))
    compare(back.fetched, 1790000000)
    compare(back.countries.map(function (c) { return c.name }), ["France", "Germany"])
    compare(S.parseCache({ countries: "no" }).countries, [])
    compare(S.parseCache({ countries: [], fetched: -1 }).fetched, 0)
    compare(S.age(0, 100), Infinity)
    compare(S.age(40, 100), 60)
  }
}
