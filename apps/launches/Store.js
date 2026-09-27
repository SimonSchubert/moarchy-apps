// What survives the app being killed: the stars, and the last launches seen,
// in the two files the GTK version (0.1.0) wrote, in the same shapes.
//
// favourites.json is a list of launch ids and is the only thing in this app a
// person made. It is written the instant a star is tapped. upcoming.json is the
// last answer Launch Library gave: it exists so that an app opened on a train
// with no signal opens on countdowns rather than an apology, it is disposable
// by definition, and it is written when the window closes rather than on each
// refresh -- around T-0 a refresh is every two minutes, and the file is a
// hundred kilobytes.
//
// Both are read by DataFile, which moves a file that will not parse aside
// before anything is written over it.
.pragma library

.import "Launches.js" as L

var SCHEMA = 1
// A guard on the file rather than on the person: nobody stars two hundred
// launches, and a file that says they did was written by something else.
var MAX_FAVOURITES = 200

function pad2(n) { return n < 10 ? "0" + n : String(n) }

// The shape Python's _iso() writes: seconds, and a Z.
function iso(ms) {
  if (!ms) return null
  var d = new Date(ms)
  return d.getUTCFullYear() + "-" + pad2(d.getUTCMonth() + 1) + "-" + pad2(d.getUTCDate())
         + "T" + pad2(d.getUTCHours()) + ":" + pad2(d.getUTCMinutes()) + ":" + pad2(d.getUTCSeconds()) + "Z"
}

// --- the stars ------------------------------------------------------------

// The ids, once each, in the order they were starred. Anything that is not a
// non-empty string is not an id.
function parseFavourites(data) {
  var out = []
  var raw = data && typeof data === "object" ? data.favourites : null
  if (!raw || raw.constructor !== Array) return out
  for (var i = 0; i < raw.length && out.length < MAX_FAVOURITES; i++) {
    var id = raw[i]
    if (typeof id === "string" && id && out.indexOf(id) < 0) out.push(id)
  }
  return out
}

function serializeFavourites(favourites) {
  return JSON.stringify({ schema: SCHEMA, favourites: favourites || [] }, null, 1) + "\n"
}

// Star or unstar. Appends rather than inserts, which is what makes the
// starred page read in the order things were added to it.
function toggle(favourites, id) {
  var out = []
  var found = false
  for (var i = 0; i < (favourites || []).length; i++) {
    if (favourites[i] === id) { found = true; continue }
    out.push(favourites[i])
  }
  if (found) return { favourites: out, starred: false, full: false }
  if (out.length >= MAX_FAVOURITES) return { favourites: out, starred: false, full: true }
  out.push(id)
  return { favourites: out, starred: true, full: false }
}

// --- the cache ------------------------------------------------------------

// One launch back out of our own file. Separate from Launches.parse, which
// reads Launch Library's shape: folding them together would let a change in
// the API's field names quietly rewrite what last week's cache means.
function launchFrom(data) {
  if (!data || typeof data !== "object") return null
  var net = L.stamp(data.net)
  if (typeof data.id !== "string" || !data.id || !net) return null
  var statusId = Math.trunc(L.number(data.status_id) || 0)
  return {
    id: data.id,
    name: String(data.name || data.id),
    vehicle: String(data.vehicle || ""),
    agency: String(data.agency || ""),
    status_id: statusId,
    status: String(data.status || L.DISC[statusId] || L.DASH),
    net: net,
    precision: String(data.precision || ""),
    window_start: L.stamp(data.window_start),
    window_end: L.stamp(data.window_end),
    pad: String(data.pad || ""),
    location: String(data.location || ""),
    orbit: String(data.orbit || ""),
    mission_type: String(data.mission_type || ""),
    probability: L.probability(data.probability),
    weather: String(data.weather || ""),
    hold: String(data.hold || ""),
    description: String(data.description || "")
  }
}

function launchTo(item) {
  return {
    id: item.id,
    name: item.name,
    vehicle: item.vehicle,
    agency: item.agency,
    status_id: item.status_id,
    status: item.status,
    net: iso(item.net),
    precision: item.precision,
    window_start: iso(item.window_start),
    window_end: iso(item.window_end),
    pad: item.pad,
    location: item.location,
    orbit: item.orbit,
    mission_type: item.mission_type,
    probability: item.probability,
    weather: item.weather,
    hold: item.hold,
    description: item.description
  }
}

// { launches, fetched } -- fetched in epoch seconds, 0 for never.
function parseUpcoming(data) {
  var out = { launches: [], fetched: 0 }
  if (!data || typeof data !== "object") return out
  var records = data.launches
  if (!records || records.constructor !== Array) return out
  for (var i = 0; i < records.length; i++) {
    var item = launchFrom(records[i])
    if (item) out.launches.push(item)
  }
  out.fetched = L.number(data.fetched) || 0
  return out
}

function serializeUpcoming(launches, fetched) {
  var out = []
  for (var i = 0; i < (launches || []).length; i++) out.push(launchTo(launches[i]))
  return JSON.stringify({ schema: SCHEMA, fetched: fetched || 0, launches: out }, null, 1) + "\n"
}

// At most one row per launch: the later record, in the first one's place.
// Arrival order is NET order, because that is how the endpoint sorts.
function dedupe(launches) {
  var seen = {}
  var order = []
  for (var i = 0; i < (launches || []).length; i++) {
    var item = launches[i]
    if (seen[item.id] === undefined) order.push(item.id)
    seen[item.id] = item
  }
  var out = []
  for (var k = 0; k < order.length; k++) out.push(seen[order[k]])
  return out
}

// How old the cache is, in seconds: infinite when it was never fetched, and
// never negative when the clock went backwards.
function age(fetched, nowSeconds) {
  if (!(fetched > 0)) return Infinity
  return Math.max(0, nowSeconds - fetched)
}
