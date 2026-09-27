// What survives the app being killed: the last products scanned. The two
// files 0.1.0 wrote, in its shapes, so an upgrade keeps its history.
//
// `history.json` is the barcodes in the order they were scanned -- the only
// thing in this app a person has made -- and is written the instant a lookup
// succeeds. `products.json` is the last answer for each, so a row in the
// history opens on facts in a shop with no signal, and scanning the same
// packet twice does not cost a second request.
//
// The facts are cached; what you ate is not. The whole of both files is
// public data plus a list of barcodes.
//
// Every function returns a new state and leaves its argument alone.
.pragma library

.import "Facts.js" as F

var SCHEMA = 1
// Nobody scans a hundred packets in a sitting; a history that says they did
// has been written by something other than this app.
var MAX_HISTORY = 100

function fresh() { return { history: [], products: ({}), fetched: ({}) } }

function parseHistory(data) {
  var out = []
  if (!data || typeof data !== "object" || !data.codes || data.codes.constructor !== Array) return out
  for (var i = 0; i < data.codes.length; i++) {
    var c = data.codes[i]
    if (typeof c === "string" && c && out.indexOf(c) < 0) out.push(c)
    if (out.length >= MAX_HISTORY) break
  }
  return out
}

// { products: {code: product}, fetched: {code: seconds} }
function parseProducts(data) {
  var out = { products: ({}), fetched: ({}) }
  if (!data || typeof data !== "object") return out
  var records = data.products
  if (!records || typeof records !== "object" || records.constructor === Array) return out
  var fetched = data.fetched && typeof data.fetched === "object" ? data.fetched : ({})
  for (var code in records) {
    var p = F.fromDict(records[code])
    if (!p) continue
    out.products[String(code)] = p
    var stamp = fetched[code]
    if (typeof stamp === "number" && isFinite(stamp) && stamp > 0) out.fetched[String(code)] = stamp
  }
  return out
}

function serializeHistory(state) {
  return JSON.stringify({ schema: SCHEMA, codes: state.history }, null, 1) + "\n"
}

function serializeProducts(state) {
  var products = ({})
  for (var code in state.products) products[code] = F.toDict(state.products[code])
  return JSON.stringify({ schema: SCHEMA, products: products, fetched: state.fetched }, null, 1) + "\n"
}

function copy(state) {
  return {
    history: state.history.slice(),
    products: Object.assign({}, state.products),
    fetched: Object.assign({}, state.fetched)
  }
}

// Put this product at the front of the history. A code already in the list
// is moved rather than duplicated, and cached products that fell off the end
// go with it, so the file cannot grow from a weekend of shopping.
function remember(state, product, when) {
  var out = copy(state)
  out.products[product.code] = product
  out.fetched[product.code] = when !== undefined ? when : Date.now() / 1000
  out.history = [product.code].concat(out.history.filter(function (c) { return c !== product.code }))
  out.history = out.history.slice(0, MAX_HISTORY)
  return prune(out)
}

// Out of the history, and out of the cache with it.
function forget(state, code) {
  var out = copy(state)
  out.history = out.history.filter(function (c) { return c !== code })
  return prune(out)
}

function prune(state) {
  var keep = ({})
  for (var i = 0; i < state.history.length; i++) keep[state.history[i]] = true
  var products = ({}), fetched = ({})
  for (var c in state.products) if (keep[c]) products[c] = state.products[c]
  for (var d in state.fetched) if (keep[d]) fetched[d] = state.fetched[d]
  state.products = products
  state.fetched = fetched
  return state
}

// The history as products, skipping any barcode whose cache is gone.
function recent(state) {
  var out = []
  for (var i = 0; i < state.history.length; i++) {
    var p = state.products[state.history[i]]
    if (p) out.push(p)
  }
  return out
}

// Rows whose name, brand or barcode contain the query.
function filter(products, query) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return products
  return products.filter(function (p) {
    return p.name.toLowerCase().indexOf(q) >= 0 || p.brand.toLowerCase().indexOf(q) >= 0 || p.code.indexOf(q) >= 0
  })
}
