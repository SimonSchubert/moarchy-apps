// The files: the world as REST Countries last described it, and the key that
// asks for it.
//
// `countries.json` is disposable by definition -- every byte of it can be
// fetched again -- and exists so the atlas opens on a plane, and so a month
// of browsing costs three requests. `account.json` is the one thing here a
// person typed. The quiz's record is Quiz.js's.
//
// Both are read as objects, because the kit's DataFile has already told an
// absent file from a broken one. What is left is a file edited by hand, which
// must not be able to put anything on screen that is not what the screen
// expects.
.pragma library

.import "Countries.js" as C

var SCHEMA = 1

function parseCache(data) {
  var out = { countries: [], fetched: 0 }
  if (!data || typeof data !== "object" || !Array.isArray(data.countries)) return out
  var list = []
  var seen = {}
  for (var i = 0; i < data.countries.length; i++) {
    var c = C.restore(data.countries[i])
    if (!c || seen[c.code]) continue
    seen[c.code] = true
    list.push(c)
  }
  out.countries = C.sorted(list, "name")
  out.fetched = typeof data.fetched === "number" && isFinite(data.fetched) && data.fetched > 0 ? data.fetched : 0
  return out
}

function serializeCache(countries, fetched) {
  return JSON.stringify({ schema: SCHEMA, fetched: fetched, countries: countries }) + "\n"
}

// A key is letters, digits, underscores and dashes; anything else -- a pasted
// line with the word "Bearer" in it, a trailing newline -- is tidied or
// refused, because it goes into a header.
function cleanKey(value) {
  var s = String(value || "").trim().replace(/^bearer\s+/i, "")
  return /^[A-Za-z0-9_\-]{8,200}$/.test(s) ? s : ""
}

function parseAccount(data) {
  return { key: data && typeof data === "object" ? cleanKey(data.key) : "" }
}

function serializeAccount(key) {
  return JSON.stringify({ schema: SCHEMA, key: cleanKey(key) }, null, 1) + "\n"
}

function age(fetched, nowSeconds) {
  return fetched > 0 ? Math.max(0, nowSeconds - fetched) : Infinity
}
