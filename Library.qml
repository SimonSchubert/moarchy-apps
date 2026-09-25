import QtQuick
import "Api.mjs" as Api

// Your own Trakt: what is on the watchlist, which movies you have seen, how
// you rated things, which episodes are watched -- and the writes that change
// them.
//
// Every write shows at once. A local override stands in for the answer until
// a fresh copy of the list it belongs to arrives from Trakt (asked for after
// the write went through); then Trakt's word is the only one again. A write
// that fails puts things back as they were and says so.
Item {
  id: root
  property var app
  readonly property var trakt: app.trakt
  readonly property bool signedIn: trakt.signedIn

  // key -> { v, t }. Keys: "movie:12" for the watchlist and ratings, the
  // movie's id for plays, "<show id>" -> { "s:e": { v, t } } for episodes.
  property var watchlistOver: ({})
  property var playsOver: ({})
  property var ratingOver: ({})
  property var episodeOver: ({})
  property int rev: 0

  readonly property string watchlistMovies: Api.watchlistUrl("movie")
  readonly property string watchlistShows: Api.watchlistUrl("show")

  function key(m) { return m.type + ":" + m.id }

  // Sets rebuilt when an answer lands, not per card.
  readonly property var watchlistSet: {
    trakt.revision
    var s = {}
    var lists = [trakt.peek(watchlistMovies) || [], trakt.peek(watchlistShows) || []]
    for (var l = 0; l < 2; l++) for (var i = 0; i < lists[l].length; i++) s[lists[l][i].type + ":" + lists[l][i].id] = true
    return s
  }
  readonly property var playsMap: { trakt.revision; return trakt.peek(Api.watchedMoviesUrl()) || {} }
  readonly property var ratingMap: { trakt.revision; return trakt.peek(Api.ratingsUrl()) || {} }

  function ensure(force) {
    if (!signedIn) return
    var t = force ? 0 : 600000
    trakt.want(watchlistMovies, "watchlist", t, false)
    trakt.want(watchlistShows, "watchlist", t, false)
    trakt.want(Api.watchedMoviesUrl(), "watched", force ? 0 : 1800000, false)
    trakt.want(Api.ratingsUrl(), "ratings", force ? 0 : 1800000, false)
  }

  function over(map, k) { return Object.prototype.hasOwnProperty.call(map, k) ? map[k].v : undefined }

  function inWatchlist(m) {
    rev
    if (!m || !signedIn) return false
    var o = over(watchlistOver, key(m))
    return o !== undefined ? o : !!watchlistSet[key(m)]
  }

  function plays(m) {
    rev
    if (!m || m.type !== "movie" || !signedIn) return 0
    var o = over(playsOver, m.id)
    return o !== undefined ? o : (playsMap[m.id] || 0)
  }

  function rating(m) {
    rev
    if (!m || !signedIn) return 0
    var o = over(ratingOver, key(m))
    return o !== undefined ? o : (ratingMap[key(m)] || 0)
  }

  function episodeWatched(showId, progress, ep) {
    rev
    var o = episodeOver[showId] ? over(episodeOver[showId], ep.season + ":" + ep.number) : undefined
    if (o !== undefined) return o
    var w = progress && progress.watched ? progress.watched[ep.season] : null
    return !!w && w.indexOf(ep.number) >= 0
  }

  function setOver(name, k, v) {
    var m = Object.assign({}, root[name])
    if (v === undefined) delete m[k]; else m[k] = { v: v, t: Date.now() }
    root[name] = m
    rev++
  }

  function body(m) {
    var b = {}
    b[Api.plural(m.type)] = [{ ids: { trakt: m.id } }]
    return b
  }

  function failed(what) { app.toast("Couldn't " + what + ". Try again in a moment.") }

  // Answers that are out of date after a write about `m`.
  function staleAfter(m, lists) {
    trakt.stale(function (url) {
      if (lists.indexOf("watchlist") >= 0 && url.indexOf("/sync/watchlist/") > 0) return true
      if (lists.indexOf("history") >= 0 && (url.indexOf("/sync/history") > 0 || url.indexOf("/sync/watched/") > 0
        || url.indexOf("/sync/progress/") > 0 || url.indexOf("/users/") > 0)) return true
      if (lists.indexOf("ratings") >= 0 && url.indexOf("/sync/ratings") > 0) return true
      if (m && m.type === "show" && url === Api.progressUrl(m.id)) return true
      return false
    })
    app.refresh(false)
    ensure(false)
  }

  function requireSignIn() {
    if (signedIn) return true
    app.toast("Sign in to Trakt first")
    app.openSettings()
    return false
  }

  // ------------------------------------------------------------ writes

  function toggleWatchlist(m) {
    if (!m || !requireSignIn()) return
    var k = key(m)
    var add = !inWatchlist(m)
    setOver("watchlistOver", k, add)
    app.toast(add ? "Added to your watchlist" : "Removed from your watchlist")
    trakt.write(add ? "/sync/watchlist" : "/sync/watchlist/remove", body(m), function (ok) {
      if (!ok) { root.setOver("watchlistOver", k, undefined); root.failed("update your watchlist"); return }
      root.staleAfter(m, ["watchlist"])
    })
  }

  // Trakt takes a watched movie off the watchlist by itself.
  function markWatched(m) {
    if (!m || m.type !== "movie" || !requireSignIn()) return
    var before = plays(m)
    setOver("playsOver", m.id, before + 1)
    app.toast("Marked as watched")
    var b = {}
    b.movies = [{ ids: { trakt: m.id }, watched_at: new Date().toISOString() }]
    trakt.write("/sync/history", b, function (ok) {
      if (!ok) { root.setOver("playsOver", m.id, undefined); root.failed("mark it watched"); return }
      root.staleAfter(m, ["history", "watchlist"])
    })
  }

  function unwatch(m) {
    if (!m || m.type !== "movie" || !requireSignIn()) return
    setOver("playsOver", m.id, 0)
    app.toast("Removed from your history")
    trakt.write("/sync/history/remove", body(m), function (ok) {
      if (!ok) { root.setOver("playsOver", m.id, undefined); root.failed("remove it from your history"); return }
      root.staleAfter(m, ["history"])
    })
  }

  // 1..10, or 0 to take the rating back.
  function rate(m, v) {
    if (!m || !requireSignIn()) return
    var k = key(m)
    setOver("ratingOver", k, v)
    var b = {}
    b[Api.plural(m.type)] = [v > 0 ? { ids: { trakt: m.id }, rating: v } : { ids: { trakt: m.id } }]
    trakt.write(v > 0 ? "/sync/ratings" : "/sync/ratings/remove", b, function (ok) {
      if (!ok) { root.setOver("ratingOver", k, undefined); root.failed("save your rating"); return }
      root.staleAfter(m, ["ratings"])
    })
  }

  function setEpisodes(show, eps, watched) {
    if (!show || !eps.length || !requireSignIn()) return
    var o = Object.assign({}, episodeOver[show.id] || {})
    var t = Date.now()
    for (var i = 0; i < eps.length; i++) o[eps[i].season + ":" + eps[i].number] = { v: watched, t: t }
    var all = Object.assign({}, episodeOver)
    all[show.id] = o
    episodeOver = all
    rev++
    if (eps.length > 1) app.toast((watched ? "Marked " : "Unmarked ") + eps.length + " episodes")
    var b = { episodes: eps.map(function (e) {
      return watched ? { ids: { trakt: e.id }, watched_at: new Date().toISOString() } : { ids: { trakt: e.id } }
    }) }
    trakt.write(watched ? "/sync/history" : "/sync/history/remove", b, function (ok) {
      if (!ok) {
        var a = Object.assign({}, root.episodeOver)
        var n = Object.assign({}, a[show.id] || {})
        for (var j = 0; j < eps.length; j++) delete n[eps[j].season + ":" + eps[j].number]
        a[show.id] = n
        root.episodeOver = a
        root.rev++
        root.failed(watched ? "mark it watched" : "unmark it")
        return
      }
      root.staleAfter(show, ["history"])
      root.trakt.want(Api.progressUrl(show.id), "progress", 0, true)
    })
  }

  // A fresh answer ends the overrides it covers.
  Connections {
    target: root.trakt
    function onLanded(url, sentAt) {
      var drop = function (name, test) {
        var m = root[name], n = {}, changed = false
        for (var k in m) { if (test(k) && m[k].t < sentAt) changed = true; else n[k] = m[k] }
        if (changed) { root[name] = n; root.rev++ }
      }
      if (url.indexOf("/sync/watchlist/") > 0) drop("watchlistOver", function () { return true })
      else if (url === Api.watchedMoviesUrl()) drop("playsOver", function () { return true })
      else if (url === Api.ratingsUrl()) drop("ratingOver", function () { return true })
      var m = /\/shows\/(\d+)\/progress\/watched/.exec(url)
      if (m && root.episodeOver[m[1]]) {
        var eo = root.episodeOver[m[1]], keep = {}, any = false
        for (var e in eo) { if (eo[e].t < sentAt) any = true; else keep[e] = eo[e] }
        if (any) {
          var all = Object.assign({}, root.episodeOver)
          all[m[1]] = keep
          root.episodeOver = all
          root.rev++
        }
      }
    }
    function onSignedInChanged() {
      root.watchlistOver = {}
      root.playsOver = {}
      root.ratingOver = {}
      root.episodeOver = {}
      root.rev++
      root.ensure(false)
    }
  }
}
