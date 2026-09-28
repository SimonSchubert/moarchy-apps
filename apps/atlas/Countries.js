// Countries: what REST Countries says, and what a person reads.
//
// REST Countries retired its keyless v1-v4 in 2026, and v5 wants a key on
// every request: a free account is 1,000 requests a month. The whole world is
// 250 records, so it is three pages of a hundred, asked for once and kept for
// a month -- three requests of the thousand, and the app never asks for one
// country at a time. The flags come from the same people's CDN, which needs
// no key at all, and are kept beside the data so the quiz works on a plane.
//
// Nothing here touches QML: the half that can be wrong -- somebody else's
// JSON, a population turned into words -- is kept apart from the screen that
// draws it, and tested on its own.
.pragma library

var API = "https://api.restcountries.com/countries/v5"
var FLAGS = "https://flags.restcountries.com/v5/"
var SIGN_UP = "https://restcountries.com/sign-up"
var AGENT = "moarchy-atlas/0.1.0 (+https://github.com/SimonSchubert/moarchy-apps)"
var TIMEOUT = 20
// The free plan's ceiling for one page.
var PAGE = 100
// Past this many pages something is wrong with `more`, not with the world.
var MAX_PAGES = 6
// A hundred countries with these fields is a few hundred kilobytes.
var MAX_BYTES = 6 * 1024 * 1024
// A flag at w320 is 0.4-25 kB; anything this big is not a flag.
var MAX_FLAG_BYTES = 400 * 1024

// Populations move every few hours upstream, and nobody reading an atlas
// needs today's: a month, which is three requests of a free month's thousand.
var STALE_S = 30 * 86400
var RATE_LIMIT_S = 30

// Only what the screens draw. `names.translations` alone is most of a record.
var FIELDS = [
  "names.common", "names.official", "names.native",
  "codes.alpha_2", "codes.alpha_3",
  "capitals", "region", "subregion", "continents",
  "population", "area", "coordinates",
  "languages", "currencies", "calling_codes", "tlds", "timezones",
  "borders", "cars", "landlocked", "classification", "memberships",
  "demonyms", "descriptions", "flag.description", "flag.colors",
  "date.start_of_week"
]

var REGIONS = ["Africa", "Americas", "Asia", "Europe", "Oceania", "Antarctic"]

var SORTS = ["name", "population", "area"]

// The memberships worth a badge, in the order they are drawn, as their
// members write them.
var MEMBERSHIPS = [
  ["eu", "EU"], ["eurozone", "Eurozone"], ["schengen", "Schengen"],
  ["nato", "NATO"], ["g7", "G7"], ["g20", "G20"], ["oecd", "OECD"],
  ["commonwealth", "Commonwealth"], ["african_union", "African Union"],
  ["arab_league", "Arab League"], ["asean", "ASEAN"], ["brics", "BRICS"],
  ["opec", "OPEC"]
]

var DASH = "—"

// --- asking --------------------------------------------------------------

function url(offset) {
  return API + "?limit=" + PAGE + "&offset=" + Math.max(0, offset | 0)
    + "&response_fields=" + FIELDS.join(",")
}

// The curl command for one page. It prints the body, then a newline and the
// HTTP status, which is what `answer()` reads; the headers go to stderr for
// a Retry-After.
function command(key, offset) {
  return ["curl", "-sS", "--max-time", String(TIMEOUT),
          "--max-filesize", String(MAX_BYTES),
          "-H", "User-Agent: " + AGENT,
          "-H", "Accept: application/json",
          "-H", "Authorization: Bearer " + key,
          "-D", "/dev/stderr",
          "-w", "\n%{http_code}", url(offset)]
}

// What one page came to: { countries, more, total, error, retry, auth }.
// `auth` is true when the key itself was refused -- the one failure that
// retrying cannot fix and a person has to.
function answer(exitCode, output, headers) {
  var fail = function (error, extra) {
    var r = { countries: [], more: false, total: 0, error: error, retry: 0, auth: false }
    for (var k in (extra || {})) r[k] = extra[k]
    return r
  }
  if (exitCode === 63) return fail("REST Countries sent more than this app will read.")
  if (exitCode !== 0) return fail("No answer from REST Countries.")
  var text = String(output || "")
  var cut = text.lastIndexOf("\n")
  var status = cut >= 0 ? parseInt(text.slice(cut + 1).trim(), 10) : 0
  var body = cut >= 0 ? text.slice(0, cut) : text
  if (status === 401) return fail("REST Countries did not accept that key.", { auth: true })
  if (status === 403) return fail("This REST Countries account has used its month, or is paused.")
  if (status === 429) {
    var m = String(headers || "").match(/^retry-after:\s*(\d+)\s*$/im)
    return fail("REST Countries asked this app to slow down.", { retry: m ? parseInt(m[1], 10) : RATE_LIMIT_S })
  }
  if (status === 410) return fail("REST Countries has retired the version this app speaks.")
  if (status >= 500 && status < 600) return fail("REST Countries is having trouble.")
  if (status !== 200) return fail("REST Countries refused the request (" + status + ").")
  var page = parsePage(body)
  if (page.error) return fail(page.error)
  return { countries: page.countries, more: page.more, total: page.total, error: "", retry: 0, auth: false }
}

// { data: { objects: [...], meta: { total, more } } }. The demo key answers
// in the same shape with a `_demo` beside it and one sample country, which is
// not the world and must not be kept as though it were.
function parsePage(body) {
  var data
  try { data = JSON.parse(body) } catch (e) { return { countries: [], more: false, total: 0, error: "REST Countries sent something that is not JSON." } }
  var root = data && typeof data === "object" ? data.data : null
  if (!root || typeof root !== "object") {
    var why = data && data.errors && data.errors[0] && text(data.errors[0].message)
    return { countries: [], more: false, total: 0, error: why ? "REST Countries: " + why : "REST Countries sent an answer this app does not know." }
  }
  if (root._demo) return { countries: [], more: false, total: 0, error: "That is REST Countries' demo key, which answers with one sample country. Atlas needs a key of your own." }
  var objects = Array.isArray(root.objects) ? root.objects : []
  var out = []
  for (var i = 0; i < objects.length; i++) {
    var c = parse(objects[i])
    if (c) out.push(c)
  }
  var meta = root.meta && typeof root.meta === "object" ? root.meta : {}
  return { countries: out, more: meta.more === true && objects.length > 0,
           total: number(meta.total) || 0, error: "" }
}

// --- reading the wire ----------------------------------------------------

function text(value) {
  return typeof value === "string" ? value.trim() : ""
}

// A number, and never a boolean or a string that looks like one.
function number(value) {
  return typeof value === "number" && isFinite(value) ? value : null
}

function strings(value) {
  var out = []
  if (!Array.isArray(value)) return out
  for (var i = 0; i < value.length; i++) {
    var s = text(value[i])
    if (s && out.indexOf(s) < 0) out.push(s)
  }
  return out
}

function obj(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {}
}

function hex(value) {
  var s = text(value)
  return /^#[0-9a-fA-F]{6}$/.test(s) ? s.toLowerCase() : ""
}

// One record, as this app keeps it -- flat, and every field of the type the
// screen expects, whatever the wire said. Null for a record with no code or
// no name, which could be neither drawn nor found again.
function parse(record) {
  var r = obj(record)
  var names = obj(r.names)
  var codes = obj(r.codes)
  var code = text(codes.alpha_2).toUpperCase()
  var name = text(names.common)
  if (!/^[A-Z]{2}$/.test(code) || !name) return null

  var natives = []
  var nat = obj(names["native"])
  for (var lang in nat) {
    var n = text(obj(nat[lang]).common)
    if (n && n !== name && natives.indexOf(n) < 0) natives.push(n)
  }

  var capitals = []
  var capitalAt = null
  var caps = Array.isArray(r.capitals) ? r.capitals : []
  for (var i = 0; i < caps.length; i++) {
    var cap = caps[i]
    var cn = typeof cap === "string" ? text(cap) : text(obj(cap).name)
    if (!cn || capitals.indexOf(cn) >= 0) continue
    // The primary capital first: Bolivia's is Sucre, where La Paz governs.
    var primary = obj(obj(cap).attributes).primary === true
    if (primary) capitals.unshift(cn); else capitals.push(cn)
    var at = obj(obj(cap).coordinates)
    if ((primary || !capitalAt) && number(at.lat) !== null && number(at.lng) !== null)
      capitalAt = { lat: at.lat, lng: at.lng }
  }

  var languages = []
  var langs = Array.isArray(r.languages) ? r.languages : []
  for (var l = 0; l < langs.length; l++) {
    var ln = typeof langs[l] === "string" ? text(langs[l]) : text(obj(langs[l]).name)
    if (ln && languages.indexOf(ln) < 0) languages.push(ln)
  }

  var currencies = []
  var curs = Array.isArray(r.currencies) ? r.currencies : []
  for (var c = 0; c < curs.length; c++) {
    var cur = obj(curs[c])
    var ccode = text(cur.code).toUpperCase()
    var cname = text(cur.name)
    if (!ccode && !cname) continue
    currencies.push({ code: ccode, name: cname, symbol: text(cur.symbol) })
  }

  var memberships = []
  var mem = obj(r.memberships)
  for (var m = 0; m < MEMBERSHIPS.length; m++)
    if (mem[MEMBERSHIPS[m][0]] === true) memberships.push(MEMBERSHIPS[m][1])

  var cls = obj(r.classification)
  var area = obj(r.area)
  var at2 = obj(r.coordinates)
  var dem = obj(obj(r.demonyms).eng)
  var desc = obj(r.descriptions)
  var flag = obj(r.flag)
  var colors = obj(flag.colors)
  var drive = text(obj(r.cars).driving_side).toLowerCase()
  var region = text(r.region)
  var population = number(r.population)
  var km2 = number(area.kilometers)

  // `id` is what the kit's Keyed follows a row by.
  return {
    id: code,
    code: code,
    a3: text(codes.alpha_3).toUpperCase(),
    name: name,
    official: text(names.official),
    "native": natives,
    capitals: capitals,
    capitalAt: capitalAt,
    region: region,
    subregion: text(r.subregion),
    population: population !== null && population >= 0 ? Math.round(population) : null,
    area: km2 !== null && km2 > 0 ? km2 : null,
    lat: number(at2.lat),
    lng: number(at2.lng),
    languages: languages,
    currencies: currencies,
    calling: strings(r.calling_codes),
    tlds: strings(r.tlds),
    timezones: strings(r.timezones),
    borders: strings(r.borders).map(function (b) { return b.toUpperCase() }),
    drives: drive === "left" || drive === "right" ? drive : "",
    landlocked: r.landlocked === true,
    sovereign: cls.sovereign === true,
    un: cls.un_member === true || mem.un === true,
    memberships: memberships,
    demonym: text(dem.m) || text(dem.f),
    about: text(desc["long"]) || text(desc["short"]),
    flagAbout: text(flag.description),
    tint: hex(colors.prominent) || hex(colors.dominant),
    weekStarts: text(obj(r.date).start_of_week).toLowerCase()
  }
}

// A record that was written by this app, read back: the same checks, on the
// flat shape. Anything that is not the right type is dropped rather than
// drawn.
function restore(item) {
  var r = obj(item)
  var code = text(r.code).toUpperCase()
  var name = text(r.name)
  if (!/^[A-Z]{2}$/.test(code) || !name) return null
  var currencies = []
  var curs = Array.isArray(r.currencies) ? r.currencies : []
  for (var i = 0; i < curs.length; i++) {
    var cur = obj(curs[i])
    if (text(cur.code) || text(cur.name))
      currencies.push({ code: text(cur.code), name: text(cur.name), symbol: text(cur.symbol) })
  }
  var at = obj(r.capitalAt)
  var pop = number(r.population)
  var km2 = number(r.area)
  return {
    id: code, code: code, a3: text(r.a3).toUpperCase(), name: name, official: text(r.official),
    "native": strings(r["native"]), capitals: strings(r.capitals),
    capitalAt: number(at.lat) !== null && number(at.lng) !== null ? { lat: at.lat, lng: at.lng } : null,
    region: text(r.region), subregion: text(r.subregion),
    population: pop !== null && pop >= 0 ? Math.round(pop) : null,
    area: km2 !== null && km2 > 0 ? km2 : null,
    lat: number(r.lat), lng: number(r.lng),
    languages: strings(r.languages), currencies: currencies,
    calling: strings(r.calling), tlds: strings(r.tlds), timezones: strings(r.timezones),
    borders: strings(r.borders), drives: r.drives === "left" || r.drives === "right" ? r.drives : "",
    landlocked: r.landlocked === true, sovereign: r.sovereign === true, un: r.un === true,
    memberships: strings(r.memberships), demonym: text(r.demonym), about: text(r.about),
    flagAbout: text(r.flagAbout), tint: hex(r.tint), weekStarts: text(r.weekStarts).toLowerCase()
  }
}

// Pages put together: one record per code, in alphabetical order by the name
// a person would look for.
function merge(pages) {
  var seen = {}
  var out = []
  for (var p = 0; p < pages.length; p++) {
    var list = pages[p] || []
    for (var i = 0; i < list.length; i++) {
      if (!list[i] || seen[list[i].code]) continue
      seen[list[i].code] = true
      out.push(list[i])
    }
  }
  return sorted(out, "name")
}

// --- looking things up ---------------------------------------------------

// { byCode, byA3, popRank, areaRank }: rank 1 is the most people, the most
// land. Records with no figure have no rank.
function index(list) {
  var byCode = {}
  var byA3 = {}
  for (var i = 0; i < list.length; i++) {
    byCode[list[i].code] = list[i]
    if (list[i].a3) byA3[list[i].a3] = list[i]
  }
  return { byCode: byCode, byA3: byA3,
           popRank: ranks(list, "population"), areaRank: ranks(list, "area") }
}

function ranks(list, field) {
  var have = list.filter(function (c) { return c[field] !== null && c[field] !== undefined })
  have.sort(function (a, b) { return b[field] - a[field] })
  var out = {}
  for (var i = 0; i < have.length; i++) out[have[i].code] = i + 1
  return out
}

// Accents off and lower case, so "cote" finds Côte d'Ivoire and "reyk" finds
// Reykjavík. The range is built rather than written, because this file is
// read by more than one tool and a literal combining mark is invisible.
var MARKS = new RegExp("[" + String.fromCharCode(0x300) + "-" + String.fromCharCode(0x36f) + "]", "g")
function fold(s) {
  return String(s || "").normalize("NFD").replace(MARKS, "").toLowerCase()
}

function matches(c, query) {
  var q = fold(query).trim()
  if (!q) return true
  if (q.length <= 3 && (c.code.toLowerCase() === q || c.a3.toLowerCase() === q)) return true
  var hay = [c.name, c.official].concat(c["native"], c.capitals)
  for (var i = 0; i < hay.length; i++) if (fold(hay[i]).indexOf(q) >= 0) return true
  return false
}

function sorted(list, by) {
  var out = list.slice()
  var byName = function (a, b) { return fold(a.name) < fold(b.name) ? -1 : fold(a.name) > fold(b.name) ? 1 : 0 }
  if (by === "population" || by === "area") {
    out.sort(function (a, b) {
      var x = a[by] === null ? -1 : a[by]
      var y = b[by] === null ? -1 : b[by]
      return y - x || byName(a, b)
    })
  } else {
    out.sort(byName)
  }
  return out
}

// The list a tab shows: one region or all of them, what was typed, in order.
function shown(list, region, query, by) {
  var out = []
  for (var i = 0; i < list.length; i++) {
    var c = list[i]
    if (region && region !== "all" && c.region !== region) continue
    if (!matches(c, query)) continue
    out.push(c)
  }
  return by === "name" ? out : sorted(out, by)
}

function regionsIn(list) {
  var have = {}
  for (var i = 0; i < list.length; i++) have[list[i].region] = (have[list[i].region] || 0) + 1
  return REGIONS.filter(function (r) { return have[r] > 0 })
}

function neighbours(c, idx) {
  if (!c) return []
  var out = []
  for (var i = 0; i < c.borders.length; i++) {
    var n = idx.byA3[c.borders[i]]
    if (n) out.push(n)
  }
  return sorted(out, "name")
}

// --- saying it -----------------------------------------------------------

function grouped(n) {
  if (n === null || n === undefined) return DASH
  var neg = n < 0
  var s = String(Math.round(Math.abs(n)))
  var out = ""
  while (s.length > 3) { out = "," + s.slice(-3) + out; s = s.slice(0, -3) }
  return (neg ? "-" : "") + s + out
}

// 83,491,249 as "83.5 M": the figure a person remembers. Under ten thousand
// the whole number is short enough.
function compact(n) {
  if (n === null || n === undefined) return DASH
  var a = Math.abs(n)
  var one = function (x) { var r = Math.round(x * 10) / 10; return r >= 100 ? String(Math.round(x)) : String(r) }
  if (a >= 1e9) return one(n / 1e9) + " B"
  if (a >= 1e6) return one(n / 1e6) + " M"
  if (a >= 1e4) return one(n / 1e3) + " K"
  return grouped(n)
}

function people(n) {
  if (n === null || n === undefined) return "Population not known"
  if (n === 0) return "No permanent population"
  return compact(n) + (n >= 1e4 ? "" : n === 1 ? " person" : " people")
}

function areaText(km2) {
  if (km2 === null || km2 === undefined) return DASH
  if (km2 < 10) return (Math.round(km2 * 100) / 100) + " km²"
  return grouped(km2) + " km²"
}

function density(c) {
  if (!c || !c.population || !c.area) return DASH
  var d = c.population / c.area
  return (d >= 10 ? grouped(d) : String(Math.round(d * 10) / 10)) + " per km²"
}

function degrees(lat, lng) {
  if (lat === null || lng === null || lat === undefined || lng === undefined) return ""
  var f = function (v, pos, neg) {
    var a = Math.abs(v)
    return (a >= 10 ? Math.round(a) : Math.round(a * 10) / 10) + "°" + (v >= 0 ? pos : neg)
  }
  return f(lat, "N", "S") + " " + f(lng, "E", "W")
}

function capital(c) {
  return c && c.capitals.length ? c.capitals[0] : ""
}

function currencyText(cur) {
  var s = cur.name || cur.code
  var extra = [cur.code, cur.symbol].filter(function (x) { return x && x !== s })
  return extra.length ? s + " (" + extra.join(", ") + ")" : s
}

function calling(c) {
  if (!c.calling.length) return ""
  return c.calling.slice(0, 3).map(function (x) { return "+" + x.replace(/^\+/, "") }).join(", ")
    + (c.calling.length > 3 ? " …" : "")
}

function zones(c) {
  var z = c.timezones
  if (!z.length) return ""
  if (z.length <= 2) return z.join(", ")
  return z[0] + " to " + z[z.length - 1] + " (" + z.length + " zones)"
}

function capitalise(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : "" }

// The card of facts on a country's page, in the order somebody asks them:
// only the ones that were sent.
function facts(c) {
  if (!c) return []
  var out = []
  var add = function (label, value) { if (value) out.push({ label: label, value: value }) }
  add(c.capitals.length > 1 ? "Capitals" : "Capital", c.capitals.join(", "))
  add(c.languages.length > 1 ? "Languages" : "Language", c.languages.join(", "))
  add(c.currencies.length > 1 ? "Currencies" : "Currency", c.currencies.map(currencyText).join(", "))
  add("Calling code", calling(c))
  add("Internet", c.tlds.join(", "))
  add("Time", zones(c))
  add("People are", c.demonym)
  add("Drives on the", c.drives)
  add("Week starts", capitalise(c.weekStarts))
  add("Centre", degrees(c.lat, c.lng))
  return out
}

// The words under a name in a list: its capital, or where it is.
function line(c) {
  return capital(c) || c.subregion || c.region
}

// Its place in the world, as tags: region first, then what it belongs to.
function tags(c) {
  if (!c) return []
  var out = []
  if (c.subregion) out.push(c.subregion)
  else if (c.region) out.push(c.region)
  if (c.un) out.push("UN")
  if (!c.sovereign) out.push("Territory")
  if (c.landlocked) out.push("Landlocked")
  return out.concat(c.memberships)
}

function freshness(seconds) {
  if (seconds < 60) return "just now"
  if (seconds < 3600) return Math.floor(seconds / 60) + " min ago"
  if (seconds < 86400) {
    var hours = Math.floor(seconds / 3600)
    return hours === 1 ? "1 hour ago" : hours + " hours ago"
  }
  var days = Math.floor(seconds / 86400)
  return days === 1 ? "yesterday" : days + " days ago"
}

// --- flags ---------------------------------------------------------------

function flagUrl(code, width) {
  return FLAGS + "w" + (width || 320) + "/" + String(code).toLowerCase() + ".png"
}

function flagFile(dir, code) {
  return dir + "/" + String(code).toLowerCase() + ".png"
}

// The codes whose flag is not on disk yet.
function missingFlags(list, have) {
  var out = []
  for (var i = 0; i < list.length; i++) if (!have[list[i].code]) out.push(list[i].code)
  return out
}

// One curl for all of them, eight at a time. A flag that fails is removed
// rather than left half-written, and asked for again next time.
function flagCommand(dir, codes) {
  var argv = ["curl", "-sS", "--fail", "--parallel", "--parallel-max", "8",
              "--max-time", "90", "--max-filesize", String(MAX_FLAG_BYTES),
              "--remove-on-error", "--create-dirs",
              "-H", "User-Agent: " + AGENT]
  for (var i = 0; i < codes.length; i++)
    argv.push("-o", flagFile(dir, codes[i]), flagUrl(codes[i], 320))
  return argv
}

// `ls -1` of the flags folder, as { "DE": true }. Only a whole name counts:
// a curl that died leaves nothing behind, and a stray file is not a flag.
function flagsIn(listing) {
  var have = {}
  var lines = String(listing || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].trim().match(/^([a-z]{2})\.png$/)
    if (m) have[m[1].toUpperCase()] = true
  }
  return have
}
