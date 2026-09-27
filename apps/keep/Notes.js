// The notes, and the one file they live in: ~/.local/share/moarchy-keep/
// notes.json, in the shape the GTK version (0.1.1) wrote, so every note typed
// there is here.
//
// No database. A phone holds a few hundred notes, and a JSON file can be read
// by anything, diffed, synced with rsync and repaired by hand.
//
// Ported from that version's notes.py, rule for rule. Every function takes a
// store `{ notes, view }` or a note and returns a new one, so a property write
// is a new value and every binding notices.
.pragma library

var SCHEMA = 1
var TEXT = "text"
var LIST = "list"

// How many items of a checklist a card shows before it says "+3 more". The
// grid is for scanning, and a 40-item shopping list in full is a column.
var CARD_ITEMS = 7

// The nine colours a note can wear, named for what they look like rather than
// for the theme's hue underneath: "coral" is a colour a person picks, "red" is
// a slot the theme fills.
var COLOURS = [
  { key: "default", label: "Default", role: "" },
  { key: "coral", label: "Coral", role: "red" },
  { key: "peach", label: "Peach", role: "orange" },
  { key: "sand", label: "Sand", role: "yellow" },
  { key: "mint", label: "Mint", role: "green" },
  { key: "sage", label: "Sage", role: "cyan" },
  { key: "fog", label: "Fog", role: "blue" },
  { key: "dusk", label: "Dusk", role: "magenta" },
  { key: "clay", label: "Clay", role: "brown" }
]

function roleOf(key) {
  for (var i = 0; i < COLOURS.length; i++) if (COLOURS[i].key === key) return COLOURS[i].role
  return ""
}

// Twelve hex digits, as notes.py's uuid4().hex[:12].
function newId() {
  var out = ""
  for (var i = 0; i < 12; i++) out += Math.floor(Math.random() * 16).toString(16)
  return out
}

function now() { return Date.now() / 1000 }

function emptyStore() { return { notes: [], view: "grid" } }

// Whether a parsed file is ours. JSON that is not a notes file -- `notes` not
// a list -- is moved aside like a broken one: the next save would destroy it.
function valid(data) {
  return !!data && typeof data === "object" && !!data.notes && data.notes.constructor === Array
}

function parse(data) {
  var store = emptyStore()
  if (!valid(data)) return store
  for (var i = 0; i < data.notes.length; i++) {
    if (data.notes[i] && typeof data.notes[i] === "object" && data.notes[i].constructor !== Array)
      store.notes.push(noteFrom(data.notes[i]))
  }
  if (data.view === "grid" || data.view === "list") store.view = data.view
  return store
}

function serialize(store) {
  var notes = []
  for (var i = 0; i < store.notes.length; i++) notes.push(noteTo(store.notes[i]))
  return JSON.stringify({ schema: SCHEMA, view: store.view || "grid", notes: notes }, null, 1) + "\n"
}

function str(v, fallback) {
  if (v === undefined || v === null) return fallback
  return String(v)
}

function noteFrom(data) {
  var kind = data.kind
  // An unknown kind from a newer version still has a title and probably a
  // body; showing it as text loses less than dropping it.
  if (kind !== TEXT && kind !== LIST) kind = data.items && data.items.length ? LIST : TEXT
  var items = []
  if (data.items && data.items.constructor === Array) {
    for (var i = 0; i < data.items.length; i++) {
      var it = data.items[i]
      if (!it || typeof it !== "object" || it.constructor === Array) continue
      items.push({ text: str(it.text, ""), done: !!it.done })
    }
  }
  var created = typeof data.created === "number" ? data.created : now()
  return {
    id: str(data.id, "") || newId(),
    kind: kind,
    title: str(data.title, ""),
    body: str(data.body, ""),
    items: items,
    colour: str(data.colour, "default"),
    pinned: !!data.pinned,
    created: created,
    edited: typeof data.edited === "number" ? data.edited : created
  }
}

// Only the field the note uses, so the file stays readable.
function noteTo(note) {
  var data = {
    id: note.id,
    kind: note.kind,
    title: note.title,
    colour: note.colour,
    pinned: !!note.pinned,
    created: Math.round(note.created * 1000) / 1000,
    edited: Math.round(note.edited * 1000) / 1000
  }
  if (note.kind === LIST) {
    data.items = []
    for (var i = 0; i < note.items.length; i++) data.items.push({ text: note.items[i].text, done: !!note.items[i].done })
  } else {
    data.body = note.body
  }
  return data
}

function clone(note) {
  var items = []
  for (var i = 0; i < (note.items || []).length; i++) items.push({ text: note.items[i].text, done: !!note.items[i].done })
  return {
    id: note.id, kind: note.kind, title: note.title, body: note.body, items: items,
    colour: note.colour, pinned: !!note.pinned, created: note.created, edited: note.edited
  }
}

// A note with nothing in it. Keep discards these on close rather than filling
// the grid with blank cards somebody tapped by accident.
function isEmpty(note) {
  if (String(note.title || "").trim()) return false
  if (note.kind === LIST) {
    for (var i = 0; i < note.items.length; i++) if (String(note.items[i].text || "").trim()) return false
    return true
  }
  return !String(note.body || "").trim()
}

function openItems(note) { return note.items.filter(function (i) { return !i.done }) }
function doneItems(note) { return note.items.filter(function (i) { return i.done }) }

// Checklist -> prose. Ticked items keep their tick as a character, because
// dropping it would quietly lose the only state they had.
function toText(note) {
  var out = clone(note)
  if (out.kind !== LIST) return out
  var lines = []
  for (var i = 0; i < out.items.length; i++) {
    if (!String(out.items[i].text).trim()) continue
    lines.push((out.items[i].done ? "✓ " : "") + out.items[i].text)
  }
  out.body = lines.join("\n")
  out.items = []
  out.kind = TEXT
  return out
}

// Prose -> checklist, one line per item, blank lines dropped. A line that
// toText() marked with a tick comes back ticked, so the two are a round trip.
function toList(note) {
  var out = clone(note)
  if (out.kind === LIST) return out
  var items = []
  var lines = String(out.body || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var done = line.indexOf("✓ ") === 0
    items.push({ text: done ? line.slice(2) : line, done: done })
  }
  out.items = items
  out.body = ""
  out.kind = LIST
  return out
}

function matches(note, query) {
  var needle = String(query || "").trim().toLowerCase()
  if (!needle) return true
  var hay = [note.title, note.body]
  for (var i = 0; i < note.items.length; i++) hay.push(note.items[i].text)
  for (var j = 0; j < hay.length; j++) if (String(hay[j] || "").toLowerCase().indexOf(needle) >= 0) return true
  return false
}

// ------------------------------------------------------------ the collection

function create(kind) {
  var t = now()
  return {
    id: newId(), kind: kind === LIST ? LIST : TEXT, title: "", body: "",
    // A new list starts with one line to type into.
    items: kind === LIST ? [{ text: "", done: false }] : [],
    colour: "default", pinned: false, created: t, edited: t
  }
}

function indexOf(store, id) {
  for (var i = 0; i < store.notes.length; i++) if (store.notes[i].id === id) return i
  return -1
}

function get(store, id) {
  var i = indexOf(store, id)
  return i < 0 ? null : store.notes[i]
}

// The note in place of the one with its id, or at the top if it is new.
function put(store, note) {
  var notes = store.notes.slice()
  var i = indexOf(store, note.id)
  if (i < 0) notes.unshift(note)
  else notes[i] = note
  return { notes: notes, view: store.view }
}

// { store, index, note }: where it was, so undo can put it back.
function remove(store, id) {
  var i = indexOf(store, id)
  if (i < 0) return { store: store, index: -1, note: null }
  var notes = store.notes.slice()
  var gone = notes.splice(i, 1)[0]
  return { store: { notes: notes, view: store.view }, index: i, note: gone }
}

function restore(store, note, index) {
  var notes = store.notes.slice()
  notes.splice(Math.max(0, Math.min(index, notes.length)), 0, note)
  return { notes: notes, view: store.view }
}

// Pinned and the rest, each newest-edited first: Keep's two sections.
function sections(store, query) {
  var matching = store.notes.filter(function (n) { return matches(n, query) })
  matching.sort(function (a, b) { return b.edited - a.edited })
  return {
    pinned: matching.filter(function (n) { return n.pinned }),
    others: matching.filter(function (n) { return !n.pinned })
  }
}

// What a card shows of a list: open items first, then ticked, at most
// CARD_ITEMS, and how many more there are.
function preview(note) {
  var ordered = openItems(note).concat(doneItems(note)).filter(function (i) { return String(i.text).trim() })
  return { items: ordered.slice(0, CARD_ITEMS), more: Math.max(0, ordered.length - CARD_ITEMS) }
}

// Trailing blank items are how a list is typed, not something anybody meant
// to keep; on a card they would show as gaps.
function tidy(note) {
  var out = clone(note)
  if (out.kind === LIST) out.items = out.items.filter(function (i) { return String(i.text).trim() })
  return out
}

// A rough height, in lines, for placing cards in the shortest column.
function weight(note) {
  var h = 2
  if (note.title) h += 1.4
  if (note.kind === LIST) h += Math.min(preview(note).items.length, CARD_ITEMS) + (preview(note).more ? 1 : 0)
  else h += Math.min(String(note.body || "").split("\n").length + Math.floor(String(note.body || "").length / 40), 10)
  return h
}

// Notes into `n` columns, each to the shortest so far, in order.
function columns(notes, n) {
  var cols = [], heights = []
  for (var c = 0; c < n; c++) { cols.push([]); heights.push(0) }
  for (var i = 0; i < notes.length; i++) {
    var k = 0
    for (var j = 1; j < n; j++) if (heights[j] < heights[k]) k = j
    cols[k].push(notes[i])
    heights[k] += weight(notes[i]) + 1
  }
  return cols
}

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

// "Edited 14:32" today, "Edited 3 Sep" this year, and the year before that.
function editedLabel(when, nowSeconds) {
  var stamp = new Date(when * 1000)
  var today = new Date((nowSeconds === undefined ? now() : nowSeconds) * 1000)
  function pad(n) { return n < 10 ? "0" + n : String(n) }
  if (stamp.toDateString() === today.toDateString())
    return "Edited " + pad(stamp.getHours()) + ":" + pad(stamp.getMinutes())
  if (stamp.getFullYear() === today.getFullYear())
    return "Edited " + stamp.getDate() + " " + MONTHS[stamp.getMonth()]
  return "Edited " + stamp.getDate() + " " + MONTHS[stamp.getMonth()] + " " + stamp.getFullYear()
}
