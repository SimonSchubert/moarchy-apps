// The questions: what Open Trivia DB is asked, what it answers, and a round
// of them played. No QML and no network here -- Panel.qml runs curl and hands
// the body in -- so all of it is testable under qmltestrunner.
//
// Open Trivia DB (opentdb.com) is a free, keyless database of about five
// thousand verified questions, CC BY-SA 4.0. It has four rules that shape
// this file:
//
// - **One question request per five seconds per address.** A sixth second
//   early is HTTP 429 with response_code 5. So a round is one request, and
//   the app waits out the gap rather than hitting it.
// - **A session token** stops it repeating a question until every one that
//   matches has been served. It dies after six hours unused.
// - **Code 1 is "not that many".** Hard mathematics has a few dozen
//   questions; twenty true-or-false ones may not exist. The answer is to ask
//   for fewer, not to fail.
// - **The text is HTML-escaped by default.** Asked for `encode=url3986`, it
//   comes percent-encoded instead, and decodeURIComponent is exact, where
//   undoing HTML entities by hand is a list that is never complete.
//
// Every function here returns a new value and leaves its argument alone.
.pragma library

.import "Glyphs.js" as G

var API = "https://opentdb.com"
var AGENT = "moarchy-trivia/0.1 (+https://github.com/SimonSchubert/moarchy-apps)"
var TIMEOUT = 15
// Five seconds, and a little: the server counts from when it answered, and
// this counts from when curl was started.
var GAP_MS = 5500
// A token unused for six hours is gone; this is a margin under that.
var TOKEN_TTL_MS = 5 * 3600 * 1000

var OK = 0
var TOO_FEW = 1
var BAD_PARAMETER = 2
var NO_TOKEN = 3
var TOKEN_EMPTY = 4
var RATE_LIMITED = 5

// The ids are Open Trivia DB's, which have not changed since it started.
// `api` is its name for the category, which is what a question carries;
// `name` is ours, without the "Entertainment:" in front of half of them.
var ANY = 0
var CATEGORIES = [
  { id: 0, name: "Anything", api: "", glyph: G.any, hue: "accent" },
  { id: 9, name: "General knowledge", api: "General Knowledge", glyph: G.general, hue: "yellow" },
  { id: 22, name: "Geography", api: "Geography", glyph: G.geography, hue: "blue" },
  { id: 23, name: "History", api: "History", glyph: G.history, hue: "orange" },
  { id: 17, name: "Science & nature", api: "Science & Nature", glyph: G.nature, hue: "green" },
  { id: 18, name: "Computers", api: "Science: Computers", glyph: G.computers, hue: "cyan" },
  { id: 19, name: "Mathematics", api: "Science: Mathematics", glyph: G.maths, hue: "magenta" },
  { id: 30, name: "Gadgets", api: "Science: Gadgets", glyph: G.gadgets, hue: "blue" },
  { id: 27, name: "Animals", api: "Animals", glyph: G.animals, hue: "green" },
  { id: 21, name: "Sports", api: "Sports", glyph: G.sports, hue: "red" },
  { id: 28, name: "Vehicles", api: "Vehicles", glyph: G.vehicles, hue: "orange" },
  { id: 20, name: "Mythology", api: "Mythology", glyph: G.mythology, hue: "yellow" },
  { id: 25, name: "Art", api: "Art", glyph: G.art, hue: "magenta" },
  { id: 24, name: "Politics", api: "Politics", glyph: G.politics, hue: "red" },
  { id: 26, name: "Celebrities", api: "Celebrities", glyph: G.celebrities, hue: "yellow" },
  { id: 10, name: "Books", api: "Entertainment: Books", glyph: G.books, hue: "orange" },
  { id: 11, name: "Film", api: "Entertainment: Film", glyph: G.film, hue: "red" },
  { id: 12, name: "Music", api: "Entertainment: Music", glyph: G.music, hue: "magenta" },
  { id: 14, name: "Television", api: "Entertainment: Television", glyph: G.television, hue: "blue" },
  { id: 13, name: "Musicals & theatre", api: "Entertainment: Musicals & Theatres", glyph: G.theatre, hue: "yellow" },
  { id: 15, name: "Video games", api: "Entertainment: Video Games", glyph: G.videoGames, hue: "green" },
  { id: 16, name: "Board games", api: "Entertainment: Board Games", glyph: G.boardGames, hue: "cyan" },
  { id: 29, name: "Comics", api: "Entertainment: Comics", glyph: G.comics, hue: "orange" },
  { id: 31, name: "Anime & manga", api: "Entertainment: Japanese Anime & Manga", glyph: G.anime, hue: "red" },
  { id: 32, name: "Cartoons", api: "Entertainment: Cartoon & Animations", glyph: G.cartoons, hue: "cyan" }
]

var DIFFICULTIES = [
  { key: "any", label: "Mixed" },
  { key: "easy", label: "Easy" },
  { key: "medium", label: "Medium" },
  { key: "hard", label: "Hard" }
]
var DIFFICULTY_KEYS = ["any", "easy", "medium", "hard"]

var TYPES = [
  { key: "any", label: "Both" },
  { key: "multiple", label: "Four answers" },
  { key: "boolean", label: "True or false" }
]
var TYPE_KEYS = ["any", "multiple", "boolean"]

var LENGTHS = [5, 10, 15, 20]
var DEFAULT_LENGTH = 10

function category(id) {
  for (var i = 0; i < CATEGORIES.length; i++) if (CATEGORIES[i].id === id) return CATEGORIES[i]
  return CATEGORIES[0]
}

function isCategory(id) {
  for (var i = 0; i < CATEGORIES.length; i++) if (CATEGORIES[i].id === id) return true
  return false
}

// A question carries its category by name; the id is what the record keys on.
function categoryByApi(name) {
  for (var i = 1; i < CATEGORIES.length; i++) if (CATEGORIES[i].api === name) return CATEGORIES[i].id
  return ANY
}

function difficultyLabel(key) {
  for (var i = 0; i < DIFFICULTIES.length; i++) if (DIFFICULTIES[i].key === key) return DIFFICULTIES[i].label
  return "Mixed"
}

function typeLabel(key) {
  for (var i = 0; i < TYPES.length; i++) if (TYPES[i].key === key) return TYPES[i].label
  return "Both"
}

// ------------------------------------------------------------ the requests

function questionsUrl(pick, amount, token) {
  var q = ["amount=" + Math.max(1, Math.min(50, amount | 0))]
  if (pick.category && isCategory(pick.category)) q.push("category=" + pick.category)
  if (pick.difficulty && pick.difficulty !== "any") q.push("difficulty=" + pick.difficulty)
  if (pick.type && pick.type !== "any") q.push("type=" + pick.type)
  q.push("encode=url3986")
  if (token) q.push("token=" + encodeURIComponent(token))
  return API + "/api.php?" + q.join("&")
}

function tokenUrl() { return API + "/api_token.php?command=request" }
function resetUrl(token) { return API + "/api_token.php?command=reset&token=" + encodeURIComponent(token) }

function tokenFresh(token, now) {
  return !!(token && token.value && now - token.used < TOKEN_TTL_MS)
}

// ------------------------------------------------------------ the answers

function decode(s) {
  var text = String(s === undefined || s === null ? "" : s)
  try { return decodeURIComponent(text) } catch (e) { return text }
}

// A small seeded generator, so a test can say where the right answer lands.
function random(seed) {
  var a = (seed >>> 0) || 1
  return function () {
    a = (a + 0x6D2B79F5) >>> 0
    var t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

function shuffled(list, rand) {
  var out = list.slice()
  for (var i = out.length - 1; i > 0; i--) {
    var j = Math.floor(rand() * (i + 1))
    var t = out[i]; out[i] = out[j]; out[j] = t
  }
  return out
}

// One question as the API sent it, as the app plays it: decoded, its answers
// in the order they will be shown, and which of them is right. True comes
// before False whatever the draw -- a shuffled pair of those reads as a trick.
function question(raw, rand) {
  if (!raw || typeof raw !== "object") return null
  var text = decode(raw.question).trim()
  var right = decode(raw.correct_answer).trim()
  var wrongs = (raw.incorrect_answers && raw.incorrect_answers.constructor === Array ? raw.incorrect_answers : [])
    .map(function (w) { return decode(w).trim() })
    .filter(function (w) { return w !== "" && w !== right })
  if (!text || !right || !wrongs.length) return null
  var type = raw.type === "boolean" ? "boolean" : "multiple"
  var answers
  if (type === "boolean") {
    answers = ["True", "False"]
    if (answers.indexOf(right) < 0) return null
  } else {
    answers = shuffled([right].concat(wrongs), rand)
  }
  var difficulty = DIFFICULTY_KEYS.indexOf(raw.difficulty) > 0 ? raw.difficulty : "medium"
  return {
    text: text,
    category: categoryByApi(decode(raw.category)),
    difficulty: difficulty,
    type: type,
    answers: answers,
    correct: answers.indexOf(right)
  }
}

// The body of api.php: { code, questions } or { code, error }.
function parseQuestions(body, rand) {
  var data
  try { data = JSON.parse(body) } catch (e) { return { code: -1, error: "Open Trivia DB sent something that is not JSON." } }
  if (!data || typeof data !== "object") return { code: -1, error: "Open Trivia DB sent an empty answer." }
  var code = typeof data.response_code === "number" ? data.response_code : -1
  if (code !== OK) return { code: code, error: problem(code) }
  var list = data.results && data.results.constructor === Array ? data.results : []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var q = question(list[i], rand || Math.random)
    if (q) out.push(q)
  }
  if (!out.length) return { code: TOO_FEW, error: problem(TOO_FEW) }
  return { code: OK, questions: out }
}

// The body of api_token.php: the token, or "".
function parseToken(body) {
  try {
    var data = JSON.parse(body)
    return data && data.response_code === 0 && typeof data.token === "string" ? data.token : ""
  } catch (e) {
    return ""
  }
}

function problem(code) {
  switch (code) {
  case TOO_FEW: return "Open Trivia DB has no questions left for that pick."
  case BAD_PARAMETER: return "Open Trivia DB did not understand the question."
  case NO_TOKEN: return "The session with Open Trivia DB ran out."
  case TOKEN_EMPTY: return "Every question for that pick has been asked."
  case RATE_LIMITED: return "Open Trivia DB wants a moment between rounds."
  default: return "Open Trivia DB answered with something unexpected."
  }
}

// ------------------------------------------------------------ a round

// { category, difficulty, type, questions, picks, index, started, recorded }
//
// `picks` is one answer index per question answered, and `index` the
// question on the screen. They differ by one while an answer is showing:
// picked, marked, and not yet moved on from. `index` reaching the number of
// questions is the score screen.
function round(pick, questions, now) {
  return {
    category: isCategory(pick.category) ? pick.category : ANY,
    difficulty: DIFFICULTY_KEYS.indexOf(pick.difficulty) >= 0 ? pick.difficulty : "any",
    type: TYPE_KEYS.indexOf(pick.type) >= 0 ? pick.type : "any",
    questions: questions.slice(),
    picks: [],
    index: 0,
    started: now || 0,
    recorded: false
  }
}

function copyRound(r) {
  var out = ({})
  for (var k in r) out[k] = r[k]
  out.questions = r.questions.slice()
  out.picks = r.picks.slice()
  return out
}

function current(r) { return r && r.index < r.questions.length ? r.questions[r.index] : null }
function answered(r) { return !!r && r.picks.length > r.index }
function finished(r) { return !!r && r.questions.length > 0 && r.index >= r.questions.length }

// Answering the question on the screen. A second tap on it does nothing.
function answer(r, choice) {
  var q = current(r)
  if (!q || answered(r) || choice < 0 || choice >= q.answers.length) return r
  var out = copyRound(r)
  out.picks.push(choice)
  return out
}

function advance(r) {
  if (!r || !answered(r) || finished(r)) return r
  var out = copyRound(r)
  out.index += 1
  return out
}

function isRight(r, i) {
  return i < r.picks.length && r.picks[i] === r.questions[i].correct
}

function score(r) {
  var n = 0
  for (var i = 0; i < r.picks.length; i++) if (isRight(r, i)) n++
  return n
}

// The run of right answers the round ends on, and its longest.
function runs(r) {
  var now = 0, best = 0
  for (var i = 0; i < r.picks.length; i++) {
    now = isRight(r, i) ? now + 1 : 0
    best = Math.max(best, now)
  }
  return { now: now, best: best }
}

// One word for a score. Not a grade: a round of hard questions at half right
// is a good round, so the words stay on the side of the person.
function verdict(right, of) {
  if (!of) return ""
  var f = right / of
  if (f >= 1) return "A clean sweep"
  if (f >= 0.8) return "Sharp"
  if (f >= 0.6) return "Solid"
  if (f >= 0.4) return "Respectable"
  if (f >= 0.2) return "A tough round"
  return "One to forget"
}

function percent(right, of) { return of ? Math.round(100 * right / of) : 0 }
