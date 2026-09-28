// Everything the app keeps, in one JSON file: ~/.local/share/moarchy-trivia/
// trivia.json, or $MOARCHY_TRIVIA_DIR.
//
// - **The pick**: the category last played, the difficulty, the kind of
//   question and how many, so the next round is one tap.
// - **The session token**, with when it was last used: Open Trivia DB forgets
//   one after six hours, and a stale one costs a request to find out.
// - **The round on the screen**, questions and all. A phone reclaims apps
//   rather than closing them, and a round that came back as a new request
//   would be a different ten questions -- and a five-second wait.
// - **The record**: every answer, counted the moment it is given rather than
//   at the end of the round, so a round left half-played still counts the
//   half that was played. The round itself -- one quiz, one score -- is
//   counted when its score screen is reached, once (`recorded`).
//
// Every function here returns a new state and leaves its argument alone.
.pragma library

.import "Trivia.js" as T

var SCHEMA = 1
var RECENT = 12

function int(value, fallback) {
  return typeof value === "number" && isFinite(value) ? Math.max(0, Math.trunc(value)) : fallback
}

function tally() { return { answered: 0, right: 0 } }
function categoryTally() { return { answered: 0, right: 0, rounds: 0, best: 0 } }

function emptyStats() {
  return {
    rounds: 0, answered: 0, right: 0, sweeps: 0,
    streak: 0, bestStreak: 0,
    byDifficulty: { easy: tally(), medium: tally(), hard: tally() },
    byCategory: ({})
  }
}

function fresh() {
  return {
    pick: { category: T.ANY, difficulty: "any", type: "any", amount: T.DEFAULT_LENGTH },
    token: null,
    round: null,
    stats: emptyStats(),
    recent: []
  }
}

// ------------------------------------------------------------ reading

function parsePick(p, base) {
  var out = Object.assign({}, base || fresh().pick)
  if (!p || typeof p !== "object") return out
  if (T.isCategory(p.category)) out.category = p.category
  if (T.DIFFICULTY_KEYS.indexOf(p.difficulty) >= 0) out.difficulty = p.difficulty
  if (T.TYPE_KEYS.indexOf(p.type) >= 0) out.type = p.type
  if (T.LENGTHS.indexOf(p.amount) >= 0) out.amount = p.amount
  return out
}

function parseQuestion(q) {
  if (!q || typeof q !== "object" || typeof q.text !== "string" || !q.text) return null
  if (!q.answers || q.answers.constructor !== Array || q.answers.length < 2) return null
  var answers = q.answers.map(function (a) { return String(a) })
  var correct = int(q.correct, -1)
  if (correct < 0 || correct >= answers.length) return null
  return {
    text: q.text,
    category: T.isCategory(q.category) ? q.category : T.ANY,
    difficulty: ["easy", "medium", "hard"].indexOf(q.difficulty) >= 0 ? q.difficulty : "medium",
    type: q.type === "boolean" ? "boolean" : "multiple",
    answers: answers,
    correct: correct
  }
}

// A round that will not play -- no questions, a pick out of range -- is no
// round, and the app opens on the categories instead.
function parseRound(r) {
  if (!r || typeof r !== "object" || !r.questions || r.questions.constructor !== Array) return null
  var questions = []
  for (var i = 0; i < r.questions.length; i++) {
    var q = parseQuestion(r.questions[i])
    if (!q) return null
    questions.push(q)
  }
  if (!questions.length) return null
  var out = T.round({ category: r.category, difficulty: r.difficulty, type: r.type }, questions, int(r.started, 0))
  var picks = r.picks && r.picks.constructor === Array ? r.picks : []
  for (var j = 0; j < picks.length && j < questions.length; j++) {
    var p = int(picks[j], -1)
    if (p < 0 || p >= questions[j].answers.length) break
    out.picks.push(p)
  }
  var index = int(r.index, 0)
  out.index = Math.max(0, Math.min(index, out.picks.length, questions.length))
  // An answer given and not moved on from is the only way they may differ.
  if (out.picks.length > out.index + 1) out.picks = out.picks.slice(0, out.index + 1)
  out.recorded = !!r.recorded && out.index >= questions.length
  return out
}

function parseTally(t, shape) {
  var out = shape()
  if (!t || typeof t !== "object") return out
  for (var k in out) out[k] = int(t[k], 0)
  if (out.right > out.answered) out.right = out.answered
  return out
}

function parseStats(s) {
  var out = emptyStats()
  if (!s || typeof s !== "object") return out
  var keys = ["rounds", "answered", "right", "sweeps", "streak", "bestStreak"]
  for (var i = 0; i < keys.length; i++) out[keys[i]] = int(s[keys[i]], 0)
  if (out.right > out.answered) out.right = out.answered
  if (s.byDifficulty && typeof s.byDifficulty === "object")
    for (var d in out.byDifficulty) out.byDifficulty[d] = parseTally(s.byDifficulty[d], tally)
  if (s.byCategory && typeof s.byCategory === "object")
    for (var c in s.byCategory) {
      var id = parseInt(c, 10)
      if (T.isCategory(id) && id !== T.ANY) out.byCategory[id] = parseTally(s.byCategory[c], categoryTally)
    }
  return out
}

function parse(data) {
  var out = fresh()
  if (!data || typeof data !== "object") return out
  out.pick = parsePick(data.pick)
  if (data.token && typeof data.token === "object" && typeof data.token.value === "string" && data.token.value)
    out.token = { value: data.token.value, used: int(data.token.used, 0) }
  out.round = parseRound(data.round)
  out.stats = parseStats(data.stats)
  if (data.recent && data.recent.constructor === Array)
    for (var i = 0; i < data.recent.length && out.recent.length < RECENT; i++) {
      var r = data.recent[i]
      if (!r || typeof r !== "object") continue
      var of = int(r.of, 0)
      if (!of) continue
      out.recent.push({
        at: int(r.at, 0),
        category: T.isCategory(r.category) ? r.category : T.ANY,
        difficulty: T.DIFFICULTY_KEYS.indexOf(r.difficulty) >= 0 ? r.difficulty : "any",
        right: Math.min(int(r.right, 0), of),
        of: of
      })
    }
  return out
}

function serialize(state) {
  return JSON.stringify({
    schema: SCHEMA,
    pick: state.pick,
    token: state.token,
    round: state.round,
    stats: state.stats,
    recent: state.recent
  }, null, 1) + "\n"
}

// ------------------------------------------------------------ changing

function copy(state) {
  var out = ({})
  for (var k in state) out[k] = state[k]
  out.pick = Object.assign({}, state.pick)
  out.recent = state.recent.slice()
  var s = Object.assign({}, state.stats)
  s.byDifficulty = ({})
  for (var d in state.stats.byDifficulty) s.byDifficulty[d] = Object.assign({}, state.stats.byDifficulty[d])
  s.byCategory = ({})
  for (var c in state.stats.byCategory) s.byCategory[c] = Object.assign({}, state.stats.byCategory[c])
  out.stats = s
  return out
}

function withPick(state, changes) {
  var out = copy(state)
  out.pick = parsePick(changes, state.pick)
  return out
}

function withToken(state, value, now) {
  var out = copy(state)
  out.token = value ? { value: value, used: now } : null
  return out
}

function withRound(state, round) {
  var out = copy(state)
  out.round = round
  return out
}

// The question on the screen, answered: the round moves, and the record
// counts it now.
function answer(state, choice) {
  var r = state.round
  if (!r || T.answered(r) || T.finished(r)) return state
  var next = T.answer(r, choice)
  if (next === r) return state
  var out = copy(state)
  out.round = next
  var q = T.current(r)
  var right = choice === q.correct
  var s = out.stats
  s.answered += 1
  if (right) s.right += 1
  s.streak = right ? s.streak + 1 : 0
  s.bestStreak = Math.max(s.bestStreak, s.streak)
  var d = s.byDifficulty[q.difficulty]
  if (d) { d.answered += 1; if (right) d.right += 1 }
  if (q.category !== T.ANY) {
    var c = s.byCategory[q.category] || categoryTally()
    c.answered += 1
    if (right) c.right += 1
    s.byCategory[q.category] = c
  }
  return out
}

// On to the next question, or to the score -- which counts the round, once.
function advance(state, now) {
  var r = state.round
  if (!r || !T.answered(r) || T.finished(r)) return state
  var out = copy(state)
  out.round = T.advance(r)
  if (T.finished(out.round) && !out.round.recorded) out = recordRound(out, now)
  return out
}

function recordRound(state, now) {
  var out = copy(state)
  var r = T.copyRound(out.round)
  r.recorded = true
  out.round = r
  var right = T.score(r)
  var of = r.questions.length
  out.stats.rounds += 1
  if (right === of) out.stats.sweeps += 1
  if (r.category !== T.ANY) {
    var c = out.stats.byCategory[r.category] || categoryTally()
    c.rounds += 1
    // Best as a percentage, so five out of five and nine out of ten compare.
    c.best = Math.max(c.best, T.percent(right, of))
    out.stats.byCategory[r.category] = c
  }
  out.recent = [{ at: now || 0, category: r.category, difficulty: r.difficulty, right: right, of: of }]
    .concat(out.recent).slice(0, RECENT)
  return out
}

// ------------------------------------------------------------ reading back

function categoryRecord(state, id) {
  return state.stats.byCategory[id] || categoryTally()
}

// The categories somebody has played, most answered first.
function playedCategories(state) {
  var out = []
  for (var c in state.stats.byCategory) {
    var t = state.stats.byCategory[c]
    if (t.answered) out.push({ id: parseInt(c, 10), answered: t.answered, right: t.right, rounds: t.rounds, best: t.best })
  }
  out.sort(function (a, b) { return b.answered - a.answered || a.id - b.id })
  return out
}
