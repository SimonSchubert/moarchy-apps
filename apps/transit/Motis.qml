import QtQuick
import Quickshell
import Quickshell.Io
import "Api.mjs" as Api

// Every request to Transitous goes through here, one at a time.
//
// Transitous is a free service run by volunteers, and asks its clients to go
// easy on it. So the queue sends one request at a time with a gap between
// them, keeps every answer for as long as it is worth keeping, and stops for
// as long as the server says when it is told to. Views never hold a callback:
// they ask for a URL with want() and read it back with peek(), which follows
// `revision`. A view destroyed mid-request has nothing to be called back on.
Item {
  id: root

  // MOARCHY_TRANSIT_OFFLINE: no request leaves the app, for the shots. What
  // it would have asked is answered from MOARCHY_TRANSIT_DIR/fixture.json,
  // which dev/capture.py recorded and dev/demo.py put there, and goes through
  // the worker like any answer; a URL the fixture has no answer for is never
  // answered, and never an error either.
  readonly property bool sealed: (Quickshell.env("MOARCHY_TRANSIT_OFFLINE") || "") !== ""
  readonly property string fixtureDir: Quickshell.env("MOARCHY_TRANSIT_DIR") || ""
  property var fixture: null   // url -> the answer, once read

  // Bumped on every change to the cache or to what is in flight. Bindings
  // read it to re-evaluate peek(), status() and error().
  property int revision: 0

  // Rate-limit and connectivity state, for the strip under the header.
  property real blockedUntil: 0
  property real now: Date.now()
  property bool offline: false
  readonly property int waitSeconds: Math.max(0, Math.ceil((blockedUntil - now) / 1000))
  readonly property string banner: waitSeconds > 0
    ? "Transitous is busy · retrying in " + waitSeconds + " s"
    : offline ? "Offline · showing what was saved" : ""

  // Every request here is one somebody asked for, or a refresh of what is on
  // screen; a second between them is plenty.
  readonly property int gap: 1000

  property var cache: ({})     // url -> { t, data }
  property var failures: ({})  // url -> { t, message }
  property var queue: []       // [{ url, kind }]
  property var parsing: ({})   // url -> true while the worker shapes it
  property var outbox: []      // messages for a worker still loading
  property string inflight: ""
  property real lastSent: 0
  property var xhr: null

  signal changed()

  // Coalesced and deferred: want() is often called from a handler that runs
  // while a binding reading `revision` is being evaluated, and bumping it
  // there is a binding loop. One bump per turn of the event loop is plenty.
  function touch() { Qt.callLater(root.bump) }
  function bump() { revision++; changed() }

  function peek(url) {
    var e = cache[url]
    return e ? e.data : null
  }

  function age(url) {
    var e = cache[url]
    return e ? Date.now() - e.t : Infinity
  }

  function busy(url) {
    if (inflight === url || parsing[url]) return true
    for (var i = 0; i < queue.length; i++) if (queue[i].url === url) return true
    return false
  }

  function error(url) {
    var f = failures[url]
    return f && !cache[url] ? f.message : ""
  }

  // Ask for `url` unless a copy younger than `ttl` ms is cached. `urgent`
  // puts it at the front: what the person just tapped beats a refresh of a
  // list behind it.
  function want(url, kind, ttl, urgent) {
    if (!url) return
    if (age(url) < ttl) return
    var f = failures[url]
    if (f && Date.now() - f.t < 15000 && !urgent) return
    for (var i = 0; i < queue.length; i++) {
      if (queue[i].url !== url) continue
      if (urgent && i > 0) {
        var q = queue.slice()
        q.unshift(q.splice(i, 1)[0])
        queue = q
      }
      return
    }
    if (inflight === url) return
    var job = { url: url, kind: kind }
    var next = queue.slice()
    if (urgent) next.unshift(job); else next.push(job)
    queue = next
    touch()
    pump()
  }

  // A detail page closed before its turn came: nobody will read the answer.
  function forget(urls) {
    var keep = queue.filter(function (j) { return urls.indexOf(j.url) < 0 })
    if (keep.length !== queue.length) { queue = keep; touch() }
  }

  // The answers worth keeping on disk: the last boards and journeys, only the
  // freshest few so the file stays small.
  function snapshot(kinds, limit) {
    var keys = Object.keys(cache).filter(function (u) { return kinds.indexOf(cache[u].kind) >= 0 })
    keys.sort(function (a, b) { return cache[b].t - cache[a].t })
    var out = {}
    for (var i = 0; i < keys.length && i < limit; i++) out[keys[i]] = cache[keys[i]]
    return out
  }

  function clear() {
    cache = {}
    failures = {}
    touch()
  }

  // The saved snapshot's text, parsed on the worker; restore() takes it from
  // there.
  function restoreText(text) {
    if (text) post({ op: "parse", text: text })
  }

  // Seed from the snapshot saved last time, keeping each entry's age so it is
  // shown at once and refreshed as soon as it is due.
  function restore(entries) {
    var c = {}
    for (var url in entries) {
      var e = entries[url]
      if (e && e.data !== undefined && typeof e.t === "number" && url.indexOf(Api.BASE) === 0) c[url] = e
    }
    for (var k in cache) c[k] = cache[k]
    cache = c
    touch()
  }

  function pump() {
    if (inflight || !queue.length) return
    if (sealed) { answerFromFixture(); return }
    var t = Date.now()
    var wait = Math.max(blockedUntil - t, lastSent + gap - t)
    if (wait > 0) {
      pumpTimer.interval = Math.min(wait + 20, 120000)
      pumpTimer.restart()
      return
    }
    var q = queue.slice()
    var job = q.shift()
    queue = q
    send(job)
  }

  // The app's only HTTP request. `binary` answers with an ArrayBuffer instead
  // of text. done(status, body, req).
  function get(url, headers, binary, done) {
    var req = new XMLHttpRequest()
    if (binary) req.responseType = "arraybuffer"
    req.onreadystatechange = function () {
      if (req.readyState === 4) done(req.status, binary ? req.response : req.responseText, req)
    }
    req.open("GET", url)
    for (var h in headers) req.setRequestHeader(h, headers[h])
    req.send()
    return req
  }

  function send(job) {
    inflight = job.url
    lastSent = Date.now()
    touch()
    var headers = { "Accept": "application/json", "User-Agent": Api.USER_AGENT }
    var req = get(job.url, headers, false, function (status, body, r) {
      if (xhr !== r) return
      timeout.stop()
      xhr = null
      finish(job, status, body, r.getResponseHeader("retry-after"))
    })
    xhr = req
    timeout.restart()
  }

  // Torn down mid-request (a plugin reload, the shell restarting): drop the
  // request. Its answer would otherwise arrive in a context that is gone,
  // and log an error for a variable that no longer exists.
  Component.onDestruction: {
    var r = xhr
    xhr = null
    if (!r) return
    r.onreadystatechange = function () {}
    r.abort()
  }

  function finish(job, status, body, retryAfter) {
    inflight = ""
    if (status === 200) {
      // Shaped on the worker; the queue moves on meanwhile.
      var p = Object.assign({}, parsing)
      p[job.url] = true
      parsing = p
      offline = false
      post({ op: "shape", url: job.url, kind: job.kind, text: body })
    } else if (status === 429) {
      var secs = parseInt(retryAfter, 10)
      blockedUntil = Date.now() + (isFinite(secs) && secs > 0 ? Math.min(secs, 300) : 60) * 1000
      now = Date.now()
      var back = queue.slice()
      back.unshift(job)
      queue = back
    } else if (status === 0) {
      offline = true
      fail(job, "Can't reach Transitous")
    } else if (status === 400 || status === 404 || status === 422) {
      fail(job, noRoute(body))
    } else if (status === 403) {
      fail(job, "Transitous refused the request")
    } else if (status >= 500) {
      fail(job, "Transitous is having trouble (" + status + ")")
    } else {
      fail(job, "Transitous error " + status)
    }
    touch()
    pump()
  }

  // MOTIS says why in plain text or a small JSON; the useful case is a place
  // outside every timetable it has.
  function noRoute(body) {
    var t = String(body || "")
    if (/timetable location|could not find|no.*station|not found/i.test(t)) return "No timetable covers this place"
    return "Transitous couldn't answer that"
  }

  // The worker loads its script asynchronously and drops whatever is sent
  // before it is ready -- the snapshot, read at startup, arrived first.
  function post(message) {
    if (worker.ready) worker.sendMessage(message)
    else outbox.push(message)
  }

  function shaped(url, kind, data) {
    var p = Object.assign({}, parsing)
    delete p[url]
    parsing = p
    if (data === null) {
      fail({ url: url }, "Transitous sent something unreadable")
    } else {
      var c = cache
      c[url] = { t: Date.now(), data: data, kind: kind }
      prune(c)
      cache = c
      var f = failures
      delete f[url]
      failures = f
    }
    touch()
  }

  function fail(job, message) {
    var f = failures
    f[job.url] = { t: Date.now(), message: message }
    failures = f
  }

  // Eighty answers is every screen of a long session; past that the oldest go.
  function prune(c) {
    var keys = Object.keys(c)
    if (keys.length <= 80) return
    keys.sort(function (a, b) { return c[a].t - c[b].t })
    for (var i = 0; i < keys.length - 80; i++) delete c[keys[i]]
  }

  function answerFromFixture() {
    if (fixture === null) return
    var q = queue
    queue = []
    for (var i = 0; i < q.length; i++) {
      var answer = fixture[q[i].url]
      if (answer === undefined) continue
      var p = Object.assign({}, parsing)
      p[q[i].url] = true
      parsing = p
      post({ op: "shape", url: q[i].url, kind: q[i].kind, text: JSON.stringify(answer) })
    }
    touch()
  }

  FileView {
    path: root.sealed && root.fixtureDir ? root.fixtureDir + "/fixture.json" : ""
    printErrors: false
    onLoaded: {
      var answers = {}
      try { answers = JSON.parse(text()).answers || {} } catch (e) {}
      root.fixture = answers
      root.pump()
    }
    onLoadFailed: { root.fixture = {}; root.pump() }
  }

  WorkerScript {
    id: worker
    source: "Worker.mjs"
    onReadyChanged: {
      if (!ready) return
      var pending = root.outbox
      root.outbox = []
      for (var i = 0; i < pending.length; i++) worker.sendMessage(pending[i])
    }
    onMessage: function (m) {
      if (m.op === "shaped") root.shaped(m.url, m.kind, m.data)
      else if (m.op === "parsed" && m.entries) root.restore(m.entries)
    }
  }

  Timer {
    id: pumpTimer
    repeat: false
    onTriggered: root.pump()
  }

  Timer {
    id: timeout
    // A long-distance plan can take the router several seconds.
    interval: 25000
    onTriggered: {
      if (!root.xhr) return
      var req = root.xhr
      root.xhr = null
      req.abort()
      var job = { url: root.inflight, kind: "" }
      root.inflight = ""
      root.fail(job, "Transitous took too long to answer")
      root.touch()
      root.pump()
    }
  }

  // Drives the countdown in the banner, only while there is one.
  Timer {
    interval: 1000
    repeat: true
    running: root.blockedUntil > root.now
    onTriggered: root.now = Date.now()
  }
}
