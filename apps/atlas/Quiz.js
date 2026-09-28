// The quiz: ten questions, four answers each, and the wrong three chosen to
// be wrong in an interesting way -- a neighbour's flag rather than a random
// one, so a round in Europe is about Europe and not about telling Sweden from
// Nepal.
//
// A round is a plain object that only grows: the questions are all chosen
// when it starts, and each answer appends a pick. That keeps it one value the
// panel can hold, save and throw away, and it keeps the screen honest -- what
// it draws is what was asked, not what a generator would ask now.
.pragma library

var LENGTH = 10

// key, the question, what the four answers are.
var MODES = [
  { key: "flags", label: "Name the flag", note: "A flag, four countries" },
  { key: "find", label: "Find the flag", note: "A country, four flags" },
  { key: "capitals", label: "Capitals", note: "A country, four cities" }
]

// Flags a person cannot be expected to tell apart at a glance, so they are
// never offered side by side: Chad and Romania differ by a shade of blue, and
// Monaco and Indonesia only by their proportions.
var TWINS = [["TD", "RO"], ["MC", "ID"], ["IE", "CI"], ["NL", "LU"], ["AU", "NZ"], ["SN", "ML"]]

function mode(key) {
  for (var i = 0; i < MODES.length; i++) if (MODES[i].key === key) return MODES[i]
  return MODES[0]
}

// mulberry32: a seeded generator, so a round can be drawn twice the same way
// -- for the screenshots, and for the tests.
function rng(seed) {
  var a = (seed >>> 0) || 1
  return function () {
    a = (a + 0x6D2B79F5) >>> 0
    var t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

function shuffle(list, rnd) {
  var out = list.slice()
  for (var i = out.length - 1; i > 0; i--) {
    var j = Math.floor(rnd() * (i + 1))
    var t = out[i]; out[i] = out[j]; out[j] = t
  }
  return out
}

function twins(a, b) {
  for (var i = 0; i < TWINS.length; i++) {
    var t = TWINS[i]
    if (t.indexOf(a) >= 0 && t.indexOf(b) >= 0) return true
  }
  return false
}

// Who can be asked about. Countries rather than territories -- Bouvet Island
// flies Norway's flag, and asking for it is a trick -- unless the list has no
// such distinction in it, as an old cache might not. Capitals need a capital.
function pool(list, scope, modeKey) {
  var inScope = list.filter(function (c) { return !scope || scope === "world" || c.region === scope })
  var sovereign = inScope.filter(function (c) { return c.sovereign || c.un })
  var out = sovereign.length >= 4 ? sovereign : inScope
  if (modeKey === "capitals") out = out.filter(function (c) { return c.capitals.length > 0 })
  return out
}

// Enough to play: four answers to a question.
function playable(list, scope, modeKey) {
  return pool(list, scope, modeKey).length >= 4
}

// Three wrong answers for `answer`: its subregion first, then its region, then
// anywhere in the pool. Never its twin, and in the capitals round never a city
// with the same name as the right one.
function distractors(answer, candidates, modeKey, rnd) {
  var near = [], region = [], far = []
  for (var i = 0; i < candidates.length; i++) {
    var c = candidates[i]
    if (c.code === answer.code || twins(c.code, answer.code)) continue
    if (modeKey === "capitals" && c.capitals[0] === answer.capitals[0]) continue
    if (answer.subregion && c.subregion === answer.subregion) near.push(c)
    else if (c.region === answer.region) region.push(c)
    else far.push(c)
  }
  var order = shuffle(near, rnd).concat(shuffle(region, rnd), shuffle(far, rnd))
  var out = []
  for (var k = 0; k < order.length && out.length < 3; k++) {
    var clash = false
    for (var o = 0; o < out.length; o++) if (twins(out[o].code, order[k].code)) clash = true
    if (!clash) out.push(order[k])
  }
  return out
}

// A new round: { mode, scope, questions: [{ answer, options }], picks: [] }.
// Codes only -- the countries themselves stay in the list they came from.
function round(list, modeKey, scope, rnd, length) {
  var candidates = pool(list, scope, modeKey)
  var n = Math.min(length || LENGTH, candidates.length)
  var chosen = shuffle(candidates, rnd).slice(0, n)
  var questions = []
  for (var i = 0; i < chosen.length; i++) {
    var wrong = distractors(chosen[i], candidates, modeKey, rnd)
    if (wrong.length < 3) continue
    var options = shuffle([chosen[i]].concat(wrong), rnd).map(function (c) { return c.code })
    questions.push({ answer: chosen[i].code, options: options })
  }
  return { mode: mode(modeKey).key, scope: scope || "world", questions: questions, picks: [] }
}

function current(r) {
  return r && r.picks.length < r.questions.length ? r.questions[r.picks.length] : null
}

function finished(r) {
  return !!r && r.questions.length > 0 && r.picks.length >= r.questions.length
}

// The round with one more answer in it. A second tap on the same question
// changes nothing: the first answer is the answer.
function pick(r, code) {
  var q = current(r)
  if (!q || q.options.indexOf(code) < 0) return r
  return { mode: r.mode, scope: r.scope, questions: r.questions, picks: r.picks.concat([code]) }
}

function right(r, i) {
  return !!r && i < r.picks.length && r.picks[i] === r.questions[i].answer
}

function score(r) {
  var s = 0
  if (r) for (var i = 0; i < r.picks.length; i++) if (right(r, i)) s++
  return s
}

// Right answers in a row, ending with the last one.
function streak(r) {
  var s = 0
  if (r) for (var i = r.picks.length - 1; i >= 0 && right(r, i); i--) s++
  return s
}

// The codes that were missed, in the order they were asked.
function misses(r) {
  var out = []
  if (r) for (var i = 0; i < r.picks.length; i++) if (!right(r, i)) out.push(r.questions[i].answer)
  return out
}

function verdict(s, total) {
  if (!total) return ""
  if (s === total) return "Flawless"
  var f = s / total
  if (f >= 0.8) return "Well travelled"
  if (f >= 0.5) return "Getting there"
  if (f > 0) return "Back to the atlas"
  return "Every one a surprise"
}

// --- the record ----------------------------------------------------------

function bestKey(modeKey, scope) {
  return mode(modeKey).key + ":" + (scope || "world")
}

function emptyStats() {
  return { rounds: 0, asked: 0, right: 0, best: {} }
}

function int(v) {
  return typeof v === "number" && isFinite(v) && v >= 0 ? Math.floor(v) : 0
}

function parseStats(data) {
  var s = emptyStats()
  if (!data || typeof data !== "object") return s
  s.rounds = int(data.rounds)
  s.asked = int(data.asked)
  s.right = Math.min(int(data.right), s.asked)
  var best = data.best && typeof data.best === "object" ? data.best : {}
  for (var k in best) {
    if (!/^[a-z]+:[A-Za-z]+$/.test(k)) continue
    var b = best[k]
    if (b && typeof b === "object" && int(b.total) > 0)
      s.best[k] = { score: Math.min(int(b.score), int(b.total)), total: int(b.total) }
  }
  return s
}

function serializeStats(s) {
  return JSON.stringify({ schema: 1, rounds: s.rounds, asked: s.asked, right: s.right, best: s.best }, null, 1) + "\n"
}

// The record with a finished round counted: { stats, record } -- record is
// true when this round beat the best for its mode and scope.
function record(stats, r) {
  var s = parseStats(stats)
  if (!finished(r)) return { stats: s, record: false }
  var got = score(r)
  var total = r.questions.length
  s.rounds += 1
  s.asked += total
  s.right += got
  var key = bestKey(r.mode, r.scope)
  var old = s.best[key]
  var beat = !old || got / total > old.score / old.total
  if (beat) s.best[key] = { score: got, total: total }
  return { stats: s, record: beat && got > 0 }
}

function best(stats, modeKey, scope) {
  var b = stats && stats.best ? stats.best[bestKey(modeKey, scope)] : null
  return b ? b.score + "/" + b.total : ""
}
