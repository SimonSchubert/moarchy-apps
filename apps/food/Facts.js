// Open Food Facts: one barcode in, one product out.
//
// Ported from 0.1.0's facts.py, rule for rule, and tested with its cases:
// parsing somebody else's JSON and turning a grade into the letter a person
// reads is the half of this app that can be wrong, so it is kept apart from
// anything that draws.
//
// **The endpoint is /api/v2/product/{code}, once, for the barcode just
// scanned.** One request returns the name, the scores, the nutrients and the
// allergens -- every fact this app draws. It goes through curl, as Launches'
// does, so the timeout, the size cap and the User-Agent are curl's flags
// rather than something QML's XMLHttpRequest cannot promise.
//
// **No API key.** Open Food Facts asks only that the User-Agent name the app.
// A 429 is an ordinary answer: `retry` says how long to wait.
//
// **Every field is optional.** A product with no Nutri-Score, no photo and no
// ingredients is still a product: the barcode was on a shelf.
.pragma library

var API = "https://world.openfoodfacts.org/api/v2/product/"
var AGENT = "moarchy-food/0.2.0 (+https://github.com/SimonSchubert/moarchy-apps)"

// Twelve seconds: a phone on a cell connection is slow rather than absent.
var TIMEOUT = 12
// A product record is tens of kilobytes with the fields asked for; four
// megabytes is a body that has gone wrong.
var MAX_BYTES = 4 * 1024 * 1024
// A front-of-pack JPEG is a few tens of kilobytes.
var MAX_IMAGE_BYTES = 512 * 1024
// What a 429 costs when the answer did not say how long to wait.
var RATE_LIMIT_S = 60

var FIELDS = ["code", "product_name", "product_name_en", "brands", "quantity",
  "nutriscore_grade", "nova_group", "ecoscore_grade", "allergens_tags",
  "traces_tags", "ingredients_text", "ingredients_text_en", "nutriments",
  "image_front_small_url", "additives_n"]

// Nutri-Score and Eco-Score share the same five letters.
var GRADES = ["a", "b", "c", "d", "e"]

var NOVA_LABELS = { 1: "Unprocessed", 2: "Ingredients", 3: "Processed", 4: "Ultra-processed" }

// Per 100 g, in the order a nutrition table is read.
var NUTRIENTS = [
  ["energy-kcal_100g", "Energy", "kcal"],
  ["fat_100g", "Fat", "g"],
  ["saturated-fat_100g", "Saturates", "g"],
  ["carbohydrates_100g", "Carbohydrates", "g"],
  ["sugars_100g", "Sugars", "g"],
  ["fiber_100g", "Fibre", "g"],
  ["proteins_100g", "Protein", "g"],
  ["salt_100g", "Salt", "g"]
]

// zbar's names for the codes a packet of food carries. QR is a URL more
// often than a barcode, and this app has nowhere to put a URL.
var PRODUCT_KINDS = ["EAN-13", "EAN-8", "EAN13", "EAN8", "UPC-A", "UPC-E",
  "UPCA", "UPCE", "ISBN-13", "ISBN-10"]

var DASH = "—"

// --- reading ------------------------------------------------------------

function number(value) {
  if (typeof value !== "number" || !isFinite(value)) return null
  return value
}

function grade(value) {
  if (typeof value !== "string") return ""
  var letter = value.trim().toLowerCase()
  return GRADES.indexOf(letter) >= 0 ? letter : ""
}

// `en:milk` becomes `Milk`.
function tagLabel(tag) {
  if (typeof tag !== "string" || !tag) return ""
  var i = tag.indexOf(":")
  var name = (i >= 0 ? tag.slice(i + 1) : tag).replace(/-/g, " ").trim()
  return name ? name.charAt(0).toUpperCase() + name.slice(1) : ""
}

function firstBrand(value) {
  if (typeof value !== "string") return ""
  return value.split(",")[0].trim()
}

function text() {
  for (var i = 0; i < arguments.length; i++) {
    var v = arguments[i]
    if (typeof v === "string" && v.trim()) return v.trim()
  }
  return ""
}

function nova(value) {
  return typeof value === "number" && Math.floor(value) === value && value >= 1 && value <= 4 ? value : null
}

function error(message, extra) {
  var e = { message: message, missing: false, retry: 0 }
  for (var k in extra) e[k] = extra[k]
  return e
}

// One product out of Open Food Facts' shape: { product } or { error }.
// `status` 0 is a missing product, not a malformed one: the barcode was read
// correctly and the catalogue has no row for it.
function parse(payload, scanned) {
  if (!payload || typeof payload !== "object" || payload.constructor === Array)
    return { error: error("Open Food Facts sent something that is not a product.") }
  if (payload.status === 0) {
    var missingCode = String(payload.code || scanned || "")
    return { error: error(missingCode ? "Nothing in Open Food Facts for " + missingCode + "."
                                      : "Nothing in Open Food Facts for this barcode.", { missing: true }) }
  }
  var record = payload.product
  if (!record || typeof record !== "object" || record.constructor === Array)
    return { error: error("Open Food Facts sent a product in a shape this app cannot read.") }
  var code = String(record.code || payload.code || scanned || "")
  var name = text(record.product_name_en, record.product_name)
  if (!code || !name) return { error: error("Open Food Facts sent a product with no name.") }
  var nutrients = []
  var n = record.nutriments
  if (n && typeof n === "object") {
    for (var i = 0; i < NUTRIENTS.length; i++) {
      var v = number(n[NUTRIENTS[i][0]])
      if (v === null) continue
      nutrients.push({ key: NUTRIENTS[i][0], label: NUTRIENTS[i][1], value: v, unit: NUTRIENTS[i][2] })
    }
  }
  var allergens = []
  if (record.allergens_tags && record.allergens_tags.constructor === Array) {
    for (var j = 0; j < record.allergens_tags.length; j++) {
      var label = tagLabel(record.allergens_tags[j])
      if (label && allergens.indexOf(label) < 0) allergens.push(label)
    }
  }
  var additives = number(record.additives_n)
  var image = record.image_front_small_url || record.image_url || ""
  return { product: {
    code: code,
    name: name,
    brand: firstBrand(record.brands),
    quantity: text(record.quantity),
    nutriscore: grade(record.nutriscore_grade),
    nova: nova(record.nova_group),
    ecoscore: grade(record.ecoscore_grade),
    allergens: allergens,
    ingredients: text(record.ingredients_text_en, record.ingredients_text),
    nutrients: nutrients,
    image_url: typeof image === "string" ? image : "",
    additives: additives !== null && additives >= 0 ? Math.floor(additives) : null
  } }
}

// One product back out of our own cache file, or null. Separate from parse on
// purpose: that reads Open Food Facts' shape and this reads ours.
function fromDict(data) {
  if (!data || typeof data !== "object" || data.constructor === Array) return null
  var code = String(data.code || "")
  var name = String(data.name || "")
  if (!code || !name) return null
  var nutrients = []
  if (data.nutrients && data.nutrients.constructor === Array) {
    for (var i = 0; i < data.nutrients.length; i++) {
      var row = data.nutrients[i]
      if (!row || typeof row !== "object") continue
      var v = number(row.value)
      if (v === null) continue
      nutrients.push({ key: String(row.key || ""), label: String(row.label || ""), value: v, unit: String(row.unit || "g") })
    }
  }
  var allergens = []
  if (data.allergens && data.allergens.constructor === Array)
    for (var j = 0; j < data.allergens.length; j++) if (data.allergens[j]) allergens.push(String(data.allergens[j]))
  var additives = data.additives
  return {
    code: code,
    name: name,
    brand: String(data.brand || ""),
    quantity: String(data.quantity || ""),
    nutriscore: grade(data.nutriscore),
    nova: nova(data.nova),
    ecoscore: grade(data.ecoscore),
    allergens: allergens,
    ingredients: String(data.ingredients || ""),
    nutrients: nutrients,
    image_url: String(data.image_url || ""),
    additives: typeof additives === "number" && Math.floor(additives) === additives && additives >= 0 ? additives : null
  }
}

// Our cache file's shape, which is 0.1.0's Product.to_dict().
function toDict(p) {
  return {
    code: p.code, name: p.name, brand: p.brand, quantity: p.quantity,
    nutriscore: p.nutriscore, nova: p.nova, ecoscore: p.ecoscore,
    allergens: p.allergens.slice(), ingredients: p.ingredients,
    nutrients: p.nutrients.map(function (n) { return { key: n.key, label: n.label, value: n.value, unit: n.unit } }),
    image_url: p.image_url, additives: p.additives
  }
}

// --- drawing ------------------------------------------------------------

// Python's round() rounds halves to even; the table has to agree with 0.1.0.
function pyround(x, places) {
  var m = Math.pow(10, places || 0)
  var y = x * m
  var r = Math.round(y)
  if (Math.abs(y - Math.trunc(y)) === 0.5 && r % 2 !== 0) r -= 1
  return r / m
}

function drawn(n) {
  if (n.unit === "kcal") return pyround(n.value, 0).toFixed(0) + " kcal"
  if (Math.abs(n.value - pyround(n.value, 0)) < 0.05) return pyround(n.value, 0).toFixed(0) + " g"
  if (n.value >= 1) return n.value.toFixed(1) + " g"
  return n.value.toFixed(2) + " g"
}

function subtitle(p) {
  return [p.brand, p.quantity].filter(function (s) { return !!s }).join(" · ")
}

function novaLabel(p) {
  if (p.nova === null || p.nova === undefined) return DASH
  return NOVA_LABELS[p.nova] || "NOVA " + p.nova
}

function freshness(seconds) {
  if (seconds < 60) return "just now"
  if (seconds < 3600) return Math.floor(seconds / 60) + " min ago"
  if (seconds < 86400) {
    var h = Math.floor(seconds / 3600)
    return h === 1 ? "1 hour ago" : h + " hours ago"
  }
  var d = Math.floor(seconds / 86400)
  return d === 1 ? "yesterday" : d + " days ago"
}

// --- barcodes -----------------------------------------------------------

// The check digit for an EAN/UPC body: from the right, ×3 then ×1.
function checksum(digits) {
  var total = 0
  for (var i = 0; i < digits.length; i++) {
    var d = parseInt(digits.charAt(digits.length - 1 - i), 10)
    total += d * (i % 2 === 0 ? 3 : 1)
  }
  return (10 - (total % 10)) % 10
}

function digitsOf(s) { return String(s || "").replace(/[^0-9]/g, "") }

// UPC-E (7 or 8 digits) to a 12-digit UPC-A, or null.
function expandUpce(code) {
  var d = digitsOf(code)
  var ns, body, check
  if (d.length === 8) { ns = d.charAt(0); body = d.slice(1, 7); check = d.charAt(7) }
  else if (d.length === 7) { ns = "0"; body = d.slice(0, 6); check = d.charAt(6) }
  else return null
  if (ns !== "0" && ns !== "1") return null
  var last = body.charAt(5)
  var middle
  if ("012".indexOf(last) >= 0) middle = body.slice(0, 2) + last + "0000" + body.slice(2, 5)
  else if (last === "3") middle = body.slice(0, 3) + "00000" + body.slice(3, 5)
  else if (last === "4") middle = body.slice(0, 4) + "00000" + body.charAt(4)
  else middle = body.slice(0, 5) + "0000" + last
  var upca = ns + middle
  if (checksum(upca) !== parseInt(check, 10)) return null
  return upca + check
}

// A barcode Open Food Facts will accept, or null. UPC-A is padded to EAN-13;
// a code whose check digit is wrong is not sent -- the camera misread it.
function normalize(text) {
  var d = digitsOf(text)
  if (!d) return null
  if (d.length === 8) {
    if (checksum(d.slice(0, 7)) === parseInt(d.charAt(7), 10)) return d
    var e8 = expandUpce(d)
    return e8 ? "0" + e8 : null
  }
  if (d.length === 12) return checksum(d.slice(0, 11)) === parseInt(d.charAt(11), 10) ? "0" + d : null
  if (d.length === 13) return checksum(d.slice(0, 12)) === parseInt(d.charAt(12), 10) ? d : null
  if (d.length === 7) {
    var e7 = expandUpce(d)
    return e7 ? "0" + e7 : null
  }
  return null
}

// A product barcode out of one zbar message, or null. An empty kind with a
// plausible digit string is allowed; a kind we do not know -- a QR -- is not.
function fromScan(kind, symbol) {
  var family = String(kind || "").toUpperCase().replace(/_/g, "-")
  if (family) {
    var known = false
    for (var i = 0; i < PRODUCT_KINDS.length; i++) {
      var k = PRODUCT_KINDS[i]
      if (family === k || family === k.replace(/-/g, "") || family.replace(/-/g, "") === k.replace(/-/g, "")) known = true
    }
    if (!known) return null
  }
  return normalize(symbol)
}

// --- the wire -----------------------------------------------------------

function url(code) {
  return API + encodeURIComponent(code) + "?fields=" + encodeURIComponent(FIELDS.join(","))
}

// curl for one product. The status is the last line (-w), the headers go
// to stderr (-D) for a Retry-After.
function command(code) {
  return ["curl", "-sS", "--max-time", String(TIMEOUT), "--max-filesize", String(MAX_BYTES),
          "-H", "User-Agent: " + AGENT, "-H", "Accept: application/json",
          "-D", "/dev/stderr", "-w", "\n%{http_code}", url(code)]
}

// curl for the front-of-pack thumbnail, straight to a file.
function imageCommand(imageUrl, path) {
  return ["curl", "-sS", "-f", "--max-time", String(TIMEOUT), "--max-filesize", String(MAX_IMAGE_BYTES),
          "-H", "User-Agent: " + AGENT, "-o", path, imageUrl]
}

function httpImage(u) { return /^https?:\/\//.test(String(u || "")) }

// What one fetch came to: { product } or { error: { message, missing, retry } }.
function answer(exitCode, output, headers, scanned) {
  if (exitCode === 63) return { error: error("Open Food Facts sent more than this app will read.") }
  if (exitCode !== 0) return { error: error("No answer from Open Food Facts.") }
  var t = String(output || "")
  var cut = t.lastIndexOf("\n")
  var status = cut >= 0 ? parseInt(t.slice(cut + 1).trim(), 10) : 0
  var body = cut >= 0 ? t.slice(0, cut) : t
  if (status === 404) return { error: error("Nothing in Open Food Facts for this barcode.", { missing: true }) }
  if (status === 429) {
    var m = String(headers || "").match(/^retry-after:\s*(\d+)\s*$/im)
    return { error: error("Open Food Facts is rate-limiting this connection.", { retry: m ? parseInt(m[1], 10) : RATE_LIMIT_S }) }
  }
  if (status >= 500 && status < 600) return { error: error("Open Food Facts is having trouble.") }
  if (status !== 200) return { error: error("Open Food Facts refused the request (" + status + ").") }
  if (body.length > MAX_BYTES) return { error: error("Open Food Facts sent more than this app will read.") }
  var payload
  try { payload = JSON.parse(body) } catch (e) {
    return { error: error("Open Food Facts sent something that is not JSON.") }
  }
  return parse(payload, scanned)
}
