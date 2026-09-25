// Transitous (MOTIS 2): URLs in, small plain objects out, and the formatting
// every view shares. Pure functions only, so the same module runs in the
// views and on the worker thread.
//
// API: https://transitous.org/api/  ·  schema: motis-project/motis openapi.yaml
// (v6 for routing and departures, v1 for the geocoder, which has no v6).

export const BASE = "https://api.transitous.org"
export const VERSION = "1.0.0"
// Transitous asks every client to name itself and give a way to reach its
// author. Qt's XHR does send a custom User-Agent (checked against an echo
// server on the phone).
export const USER_AGENT = "omarchy-transit/" + VERSION + " (+https://github.com/SimonSchubert/omarchy-transit)"

// ------------------------------------------------------------ modes

// What the mode chips switch. The router takes the concrete modes; the person
// thinks in five groups.
export const GROUPS = [
  { key: "rail", label: "Trains", modes: ["HIGHSPEED_RAIL", "LONG_DISTANCE", "NIGHT_RAIL", "REGIONAL_FAST_RAIL", "REGIONAL_RAIL", "RAIL"] },
  { key: "city", label: "Metro & commuter", modes: ["SUBURBAN", "SUBWAY", "METRO"] },
  { key: "tram", label: "Tram", modes: ["TRAM", "FUNICULAR", "CABLE_CAR", "AERIAL_LIFT", "AREAL_LIFT"] },
  { key: "bus", label: "Bus", modes: ["BUS", "COACH"] },
  { key: "ferry", label: "Ferry", modes: ["FERRY"] }
]
export const GROUP_KEYS = GROUPS.map(function (g) { return g.key })

function g(cp) { return String.fromCodePoint(cp) }

// Nerd Font (Material Design) glyphs, each checked by its md- name against
// the font the phone draws them with.
export const GLYPH = {
  train: g(0xF052C),          // md-train
  trainVariant: g(0xF08C4),   // md-train_variant
  subway: g(0xF06AC),         // md-subway
  tram: g(0xF052D),           // md-tram
  bus: g(0xF00E7),            // md-bus
  ferry: g(0xF0213),          // md-ferry
  gondola: g(0xF0686),        // md-gondola
  plane: g(0xF001D),          // md-airplane
  walk: g(0xF0583),           // md-walk
  bike: g(0xF00A3),           // md-bike
  car: g(0xF010B),            // md-car
  transfer: g(0xF06AE),       // md-transit_transfer
  swap: g(0xF04E2),           // md-swap_vertical
  marker: g(0xF034E),         // md-map_marker
  markerOutline: g(0xF07D9),  // md-map_marker_outline
  stop: g(0xF1012),           // md-bus_stop
  home: g(0xF02DC),           // md-home
  work: g(0xF00D6),           // md-briefcase
  star: g(0xF04CE),           // md-star
  starOutline: g(0xF04D2),    // md-star_outline
  search: g(0xF0349),         // md-magnify
  settings: g(0xF08BB),       // md-cog_outline
  back: g(0xF004D),           // md-arrow_left
  close: g(0xF0156),          // md-close
  clock: g(0xF0150),          // md-clock_outline
  chevronRight: g(0xF0142),   // md-chevron_right
  chevronDown: g(0xF0140),    // md-chevron_down
  chevronUp: g(0xF0143),      // md-chevron_up
  alert: g(0xF0026),          // md-alert
  alertCircle: g(0xF05D6),    // md-alert_circle_outline
  info: g(0xF02FD),           // md-information_outline
  wheelchair: g(0xF05A4),     // md-wheelchair_accessibility
  refresh: g(0xF0450),        // md-refresh
  history: g(0xF02DA),        // md-history
  board: g(0xF0520),          // md-timetable
  route: g(0xF0641),          // md-directions_fork
  bookmark: g(0xF00C0),       // md-bookmark
  bookmarkOutline: g(0xF00C3),// md-bookmark_outline
  trash: g(0xF09E7),          // md-delete_outline
  calendar: g(0xF00F0),       // md-calendar_clock
  arrowRight: g(0xF19B0)      // md-arrow_right_thin
}

const MODE_INFO = {
  HIGHSPEED_RAIL: { glyph: "train", color: "#e5484d", label: "High-speed train" },
  LONG_DISTANCE: { glyph: "train", color: "#e5484d", label: "Long-distance train" },
  NIGHT_RAIL: { glyph: "train", color: "#6e56cf", label: "Night train" },
  REGIONAL_FAST_RAIL: { glyph: "trainVariant", color: "#e8590c", label: "Regional express" },
  REGIONAL_RAIL: { glyph: "trainVariant", color: "#e8590c", label: "Regional train" },
  RAIL: { glyph: "trainVariant", color: "#e8590c", label: "Train" },
  SUBURBAN: { glyph: "trainVariant", color: "#12a150", label: "Suburban train" },
  SUBWAY: { glyph: "subway", color: "#2563eb", label: "Metro" },
  METRO: { glyph: "subway", color: "#2563eb", label: "Metro" },
  TRAM: { glyph: "tram", color: "#d6336c", label: "Tram" },
  FUNICULAR: { glyph: "gondola", color: "#0ca678", label: "Funicular" },
  CABLE_CAR: { glyph: "gondola", color: "#0ca678", label: "Cable car" },
  AERIAL_LIFT: { glyph: "gondola", color: "#0ca678", label: "Aerial lift" },
  AREAL_LIFT: { glyph: "gondola", color: "#0ca678", label: "Aerial lift" },
  BUS: { glyph: "bus", color: "#7c4dff", label: "Bus" },
  COACH: { glyph: "bus", color: "#0d9488", label: "Coach" },
  FERRY: { glyph: "ferry", color: "#0891b2", label: "Ferry" },
  AIRPLANE: { glyph: "plane", color: "#475569", label: "Flight" },
  WALK: { glyph: "walk", color: "", label: "Walk" },
  BIKE: { glyph: "bike", color: "", label: "Bike" },
  CAR: { glyph: "car", color: "", label: "Car" }
}

export function modeGlyph(mode) {
  var m = MODE_INFO[mode]
  return GLYPH[m ? m.glyph : "bus"]
}
export function modeColor(mode) {
  var m = MODE_INFO[mode]
  return m && m.color ? m.color : "#64748b"
}
export function modeLabel(mode) {
  var m = MODE_INFO[mode]
  return m ? m.label : "Transit"
}
export function isTransit(mode) {
  return mode !== "WALK" && mode !== "BIKE" && mode !== "CAR" && mode !== "RENTAL"
    && mode !== "CAR_PARKING" && mode !== "CAR_DROPOFF" && mode !== "ODM" && mode !== "FLEX"
}
// The router's transitModes for the groups that are switched on. All of them
// is the router's own default, and a shorter URL.
export function transitModes(groups) {
  var on = GROUPS.filter(function (x) { return groups.indexOf(x.key) >= 0 })
  if (!on.length || on.length === GROUPS.length) return ""
  var modes = []
  for (var i = 0; i < on.length; i++) modes = modes.concat(on[i].modes)
  return modes.join(",")
}

// ------------------------------------------------------------ URLs

function qs(params) {
  var out = []
  for (var k in params) {
    var v = params[k]
    if (v === undefined || v === null || v === "") continue
    out.push(k + "=" + encodeURIComponent(String(v)))
  }
  return out.join("&")
}

// A place as the router takes it: a stop by its id, anything else by where it
// is. Ids are only ever the ones the geocoder handed out.
export function placeParam(p) {
  if (!p) return ""
  if (p.type === "STOP" && p.id) return p.id
  if (isFinite(p.lat) && isFinite(p.lon)) return round6(p.lat) + "," + round6(p.lon)
  return p.id || ""
}
function round6(x) { return Math.round(x * 1e6) / 1e6 }

export function geocodeUrl(text, lang, near, stopsOnly) {
  var t = String(text || "").trim()
  if (t.length < 2) return ""
  return BASE + "/api/v1/geocode?" + qs({
    text: t.slice(0, 120),
    type: stopsOnly ? "STOP" : "",
    language: lang,
    place: near && isFinite(near.lat) ? round6(near.lat) + "," + round6(near.lon) : "",
    placeBias: near && isFinite(near.lat) ? 2 : ""
  })
}

// q: { from, to, time (ms or 0 for now), arriveBy }, opts: { groups,
// wheelchair, maxTransfers, walk: "slow" | "normal" | "fast" }
export function planUrl(q, opts, cursor, lang) {
  if (!q || !q.from || !q.to) return ""
  var from = placeParam(q.from), to = placeParam(q.to)
  if (!from || !to) return ""
  var speed = opts && opts.walk === "slow" ? 0.9 : opts && opts.walk === "fast" ? 1.7 : ""
  return BASE + "/api/v6/plan?" + qs({
    fromPlace: from,
    toPlace: to,
    time: q.time ? new Date(q.time).toISOString() : "",
    arriveBy: q.arriveBy ? "true" : "",
    transitModes: transitModes(opts && opts.groups ? opts.groups : GROUP_KEYS),
    pedestrianProfile: opts && opts.wheelchair ? "WHEELCHAIR" : "",
    pedestrianSpeed: speed,
    maxTransfers: opts && opts.maxTransfers >= 0 ? opts.maxTransfers : "",
    numItineraries: 6,
    pageCursor: cursor || "",
    language: lang
  })
}

export function stoptimesUrl(stopId, time, arriveBy, groups, cursor, lang) {
  if (!stopId) return ""
  var modes = transitModes(groups || GROUP_KEYS)
  return BASE + "/api/v6/stoptimes?" + qs({
    stopId: stopId,
    time: time ? new Date(time).toISOString() : "",
    arriveBy: arriveBy ? "true" : "",
    n: 40,
    mode: modes,
    pageCursor: cursor || "",
    language: lang
  })
}

export function tripUrl(tripId, lang) {
  if (!tripId) return ""
  return BASE + "/api/v6/trip?" + qs({ tripId: tripId, language: lang })
}

// ------------------------------------------------------------ shaping

function ms(iso) {
  if (!iso) return 0
  var t = Date.parse(iso)
  return isFinite(t) ? t : 0
}
// Every string from the server passes through here. Angle brackets become
// look-alikes: a Qt Text guesses rich text from a tag, and a stop name or a
// notice must never render as markup (or fetch an <img>).
function str(x, max) {
  if (typeof x !== "string") return ""
  var s = max && x.length > max ? x.slice(0, max) : x
  return s.replace(/</g, "\u2039").replace(/>/g, "\u203a")
}
function num(x) { return typeof x === "number" && isFinite(x) ? x : NaN }
function hex(x) { return typeof x === "string" && /^[0-9a-fA-F]{6}$/.test(x) ? "#" + x.toLowerCase() : "" }

function shapeAlerts(list) {
  if (!Array.isArray(list)) return []
  var out = []
  for (var i = 0; i < list.length && out.length < 6; i++) {
    var a = list[i]
    if (!a) continue
    var head = str(a.headerText, 300), body = str(a.descriptionText, 1500)
    if (!head && !body) continue
    // Feeds repeat the same notice on every stop of a trip; one is enough.
    if (out.some(function (o) { return o.header === head && o.text === body })) continue
    out.push({ header: head, text: body, severe: a.severityLevel === "SEVERE" || a.effect === "NO_SERVICE" })
  }
  return out
}

// The area line under a name: the town it is in, and the country when it is
// not the one most results are in.
function areaOf(p) {
  var areas = Array.isArray(p.areas) ? p.areas : []
  var town = "", region = ""
  for (var i = 0; i < areas.length; i++) {
    var a = areas[i]
    if (!a || typeof a.name !== "string") continue
    if (a["default"] && !town) town = a.name
    if (a.adminLevel === 4 && !region) region = a.name
  }
  var name = str(p.name)
  var parts = []
  if (town && name.indexOf(town) < 0) parts.push(town)
  if (region && region !== town && parts.length === 0 && name.indexOf(region) < 0) parts.push(region)
  if (p.country) parts.push(str(p.country, 3))
  return parts.join(", ")
}

export function shapeGeocode(json) {
  if (!Array.isArray(json)) return null
  var out = []
  for (var i = 0; i < json.length && out.length < 12; i++) {
    var p = json[i]
    if (!p || typeof p.name !== "string") continue
    var lat = num(p.lat), lon = num(p.lon)
    if (!isFinite(lat) || !isFinite(lon)) continue
    out.push({
      id: str(p.id, 300),
      name: str(p.name, 160),
      type: p.type === "STOP" ? "STOP" : p.type === "ADDRESS" ? "ADDRESS" : "PLACE",
      lat: lat,
      lon: lon,
      area: areaOf(p),
      modes: Array.isArray(p.modes) ? p.modes.filter(function (m) { return typeof m === "string" }).slice(0, 12) : []
    })
  }
  return out
}

function shapePlace(p) {
  if (!p) return null
  return {
    name: str(p.name, 160),
    stopId: str(p.stopId, 300),
    lat: num(p.lat),
    lon: num(p.lon),
    arr: ms(p.arrival),
    dep: ms(p.departure),
    sArr: ms(p.scheduledArrival),
    sDep: ms(p.scheduledDeparture),
    track: str(p.track, 24),
    sTrack: str(p.scheduledTrack, 24),
    cancelled: p.cancelled === true,
    alerts: shapeAlerts(p.alerts)
  }
}

// "RE4 (3155)" is how DELFI names a regional train: the line, then the
// train's own number. The badge wants the line; the number goes beside it.
export function lineName(x) {
  var n = str(x.displayName) || str(x.routeShortName) || str(x.tripShortName)
  return n.replace(/\s*\(\d+\)\s*$/, "").slice(0, 24)
}
function tripNumber(x) {
  var m = /\((\d+)\)\s*$/.exec(str(x.displayName))
  if (m) return m[1]
  var t = str(x.tripShortName)
  return t && t !== lineName(x) ? t.slice(0, 24) : ""
}

function shapeLine(x) {
  return {
    mode: str(x.mode, 32),
    line: lineName(x),
    number: tripNumber(x),
    color: hex(x.routeColor),
    textColor: hex(x.routeTextColor),
    headsign: str(x.headsign, 160),
    agency: str(x.agencyName, 120),
    tripId: str(x.tripId, 300),
    realTime: x.realTime === true,
    wheelchair: x.wheelchairAccessible === "ACCESSIBLE",
    bikes: x.bikesAllowed === true
  }
}

function shapeLeg(l) {
  var leg = shapeLine(l)
  leg.transit = isTransit(leg.mode)
  leg.from = shapePlace(l.from)
  leg.to = shapePlace(l.to)
  leg.start = ms(l.startTime)
  leg.end = ms(l.endTime)
  leg.sStart = ms(l.scheduledStartTime) || leg.start
  leg.sEnd = ms(l.scheduledEndTime) || leg.end
  leg.duration = num(l.duration) || Math.max(0, (leg.end - leg.start) / 1000)
  leg.distance = num(l.distance)
  leg.cancelled = l.cancelled === true
  leg.alerts = shapeAlerts(l.alerts)
  var stops = Array.isArray(l.intermediateStops) ? l.intermediateStops : []
  leg.stops = []
  for (var i = 0; i < stops.length && i < 200; i++) leg.stops.push(shapePlace(stops[i]))
  return leg
}

// Identifies one journey across refreshes: the trips it rides, in order.
// MOTIS's own id changes with every realtime update.
function journeyKey(legs) {
  return legs.map(function (l) {
    return l.transit ? l.tripId : l.mode
  }).join("|")
}

export function shapeItinerary(it) {
  if (!it || !Array.isArray(it.legs)) return null
  var legs = []
  for (var i = 0; i < it.legs.length && i < 30; i++) legs.push(shapeLeg(it.legs[i]))
  if (!legs.length) return null
  var first = legs[0], last = legs[legs.length - 1]
  var live = legs.some(function (l) { return l.transit && l.realTime })
  return {
    key: journeyKey(legs) + "@" + first.sStart,
    start: first.start || ms(it.startTime),
    end: last.end || ms(it.endTime),
    sStart: first.sStart,
    sEnd: last.sEnd,
    duration: num(it.duration) || (last.end - first.start) / 1000,
    transfers: Math.max(0, num(it.transfers) || 0),
    realTime: live,
    cancelled: legs.some(function (l) { return l.cancelled || (l.from && l.from.cancelled) || (l.to && l.to.cancelled) }),
    legs: legs
  }
}

function shapePlan(json) {
  if (!json || !Array.isArray(json.itineraries)) return null
  var its = []
  for (var i = 0; i < json.itineraries.length; i++) {
    var x = shapeItinerary(json.itineraries[i])
    if (x) its.push(x)
  }
  // A walk (or bike ride) the router thinks is as good as transit.
  var direct = []
  if (Array.isArray(json.direct)) for (var j = 0; j < json.direct.length && j < 2; j++) {
    var d = shapeItinerary(json.direct[j])
    if (d) direct.push(d)
  }
  return {
    itineraries: its,
    direct: direct,
    prev: str(json.previousPageCursor, 400),
    next: str(json.nextPageCursor, 400)
  }
}

function shapeStoptimes(json) {
  if (!json || !Array.isArray(json.stopTimes)) return null
  var rows = []
  for (var i = 0; i < json.stopTimes.length && i < 120; i++) {
    var s = json.stopTimes[i]
    if (!s || !s.place) continue
    var r = shapeLine(s)
    r.place = shapePlace(s.place)
    r.cancelled = s.cancelled === true || s.tripCancelled === true || r.place.cancelled
    r.alerts = shapeAlerts(s.place.alerts)
    r.origin = s.tripFrom ? str(s.tripFrom.name, 160) : ""
    r.terminus = s.tripTo ? str(s.tripTo.name, 160) : ""
    rows.push(r)
  }
  return {
    rows: rows,
    stop: json.place ? shapePlace(json.place) : null,
    prev: str(json.previousPageCursor, 400),
    next: str(json.nextPageCursor, 400)
  }
}

export function shape(kind, json) {
  switch (kind) {
  case "geocode": return shapeGeocode(json)
  case "plan": return shapePlan(json)
  case "stoptimes": return shapeStoptimes(json)
  case "trip": return shapeItinerary(json)
  }
  return null
}

// ------------------------------------------------------------ validation

// A place worth keeping in prefs: what the geocoder gave, nothing more.
export function cleanPlace(p) {
  if (!p || typeof p !== "object") return null
  var lat = Number(p.lat), lon = Number(p.lon)
  if (!isFinite(lat) || !isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) return null
  var name = str(p.name, 160)
  if (!name) return null
  return {
    id: str(p.id, 300),
    name: name,
    type: p.type === "STOP" ? "STOP" : p.type === "ADDRESS" ? "ADDRESS" : "PLACE",
    lat: lat,
    lon: lon,
    area: str(p.area, 120),
    modes: Array.isArray(p.modes) ? p.modes.filter(function (m) { return typeof m === "string" }).slice(0, 12) : []
  }
}

export function samePlace(a, b) {
  if (!a || !b) return false
  if (a.id && b.id) return a.id === b.id
  return Math.abs(a.lat - b.lat) < 1e-5 && Math.abs(a.lon - b.lon) < 1e-5
}

// ------------------------------------------------------------ formatting

function pad(n) { return n < 10 ? "0" + n : "" + n }

// In the phone's own time zone, which is where the person is.
export function clock(t, h24) {
  if (!t) return "–"
  var d = new Date(t)
  var h = d.getHours(), m = d.getMinutes()
  if (h24) return pad(h) + ":" + pad(m)
  var ap = h < 12 ? "am" : "pm"
  h = h % 12
  if (h === 0) h = 12
  return h + ":" + pad(m) + " " + ap
}

export function delayMinutes(live, planned) {
  if (!live || !planned) return 0
  return Math.round((live - planned) / 60000)
}

export function duration(seconds) {
  var m = Math.max(0, Math.round(seconds / 60))
  if (m < 60) return m + " min"
  var h = Math.floor(m / 60), r = m % 60
  if (h >= 24) {
    var d = Math.floor(h / 24)
    return d + " d " + (h % 24) + " h"
  }
  return r ? h + " h " + r + " min" : h + " h"
}

export function distance(meters) {
  if (!isFinite(meters)) return ""
  if (meters < 1000) return Math.max(10, Math.round(meters / 10) * 10) + " m"
  return (Math.round(meters / 100) / 10) + " km"
}

// "in 12 min", "in 2 h 5 min", or the day when it is not today.
export function leavesIn(t, now) {
  var m = Math.round((t - now) / 60000)
  if (m <= 0) return "now"
  if (m < 60) return "in " + m + " min"
  if (m < 180) return "in " + Math.floor(m / 60) + " h" + (m % 60 ? " " + (m % 60) + " min" : "")
  var d = dayLabel(t, now)
  return d === "Today" ? "" : d
}

const DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

export function dayLabel(t, now) {
  var d = new Date(t), n = new Date(now)
  var a = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
  var b = new Date(n.getFullYear(), n.getMonth(), n.getDate()).getTime()
  var diff = Math.round((a - b) / 86400000)
  if (diff === 0) return "Today"
  if (diff === 1) return "Tomorrow"
  if (diff === -1) return "Yesterday"
  return DAYS[d.getDay()] + " " + d.getDate() + " " + MONTHS[d.getMonth()]
}

// "Pl. 4" for a bare number; a feed that already says "Pos. 2" or "Gleis 5"
// keeps its own words.
export function platform(track) {
  if (!track) return ""
  return /^\d{1,3}[a-zA-Z]?(-\d{1,3}[a-zA-Z]?)?$/.test(track) ? "Pl. " + track : track
}

// The minutes between arriving on one leg and leaving on the next transit leg,
// walks included, and the walk that fills them.
export function transfers(it) {
  var out = []
  if (!it) return out
  var legs = it.legs
  for (var i = 0; i < legs.length; i++) {
    if (!legs[i].transit) continue
    for (var j = i + 1; j < legs.length; j++) {
      if (!legs[j].transit) continue
      var walk = 0
      for (var k = i + 1; k < j; k++) walk += legs[k].duration
      out.push({ after: i, before: j, minutes: Math.round((legs[j].start - legs[i].end) / 60000), walk: Math.round(walk / 60) })
      break
    }
  }
  return out
}
