// Everything about radio-browser.info that is not a request: where to ask,
// what to keep of the answer, and how to print it. Pure functions. An
// ECMAScript module rather than a `.pragma library` script so the worker thread
// that shapes answers (Worker.mjs) imports the very same code the views do.
//
// radio-browser is a community directory: anybody can add a station, and every
// field of it is whatever they typed. So answers are copied field by field
// into small plain objects, every string that reaches a Text item has passed
// through here, and a link or a stream is kept only when it is http(s).

// No key and no account. The API asks to be spread over its mirrors, found
// through /json/servers; this one name answers from any of them, and is where
// the app starts and falls back to.
export var ANY_SERVER = "https://all.api.radio-browser.info"
export var SITE = "https://www.radio-browser.info"

// Answers are cached by path, so the same list stays one entry whichever
// mirror served it.
export var PAGE = 40

// ------------------------------------------------------------ checks

export function uuid(v) {
  var s = String(v || "").toLowerCase()
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(s) ? s : ""
}

// A mirror's host name, as /json/servers lists it.
export function serverName(v) {
  var s = String(v || "").toLowerCase()
  return /^[a-z0-9-]{1,40}\.api\.radio-browser\.info$/.test(s) ? s : ""
}

export function webUrl(v) {
  var s = String(v || "").trim()
  if (s.length > 2000 || !/^https?:\/\/[^\s/?#]+/i.test(s)) return ""
  if (/[\s<>"]/.test(s)) return ""
  return s
}

export function httpsUrl(v) {
  var s = webUrl(v)
  return /^https:/i.test(s) ? s : ""
}

// Printable text only: no control characters, one line, at most `max`.
export function clean(v, max) {
  if (v === null || v === undefined) return ""
  var s = String(v).replace(/[\x00-\x1f\x7f]+/g, " ").replace(/\s+/g, " ").trim()
  return s.length > max ? s.slice(0, max - 1) + "…" : s
}

export function count(v) {
  var n = Math.floor(Number(v))
  return isFinite(n) && n > 0 ? Math.min(n, 1e9) : 0
}

export function q(v) { return encodeURIComponent(String(v)) }

// ------------------------------------------------------------ endpoints

// How a list of stations can be ordered, as the chips offer it.
export var ORDERS = [
  { key: "clickcount", label: "Popular", reverse: true },
  { key: "clicktrend", label: "Trending", reverse: true },
  { key: "votes", label: "Most loved", reverse: true },
  { key: "bitrate", label: "Best quality", reverse: true },
  { key: "name", label: "A–Z", reverse: false }
]

function order(key) {
  for (var i = 0; i < ORDERS.length; i++) if (ORDERS[i].key === key) return ORDERS[i]
  return ORDERS[0]
}

// The one search endpoint does every list: a genre, a country, a language, a
// name, or none of those for the whole directory.
export function stationsPath(filter, orderKey, page) {
  var o = order(orderKey)
  var p = "/json/stations/search?hidebroken=true&order=" + o.key + "&reverse=" + o.reverse
    + "&limit=" + PAGE + "&offset=" + Math.max(0, Math.floor(Number(page) || 0)) * PAGE
  var f = filter || {}
  if (f.tag) p += "&tag=" + q(f.tag) + "&tagExact=true"
  if (f.tagLike) p += "&tag=" + q(f.tagLike)
  if (f.country) p += "&countrycode=" + q(f.country)
  if (f.language) p += "&language=" + q(f.language) + "&languageExact=true"
  if (f.name) p += "&name=" + q(f.name)
  return p
}

export function tagsPath() { return "/json/tags?order=stationcount&reverse=true&hidebroken=true&limit=400" }
export function countriesPath() { return "/json/countries?order=stationcount&reverse=true&hidebroken=true" }
export function languagesPath() { return "/json/languages?order=stationcount&reverse=true&hidebroken=true&limit=250" }
export function statsPath() { return "/json/stats" }
export function serversPath() { return "/json/servers" }
export function stationPath(id) { return "/json/stations/byuuid/" + uuid(id) }
// Counts a listen, as the API asks every player to.
export function clickPath(id) { return "/json/url/" + uuid(id) }
export function votePath(id) { return "/json/vote/" + uuid(id) }

// ------------------------------------------------------------ shaping

// Longer official names, shortened to what anybody calls the place.
var COUNTRY_NAMES = {
  "The United States Of America": "United States",
  "The United Kingdom Of Great Britain And Northern Ireland": "United Kingdom",
  "The Russian Federation": "Russia",
  "Russian Federation": "Russia",
  "The Netherlands": "Netherlands",
  "Republic Of Korea": "South Korea",
  "The Republic Of Korea": "South Korea",
  "Korea, Republic Of": "South Korea",
  "Iran (Islamic Republic Of)": "Iran",
  "Islamic Republic Of Iran": "Iran",
  "Bolivarian Republic Of Venezuela": "Venezuela",
  "Plurinational State Of Bolivia": "Bolivia",
  "United Republic Of Tanzania": "Tanzania",
  "The Philippines": "Philippines",
  "The Czech Republic": "Czechia",
  "Czech Republic": "Czechia",
  "The Dominican Republic": "Dominican Republic",
  "Viet Nam": "Vietnam",
  "Türkiye": "Turkey",
  "Taiwan, Republic Of China": "Taiwan",
  "Republic Of Moldova": "Moldova",
  "The Democratic Republic Of The Congo": "DR Congo",
  "Syrian Arab Republic": "Syria",
  "Lao People's Democratic Republic": "Laos",
  "The United Arab Emirates": "United Arab Emirates"
}

export function countryName(v) {
  var s = clean(v, 80)
  if (COUNTRY_NAMES[s]) return COUNTRY_NAMES[s]
  return s.replace(/^The /, "")
}

export function cc(v) {
  var s = String(v || "").toUpperCase()
  return /^[A-Z]{2}$/.test(s) ? s : ""
}

function capital(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : "" }

export function languageName(v) {
  return clean(v, 40).split(" ").map(capital).join(" ")
}

// "rock,Classic Rock, 80s ,rock" -> ["rock", "classic rock", "80s"]
export function tags(v, max) {
  var out = []
  var parts = String(v || "").split(",")
  for (var i = 0; i < parts.length && out.length < max; i++) {
    var t = clean(parts[i], 32).toLowerCase()
    if (t.length < 2 || out.indexOf(t) >= 0) continue
    out.push(t)
  }
  return out
}

// A stable colour per station, from its name: the tile it wears until its
// logo arrives, and when it has none.
export function hue(v) {
  var s = String(v || "")
  var h = 0
  for (var i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) % 360
  return h
}

// Up to two letters from the name, for that tile.
export function initials(name) {
  var words = String(name || "").replace(/[^0-9A-Za-zÀ-ÿ ]+/g, " ").trim().split(/\s+/)
  var a = words[0] ? words[0].charAt(0) : ""
  var b = words.length > 1 ? words[1].charAt(0) : (words[0] && words[0].length > 1 ? words[0].charAt(1) : "")
  return (a + b).toUpperCase() || "FM"
}

export function station(o) {
  if (!o || typeof o !== "object") return null
  var id = uuid(o.stationuuid)
  var stream = webUrl(o.url_resolved) || webUrl(o.url)
  if (!id || !stream) return null
  var name = clean(o.name, 120) || "Unnamed station"
  var langs = String(o.language || "").split(",").map(function (l) { return languageName(l) }).filter(function (l) { return l })
  return {
    id: id,
    name: name,
    stream: stream,
    homepage: webUrl(o.homepage),
    favicon: webUrl(o.favicon),
    tags: tags(o.tags, 10),
    country: countryName(o.country),
    cc: cc(o.countrycode),
    state: clean(o.state, 60),
    language: langs.slice(0, 3).join(", "),
    codec: clean(o.codec, 12).toUpperCase().replace(/^UNKNOWN$/, ""),
    bitrate: Math.min(count(o.bitrate), 9999),
    hls: Number(o.hls) === 1,
    votes: count(o.votes),
    clicks: count(o.clickcount),
    trend: Math.floor(Number(o.clicktrend)) || 0,
    ok: Number(o.lastcheckok) !== 0,
    hue: hue(name)
  }
}

// A station as saved in favourites and history: the same fields, checked
// again, since the file could have been edited by hand.
export function saved(o) {
  if (!o || typeof o !== "object") return null
  var id = uuid(o.id)
  var stream = webUrl(o.stream)
  if (!id || !stream) return null
  var name = clean(o.name, 120) || "Unnamed station"
  return {
    id: id,
    name: name,
    stream: stream,
    homepage: webUrl(o.homepage),
    favicon: webUrl(o.favicon),
    tags: Array.isArray(o.tags) ? tags(o.tags.join(","), 10) : [],
    country: clean(o.country, 80),
    cc: cc(o.cc),
    state: clean(o.state, 60),
    language: clean(o.language, 80),
    codec: clean(o.codec, 12),
    bitrate: Math.min(count(o.bitrate), 9999),
    hls: o.hls === true,
    votes: count(o.votes),
    clicks: count(o.clicks),
    trend: Math.floor(Number(o.trend)) || 0,
    ok: o.ok !== false,
    hue: hue(name)
  }
}

export function stations(json, max) {
  if (!Array.isArray(json)) return null
  var out = []
  var seen = {}
  for (var i = 0; i < json.length && out.length < (max || 500); i++) {
    var s = station(json[i])
    if (!s || seen[s.id]) continue
    seen[s.id] = true
    out.push(s)
  }
  return out
}

// Tags, countries and languages: a name, a code where there is one, and how
// many stations. Tiny tags -- one station's typo -- are left out.
export function facets(json, kind) {
  if (!Array.isArray(json)) return null
  var out = []
  for (var i = 0; i < json.length && out.length < 400; i++) {
    var f = json[i]
    if (!f) continue
    var n = count(f.stationcount)
    if (!n) continue
    if (kind === "countries") {
      var code = cc(f.iso_3166_1)
      if (!code) continue
      out.push({ key: code, code: code, name: countryName(f.name), count: n })
    } else if (kind === "languages") {
      var l = clean(f.name, 40).toLowerCase()
      if (!l || n < 3) continue
      out.push({ key: l, code: l, name: languageName(l), count: n })
    } else {
      var t = clean(f.name, 32).toLowerCase()
      if (t.length < 2 || n < 5) continue
      out.push({ key: t, code: t, name: t, count: n, hue: hue(t) })
    }
  }
  if (kind === "countries") out.sort(function (a, b) { return b.count - a.count })
  return out
}

export function stats(json) {
  if (!json || typeof json !== "object") return null
  return { stations: count(json.stations), countries: count(json.countries), tags: count(json.tags), languages: count(json.languages) }
}

export function servers(json) {
  if (!Array.isArray(json)) return null
  var out = []
  for (var i = 0; i < json.length; i++) {
    var n = serverName(json[i] && json[i].name)
    if (n && out.indexOf(n) < 0) out.push(n)
  }
  return out
}

export function shape(kind, json) {
  switch (kind) {
  case "stations": return stations(json, 200)
  case "station": { var s = stations(json, 1); return s && s.length ? s[0] : null }
  case "tags": return facets(json, "tags")
  case "countries": return facets(json, "countries")
  case "languages": return facets(json, "languages")
  case "stats": return stats(json)
  case "servers": return servers(json)
  }
  return null
}

// ------------------------------------------------------------ what the player hears

// The song, out of the metadata mpv reports for a stream: Icecast and
// Shoutcast send "StreamTitle" (icy-title); HLS and some Ogg streams send
// artist and title tags. Stations fill it with anything, so what is only the
// station's own name, a URL or punctuation is not a song.
export function song(meta, stationName) {
  if (!meta || typeof meta !== "object") return ""
  var m = {}
  for (var k in meta) m[String(k).toLowerCase()] = meta[k]
  var s = m["icy-title"] || m["streamtitle"] || ""
  if (!s && m.title) s = m.artist ? m.artist + " – " + m.title : m.title
  s = clean(s, 200)
  if (!/[0-9A-Za-zÀ-ɏͰ-ϿЀ-ӿ぀-ヿ一-鿿가-힯؀-ۿ]/.test(s)) return ""
  if (/^https?:\/\//i.test(s)) return ""
  var n = String(stationName || "").toLowerCase().trim()
  if (n && s.toLowerCase() === n) return ""
  return s
}

// ------------------------------------------------------------ printing

export function compact(n) {
  if (!n) return "0"
  if (n >= 1e6) return (n / 1e6).toFixed(n >= 1e7 ? 0 : 1).replace(/\.0$/, "") + "M"
  if (n >= 1e3) return (n / 1e3).toFixed(n >= 1e4 ? 0 : 1).replace(/\.0$/, "") + "K"
  return String(n)
}

export function group(n) { return String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ",") }

// "AAC · 64 kbps"
export function quality(s) {
  if (!s) return ""
  var parts = []
  if (s.codec) parts.push(s.codec)
  if (s.bitrate) parts.push(s.bitrate + " kbps")
  return parts.join(" · ")
}

// The line under a station's name: where it is and what it plays.
export function subtitle(s) {
  if (!s) return ""
  var parts = []
  if (s.country) parts.push(s.country)
  if (s.tags && s.tags.length) parts.push(s.tags.slice(0, 2).join(", "))
  return parts.join(" · ")
}

export function place(s) {
  if (!s) return ""
  if (s.state && s.country && s.state.toLowerCase() !== s.country.toLowerCase()) return s.state + ", " + s.country
  return s.country || s.state || ""
}

export function greeting(d) {
  var h = d.getHours()
  return h < 5 ? "Good night" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
}

// The genres on Discover, in the order they are shown. `tag` is the exact tag
// on radio-browser; `hue` is the tile's colour.
export var GENRES = [
  { tag: "pop", label: "Pop", hue: 330 },
  { tag: "rock", label: "Rock", hue: 8 },
  { tag: "jazz", label: "Jazz", hue: 36 },
  { tag: "classical", label: "Classical", hue: 48 },
  { tag: "electronic", label: "Electronic", hue: 262 },
  { tag: "news", label: "News", hue: 212 },
  { tag: "chillout", label: "Chillout", hue: 172 },
  { tag: "dance", label: "Dance", hue: 292 },
  { tag: "hiphop", label: "Hip hop", hue: 22 },
  { tag: "talk", label: "Talk", hue: 196 },
  { tag: "80s", label: "80s", hue: 312 },
  { tag: "oldies", label: "Oldies", hue: 28 },
  { tag: "ambient", label: "Ambient", hue: 228 },
  { tag: "lounge", label: "Lounge", hue: 184 },
  { tag: "country", label: "Country", hue: 32 },
  { tag: "folk", label: "Folk", hue: 96 },
  { tag: "soul", label: "Soul", hue: 348 },
  { tag: "blues", label: "Blues", hue: 220 },
  { tag: "metal", label: "Metal", hue: 0 },
  { tag: "reggae", label: "Reggae", hue: 128 },
  { tag: "sports", label: "Sports", hue: 146 },
  { tag: "kids", label: "Kids", hue: 52 }
]

// The country this computer is set to, from its locale ("de_DE" -> "DE").
export function localeCountry(name) {
  var m = /^[a-z]{2,3}[_-]([A-Z]{2})/.exec(String(name || ""))
  return m ? m[1] : ""
}

export function two(n) { return ("0" + n).slice(-2) }

// "1:05:00" / "42:10" / "0:09"
export function clock(ms) {
  var s = Math.max(0, Math.round(ms / 1000))
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  return (h ? h + ":" + two(m) : String(m)) + ":" + two(s % 60)
}
