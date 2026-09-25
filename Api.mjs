// Everything about Trakt that is not a request: where to ask, what to keep of
// the answer, and how to print it. Pure functions. An ECMAScript module rather
// than a `.pragma library` script so the worker thread that shapes responses
// (Worker.mjs) imports the very same code the views do.
//
// Answers are copied field by field into small plain objects. A page of thirty
// trending movies with full info and images is ~120 KB of JSON; a poster card
// needs a title, a year and two picture addresses. Every string that reaches a
// Text item has passed through here.

export var BASE = "https://api.trakt.tv"
export var SITE = "https://trakt.tv"

// ------------------------------------------------------------ ids

// Trakt ids are positive integers; slugs are lowercase words and dashes.
// Anything else did not come from Trakt and goes into no URL.
export function tid(v) {
  var n = Number(v)
  return isFinite(n) && n > 0 && Math.floor(n) === n && n < 1e10 ? n : 0
}

export function slug(v) {
  var s = String(v || "")
  return /^[a-z0-9][a-z0-9-]{0,159}$/.test(s) ? s : ""
}

export function plural(type) { return type === "show" ? "shows" : "movies" }

export function q(v) { return encodeURIComponent(String(v)) }

// ------------------------------------------------------------ endpoints

var LIST_EXT = "full,images,colors"

// Discover sections, per media type. Box office is movies only; the others
// exist for both.
export var SECTIONS = [
  { key: "trending", label: "Trending", note: "Most watched on Trakt right now" },
  { key: "popular", label: "Popular", note: "Best rated by the most people, all time" },
  { key: "anticipated", label: "Anticipated", note: "Most added to lists, not out yet" },
  { key: "streaming", label: "Streaming", note: "Top on streaming services this week" },
  { key: "boxoffice", label: "Box office", note: "Top 10 at the US box office last weekend", movies: true }
]

export function discoverUrl(type, section, page, perPage) {
  var p = BASE + "/" + plural(type) + "/"
  if (section === "boxoffice") return p + "boxoffice?extended=" + LIST_EXT
  if (section === "streaming") p += "streaming/weekly"
  else p += ["trending", "popular", "anticipated"].indexOf(section) >= 0 ? section : "trending"
  return p + "?extended=" + LIST_EXT + "&page=" + page + "&limit=" + perPage
}

export function searchUrl(query, types) {
  return BASE + "/search/" + (types || "movie,show") + "?query=" + q(query) + "&extended=full,images&limit=40"
}

export function summaryUrl(type, id) {
  return BASE + "/" + plural(type) + "/" + tid(id) + "?extended=full,images,colors"
}
export function peopleUrl(type, id) { return BASE + "/" + plural(type) + "/" + tid(id) + "/people?extended=images" }
export function relatedUrl(type, id) {
  return BASE + "/" + plural(type) + "/" + tid(id) + "/related?extended=full,images&limit=18"
}
export function seasonsUrl(id) { return BASE + "/shows/" + tid(id) + "/seasons?extended=full,images" }
export function seasonUrl(id, n) {
  return BASE + "/shows/" + tid(id) + "/seasons/" + Math.max(0, Math.floor(Number(n) || 0)) + "?extended=full,images"
}
export function progressUrl(id) { return BASE + "/shows/" + tid(id) + "/progress/watched?hidden=false&specials=false" }

// Signed in.
export function upNextUrl(page) { return BASE + "/sync/progress/up_next?extended=full,images&page=" + page + "&limit=40" }
export function calendarUrl(target, what, start, days) {
  return BASE + "/calendars/" + (target === "my" ? "my" : "all") + "/" + what + "/" + start + "/" + days + "?extended=full,images"
}
export function watchlistUrl(type) { return BASE + "/sync/watchlist/" + plural(type) + "/added/desc?extended=full,images,colors" }
export function historyUrl(page) { return BASE + "/sync/history?extended=full,images&page=" + page + "&limit=40" }
export function watchedMoviesUrl() { return BASE + "/sync/watched/movies" }
export function ratingsUrl() { return BASE + "/sync/ratings" }
export function settingsUrl() { return BASE + "/users/settings" }
export function statsUrl(user) { return BASE + "/users/" + slug(user) + "/stats" }

// Everything that is somebody's own and must go when they sign out.
export function personal(url) {
  return url.indexOf(BASE + "/sync/") === 0 || url.indexOf(BASE + "/calendars/my/") === 0
    || url.indexOf("/progress/") > 0 || url.indexOf(BASE + "/users/") === 0
}

export function siteUrl(item) {
  if (!item) return SITE
  var s = slug(item.slug) || tid(item.id)
  return SITE + "/" + plural(item.type) + "/" + s
}

// ------------------------------------------------------------ shaping

export function num(v) {
  if (v === null || v === undefined || v === "") return NaN
  var n = Number(v)
  return isFinite(n) ? n : NaN
}

export function str(v, max) {
  if (v === null || v === undefined) return ""
  var s = String(v).replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g, " ")
  return s.length > max ? s.slice(0, max).replace(/\s+\S*$/, "") + "…" : s
}

export function httpsUrl(v) {
  var s = str(v, 400).trim()
  return /^https:\/\/[^\s"'<>]+$/i.test(s) ? s : ""
}

// Trakt's pictures come as bare "host/path" strings, always on one of its
// own hosts. Anything else is not loaded. `size` swaps the rendition:
// "thumb" for a list, "medium" for a page.
export function image(list, size) {
  var v = Array.isArray(list) && list.length ? String(list[0] || "") : ""
  v = v.replace(/^https?:\/\//i, "")
  if (!/^[a-z0-9.-]+\.trakt\.tv\/[A-Za-z0-9._\/-]+$/.test(v)) return ""
  if (size) v = v.replace(/\/(thumb|medium|full)\//, "/" + size + "/")
  // "x.jpg.webp" is also served as plain "x.jpg": a little larger, but every
  // Qt decodes it, and WebP needs qt6-imageformats, which not every
  // desktop has.
  v = v.replace(/\.(jpe?g|png)\.webp$/i, ".$1")
  return "https://" + v
}

export function color(list) {
  var v = Array.isArray(list) && list.length ? String(list[0] || "") : ""
  return /^#[0-9a-fA-F]{6}$/.test(v) ? v : ""
}

var GENRE_WORDS = { "science-fiction": "Sci-Fi", "tv-movie": "TV Movie", "game-show": "Game Show",
  "reality": "Reality", "talk-show": "Talk Show", "home-and-garden": "Home & Garden" }

export function genre(g) {
  var s = slug(g)
  if (!s) return ""
  if (GENRE_WORDS[s]) return GENRE_WORDS[s]
  return s.split("-").map(function (w) { return w.charAt(0).toUpperCase() + w.slice(1) }).join(" ")
}

// A movie or show, from any of the wrappers Trakt puts one in.
export function media(o, type, deep) {
  if (!o || typeof o !== "object") return null
  var id = tid(o.ids ? o.ids.trakt : 0)
  if (!id) return null
  var im = o.images || {}
  var colors = o.colors || {}
  var genres = []
  var raw = Array.isArray(o.genres) ? o.genres : []
  for (var i = 0; i < raw.length && genres.length < (deep ? 6 : 3); i++) {
    var g = genre(raw[i])
    if (g) genres.push(g)
  }
  var m = {
    type: type === "show" ? "show" : "movie",
    id: id,
    slug: slug(o.ids.slug),
    imdb: /^tt\d{1,10}$/.test(String(o.ids.imdb || "")) ? o.ids.imdb : "",
    title: str(o.title, 120),
    year: num(o.year),
    poster: image(im.poster, "thumb"),
    fanart: image(im.fanart, "medium"),
    tint: color(colors.poster),
    rating: num(o.rating),
    votes: num(o.votes),
    runtime: num(o.runtime),
    genres: genres,
    certification: str(o.certification, 12),
    released: str(type === "show" ? o.first_aired : o.released, 40),
    status: str(o.status, 30),
    network: str(o.network, 60),
    overview: str(o.overview, deep ? 3000 : 320)
  }
  if (deep) {
    m.posterLarge = image(im.poster, "medium")
    m.logo = image(im.logo, "medium")
    m.tagline = str(o.tagline, 200)
    m.trailer = httpsUrl(o.trailer)
    m.homepage = httpsUrl(o.homepage)
    m.country = str(o.country, 8).toUpperCase()
    m.language = str(o.language, 8)
    m.airedEpisodes = num(o.aired_episodes)
    m.airs = o.airs && o.airs.day ? str(o.airs.day, 12) + (o.airs.time ? " " + str(o.airs.time, 8) : "")
      + (o.airs.timezone ? " (" + str(o.airs.timezone, 40) + ")" : "") : ""
    m.comments = num(o.comment_count)
  }
  return m
}

// The item inside a list entry, with what the list says about it.
function entry(e) {
  if (!e || typeof e !== "object") return null
  var m = null
  if (e.movie) m = media(e.movie, "movie")
  else if (e.show) m = media(e.show, "show")
  else if (e.ids) m = media(e, e.aired_episodes !== undefined || e.network !== undefined ? "show" : "movie")
  if (!m) return null
  // A short figure for a poster's corner, and what it counts.
  if (!isNaN(num(e.watchers))) { m.stat = compact(num(e.watchers)); m.statKind = "watching" }
  else if (!isNaN(num(e.list_count))) { m.stat = compact(num(e.list_count)); m.statKind = "lists" }
  else if (!isNaN(num(e.revenue))) { m.stat = "$" + compact(num(e.revenue)); m.statKind = "" }
  if (e.listed_at) m.listedAt = str(e.listed_at, 40)
  return m
}

export function list(json, max) {
  var out = []
  var seen = {}
  if (!Array.isArray(json)) return out
  for (var i = 0; i < json.length && out.length < (max || 250); i++) {
    var m = entry(json[i])
    if (!m || seen[m.type + m.id]) continue
    seen[m.type + m.id] = true
    out.push(m)
  }
  return out
}

// Search answers with people and lists too; only movies and shows are kept.
export function search(json) {
  var out = []
  if (!Array.isArray(json)) return out
  for (var i = 0; i < json.length && out.length < 40; i++) {
    var r = json[i]
    if (!r || (r.type !== "movie" && r.type !== "show")) continue
    var m = media(r[r.type], r.type)
    if (m) out.push(m)
  }
  return out
}

export function episode(e, deep) {
  if (!e || typeof e !== "object") return null
  var id = tid(e.ids ? e.ids.trakt : 0)
  if (!id) return null
  return {
    id: id,
    season: Math.max(0, Math.floor(num(e.season) || 0)),
    number: Math.max(0, Math.floor(num(e.number) || 0)),
    title: str(e.title, 160),
    aired: str(e.first_aired, 40),
    runtime: num(e.runtime),
    rating: num(e.rating),
    kind: str(e.episode_type, 30),
    overview: str(e.overview, deep ? 1200 : 0),
    still: e.images ? image(e.images.screenshot, "thumb") : ""
  }
}

export function people(json) {
  var cast = []
  var raw = json && Array.isArray(json.cast) ? json.cast : []
  for (var i = 0; i < raw.length && cast.length < 30; i++) {
    var c = raw[i]
    if (!c || !c.person) continue
    var chars = Array.isArray(c.characters) ? c.characters : (c.character ? [c.character] : [])
    cast.push({
      name: str(c.person.name, 80),
      slug: slug(c.person.ids ? c.person.ids.slug : ""),
      role: str(chars.join(" / "), 80),
      headshot: image((c.images || c.person.images || {}).headshot, "thumb")
    })
  }
  // Who made it, one line per job: "Directed by A", "Written by B, C".
  var crew = []
  var jobs = json && json.crew ? json.crew : {}
  var wanted = [["created by", "Created by", null], ["directing", "Directed by", "Director"],
    ["writing", "Written by", null]]
  for (var w = 0; w < wanted.length; w++) {
    var group = Array.isArray(jobs[wanted[w][0]]) ? jobs[wanted[w][0]] : []
    var names = []
    for (var j = 0; j < group.length && names.length < 3; j++) {
      var p = group[j]
      if (!p || !p.person) continue
      var js = Array.isArray(p.jobs) ? p.jobs : [p.job]
      if (wanted[w][2] && js.indexOf(wanted[w][2]) < 0) continue
      var name = str(p.person.name, 80)
      if (name && names.indexOf(name) < 0) names.push(name)
    }
    if (names.length) crew.push({ job: wanted[w][1], names: names })
  }
  return { cast: cast, crew: crew }
}

export function seasons(json) {
  var out = []
  if (!Array.isArray(json)) return out
  for (var i = 0; i < json.length && i < 200; i++) {
    var s = json[i]
    if (!s) continue
    var n = Math.floor(num(s.number))
    if (isNaN(n) || n < 0) continue
    out.push({
      number: n,
      title: str(s.title, 80) || (n === 0 ? "Specials" : "Season " + n),
      episodes: num(s.episode_count),
      aired: num(s.aired_episodes),
      rating: num(s.rating),
      firstAired: str(s.first_aired, 40),
      poster: s.images ? image(s.images.poster, "thumb") : ""
    })
  }
  // Specials last: nobody starts a show there.
  out.sort(function (a, b) { return (a.number === 0 ? 1e6 : a.number) - (b.number === 0 ? 1e6 : b.number) })
  return out
}

export function season(json) {
  var out = []
  if (!Array.isArray(json)) return out
  for (var i = 0; i < json.length && i < 400; i++) {
    var e = episode(json[i], true)
    if (e) out.push(e)
  }
  return out
}

// Which episodes of a show are watched: { "1": [1, 2, 3], "2": [1] }.
export function progress(json) {
  if (!json || typeof json !== "object") return null
  var watched = {}
  var ss = Array.isArray(json.seasons) ? json.seasons : []
  for (var i = 0; i < ss.length; i++) {
    var s = ss[i]
    if (!s) continue
    var n = Math.floor(num(s.number))
    var eps = Array.isArray(s.episodes) ? s.episodes : []
    var done = []
    for (var j = 0; j < eps.length; j++) if (eps[j] && eps[j].completed) done.push(Math.floor(num(eps[j].number)))
    watched[n] = done
  }
  return {
    aired: num(json.aired),
    completed: num(json.completed),
    lastWatched: str(json.last_watched_at, 40),
    next: episode(json.next_episode, false),
    watched: watched
  }
}

export function upNext(json) {
  var out = []
  if (!Array.isArray(json)) return out
  for (var i = 0; i < json.length && out.length < 200; i++) {
    var r = json[i]
    if (!r) continue
    var show = media(r.show, "show")
    var p = r.progress || {}
    var next = episode(p.next_episode, false)
    if (!show || !next) continue
    out.push({
      key: "u" + show.id,
      show: show,
      next: next,
      aired: num(p.aired),
      completed: num(p.completed),
      lastWatched: str(p.last_watched_at, 40)
    })
  }
  return out
}

export function localDay(iso) {
  var d = new Date(iso)
  if (isNaN(d.getTime())) return ""
  return ymd(d)
}

export function calendar(json, what) {
  var out = []
  if (!Array.isArray(json)) return out
  for (var i = 0; i < json.length && out.length < 600; i++) {
    var r = json[i]
    if (!r) continue
    var e = null, m = null, at = ""
    if (r.show) {
      m = media(r.show, "show")
      e = episode(r.episode, false)
      at = str(r.first_aired, 40)
      if (!e) continue
    } else if (r.movie) {
      m = media(r.movie, "movie")
      // Movie releases are dates, not moments: noon keeps them on their day in
      // every time zone.
      at = str(r.released, 20) + "T12:00:00"
    }
    if (!m || !localDay(at)) continue
    out.push({ key: (e ? "e" + e.id : "m" + m.id) + at, at: at, day: localDay(at), media: m, episode: e })
  }
  return out
}

export function history(json) {
  var out = []
  if (!Array.isArray(json)) return out
  for (var i = 0; i < json.length && out.length < 100; i++) {
    var r = json[i]
    if (!r) continue
    var m = r.movie ? media(r.movie, "movie") : r.show ? media(r.show, "show") : null
    if (!m) continue
    var e = r.episode ? episode(r.episode, false) : null
    out.push({ key: "h" + num(r.id), at: str(r.watched_at, 40), day: localDay(r.watched_at), media: m, episode: e })
  }
  return out
}

// Trakt id -> plays, for the "Watched" marks on movies.
export function watchedMovies(json) {
  var out = {}
  if (!Array.isArray(json)) return out
  for (var i = 0; i < json.length; i++) {
    var r = json[i]
    var id = r && r.movie && r.movie.ids ? tid(r.movie.ids.trakt) : 0
    if (id) out[id] = Math.max(1, Math.floor(num(r.plays) || 1))
  }
  return out
}

// "movie:123" / "show:45" / "episode:678" -> 1..10.
export function ratings(json) {
  var out = {}
  if (!Array.isArray(json)) return out
  for (var i = 0; i < json.length; i++) {
    var r = json[i]
    if (!r || ["movie", "show", "episode"].indexOf(r.type) < 0 || !r[r.type] || !r[r.type].ids) continue
    var id = tid(r[r.type].ids.trakt)
    var v = Math.floor(num(r.rating))
    if (id && v >= 1 && v <= 10) out[r.type + ":" + id] = v
  }
  return out
}

export function settings(json) {
  var u = json && json.user ? json.user : null
  if (!u) return null
  return {
    username: str(u.username, 60),
    slug: slug(u.ids ? u.ids.slug : ""),
    name: str(u.name, 80),
    vip: !!u.vip,
    joined: str(u.joined_at, 40),
    // Trakt's own picture, or the Gravatar it points to; no other host.
    avatar: u.images && u.images.avatar && /^https:\/\/([a-z0-9-]+\.)*(trakt\.tv|gravatar\.com)\//.test(httpsUrl(u.images.avatar.full))
      ? httpsUrl(u.images.avatar.full) : ""
  }
}

export function stats(json) {
  if (!json || typeof json !== "object") return null
  var mv = json.movies || {}, ep = json.episodes || {}, sh = json.shows || {}
  return {
    movies: num(mv.watched), movieMinutes: num(mv.minutes),
    shows: num(sh.watched), episodes: num(ep.watched), episodeMinutes: num(ep.minutes),
    ratings: json.ratings ? num(json.ratings.total) : NaN
  }
}

export function shape(kind, json) {
  switch (kind) {
  case "list": return list(json, 250)
  case "search": return search(json)
  case "summary": return media(json, json && json.aired_episodes !== undefined ? "show" : "movie", true)
  case "summary-show": return media(json, "show", true)
  case "summary-movie": return media(json, "movie", true)
  case "people": return people(json)
  case "seasons": return seasons(json)
  case "season": return season(json)
  case "progress": return progress(json)
  case "upnext": return upNext(json)
  case "calendar": return calendar(json)
  case "watchlist": return list(json, 1000)
  case "history": return history(json)
  case "watched": return watchedMovies(json)
  case "ratings": return ratings(json)
  case "settings": return settings(json)
  case "stats": return stats(json)
  }
  return null
}

// ------------------------------------------------------------ formatting

export var DASH = "—"
export var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
export var DAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

export function two(n) { return ("0" + n).slice(-2) }

export function ymd(d) { return d.getFullYear() + "-" + two(d.getMonth() + 1) + "-" + two(d.getDate()) }

export function compact(v) {
  if (isNaN(v)) return DASH
  var a = Math.abs(v)
  if (a >= 1e9) return (a / 1e9).toFixed(1).replace(/\.0$/, "") + "B"
  if (a >= 1e6) return (a / 1e6).toFixed(1).replace(/\.0$/, "") + "M"
  if (a >= 1e3) return (a / 1e3).toFixed(a >= 1e4 ? 0 : 1).replace(/\.0$/, "") + "K"
  return String(Math.round(a))
}

export function group(n) { return String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ",") }

// Trakt rates 1 to 10 and shows it as a percentage.
export function percent(r) { return isNaN(r) || r <= 0 ? "" : Math.round(r * 10) + "%" }

export function runtime(min) {
  if (isNaN(min) || min <= 0) return ""
  var h = Math.floor(min / 60), m = Math.round(min % 60)
  return h ? h + "h" + (m ? " " + m + "m" : "") : m + "m"
}

export function epCode(e) {
  if (!e) return ""
  return "S" + two(e.season) + "E" + two(e.number)
}

export function date(iso) {
  var d = new Date(iso)
  if (isNaN(d.getTime())) return ""
  return MONTHS[d.getMonth()] + " " + d.getDate() + ", " + d.getFullYear()
}

export function time(iso) {
  var d = new Date(iso)
  if (isNaN(d.getTime())) return ""
  return two(d.getHours()) + ":" + two(d.getMinutes())
}

// "Today", "Tomorrow", "Friday", then "Sat, Oct 12".
export function dayLabel(day, now) {
  var p = String(day).split("-")
  var d = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]))
  if (isNaN(d.getTime())) return ""
  var t = new Date(now || Date.now())
  var today = new Date(t.getFullYear(), t.getMonth(), t.getDate())
  var diff = Math.round((d - today) / 86400000)
  if (diff === 0) return "Today"
  if (diff === 1) return "Tomorrow"
  if (diff === -1) return "Yesterday"
  if (diff > 1 && diff < 7) return DAYS[d.getDay()]
  return DAYS[d.getDay()].slice(0, 3) + ", " + MONTHS[d.getMonth()] + " " + d.getDate()
    + (d.getFullYear() !== today.getFullYear() ? ", " + d.getFullYear() : "")
}

export function ago(iso, now) {
  var d = new Date(iso)
  if (isNaN(d.getTime())) return ""
  var s = Math.max(0, ((now || Date.now()) - d.getTime()) / 1000)
  if (s < 90) return "just now"
  if (s < 3600) return Math.round(s / 60) + " min ago"
  if (s < 86400) return Math.round(s / 3600) + " h ago"
  var days = Math.round(s / 86400)
  if (days < 2) return "yesterday"
  if (days < 30) return days + " days ago"
  if (days < 365) return Math.round(days / 30.4) + " months ago"
  return (days / 365.25).toFixed(1).replace(/\.0$/, "") + " years ago"
}

// "in 3 days", "in 5 h" -- for what has not aired yet.
export function until(iso, now) {
  var d = new Date(iso)
  if (isNaN(d.getTime())) return ""
  var s = (d.getTime() - (now || Date.now())) / 1000
  if (s <= 0) return ""
  if (s < 3600) return "in " + Math.max(1, Math.round(s / 60)) + " min"
  if (s < 86400) return "in " + Math.round(s / 3600) + " h"
  return "in " + Math.round(s / 86400) + " days"
}

// "8.5K watching", "1.2K lists", "$12M".
export function statText(m) { return m && m.stat ? m.stat + (m.statKind ? " " + m.statKind : "") : "" }

export function year(v) { return isNaN(v) || !v ? "" : String(v) }

export function status(s) {
  var map = { "returning series": "Returning", "in production": "In production", "planned": "Planned",
    "canceled": "Canceled", "ended": "Ended", "released": "Released", "post production": "Post-production",
    "upcoming": "Upcoming", "pilot": "Pilot", "rumored": "Rumored" }
  return map[s] || ""
}

// The meta line under a title: "2024 · 2h 14m · PG-13".
export function metaLine(m) {
  if (!m) return ""
  var parts = []
  if (year(m.year)) parts.push(year(m.year))
  if (m.type === "show" && m.network) parts.push(m.network)
  if (runtime(m.runtime)) parts.push(runtime(m.runtime) + (m.type === "show" ? " per ep" : ""))
  if (m.certification) parts.push(m.certification)
  return parts.join("  ·  ")
}
