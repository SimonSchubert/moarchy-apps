// Open Library, as it answers anybody: what to ask, and what the answer means
// to a person. Plus the reading list, which is ours.
//
// One host and one CDN, neither with a key:
//
//   openlibrary.org       search.json (books, and an author's books, sorted),
//                         search/authors.json, trending/<period>.json,
//                         works/<id>.json with its ratings.json and
//                         bookshelves.json, authors/<id>.json
//   covers.openlibrary.org  a cover or an author's photo by its number, at
//                         S, M or L; by number it is not rate-limited
//
// Open Library asks callers to say who they are, so every request carries a
// User-Agent with the app's name and where it lives.
//
// Nothing here touches QML, which keeps the half that can be wrong --
// somebody else's JSON -- apart from the screen that draws it.
.pragma library

var BASE = "https://openlibrary.org"
var COVERS = "https://covers.openlibrary.org"
var AGENT = "moarchy-books/0.1.0 (+https://github.com/SimonSchubert/moarchy-apps)"
var TIMEOUT = 20
// A page of search results with the fields below is a few kilobytes; a work
// is tens. Four megabytes is a body that has gone wrong.
var MAX_BYTES = 4 * 1024 * 1024
var PAGE = 24
// Discover's shelves change by the day; asked again after six hours.
var SHELF_TTL = 6 * 3600
var MAX_BOOKS = 2000

// What search.json is asked to send: the fields a card and a page read.
var FIELDS = "key,title,subtitle,author_name,author_key,cover_i,first_publish_year,edition_count,"
  + "ratings_average,ratings_count,number_of_pages_median,want_to_read_count,already_read_count"
var AUTHOR_FIELDS = "key,name,birth_date,death_date,top_work,work_count"

// Discover's shelves after Trending: Open Library's subject keys, which are
// its subject names lower-cased with underscores, and what they are called
// here. Most read first -- the books people have put on a shelf there.
var SUBJECTS = [
  { key: "fantasy", label: "Fantasy" },
  { key: "science_fiction", label: "Science fiction" },
  { key: "mystery_and_detective_stories", label: "Mystery" },
  { key: "historical_fiction", label: "Historical fiction" },
  { key: "classic_literature", label: "Classics" },
  { key: "horror", label: "Horror" },
  { key: "romance", label: "Romance" },
  { key: "young_adult_fiction", label: "Young adult" },
  { key: "biography", label: "Biography" },
  { key: "history", label: "History" },
  { key: "science", label: "Science" },
  { key: "philosophy", label: "Philosophy" },
  { key: "psychology", label: "Psychology" },
  { key: "poetry", label: "Poetry" },
  { key: "cooking", label: "Cooking" }
]

// The three shelves of the reading list, in the order a book moves along them.
var SHELVES = [
  { key: "reading", label: "Reading" },
  { key: "want", label: "Want to read" },
  { key: "read", label: "Read" }
]

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

// --- asking ----------------------------------------------------------------

function get(url) {
  return ["curl", "-sS", "-L", "--compressed", "--max-time", String(TIMEOUT),
          "--max-filesize", String(MAX_BYTES),
          "-H", "User-Agent: " + AGENT, "-H", "Accept: application/json",
          "-w", "\n%{http_code}", url]
}

function trending(page) {
  return get(BASE + "/trending/weekly.json?limit=" + PAGE + "&page=" + Math.max(1, page || 1))
}

function search(text, page) {
  return get(BASE + "/search.json?q=" + encodeURIComponent(text) + "&fields=" + FIELDS
    + "&limit=" + PAGE + "&page=" + Math.max(1, page || 1))
}

function subject(key, page) {
  return get(BASE + "/search.json?q=" + encodeURIComponent("subject_key:" + key) + "&sort=readinglog&fields=" + FIELDS
    + "&limit=" + PAGE + "&page=" + Math.max(1, page || 1))
}

// An author's books, most read first -- the author's own works list is in
// the order they were catalogued, which puts a 2022 omnibus before Dune.
function byAuthor(id, page) {
  return get(BASE + "/search.json?author=" + encodeURIComponent(id) + "&sort=readinglog&fields=" + FIELDS
    + "&limit=" + PAGE + "&page=" + Math.max(1, page || 1))
}

function authorSearch(text, page) {
  return get(BASE + "/search/authors.json?q=" + encodeURIComponent(text) + "&sort=" + encodeURIComponent("work_count desc")
    + "&fields=" + AUTHOR_FIELDS + "&limit=" + PAGE + "&offset=" + (Math.max(1, page || 1) - 1) * PAGE)
}

function work(id) { return get(BASE + "/works/" + id + ".json") }
function ratings(id) { return get(BASE + "/works/" + id + "/ratings.json") }
function bookshelves(id) { return get(BASE + "/works/" + id + "/bookshelves.json") }
function author(id) { return get(BASE + "/authors/" + id + ".json") }

// What curl printed: the body, a newline, the status.
function split(output) {
  var text = String(output || "")
  var cut = text.lastIndexOf("\n")
  return {
    status: cut >= 0 ? parseInt(text.slice(cut + 1).trim(), 10) || 0 : 0,
    body: cut >= 0 ? text.slice(0, cut) : text
  }
}

// { data, error }: the JSON body, or the sentence a person reads instead.
function answer(exitCode, output) {
  var who = "Open Library"
  if (exitCode === 63) return { data: null, error: who + " sent more than this app will read." }
  if (exitCode === 28) return { data: null, error: who + " took too long to answer." }
  if (exitCode !== 0) return { data: null, error: "No answer from " + who + "." }
  var got = split(output)
  if (got.status === 404) return { data: null, error: who + " has no such page." }
  if (got.status === 429) return { data: null, error: who + " is rate-limiting this connection. Try again in a minute." }
  if (got.status >= 500) return { data: null, error: who + " is having trouble." }
  if (got.status !== 200) return { data: null, error: who + " refused the request (" + got.status + ")." }
  var data
  try { data = JSON.parse(got.body) } catch (e) { return { data: null, error: who + " sent something that is not JSON." } }
  if (!data || typeof data !== "object") return { data: null, error: who + " sent an empty answer." }
  return { data: data, error: "" }
}

// --- reading the answers -----------------------------------------------------

// "/works/OL893414W" -> "OL893414W"
function olid(key) {
  var s = String(key || "")
  var cut = s.lastIndexOf("/")
  return cut >= 0 ? s.slice(cut + 1) : s
}

function isWork(id) { return /^OL\d+W$/.test(String(id || "")) }
function isAuthor(id) { return /^OL\d+A$/.test(String(id || "")) }

// Open Library's long text is a string or { type, value }.
function text(value) {
  if (value === null || value === undefined) return ""
  if (typeof value === "object") return text(value.value)
  return String(value)
}

// Descriptions and biographies are Markdown written by many hands: links,
// footnotes, rules, the source in brackets at the end. Plain paragraphs out.
function plain(md) {
  var s = text(md).replace(/\r\n?/g, "\n")
  // A rule and everything after it is almost always a list of sources or of
  // the other books in a series.
  s = s.replace(/\n\s*-{3,}[\s\S]*$/, "")
  // [text](url) and [text][1] -> text; the footnote lines themselves go.
  s = s.replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
  s = s.replace(/\[([^\]]*)\]\[\d+\]/g, "$1")
  s = s.replace(/^\s*\[\d+\]:.*$/gm, "")
  s = s.replace(/\(\s*(?:source|from)\s*:?\s*\)/gi, "")
  s = s.replace(/[*_]{1,2}([^*_\n]+)[*_]{1,2}/g, "$1")
  s = s.replace(/<[^>]+>/g, "")
  s = s.replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n")
  return s.trim()
}

function num(v) {
  var n = typeof v === "number" ? v : parseFloat(v)
  return isFinite(n) ? n : 0
}

// A book as every list and page here holds it -- one search.json or trending
// document, whichever fields it came with.
function book(doc) {
  if (!doc || typeof doc !== "object") return null
  var id = olid(doc.key)
  if (!isWork(id)) return null
  var names = Array.isArray(doc.author_name) ? doc.author_name : []
  var keys = Array.isArray(doc.author_key) ? doc.author_key : []
  var authors = []
  for (var i = 0; i < names.length && authors.length < 4; i++)
    authors.push({ id: keys[i] ? olid(keys[i]) : "", name: String(names[i]) })
  return {
    id: id,
    title: String(doc.title || "Untitled"),
    subtitle: doc.subtitle ? String(doc.subtitle) : "",
    authors: authors,
    cover: num(doc.cover_i || doc.cover_id) > 0 ? num(doc.cover_i || doc.cover_id) : 0,
    year: num(doc.first_publish_year),
    editions: num(doc.edition_count),
    pages: num(doc.number_of_pages_median),
    rating: num(doc.ratings_average),
    ratings: num(doc.ratings_count),
    wants: num(doc.want_to_read_count),
    reads: num(doc.already_read_count)
  }
}

// A page of books: search.json's docs or trending's works, each once.
function books(data) {
  var list = data ? (Array.isArray(data.docs) ? data.docs : Array.isArray(data.works) ? data.works : []) : []
  var out = []
  var seen = {}
  for (var i = 0; i < list.length; i++) {
    var b = book(list[i])
    if (!b || seen[b.id]) continue
    seen[b.id] = true
    out.push(b)
  }
  return out
}

// How many there are in all, where the answer says.
function total(data) {
  return data ? num(data.numFound || data.num_found) : 0
}

function authorHit(doc) {
  if (!doc || typeof doc !== "object") return null
  var id = olid(doc.key)
  if (!isAuthor(id)) return null
  return {
    id: id,
    name: String(doc.name || "Unknown"),
    born: text(doc.birth_date),
    died: text(doc.death_date),
    topWork: text(doc.top_work),
    works: num(doc.work_count)
  }
}

function authors(data) {
  var list = data && Array.isArray(data.docs) ? data.docs : []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var a = authorHit(list[i])
    if (a) out.push(a)
  }
  return out
}

// Subjects worth a tap: not Open Library's bookkeeping (nyt:..., award:...,
// "Accessible book"), not the same one twice in another case or language
// form, and not a sentence.
var DULL = ["fiction", "accessible book", "protected daisy", "in library", "large type books",
            "new york times bestseller", "new york times reviewed", "open library staff picks",
            "lending library", "overdrive", "long now manual for civilization", "reading level-grade 11",
            "reading level-grade 12", "translations into russian", "internet archive wishlist"]

function subjects(list, max) {
  var out = []
  var seen = {}
  if (!Array.isArray(list)) return out
  for (var i = 0; i < list.length && out.length < (max || 12); i++) {
    var s = String(list[i] || "").trim()
    if (!s || s.length > 32 || s.indexOf(":") >= 0 || s.indexOf("=") >= 0) continue
    var low = s.toLowerCase()
    if (DULL.indexOf(low) >= 0 || low.indexOf("fiction, ") === 0 || low.indexOf("(") >= 0) continue
    var k = low.replace(/[^a-z0-9]+/g, "")
    if (!k || seen[k]) continue
    seen[k] = true
    out.push(s)
  }
  return out
}

// Open Library's subject key for a subject's name.
function subjectKey(name) {
  return String(name || "").trim().toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "")
}

function subjectLabel(key) {
  for (var i = 0; i < SUBJECTS.length; i++) if (SUBJECTS[i].key === key) return SUBJECTS[i].label
  var s = String(key || "").replace(/_/g, " ")
  return s.charAt(0).toUpperCase() + s.slice(1)
}

// A work's page: what the list did not have.
function workDetail(data) {
  if (!data || typeof data !== "object") return null
  var covers = Array.isArray(data.covers) ? data.covers.filter(function (c) { return num(c) > 0 }) : []
  var authorIds = []
  if (Array.isArray(data.authors))
    for (var i = 0; i < data.authors.length; i++) {
      var a = data.authors[i]
      var id = olid(a && a.author ? a.author.key : a && a.key)
      if (isAuthor(id) && authorIds.indexOf(id) < 0) authorIds.push(id)
    }
  var excerpt = ""
  if (Array.isArray(data.excerpts) && data.excerpts.length) excerpt = plain(data.excerpts[0].excerpt)
  return {
    title: String(data.title || ""),
    subtitle: data.subtitle ? String(data.subtitle) : "",
    description: plain(data.description),
    excerpt: excerpt.length > 600 ? excerpt.slice(0, 600).replace(/\s+\S*$/, "") + "…" : excerpt,
    subjects: subjects(data.subjects, 12),
    places: subjects(data.subject_places, 4),
    people: subjects(data.subject_people, 4),
    published: text(data.first_publish_date),
    cover: covers.length ? num(covers[0]) : 0,
    authorIds: authorIds
  }
}

function ratingsDetail(data) {
  var s = data && data.summary ? data.summary : {}
  var c = data && data.counts ? data.counts : {}
  return {
    average: num(s.average),
    count: num(s.count),
    counts: [num(c["1"]), num(c["2"]), num(c["3"]), num(c["4"]), num(c["5"])]
  }
}

function shelvesDetail(data) {
  var c = data && data.counts ? data.counts : {}
  return { want: num(c.want_to_read), reading: num(c.currently_reading), read: num(c.already_read) }
}

function authorDetail(data) {
  if (!data || typeof data !== "object") return null
  var photos = Array.isArray(data.photos) ? data.photos.filter(function (p) { return num(p) > 0 }) : []
  var wiki = text(data.wikipedia)
  if (!wiki && Array.isArray(data.links))
    for (var i = 0; i < data.links.length; i++) {
      var u = text(data.links[i] && data.links[i].url)
      if (u.indexOf("wikipedia.org") >= 0) { wiki = u; break }
    }
  return {
    id: olid(data.key),
    name: String(data.name || data.personal_name || "Unknown"),
    bio: plain(data.bio),
    born: text(data.birth_date),
    died: text(data.death_date),
    photo: photos.length ? num(photos[0]) : 0,
    wikipedia: wiki
  }
}

// --- where things are --------------------------------------------------------

// A cover by its number: S (about 40 px wide), M (180) or L (500).
function coverUrl(id, size) {
  if (!(num(id) > 0)) return ""
  return COVERS + "/b/id/" + id + "-" + (size || "M") + ".jpg"
}

function photoUrl(id, size) {
  if (!(num(id) > 0)) return ""
  return COVERS + "/a/id/" + id + "-" + (size || "M") + ".jpg"
}

// An author by OLID, for a search hit that has no photo number: a 404 rather
// than Open Library's blank picture when there is none.
function authorPhotoUrl(authorId, size) {
  if (!isAuthor(authorId)) return ""
  return COVERS + "/a/olid/" + authorId + "-" + (size || "M") + ".jpg?default=false"
}

function workWeb(id) { return BASE + "/works/" + id }
function authorWeb(id) { return BASE + "/authors/" + id }

// An openlibrary.org link, a bare OLID, or an ISBN: what it names.
// { kind: "work"|"author"|"isbn", id } or null.
function link(input) {
  var s = String(input || "").trim()
  var m = s.match(/openlibrary\.org\/works\/(OL\d+W)/i) || s.match(/^(OL\d+W)$/i)
  if (m) return { kind: "work", id: m[1].toUpperCase() }
  m = s.match(/openlibrary\.org\/authors\/(OL\d+A)/i) || s.match(/^(OL\d+A)$/i)
  if (m) return { kind: "author", id: m[1].toUpperCase() }
  var digits = s.replace(/[-\s]/g, "")
  if (/^(97[89]\d{10}|\d{9}[\dXx])$/.test(digits)) return { kind: "isbn", id: digits.toUpperCase() }
  return null
}

// --- saying it ---------------------------------------------------------------

function names(b, max) {
  if (!b || !b.authors || !b.authors.length) return ""
  var list = b.authors.slice(0, max || 2).map(function (a) { return a.name })
  return list.join(", ") + (b.authors.length > (max || 2) ? " and others" : "")
}

function byline(b) {
  if (!b) return ""
  var who = names(b, 1)
  return [who, b.year > 0 ? String(b.year) : ""].filter(function (s) { return s !== "" }).join(" · ")
}

function count(n) {
  n = num(n)
  if (n >= 1000000) return (n / 1000000).toFixed(n >= 10000000 ? 0 : 1).replace(/\.0$/, "") + "M"
  if (n >= 10000) return Math.round(n / 1000) + "k"
  if (n >= 1000) return (n / 1000).toFixed(1).replace(/\.0$/, "") + "k"
  return String(Math.round(n))
}

// 1234567 -> "1,234,567"
function grouped(n) {
  return String(Math.round(num(n))).replace(/\B(?=(\d{3})+(?!\d))/g, ",")
}

function plural(n, one, many) { return grouped(n) + " " + (Math.round(n) === 1 ? one : (many || one + "s")) }

function rating(avg) { return num(avg) > 0 ? num(avg).toFixed(1) : "" }

// The facts under a title: first published, pages, editions.
function facts(b, detail) {
  if (!b) return []
  var out = []
  var pub = detail && detail.published ? detail.published : b.year > 0 ? String(b.year) : ""
  if (pub) out.push(pub)
  if (b.pages > 0) out.push(plural(b.pages, "page"))
  if (b.editions > 1) out.push(plural(b.editions, "edition"))
  return out
}

// "Ursula K. Le Guin" -> "UG": a face for somebody with no photo.
function initials(name) {
  var parts = String(name || "").split(/[\s.]+/).filter(function (p) { return /^[A-Za-z]/.test(p) })
  if (!parts.length) return String(name || "?").charAt(0).toUpperCase()
  if (parts.length === 1) return parts[0].charAt(0).toUpperCase()
  return (parts[0].charAt(0) + parts[parts.length - 1].charAt(0)).toUpperCase()
}

function lifespan(a) {
  if (!a) return ""
  var y = function (s) { var m = String(s || "").match(/\d{3,4}/g); return m ? m[m.length - 1] : "" }
  var b = y(a.born), d = y(a.died)
  if (b && d) return b + " – " + d
  if (b) return "born " + b
  if (d) return "died " + d
  return ""
}

function date(sec) {
  if (!(sec > 0)) return ""
  var d = new Date(sec * 1000)
  return d.getDate() + " " + MONTHS[d.getMonth()] + " " + d.getFullYear()
}

function ago(sec, nowSec) {
  if (!(sec > 0)) return ""
  var s = Math.max(0, nowSec - sec)
  if (s < 3600) return "just now"
  if (s < 86400) return Math.floor(s / 3600) + " h ago"
  var d = Math.floor(s / 86400)
  if (d === 1) return "yesterday"
  if (d < 30) return d + " days ago"
  return date(sec)
}

// 0..1, how far through a book the page is.
function progress(entry) {
  if (!entry || !(entry.pages > 0)) return 0
  return Math.max(0, Math.min(1, (entry.page || 0) / entry.pages))
}

function progressText(entry) {
  if (!entry) return ""
  if (entry.pages > 0) return "Page " + grouped(entry.page || 0) + " of " + grouped(entry.pages)
    + "  ·  " + Math.round(progress(entry) * 100) + "%"
  return entry.page > 0 ? "Page " + grouped(entry.page) : "Not started"
}

// --- the reading list --------------------------------------------------------

// A book on a shelf: the book as it was listed, and ours --
//   shelf     "want" | "reading" | "read"
//   added     when it went on the list
//   started   when it went on Reading, first
//   finished  when it went on Read
//   page      how far, of `pages`
//   stars     1-5 of our own, 0 for none

function keep(b) {
  var out = {
    id: b.id, title: b.title, subtitle: b.subtitle || "", authors: (b.authors || []).slice(0, 4),
    cover: b.cover || 0, year: b.year || 0, pages: b.pages || 0, editions: b.editions || 0,
    rating: b.rating || 0, ratings: b.ratings || 0
  }
  return out
}

function indexOf(list, id) {
  for (var i = 0; i < list.length; i++) if (list[i].id === id) return i
  return -1
}

function entry(list, id) {
  var i = indexOf(list, id)
  return i >= 0 ? list[i] : null
}

// Onto a shelf, or off it when it is already there. A new list back, with
// what happened: { list, on, full }.
function shelve(list, b, shelf, nowSec) {
  var i = indexOf(list, b.id)
  var cur = i >= 0 ? list[i] : null
  if (cur && cur.shelf === shelf) return { list: remove(list, b.id), on: false, full: false }
  if (!cur && list.length >= MAX_BOOKS) return { list: list, on: false, full: true }
  var e = Object.assign({}, cur || keep(b), cur ? {} : { added: nowSec, page: 0, stars: 0 })
  // Fresher facts, where the book in hand has them.
  if (b.pages > 0 && !(e.pages > 0)) e.pages = b.pages
  if (b.cover > 0 && !(e.cover > 0)) e.cover = b.cover
  e.shelf = shelf
  if (shelf === "reading" && !e.started) e.started = nowSec
  if (shelf === "read") {
    e.finished = nowSec
    if (e.pages > 0) e.page = e.pages
  } else {
    delete e.finished
  }
  var out = list.slice()
  if (i >= 0) out.splice(i, 1)
  out.unshift(e)
  return { list: out, on: true, full: false }
}

function remove(list, id) {
  return list.filter(function (e) { return e.id !== id })
}

// Changes to one entry, in place in a new list; the same list when it is not
// on one.
function update(list, id, patch) {
  var i = indexOf(list, id)
  if (i < 0) return list
  var out = list.slice()
  out[i] = Object.assign({}, list[i], patch)
  return out
}

function setPage(list, id, page) {
  var e = entry(list, id)
  if (!e) return list
  var p = Math.max(0, Math.round(num(page)))
  if (e.pages > 0) p = Math.min(p, e.pages)
  return update(list, id, { page: p })
}

function setStars(list, id, stars) {
  var e = entry(list, id)
  if (!e) return list
  var s = Math.max(0, Math.min(5, Math.round(num(stars))))
  return update(list, id, { stars: e.stars === s ? 0 : s })
}

// A shelf's books, in the order that reads best for it: what you are reading
// by when you last moved it, what you read by when you finished, what you
// want by when you added it.
function onShelf(list, shelf) {
  var out = list.filter(function (e) { return e.shelf === shelf })
  var at = function (e) { return shelf === "read" ? (e.finished || e.added || 0) : (e.added || 0) }
  out.sort(function (a, b) { return at(b) - at(a) })
  return out
}

function counts(list) {
  var c = { want: 0, reading: 0, read: 0 }
  for (var i = 0; i < list.length; i++) if (c[list[i].shelf] !== undefined) c[list[i].shelf]++
  return c
}

// Finished in the calendar year `nowSec` falls in, and the pages they had.
function yearStats(list, nowSec) {
  var year = new Date(nowSec * 1000).getFullYear()
  var books = 0, pages = 0
  for (var i = 0; i < list.length; i++) {
    var e = list[i]
    if (e.shelf !== "read" || !(e.finished > 0)) continue
    if (new Date(e.finished * 1000).getFullYear() !== year) continue
    books++
    pages += e.pages || 0
  }
  return { year: year, books: books, pages: pages }
}

// library.json: { version: 1, books: [...] }. Anything unreadable in it is
// dropped a book at a time, not the whole file.
function parseLibrary(data) {
  var out = []
  var list = data && Array.isArray(data.books) ? data.books : []
  var seen = {}
  for (var i = 0; i < list.length && out.length < MAX_BOOKS; i++) {
    var e = list[i]
    if (!e || typeof e !== "object" || !isWork(e.id) || seen[e.id]) continue
    if (["want", "reading", "read"].indexOf(e.shelf) < 0) continue
    seen[e.id] = true
    out.push({
      id: e.id, title: String(e.title || "Untitled"), subtitle: String(e.subtitle || ""),
      authors: Array.isArray(e.authors) ? e.authors.filter(function (a) { return a && a.name })
        .map(function (a) { return { id: String(a.id || ""), name: String(a.name) } }).slice(0, 4) : [],
      cover: num(e.cover), year: num(e.year), pages: num(e.pages), editions: num(e.editions),
      rating: num(e.rating), ratings: num(e.ratings),
      shelf: e.shelf, added: num(e.added), started: num(e.started), finished: num(e.finished),
      page: num(e.page), stars: Math.max(0, Math.min(5, Math.round(num(e.stars))))
    })
  }
  return out
}

function serializeLibrary(list) {
  return JSON.stringify({ version: 1, books: list }, null, 1) + "\n"
}

// discover.json: the first page of each of Discover's shelves as last seen,
// so an app opened with no signal opens on books rather than an apology.
function parseShelves(data) {
  var out = {}
  var feeds = data && data.feeds && typeof data.feeds === "object" ? data.feeds : {}
  for (var k in feeds) {
    var f = feeds[k]
    if (!f || !Array.isArray(f.items)) continue
    var items = f.items.filter(function (b) { return b && isWork(b.id) })
    if (items.length) out[k] = { items: items, at: num(f.at), total: num(f.total) }
  }
  return out
}

function serializeShelves(feeds) {
  var keep = {}
  for (var k in feeds) {
    var f = feeds[k]
    if (k !== "trending" && k.indexOf("subject:") !== 0) continue
    if (!f || !f.items || !f.items.length) continue
    keep[k] = { items: f.items.slice(0, PAGE), at: f.at, total: f.total || 0 }
  }
  return JSON.stringify({ version: 1, feeds: keep }) + "\n"
}

// Page two onto page one, without the books already on it.
function append(list, more) {
  var seen = {}
  for (var i = 0; i < list.length; i++) seen[list[i].id] = true
  return list.concat(more.filter(function (b) { return !seen[b.id] }))
}

// A number from a string, the same every time: which cloth a book with no
// cover picture is bound in.
function hash(s) {
  var h = 0
  s = String(s || "")
  for (var i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0
  return Math.abs(h)
}
