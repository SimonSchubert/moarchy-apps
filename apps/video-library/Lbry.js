// LBRY, as Odysee serves it to anybody: what to ask, and what the answer
// means to a person.
//
// Three public endpoints, none of them with a key:
//
//   the proxy    api.na-backend.odysee.com/api/v1/proxy -- the SDK's JSON-RPC,
//                claim_search and resolve, which is everything on the chain
//   Lighthouse   lighthouse.odysee.tv/search -- Odysee's own search, which
//                ranks far better than claim_search's `text` does; it answers
//                claim ids, which the proxy then fills in
//   the homepage odysee.com/$/api/content/v2/get -- the curated categories
//                on Odysee's front page, each a list of channels
//
// and two CDNs: player.odycdn.com for the stream itself (it wants a Referer),
// thumbnails.odycdn.com for an image at the size it is drawn.
//
// Nothing here touches QML, which keeps the half that can be wrong --
// somebody else's JSON -- apart from the screen that draws it.
.pragma library

var PROXY = "https://api.na-backend.odysee.com/api/v1/proxy"
var LIGHTHOUSE = "https://lighthouse.odysee.tv/search"
var HOMEPAGE = "https://odysee.com/$/api/content/v2/get?format=roku"
// The address Odysee's own `get` hands out. The older
// /api/v3/streams/free/<name>/<id>/<sd> form answers 429 at random.
var PLAYER = "https://player.odycdn.com/v6/streams/"
var IMAGES = "https://thumbnails.odycdn.com/card/"
var WEB = "https://odysee.com/"
var REFERER = "https://odysee.com/"
var AGENT = "moarchy-video-library/0.1.0 (+https://github.com/SimonSchubert/moarchy-apps)"
var TIMEOUT = 20
// The homepage is a megabyte and a half, every language's channel lists; a
// page of claims is a few hundred kilobytes. Eight megabytes is a body that
// has gone wrong.
var MAX_BYTES = 8 * 1024 * 1024
var PAGE = 24
// The homepage changes a few times a week.
var HOMEPAGE_TTL = 24 * 3600
var MAX_SAVED = 500
var MAX_HISTORY = 200
var MAX_FOLLOWS = 500
// Under a minute is a short, which Odysee keeps off its own front page.
var SHORT_S = 60

// Odysee's front page hides these; so does this app, everywhere it asks.
var NOT_TAGS = ["porn", "porno", "nsfw", "mature", "xxx", "sex", "creampie",
                "blowjob", "handjob", "vagina", "boobs", "big boobs", "big dick",
                "pussy", "cumshot", "anal", "hard fucking", "ass", "fuck", "hentai",
                "c:members-only", "c:unlisted", "c:private"]

// Categories that are not a feed of videos: a list of pinned posts, and the
// unfiltered firehose.
var SKIP_CATEGORIES = ["explore", "wildwest"]

// When the homepage cannot be had and was never saved: one category, the
// chain's own trending list.
var FALLBACK = [{ key: "trending", label: "Trending", channels: [], perChannel: 0, days: 7, order: "trending", excluded: [] }]

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

// --- asking ----------------------------------------------------------------

function curl(extra, target) {
  var argv = ["curl", "-sS", "--compressed", "--max-time", String(TIMEOUT),
              "--max-filesize", String(MAX_BYTES),
              "-H", "User-Agent: " + AGENT, "-H", "Accept: application/json"]
  for (var i = 0; i < extra.length; i++) argv.push(extra[i])
  argv.push("-w", "\n%{http_code}", target)
  return argv
}

// One JSON-RPC call to the proxy.
function rpc(method, params) {
  var body = JSON.stringify({ jsonrpc: "2.0", method: method, params: params, id: 1 })
  return curl(["-H", "Content-Type: application/json", "--data-binary", body], PROXY)
}

function get(url) { return curl([], url) }

function homepage() { return get(HOMEPAGE) }

function lighthouse(text, kind, page) {
  var q = "?s=" + encodeURIComponent(text) + "&size=" + PAGE + "&from=" + (Math.max(0, page - 1) * PAGE)
    + "&nsfw=false"
  q += kind === "channels" ? "&claimType=channel" : "&claimType=file&mediaType=video,audio&free_only=true"
  return get(LIGHTHOUSE + q)
}

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
function answer(exitCode, output, who) {
  who = who || "Odysee"
  if (exitCode === 63) return { data: null, error: who + " sent more than this app will read." }
  if (exitCode === 28) return { data: null, error: who + " took too long to answer." }
  if (exitCode !== 0) return { data: null, error: "No answer from " + who + "." }
  var got = split(output)
  if (got.status === 429) return { data: null, error: who + " is rate-limiting this connection." }
  if (got.status >= 500) return { data: null, error: who + " is having trouble." }
  if (got.status !== 200) return { data: null, error: who + " refused the request (" + got.status + ")." }
  var data
  try { data = JSON.parse(got.body) } catch (e) { return { data: null, error: who + " sent something that is not JSON." } }
  return { data: data, error: "" }
}

// A JSON-RPC answer: its result, or its error said plainly.
function result(exitCode, output) {
  var got = answer(exitCode, output, "Odysee")
  if (got.error) return got
  var d = got.data
  if (!d || typeof d !== "object") return { data: null, error: "Odysee sent an empty answer." }
  if (d.error) return { data: null, error: "Odysee: " + text(d.error.message || d.error) }
  return { data: d.result, error: "" }
}

// --- the questions -----------------------------------------------------------

function base(page, size) {
  return {
    page: page || 1,
    page_size: size || PAGE,
    claim_type: ["stream"],
    has_source: true,
    no_totals: true,
    not_tags: NOT_TAGS
  }
}

// A category of the front page, a page at a time: its channels' videos from
// the last `days`, most talked-about first, at most `perChannel` each, and no
// shorts or paid ones.
function feed(cat, page, nowSec) {
  var p = base(page)
  p.stream_types = ["video"]
  p.fee_amount = "<=0"
  p.duration = ">" + SHORT_S
  p.release_time = ">" + Math.floor(nowSec - (cat.days || 30) * 86400)
  p.order_by = cat.order === "new" ? ["release_time"] : ["trending_group", "trending_mixed"]
  if (cat.channels && cat.channels.length) p.channel_ids = cat.channels
  if (cat.excluded && cat.excluded.length) p.not_channel_ids = cat.excluded
  if (cat.perChannel > 0) p.limit_claims_per_channel = cat.perChannel
  return p
}

// Everything a set of channels put up, newest first.
function uploads(channelIds, page) {
  var p = base(page)
  p.stream_types = ["video", "audio"]
  p.channel_ids = channelIds
  p.order_by = ["release_time"]
  return p
}

// The claims Lighthouse named, in full.
function claims(ids, kind) {
  var p = { claim_ids: ids, page_size: Math.max(1, ids.length), no_totals: true }
  p.claim_type = kind === "channels" ? ["channel"] : ["stream"]
  return p
}

// The ids out of a Lighthouse answer, in its order, which is the ranking.
function hits(data) {
  var out = []
  if (!Array.isArray(data)) return out
  for (var i = 0; i < data.length; i++) {
    var id = text(data[i] && data[i].claimId)
    if (/^[0-9a-f]{40}$/.test(id) && out.indexOf(id) < 0) out.push(id)
  }
  return out
}

// claim_search answers in its own order; Lighthouse's is the one wanted.
function inOrder(list, ids) {
  var by = {}
  for (var i = 0; i < list.length; i++) by[list[i].id] = list[i]
  var out = []
  for (var j = 0; j < ids.length; j++) if (by[ids[j]]) out.push(by[ids[j]])
  return out
}

// --- the homepage ------------------------------------------------------------

// The categories for one language (English when it has none of its own), as
// the handful of fields a feed needs. Odysee's `hideByDefault` ones go last.
function categories(data, lang) {
  var all = data && data.data
  if (!all || typeof all !== "object") return []
  var byLang = all[lang] || all[String(lang || "").split("-")[0]] || all.en
  var list = byLang && byLang.categories
  if (!Array.isArray(list)) return []
  var shown = [], hidden = []
  for (var i = 0; i < list.length; i++) {
    var c = list[i]
    if (!c || typeof c !== "object") continue
    var key = text(c.name)
    if (!key || SKIP_CATEGORIES.indexOf(key) >= 0) continue
    var channels = ids(c.channelIds)
    if (!channels.length) continue
    var cat = {
      key: key,
      label: text(c.label) || key,
      channels: channels,
      perChannel: Math.max(0, parseInt(c.channelLimit, 10) || 0),
      days: Math.max(1, Math.min(365, number(c.daysOfContent) || 30)),
      order: text(c.order) === "new" ? "new" : "trending",
      excluded: ids(c.excludedChannelIds),
      sort: number(c.sortOrder) || 0
    }
    if (c.hideByDefault) hidden.push(cat)
    else shown.push(cat)
  }
  function bySort(a, b) { return a.sort - b.sort }
  shown.sort(bySort)
  hidden.sort(bySort)
  return shown.concat(hidden)
}

function ids(list) {
  var out = []
  if (!Array.isArray(list)) return out
  for (var i = 0; i < list.length; i++) if (/^[0-9a-f]{40}$/.test(list[i])) out.push(list[i])
  return out
}

// --- reading a claim -----------------------------------------------------------

function text(value) {
  return typeof value === "string" ? value.trim() : ""
}

// What an uploader wrote is Markdown, which a Text draws as its punctuation:
// the words, with a link's address after its text and no pictures.
function plain(md) {
  var s = text(md)
  if (!s) return ""
  s = s.replace(/!\[[^\]]*\]\([^)]*\)/g, "")
  s = s.replace(/\[([^\]]+)\]\(([^)\s]+)[^)]*\)/g, function (m, label, href) {
    return label === href ? href : label + " (" + href + ")"
  })
  s = s.replace(/^#{1,6}[ \t]+/gm, "")
  s = s.replace(/\*\*([^*\n]+)\*\*/g, "$1").replace(/__([^_\n]+)__/g, "$1")
  s = s.replace(/^[ \t]*[-*_]{3,}[ \t]*$/gm, "")
  s = s.replace(/[ \t]+$/gm, "").replace(/\n{3,}/g, "\n\n")
  return s.trim()
}

function number(value) {
  if (typeof value === "number" && isFinite(value)) return value
  if (typeof value === "string" && /^\d+(\.\d+)?$/.test(value.trim())) return parseFloat(value)
  return 0
}

function url(obj) {
  var u = obj && typeof obj === "object" ? text(obj.url) : ""
  return /^https?:\/\//.test(u) ? u : ""
}

// A channel claim as this app keeps it -- also what follows.json holds.
function channel(claim) {
  if (!claim || typeof claim !== "object" || claim.value_type !== "channel") return null
  var v = claim.value || {}
  var id = text(claim.claim_id)
  if (!id) return null
  return {
    id: id,
    name: text(claim.name),
    title: text(v.title) || text(claim.name),
    thumb: url(v.thumbnail),
    cover: url(v.cover),
    description: plain(v.description),
    count: claim.meta ? number(claim.meta.claims_in_channel) : 0,
    url: text(claim.canonical_url) || text(claim.permanent_url)
  }
}

// A stream claim as a video (or a recording) somebody can play, or null for
// anything else: a post, an image, a repost, a claim with no file behind it.
function video(claim) {
  if (!claim || typeof claim !== "object") return null
  if (claim.value_type === "repost" && claim.reposted_claim) return video(claim.reposted_claim)
  if (claim.value_type !== "stream") return null
  var v = claim.value || {}
  var kind = text(v.stream_type)
  if (kind !== "video" && kind !== "audio") return null
  var src = v.source || {}
  var sd = text(src.sd_hash)
  var id = text(claim.claim_id)
  if (!id || !sd) return null
  var media = v.video || v.audio || {}
  var tags = []
  var hasMembers = false
  if (Array.isArray(v.tags)) {
    for (var i = 0; i < v.tags.length; i++) {
      var t = text(v.tags[i])
      if (t === "c:members-only") hasMembers = true
      if (t && t.indexOf("c:") !== 0 && tags.indexOf(t) < 0 && tags.length < 16) tags.push(t)
    }
  }
  var released = number(v.release_time) || (claim.meta ? number(claim.meta.creation_timestamp) : 0) || number(claim.timestamp)
  return {
    id: id,
    name: text(claim.name),
    title: text(v.title) || text(claim.name),
    description: plain(v.description),
    thumb: url(v.thumbnail),
    kind: kind,
    media: text(src.media_type),
    size: number(src.size),
    duration: number(media.duration),
    width: v.video ? number(v.video.width) : 0,
    height: v.video ? number(v.video.height) : 0,
    released: released,
    tags: tags,
    license: text(v.license),
    languages: Array.isArray(v.languages) ? v.languages.filter(function (l) { return typeof l === "string" }) : [],
    sd: sd.slice(0, 6),
    url: text(claim.canonical_url) || text(claim.permanent_url),
    paid: !!(v.fee && number(v.fee.amount) > 0),
    members: hasMembers,
    channel: channel(claim.signing_channel)
  }
}

// Every video in a claim_search answer, once each.
function videos(data) {
  var out = []
  var seen = {}
  var items = data && Array.isArray(data.items) ? data.items : []
  for (var i = 0; i < items.length; i++) {
    var item = video(items[i])
    if (item && !seen[item.id]) { seen[item.id] = true; out.push(item) }
  }
  return out
}

function channels(data) {
  var out = []
  var items = data && Array.isArray(data.items) ? data.items : []
  for (var i = 0; i < items.length; i++) {
    var c = channel(items[i])
    if (c) out.push(c)
  }
  return out
}

// A list that grows by pages: the next page's rows, minus any the first
// already had -- a trending list moves while somebody scrolls it.
function append(list, more) {
  var have = {}
  for (var i = 0; i < list.length; i++) have[list[i].id] = true
  var out = list.slice()
  for (var j = 0; j < more.length; j++) if (!have[more[j].id]) { have[more[j].id] = true; out.push(more[j]) }
  return out
}

// --- where things are ---------------------------------------------------------

// Playable without an account: free, and not for a channel's members.
function playable(item) { return !!item && !item.paid && !item.members }

function stream(item) {
  if (!item) return ""
  return PLAYER + item.id + "/" + item.sd + ".mp4"
}

// Odysee transcodes most videos to HLS beside the original: a master list of
// 1080p, 720p, 360p and 144p. Qt's player decodes in software on a phone, so
// the size matters -- 720p is a core's worth on a Pixel 3a, 1080p60 more.
function master(item) {
  if (!item) return ""
  return PLAYER + item.id + "/" + item.sd + "/master.m3u8"
}

// The renditions in a master list, tallest first: { height, label, url }.
function variants(body, masterUrl) {
  var base = String(masterUrl || "").replace(/[^\/]*$/, "")
  var lines = String(body || "").split(/\r?\n/)
  if (!lines.length || lines[0].trim() !== "#EXTM3U") return []
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^#EXT-X-STREAM-INF:.*RESOLUTION=(\d+)x(\d+)/)
    if (!m) continue
    var uri = ""
    for (var j = i + 1; j < lines.length && !uri; j++) {
      var l = lines[j].trim()
      if (l && l.charAt(0) !== "#") uri = l
    }
    if (!uri) continue
    var h = Math.min(parseInt(m[1], 10), parseInt(m[2], 10))
    var abs = /^https?:\/\//.test(uri) ? uri : base + uri
    var seen = false
    for (var k = 0; k < out.length; k++) if (out[k].height === h) seen = true
    if (!seen) out.push({ height: h, label: h + "p", url: abs })
  }
  out.sort(function (a, b) { return b.height - a.height })
  return out
}

// The tallest rendition no taller than `want`, else the smallest there is.
function pick(list, want) {
  if (!list.length) return null
  for (var i = 0; i < list.length; i++) if (list[i].height <= want) return list[i]
  return list[list.length - 1]
}

// 1:02:03 for a position in milliseconds, as a player's clock shows it.
function clock(ms) {
  var s = Math.max(0, Math.floor(number(ms) / 1000))
  var h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), r = s % 60
  return h ? h + ":" + pad2(m) + ":" + pad2(r) : m + ":" + pad2(r)
}

// lbry://@chan#a/name#7 is https://odysee.com/@chan:a/name:7.
function web(lbryUrl) {
  var u = text(lbryUrl)
  if (u.indexOf("lbry://") !== 0) return WEB
  var parts = u.slice(7).split("/")
  for (var i = 0; i < parts.length; i++) {
    var hash = parts[i].indexOf("#")
    var name = hash >= 0 ? parts[i].slice(0, hash) : parts[i]
    var mod = hash >= 0 ? ":" + parts[i].slice(hash + 1) : ""
    parts[i] = encodeURIComponent(name).replace(/%40/g, "@") + mod
  }
  return WEB + parts.join("/")
}

// What somebody might paste: an Odysee link, an lbry:// URL, or @channel.
// The lbry:// URL to resolve, or "" when it is none of those.
function uri(input) {
  var s = text(input)
  if (!s) return ""
  var m = s.match(/^https?:\/\/(?:www\.)?odysee\.com\/(.+)$/i)
  if (m) {
    var path = m[1].split(/[?#]/)[0].replace(/\/+$/, "")
    if (!path || path.charAt(0) === "$") return ""
    var parts = path.split("/")
    for (var i = 0; i < parts.length; i++) {
      var seg
      try { seg = decodeURIComponent(parts[i]) } catch (e) { seg = parts[i] }
      parts[i] = seg.replace(/:/, "#")
    }
    return "lbry://" + parts.join("/")
  }
  if (/^lbry:\/\/\S+$/i.test(s)) return "lbry://" + s.slice(7)
  if (/^@[^\s/#:]+([#:][0-9a-f]+)?$/i.test(s)) return "lbry://" + s.replace(":", "#")
  return ""
}

// An image, at the size it is drawn (twice over, for a dense screen), as a
// JPEG: the originals are often megabytes, and sometimes WebP.
function image(src, w, h) {
  if (!src) return ""
  return IMAGES + "s:" + Math.round(w) + ":" + Math.round(h) + "/quality:85/plain/" + src
}

// --- what a person reads ------------------------------------------------------

function pad2(n) { return (n < 10 ? "0" : "") + n }

function duration(sec) {
  var s = Math.max(0, Math.round(number(sec)))
  if (!s) return ""
  var h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), r = s % 60
  return h ? h + ":" + pad2(m) + ":" + pad2(r) : m + ":" + pad2(r)
}

function ago(sec, nowSec) {
  if (!sec) return ""
  var d = Math.max(0, nowSec - sec)
  function say(n, unit) { return n + " " + unit + (n === 1 ? "" : "s") + " ago" }
  if (d < 60) return "just now"
  if (d < 3600) return say(Math.floor(d / 60), "minute")
  if (d < 86400) return say(Math.floor(d / 3600), "hour")
  if (d < 7 * 86400) return say(Math.floor(d / 86400), "day")
  if (d < 35 * 86400) return say(Math.floor(d / (7 * 86400)), "week")
  if (d < 365 * 86400) return say(Math.floor(d / (30 * 86400)), "month")
  return say(Math.floor(d / (365 * 86400)), "year")
}

function date(sec) {
  if (!sec) return ""
  var d = new Date(sec * 1000)
  return d.getUTCDate() + " " + MONTHS[d.getUTCMonth()] + " " + d.getUTCFullYear()
}

function size(bytes) {
  var b = number(bytes)
  if (!b) return ""
  if (b >= 1e9) return (b / 1e9).toFixed(b >= 1e10 ? 0 : 1) + " GB"
  if (b >= 1e6) return Math.round(b / 1e6) + " MB"
  return Math.max(1, Math.round(b / 1e3)) + " kB"
}

// 1080p, 4K: the smaller side, which is what people call a resolution.
function resolution(item) {
  if (!item || !item.width || !item.height) return ""
  var s = Math.min(item.width, item.height)
  if (s >= 2000) return "4K"
  if (s >= 1400) return "1440p"
  return s + "p"
}

function count(n) {
  n = number(n)
  if (n >= 1e6) return (n / 1e6).toFixed(n >= 1e7 ? 0 : 1).replace(/\.0$/, "") + "M"
  if (n >= 1e4) return Math.round(n / 1e3) + "k"
  if (n >= 1e3) return (n / 1e3).toFixed(1).replace(/\.0$/, "") + "k"
  return String(Math.round(n))
}

function uploadsText(ch) {
  if (!ch || !ch.count) return ""
  return count(ch.count) + (ch.count === 1 ? " upload" : " uploads")
}

// @name, for a channel whose title is something else.
function handle(ch) { return ch && ch.name ? ch.name : "" }

// Under a card: who, and when.
function byline(item, nowSec) {
  if (!item) return ""
  var who = item.channel ? item.channel.title : "Anonymous"
  var when = ago(item.released, nowSec)
  return when ? who + " · " + when : who
}

// The facts on a video's page, as label and value.
function facts(item) {
  var out = []
  if (!item) return out
  function add(label, value) { if (value) out.push({ label: label, value: value }) }
  add("Released", date(item.released))
  add("Length", duration(item.duration))
  add("Picture", resolution(item))
  add("Size", size(item.size))
  add("Language", item.languages.join(", ").toUpperCase())
  add("License", item.license)
  return out
}

// --- the library ---------------------------------------------------------------

// A copy of a video small enough to keep: no description past a screenful.
function keep(item) {
  var c = {}
  for (var k in item) c[k] = item[k]
  if (c.description && c.description.length > 2000) c.description = c.description.slice(0, 2000) + "…"
  return c
}

function indexOf(list, id) {
  for (var i = 0; i < list.length; i++) if (list[i] && list[i].id === id) return i
  return -1
}

// Saved: newest first, once each. { list, full }.
function toggle(list, item, max) {
  var i = indexOf(list, item.id)
  if (i >= 0) return { list: list.slice(0, i).concat(list.slice(i + 1)), full: false, on: false }
  if (list.length >= max) return { list: list, full: true, on: false }
  return { list: [keep(item)].concat(list), full: false, on: true }
}

// History: what was played last goes to the top; the oldest falls off.
function played(list, item, nowSec) {
  var i = indexOf(list, item.id)
  var rest = i >= 0 ? list.slice(0, i).concat(list.slice(i + 1)) : list.slice()
  var entry = keep(item)
  entry.playedAt = Math.floor(nowSec)
  return [entry].concat(rest).slice(0, MAX_HISTORY)
}

function followChannel(list, ch) {
  var i = indexOf(list, ch.id)
  if (i >= 0) return { list: list.slice(0, i).concat(list.slice(i + 1)), full: false, on: false }
  if (list.length >= MAX_FOLLOWS) return { list: list, full: true, on: false }
  var c = { id: ch.id, name: ch.name, title: ch.title, thumb: ch.thumb, cover: ch.cover,
            description: String(ch.description || "").slice(0, 1000), count: ch.count, url: ch.url }
  return { list: [c].concat(list), full: false, on: true }
}

// library.json, which is the only file of the person's own this app writes.
function parseLibrary(data) {
  var out = { follows: [], saved: [], history: [] }
  if (!data || typeof data !== "object") return out
  function clean(list, max, ok) {
    var r = []
    if (!Array.isArray(list)) return r
    for (var i = 0; i < list.length && r.length < max; i++) {
      var x = list[i]
      if (x && typeof x === "object" && /^[0-9a-f]{40}$/.test(String(x.id)) && ok(x) && indexOf(r, x.id) < 0) r.push(x)
    }
    return r
  }
  function isVideo(x) { return typeof x.name === "string" && typeof x.sd === "string" && Array.isArray(x.tags) && Array.isArray(x.languages) }
  function isChannel(x) { return typeof x.name === "string" && typeof x.title === "string" }
  out.follows = clean(data.follows, MAX_FOLLOWS, isChannel)
  out.saved = clean(data.saved, MAX_SAVED, isVideo)
  out.history = clean(data.history, MAX_HISTORY, isVideo)
  return out
}

function serializeLibrary(lib) {
  return JSON.stringify({ version: 1, follows: lib.follows, saved: lib.saved, history: lib.history }, null, 1) + "\n"
}

// homepage.json: the categories and when they were fetched.
function parseHomepage(data) {
  if (!data || typeof data !== "object" || !Array.isArray(data.categories)) return { categories: [], fetched: 0 }
  var cats = data.categories.filter(function (c) {
    return c && typeof c.key === "string" && typeof c.label === "string" && Array.isArray(c.channels)
  })
  return { categories: cats, fetched: number(data.fetched) }
}

function serializeHomepage(cats, fetched) {
  return JSON.stringify({ version: 1, fetched: Math.floor(fetched), categories: cats }) + "\n"
}
