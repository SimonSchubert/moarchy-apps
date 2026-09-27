// Everything about CoinGecko that is not a request: where to ask, what to keep
// of the answer, and how to print a number. Pure functions. An ECMAScript
// module rather than a `.pragma library` script so the worker thread that
// shapes responses (Worker.mjs) imports the very same code the views do.
//
// Responses are copied field by field into plain objects rather than kept as
// parsed. A coin page is ~60 KB of JSON of which the app shows a few hundred
// bytes, and every string that reaches a Text item has passed through here.

export var BASE = "https://api.coingecko.com/api/v3"

// ------------------------------------------------------------ currencies

// Curated rather than /simple/supported_vs_currencies: sixty codes nobody
// scrolls through, and a symbol for each is the part that makes a price read.
export var CURRENCIES = [
  { code: "usd", symbol: "$", name: "US Dollar" },
  { code: "eur", symbol: "€", name: "Euro" },
  { code: "gbp", symbol: "£", name: "British Pound" },
  { code: "jpy", symbol: "¥", name: "Japanese Yen" },
  { code: "chf", symbol: "CHF ", name: "Swiss Franc" },
  { code: "cad", symbol: "CA$", name: "Canadian Dollar" },
  { code: "aud", symbol: "A$", name: "Australian Dollar" },
  { code: "cny", symbol: "CN¥", name: "Chinese Yuan" },
  { code: "inr", symbol: "₹", name: "Indian Rupee" },
  { code: "krw", symbol: "₩", name: "South Korean Won" },
  { code: "brl", symbol: "R$", name: "Brazilian Real" },
  { code: "sek", symbol: "kr ", name: "Swedish Krona" },
  { code: "btc", symbol: "₿", name: "Bitcoin" },
  { code: "eth", symbol: "Ξ", name: "Ether" },
  { code: "sats", symbol: "sats ", name: "Satoshi" }
]

export function currency(code) {
  for (var i = 0; i < CURRENCIES.length; i++)
    if (CURRENCIES[i].code === code) return CURRENCIES[i]
  return CURRENCIES[0]
}

export function validCurrency(code) {
  return currency(code).code === code
}

// ------------------------------------------------------------ endpoints

export function q(v) { return encodeURIComponent(String(v)) }

// A coin id is lowercase letters, digits and dashes. Anything else did not
// come from CoinGecko and does not go into a URL path.
export function safeId(id) {
  return /^[a-z0-9][a-z0-9-]{0,99}$/.test(String(id || "")) ? String(id) : ""
}

export function marketsUrl(cur, page, perPage, category) {
  var u = BASE + "/coins/markets?vs_currency=" + q(cur) + "&order=market_cap_desc&per_page=" + perPage
    + "&page=" + page + "&sparkline=true&price_change_percentage=1h%2C24h%2C7d"
  if (category) u += "&category=" + q(category)
  return u
}

export function idsUrl(cur, ids) {
  var clean = []
  for (var i = 0; i < ids.length; i++) if (safeId(ids[i])) clean.push(ids[i])
  clean.sort()   // one cache entry whatever order the list was starred in
  return BASE + "/coins/markets?vs_currency=" + q(cur) + "&ids=" + q(clean.join(","))
    + "&per_page=250&page=1&sparkline=true&price_change_percentage=1h%2C24h%2C7d"
}

export function globalUrl() { return BASE + "/global" }
export function trendingUrl() { return BASE + "/search/trending" }
export function categoriesUrl() { return BASE + "/coins/categories?order=market_cap_desc" }
export function searchUrl(query) { return BASE + "/search?query=" + q(query) }

export function coinUrl(id) {
  return BASE + "/coins/" + safeId(id) + "?localization=false&tickers=false&market_data=true"
    + "&community_data=false&developer_data=false&sparkline=false"
}

export function chartUrl(id, cur, days) {
  return BASE + "/coins/" + safeId(id) + "/market_chart?vs_currency=" + q(cur) + "&days=" + q(days)
}

// ------------------------------------------------------------ shaping

export function num(v) {
  if (v === null || v === undefined || v === "") return NaN
  var n = Number(v)
  return isFinite(n) ? n : NaN
}

export function str(v, max) {
  if (v === null || v === undefined) return ""
  var s = String(v).replace(/[\u0000-\u001f\u007f]/g, " ")
  return s.length > max ? s.slice(0, max) : s
}

// Only https pictures and pages. A logo URL is loaded by an Image, a link is
// handed to the browser; neither gets anything else.
export function httpsUrl(v) {
  var s = str(v, 400).trim()
  return /^https:\/\/[^\s"'<>]+$/i.test(s) ? s : ""
}

// A picture only from CoinGecko's own image hosts. Project-supplied data
// never picks the server a logo is downloaded from.
export function imageUrl(v) {
  var u = httpsUrl(v)
  return /^https:\/\/(coin-images|assets)\.coingecko\.com\//.test(u) ? u : ""
}

// Lists want the 50 px logo, not the 250 px one: a hundred rows of it.
export function smallImage(v) {
  return imageUrl(v).replace("/large/", "/small/")
}

// 168 hourly points is more than 120 px of sparkline can show; a quarter of
// them draws the same line for a quarter of the Canvas work per row.
export function thin(points, target) {
  if (!points || !points.length) return []
  var out = []
  var step = Math.max(1, Math.floor(points.length / target))
  for (var i = 0; i < points.length; i += step) {
    var n = num(points[i])
    if (!isNaN(n)) out.push(n)
  }
  var last = num(points[points.length - 1])
  if (!isNaN(last) && out[out.length - 1] !== last) out.push(last)
  return out
}

export function marketRow(c) {
  if (!c || !safeId(c.id)) return null
  var spark = c.sparkline_in_7d ? c.sparkline_in_7d.price : null
  return {
    id: c.id,
    symbol: str(c.symbol, 16).toUpperCase(),
    name: str(c.name, 64),
    image: smallImage(c.image),
    rank: num(c.market_cap_rank),
    price: num(c.current_price),
    mcap: num(c.market_cap),
    fdv: num(c.fully_diluted_valuation),
    vol: num(c.total_volume),
    high24: num(c.high_24h),
    low24: num(c.low_24h),
    ch1h: num(c.price_change_percentage_1h_in_currency),
    ch24: isNaN(num(c.price_change_percentage_24h_in_currency))
      ? num(c.price_change_percentage_24h) : num(c.price_change_percentage_24h_in_currency),
    ch7d: num(c.price_change_percentage_7d_in_currency),
    circ: num(c.circulating_supply),
    total: num(c.total_supply),
    max: num(c.max_supply),
    ath: num(c.ath),
    athChange: num(c.ath_change_percentage),
    athDate: str(c.ath_date, 40),
    atl: num(c.atl),
    atlChange: num(c.atl_change_percentage),
    atlDate: str(c.atl_date, 40),
    spark: thin(spark, 42)
  }
}

export function markets(json) {
  var out = []
  if (!Array.isArray(json)) return out
  for (var i = 0; i < json.length && i < 250; i++) {
    var r = marketRow(json[i])
    if (r) out.push(r)
  }
  return out
}

export function globalStats(json) {
  var d = json && json.data ? json.data : {}
  var mc = d.total_market_cap || {}
  var tv = d.total_volume || {}
  var pct = d.market_cap_percentage || {}
  var byCur = {}
  var byVol = {}
  for (var k in mc) if (/^[a-z]{3,4}$/.test(k)) byCur[k] = num(mc[k])
  for (var v in tv) if (/^[a-z]{3,4}$/.test(v)) byVol[v] = num(tv[v])
  return {
    mcap: byCur,
    vol: byVol,
    btc: num(pct.btc),
    eth: num(pct.eth),
    ch24: num(d.market_cap_change_percentage_24h_usd),
    coins: num(d.active_cryptocurrencies),
    exchanges: num(d.markets)
  }
}

export function trending(json) {
  var out = []
  var coins = json && Array.isArray(json.coins) ? json.coins : []
  for (var i = 0; i < coins.length && i < 30; i++) {
    var it = coins[i] ? coins[i].item : null
    if (!it || !safeId(it.id)) continue
    out.push({
      id: it.id,
      name: str(it.name, 64),
      symbol: str(it.symbol, 16).toUpperCase(),
      rank: num(it.market_cap_rank),
      image: imageUrl(it.small || it.thumb),
      score: num(it.score)
    })
  }
  return out
}

export function categories(json) {
  var out = []
  if (!Array.isArray(json)) return out
  for (var i = 0; i < json.length && i < 400; i++) {
    var c = json[i]
    if (!c || !/^[a-z0-9][a-z0-9-]{0,99}$/.test(String(c.id || ""))) continue
    var logos = []
    var top = Array.isArray(c.top_3_coins) ? c.top_3_coins : []
    for (var j = 0; j < top.length && j < 3; j++) {
      var u = imageUrl(top[j])
      if (u) logos.push(u)
    }
    out.push({
      id: c.id,
      name: str(c.name, 80),
      mcap: num(c.market_cap),
      ch24: num(c.market_cap_change_24h),
      vol: num(c.volume_24h),
      logos: logos
    })
  }
  return out
}

export function search(json) {
  var out = []
  var coins = json && Array.isArray(json.coins) ? json.coins : []
  for (var i = 0; i < coins.length && i < 40; i++) {
    var c = coins[i]
    if (!c || !safeId(c.id)) continue
    out.push({
      id: c.id,
      name: str(c.name, 64),
      symbol: str(c.symbol, 16).toUpperCase(),
      rank: num(c.market_cap_rank),
      // `large` is 250 px; its /small/ sibling is what a 30 px row needs.
      image: smallImage(c.large || c.thumb)
    })
  }
  return out
}

// Coin descriptions are HTML written by projects. Shown as plain text, so tags
// are dropped and the handful of entities that actually occur are decoded.
export function plainText(html, max) {
  var s = str(html, 20000)
  s = s.replace(/<br\s*\/?>/gi, "\n").replace(/<\/p>/gi, "\n\n").replace(/<[^>]*>/g, "")
  s = s.replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&quot;/g, "\"").replace(/&#39;/g, "'").replace(/&#(\d+);/g, function (m, d) {
      var n = Number(d)
      return n > 31 && n < 65536 ? String.fromCharCode(n) : ""
    })
  s = s.replace(/\r/g, "").replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim()
  return s.length > max ? s.slice(0, max).replace(/\s+\S*$/, "") + "…" : s
}

export function pick(obj, cur) {
  return obj && typeof obj === "object" ? num(obj[cur]) : NaN
}

export function coin(json, cur) {
  if (!json || !safeId(json.id)) return null
  var m = json.market_data || {}
  var links = json.links || {}
  var explorers = []
  var sites = Array.isArray(links.blockchain_site) ? links.blockchain_site : []
  for (var i = 0; i < sites.length && explorers.length < 2; i++) {
    var e = httpsUrl(sites[i])
    if (e) explorers.push(e)
  }
  // Plenty of project sites are still listed as plain http; the browser gets
  // the https address, which nearly all of them answer.
  var home = Array.isArray(links.homepage) ? httpsUrl(str(links.homepage[0], 400).replace(/^http:\/\//i, "https://")) : ""
  var repos = links.repos_url && Array.isArray(links.repos_url.github) ? links.repos_url.github : []
  var cats = []
  var rawCats = Array.isArray(json.categories) ? json.categories : []
  for (var k = 0; k < rawCats.length && cats.length < 6; k++) {
    var c = str(rawCats[k], 48)
    if (c) cats.push(c)
  }
  var image = json.image || {}
  return {
    id: json.id,
    name: str(json.name, 64),
    symbol: str(json.symbol, 16).toUpperCase(),
    image: imageUrl(image.small || image.large),
    rank: num(json.market_cap_rank),
    price: pick(m.current_price, cur),
    mcap: pick(m.market_cap, cur),
    fdv: pick(m.fully_diluted_valuation, cur),
    vol: pick(m.total_volume, cur),
    high24: pick(m.high_24h, cur),
    low24: pick(m.low_24h, cur),
    ch1h: pick(m.price_change_percentage_1h_in_currency, cur),
    ch24: pick(m.price_change_percentage_24h_in_currency, cur),
    ch7d: pick(m.price_change_percentage_7d_in_currency, cur),
    ch30d: pick(m.price_change_percentage_30d_in_currency, cur),
    ch1y: pick(m.price_change_percentage_1y_in_currency, cur),
    circ: num(m.circulating_supply),
    total: num(m.total_supply),
    max: num(m.max_supply),
    ath: pick(m.ath, cur),
    athChange: pick(m.ath_change_percentage, cur),
    athDate: m.ath_date ? str(m.ath_date[cur], 40) : "",
    atl: pick(m.atl, cur),
    atlChange: pick(m.atl_change_percentage, cur),
    atlDate: m.atl_date ? str(m.atl_date[cur], 40) : "",
    about: plainText(json.description ? json.description.en : "", 4000),
    categories: cats,
    genesis: str(json.genesis_date, 20),
    algorithm: str(json.hashing_algorithm, 40),
    sentimentUp: num(json.sentiment_votes_up_percentage),
    watchers: num(json.watchlist_portfolio_users),
    homepage: home,
    explorers: explorers,
    github: repos.length ? httpsUrl(repos[0]) : "",
    reddit: httpsUrl(links.subreddit_url)
  }
}

// A year of daily points or a day of five-minute ones: about 300 either way,
// which is more than a chart this wide has pixels for.
export function chart(json) {
  var raw = json && Array.isArray(json.prices) ? json.prices : []
  var step = Math.max(1, Math.floor(raw.length / 360))
  var out = []
  for (var i = 0; i < raw.length; i += step) {
    var p = raw[i]
    if (!Array.isArray(p)) continue
    var t = num(p[0]), v = num(p[1])
    if (!isNaN(t) && !isNaN(v)) out.push([t, v])
  }
  var last = raw.length ? raw[raw.length - 1] : null
  if (Array.isArray(last) && out.length && out[out.length - 1][0] !== num(last[0]) && !isNaN(num(last[1])))
    out.push([num(last[0]), num(last[1])])
  return out
}

export function shape(kind, json, cur) {
  switch (kind) {
  case "markets": return markets(json)
  case "global": return globalStats(json)
  case "trending": return trending(json)
  case "categories": return categories(json)
  case "search": return search(json)
  case "coin": return coin(json, cur)
  case "chart": return chart(json)
  }
  return null
}

// ------------------------------------------------------------ formatting

export var DASH = "—"

export function group(s) {
  var parts = s.split(".")
  parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",")
  return parts.join(".")
}

// Decimals follow the size of the number the way CoinGecko prints it: cents
// for dollars, four places under a dollar, and four significant figures for
// the coins that cost a millionth of a cent.
export function decimalsFor(a) {
  if (a === 0) return 2
  if (a >= 1) return 2
  if (a >= 0.01) return 4
  return Math.min(12, Math.ceil(-Math.log(a) / Math.LN10) + 3)
}

export function plain(v, decimals) {
  if (isNaN(v)) return DASH
  var a = Math.abs(v)
  var d = decimals === undefined ? decimalsFor(a) : decimals
  var s = group(a.toFixed(d))
  if (d > 2 && a < 1) s = s.replace(/0+$/, "").replace(/\.$/, ".00")
  return (v < 0 ? "-" : "") + s
}

export function price(v, cur) {
  if (isNaN(v)) return DASH
  var c = currency(cur)
  if (c.code === "sats") return plain(v, v >= 100 ? 0 : 2) + " sats"
  return (v < 0 ? "-" : "") + c.symbol + plain(Math.abs(v))
}

export function compact(v) {
  if (isNaN(v)) return DASH
  var a = Math.abs(v)
  var s
  if (a >= 1e12) s = (a / 1e12).toFixed(2) + "T"
  else if (a >= 1e9) s = (a / 1e9).toFixed(2) + "B"
  else if (a >= 1e6) s = (a / 1e6).toFixed(2) + "M"
  else if (a >= 1e4) s = (a / 1e3).toFixed(1) + "K"
  else s = plain(a, a >= 100 ? 0 : 2)
  return (v < 0 ? "-" : "") + s
}

export function money(v, cur) {
  if (isNaN(v)) return DASH
  var c = currency(cur)
  if (c.code === "sats") return compact(v) + " sats"
  return (v < 0 ? "-" : "") + c.symbol + compact(Math.abs(v))
}

export function percent(v, digits) {
  if (isNaN(v)) return DASH
  var d = digits === undefined ? (Math.abs(v) >= 1000 ? 0 : 1) : digits
  var s = group(Math.abs(v).toFixed(d))
  if (Number(s.replace(/,/g, "")) === 0) return s + "%"
  return (v > 0 ? "+" : "−") + s + "%"
}

// The size of a change without its sign, for places that draw the direction.
export function magnitude(v, digits) {
  if (isNaN(v)) return DASH
  var a = Math.abs(v)
  var d = digits === undefined ? (a >= 1000 ? 0 : 1) : digits
  return group(a.toFixed(d)) + "%"
}

export function supply(v, symbol) {
  if (isNaN(v) || v <= 0) return "∞"
  return compact(v) + (symbol ? " " + symbol : "")
}

export var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

export function date(iso) {
  var d = new Date(iso)
  if (isNaN(d.getTime())) return DASH
  return MONTHS[d.getMonth()] + " " + d.getDate() + ", " + d.getFullYear()
}

export function ago(iso) {
  var d = new Date(iso)
  if (isNaN(d.getTime())) return ""
  var days = Math.floor((Date.now() - d.getTime()) / 86400000)
  if (days < 1) return "today"
  if (days < 45) return days + " days ago"
  if (days < 540) return Math.round(days / 30.4) + " months ago"
  return (days / 365.25).toFixed(1).replace(/\.0$/, "") + " years ago"
}

// Chart axis and crosshair: the range decides the precision.
export function stamp(ms, days) {
  var d = new Date(ms)
  var hh = ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2)
  if (days === "1") return hh
  if (days === "7") return MONTHS[d.getMonth()] + " " + d.getDate() + ", " + hh
  return MONTHS[d.getMonth()] + " " + d.getDate() + ", " + d.getFullYear()
}

export function isoDay(ms) {
  var d = new Date(ms)
  return d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2) + "-" + ("0" + d.getDate()).slice(-2)
}

// A number typed by a person: "1,234.5", "0,5" and " 2 " all mean something.
export function parseAmount(text) {
  var s = String(text || "").trim().replace(/\s/g, "")
  if (!s) return NaN
  if (s.indexOf(",") >= 0 && s.indexOf(".") < 0 && /,\d{1,2}$|,\d{4,}$/.test(s)) s = s.replace(",", ".")
  s = s.replace(/,/g, "")
  if (!/^\d*\.?\d+$|^\d+\.$/.test(s)) return NaN
  return Number(s)
}

export function editable(v) {
  if (isNaN(v)) return ""
  var d = decimalsFor(Math.abs(v))
  var s = Math.abs(v) >= 1 ? v.toFixed(2) : v.toFixed(Math.max(d, 4))
  if (s.indexOf(".") >= 0) s = s.replace(/0+$/, "").replace(/\.$/, "")
  return s
}

// ------------------------------------------------------------ portfolio

// Average-cost bookkeeping per coin. Transactions are kept in the currency
// they were typed in; the ones in another currency still count toward the
// amount held, but not toward cost, since yesterday's euros are not today's
// dollars.
export function position(txs, cur) {
  var qty = 0, boughtQty = 0, boughtCost = 0, realized = 0, foreign = 0
  var list = (txs || []).slice().sort(function (a, b) { return a.ts - b.ts })
  for (var i = 0; i < list.length; i++) {
    var t = list[i]
    var amt = num(t.amount), px = num(t.price)
    if (isNaN(amt) || amt <= 0) continue
    var same = t.cur === cur && !isNaN(px)
    if (!same) foreign++
    if (t.side === "sell") {
      var avg = boughtQty > 0 ? boughtCost / boughtQty : NaN
      if (same && !isNaN(avg)) realized += amt * (px - avg)
      if (boughtQty > 0) {
        var sold = Math.min(amt, boughtQty)
        boughtCost -= (boughtCost / boughtQty) * sold
        boughtQty -= sold
      }
      qty -= amt
    } else {
      if (same) { boughtQty += amt; boughtCost += amt * px }
      qty += amt
    }
  }
  qty = Math.max(0, qty)
  return {
    qty: qty,
    avg: boughtQty > 0 ? boughtCost / boughtQty : NaN,
    cost: boughtQty > 0 ? (boughtCost / boughtQty) * qty : NaN,
    realized: realized,
    foreign: foreign
  }
}
