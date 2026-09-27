import QtQuick
import "Api.mjs" as Api

// Every request to CoinGecko goes through here, one at a time.
//
// The public API allows somewhere between five and fifteen calls a minute and
// answers anything faster with 429, so the queue spaces requests out, keeps
// every answer for as long as it is worth keeping, and stops for as long as
// CoinGecko says when it is told to. Views never hold a callback: they ask for
// a URL with want() and read it back with peek(), which follows `revision`.
// A view destroyed mid-request has nothing to be called back on.
Item {
  id: root

  property string apiKey: ""
  property string currency: "usd"
  property bool active: true

  // Bumped on every change to the cache or to what is in flight. Bindings
  // read it to re-evaluate peek(), status() and error().
  property int revision: 0

  // Rate-limit and connectivity state, for the strip under the header.
  property real blockedUntil: 0
  property real now: Date.now()
  property bool offline: false
  readonly property int waitSeconds: Math.max(0, Math.ceil((blockedUntil - now) / 1000))
  readonly property string banner: waitSeconds > 0
    ? "CoinGecko rate limit reached · retrying in " + waitSeconds + " s"
    : offline ? "Can't reach CoinGecko · showing saved prices" : ""

  // With a Demo key CoinGecko allows 30 calls a minute; without one, the
  // conservative end of what the public tier tolerates.
  readonly property int gap: apiKey ? 2100 : 3200

  property var cache: ({})     // url -> { t, data }
  property var failures: ({})  // url -> { t, message }
  property var queue: []       // [{ url, kind, cur }]
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
    var job = { url: url, kind: kind, cur: currency }
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

  // The answers worth keeping on disk: lists, not coin pages or charts, and
  // only the freshest few so the file stays small.
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

  // The app's only HTTP request, for the API and for logos alike. `binary`
  // answers with an ArrayBuffer instead of text. done(status, body, req).
  // How much of an answer is ever held. The largest real ones -- a coin's
  // whole price history, 250 coins with sparklines -- are about 1 MB of JSON;
  // a logo is 1 to 20 KB.
  readonly property int maxJson: 8 * 1024 * 1024
  readonly property int maxImage: 300 * 1024

  // The app's only HTTP request, for the API and for logos alike. `binary`
  // answers with an ArrayBuffer instead of text. done(status, body, req);
  // status -1 when the answer outgrew `limit`.
  //
  // The limit holds while the answer arrives, not after: a Content-Length
  // over it stops the request before the body, and Qt reports every received
  // chunk as a LOADING state change, so a body that passes it is dropped
  // there. The abort itself waits one turn of the event loop: abort() from
  // inside Qt's HEADERS_RECEIVED notification crashes the whole shell
  // (SIGSEGV, reproduced on quickshell 0.3.1 / Qt 6.11).
  function get(url, headers, binary, done, limit) {
    var req = new XMLHttpRequest()
    var settled = false
    var give = function (status, data) {
      if (settled) return
      settled = true
      done(status, data, req)
    }
    var tooBig = function () {
      give(-1, null)
      Qt.callLater(function () { req.abort() })
    }
    if (binary) req.responseType = "arraybuffer"
    req.onreadystatechange = function () {
      if (settled) return
      if (req.readyState === 2) {
        var declared = parseInt(req.getResponseHeader("content-length"), 10)
        if (isFinite(declared) && declared > limit) tooBig()
      } else if (req.readyState === 3) {
        var size = binary ? (req.response ? req.response.byteLength : 0) : req.responseText.length
        if (size > limit) tooBig()
      } else if (req.readyState === 4) {
        var data = binary ? req.response : req.responseText
        if (data && (binary ? data.byteLength : data.length) > limit) tooBig()
        else give(req.status, data)
      }
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
    var headers = { "Accept": "application/json" }
    if (apiKey) headers["x-cg-demo-api-key"] = apiKey
    var req = get(job.url, headers, false, function (status, body, r) {
      if (xhr !== r) return
      timeout.stop()
      xhr = null
      finish(job, status, body, status > 0 ? r.getResponseHeader("retry-after") : "")
    }, maxJson)
    xhr = req
    timeout.restart()
  }

  function finish(job, status, body, retryAfter) {
    inflight = ""
    if (status === 200) {
      // Shaped on the worker; the queue moves on meanwhile.
      var p = parsing
      p[job.url] = true
      parsing = p
      offline = false
      post({ op: "shape", url: job.url, kind: job.kind, cur: job.cur, text: body })
    } else if (status === 429) {
      var secs = parseInt(retryAfter, 10)
      blockedUntil = Date.now() + (isFinite(secs) && secs > 0 ? Math.min(secs, 300) : 60) * 1000
      now = Date.now()
      var back = queue.slice()
      back.unshift(job)
      queue = back
    } else if (status === -1) {
      fail(job, "CoinGecko's answer was too large to use")
    } else if (status === 0) {
      offline = true
      fail(job, "Can't reach CoinGecko")
    } else if (status === 401 || status === 403) {
      fail(job, apiKey ? "CoinGecko refused the API key" : "CoinGecko refused the request")
    } else if (status === 404) {
      fail(job, "Not found on CoinGecko")
    } else {
      fail(job, "CoinGecko error " + status)
    }
    touch()
    pump()
  }

  // The worker loads its script asynchronously and drops whatever is sent
  // before it is ready -- the snapshot, read at startup, arrived first.
  function post(message) {
    if (worker.ready) worker.sendMessage(message)
    else outbox.push(message)
  }

  function shaped(url, kind, data) {
    var p = parsing
    delete p[url]
    parsing = p
    if (data === null) {
      fail({ url: url }, "CoinGecko sent something unreadable")
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

  // Sixty answers is every screen of a long session; past that the oldest go.
  function prune(c) {
    var keys = Object.keys(c)
    if (keys.length <= 60) return
    keys.sort(function (a, b) { return c[a].t - c[b].t })
    for (var i = 0; i < keys.length - 60; i++) delete c[keys[i]]
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
    interval: 15000
    onTriggered: {
      if (!root.xhr) return
      var req = root.xhr
      root.xhr = null
      req.abort()
      var job = { url: root.inflight, kind: "", cur: root.currency }
      root.inflight = ""
      root.fail(job, "CoinGecko took too long to answer")
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
