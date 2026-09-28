import QtQuick
import Quickshell.Io
import "Api.mjs" as Api

// Every request to radio-browser.info goes through here: reads through a
// small queue with a cache, and the two fire-and-forget calls a player owes
// the directory (a listen and a vote).
//
// Views never hold a callback for a read. They ask for a path with want() and
// read it back with peek(), which follows `revision`, so a page closed
// mid-request has nothing to be called back on.
//
// Answers are cached by path, not by URL: the directory is a set of mirrors,
// and the same list is the same list whichever of them served it.
Item {
  id: root

  // Where requests go: any mirror at first, then one picked from the list
  // the directory publishes, which is how its operators ask to be used.
  property string server: Api.ANY_SERVER
  property bool serverPicked: false

  property int revision: 0
  // Can't reach the directory: the banner says so.
  property bool offline: false
  readonly property string banner: offline ? "Can't reach radio-browser.info · showing saved lists" : ""

  readonly property int parallel: 3
  readonly property int gap: 60

  property var cache: ({})      // path -> { t, data, kind }
  property var failures: ({})   // path -> { t, message, status }
  property var queue: []        // [{ path, kind }]
  property var parsing: ({})    // path -> true while the worker shapes it
  property var inflight: ({})   // path -> { req, job, t }
  property int inflightCount: 0
  property var outbox: []
  property real lastSent: 0

  // Sent with every request: the directory asks clients to say who they are.
  readonly property string agent: "Airwaves/" + version + " (+https://github.com/SimonSchubert/moarchy-apps)"
  property string version: "1.0"

  signal changed()

  // MOARCHY_AIRWAVES_OFFLINE: no request leaves the app. A read is answered
  // from `fixtureFile` -- what dev/capture.py recorded, by path -- through the
  // same worker a real answer goes through, and a path it has no answer for
  // is simply never answered: no error, no banner.
  property bool recorded: false
  property string fixtureFile: ""
  property var fixture: null

  FileView {
    path: root.recorded ? root.fixtureFile : ""
    printErrors: false
    onLoaded: {
      try { root.fixture = JSON.parse(text()) || ({}) } catch (e) { root.fixture = ({}) }
      root.pump()
    }
    onLoadFailed: { root.fixture = ({}); root.pump() }
  }

  function answerRecorded(job) {
    var data = fixture[job.path]
    if (data === undefined) return
    var p = parsing
    p[job.path] = true
    parsing = p
    post({ op: "shape", path: job.path, kind: job.kind, text: JSON.stringify(data) })
  }

  function touch() { Qt.callLater(root.bump) }
  function bump() { revision++; changed() }

  function peek(path) { var e = cache[path]; return e ? e.data : null }
  function age(path) { var e = cache[path]; return e ? Date.now() - e.t : Infinity }

  function busy(path) {
    if (!path) return false
    if (inflight[path] || parsing[path]) return true
    for (var i = 0; i < queue.length; i++) if (queue[i].path === path) return true
    return false
  }

  function error(path) {
    var f = failures[path]
    return f && !cache[path] ? f.message : ""
  }

  // Ask for `path` unless a copy younger than `ttl` ms is cached. `urgent`
  // puts it at the front: what was just tapped beats a list behind it.
  function want(path, kind, ttl, urgent) {
    if (!path) return
    if (age(path) < ttl) return
    var f = failures[path]
    if (f && Date.now() - f.t < 15000 && !urgent) return
    if (inflight[path]) return
    for (var i = 0; i < queue.length; i++) {
      if (queue[i].path !== path) continue
      if (urgent && i > 0) {
        var q = queue.slice()
        q.unshift(q.splice(i, 1)[0])
        queue = q
      }
      return
    }
    var job = { path: path, kind: kind }
    var next = queue.slice()
    if (urgent) next.unshift(job); else next.push(job)
    queue = next
    touch()
    pump()
  }

  // Due again on the next want(), shown meanwhile.
  function stale(test) {
    for (var path in cache) if (test(path)) cache[path].t = 0
    touch()
  }

  // Lists worth keeping on disk, freshest first, so the file stays small.
  function snapshot(kinds, limit) {
    var keys = Object.keys(cache).filter(function (p) { return kinds.indexOf(cache[p].kind) >= 0 })
    keys.sort(function (a, b) { return cache[b].t - cache[a].t })
    var out = {}
    for (var i = 0; i < keys.length && i < limit; i++) out[keys[i]] = cache[keys[i]]
    return out
  }

  function clear() { cache = {}; failures = {}; touch() }

  function restoreText(text) { if (text) post({ op: "parse", text: text }) }

  function restore(entries) {
    var c = {}
    for (var path in entries) {
      var e = entries[path]
      if (!e || e.data === undefined || typeof e.t !== "number" || path.indexOf("/json/") !== 0) continue
      c[path] = e
    }
    for (var k in cache) c[k] = cache[k]
    cache = c
    touch()
  }

  function pump() {
    if (recorded) {
      if (fixture === null) return
      var jobs = queue
      queue = []
      for (var j = 0; j < jobs.length; j++) answerRecorded(jobs[j])
      touch()
      return
    }
    while (inflightCount < parallel && queue.length) {
      var t = Date.now()
      var wait = lastSent + gap - t
      if (wait > 0) {
        pumpTimer.interval = wait + 10
        pumpTimer.restart()
        return
      }
      var q = queue.slice()
      var job = q.shift()
      queue = q
      sendGet(job)
    }
  }

  // How much of an answer is ever held. The largest real one -- every tag
  // with a station count -- is under 1 MB; a page of forty stations is 40 KB.
  // A logo is rarely past 100 KB.
  readonly property int maxJson: 4 * 1024 * 1024
  readonly property int maxBinary: 1024 * 1024

  // The app's only HTTP request. `binary` answers with an ArrayBuffer.
  // done(status, body, req); status -1 when the answer outgrew its limit.
  //
  // The limit holds while the answer arrives, not after: Qt reports every
  // chunk as a LOADING state change, so a body that passes the limit is
  // aborted there and its buffer dropped. A Content-Length over the limit
  // stops it before the first byte of the body.
  function request(url, binary, done) {
    var limit = binary ? maxBinary : maxJson
    var req = new XMLHttpRequest()
    var settled = false
    var give = function (status, data) {
      if (settled) return
      settled = true
      done(status, data, req)
    }
    var tooBig = function () {
      give(-1, null)
      req.abort()
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
    req.setRequestHeader("User-Agent", agent)
    if (!binary) req.setRequestHeader("Accept", "application/json")
    req.send()
    return req
  }

  function sendGet(job) {
    var sentAt = Date.now()
    lastSent = sentAt
    var base = server
    var req = request(base + job.path, false, function (status, body, r) {
      var f = root.inflight[job.path]
      if (!f || f.req !== r) return
      delete root.inflight[job.path]
      root.inflightCount--
      root.finish(job, status, body, base)
    })
    inflight[job.path] = { req: req, job: job, t: sentAt }
    inflightCount++
    touch()
  }

  function finish(job, status, body, base) {
    if (status === 200) {
      var p = parsing
      p[job.path] = true
      parsing = p
      offline = false
      post({ op: "shape", path: job.path, kind: job.kind, text: body })
    } else if (status === 0 && base !== Api.ANY_SERVER && !job.retried) {
      // The mirror picked is down: every other request goes to any mirror
      // from now on, starting with this one again.
      server = Api.ANY_SERVER
      job.retried = true
      requeue(job)
    } else if (status === -1) {
      fail(job.path, "The directory's answer was too large to use", status)
    } else if (status === 0) {
      offline = true
      fail(job.path, "Can't reach radio-browser.info", status)
    } else if (status === 404) {
      fail(job.path, "Not found in the directory", status)
    } else if (status === 429 || status === 503) {
      fail(job.path, "The directory is busy · try again in a moment", status)
    } else if (status >= 500) {
      fail(job.path, "The directory is having trouble (" + status + ")", status)
    } else {
      fail(job.path, "The directory answered " + status, status)
    }
    touch()
    Qt.callLater(root.pump)
  }

  function requeue(job) {
    var back = queue.slice()
    back.unshift(job)
    queue = back
  }

  function post(message) {
    if (worker.ready) worker.sendMessage(message)
    else outbox.push(message)
  }

  function shaped(path, kind, data) {
    var p = parsing
    delete p[path]
    parsing = p
    if (data === null) {
      fail(path, "The directory sent something unreadable", 200)
    } else if (kind === "servers") {
      // Not a list anybody looks at: which mirror to use from now on.
      if (data.length && !serverPicked) {
        serverPicked = true
        server = "https://" + data[Math.floor(Math.random() * data.length)]
      }
    } else {
      var c = cache
      c[path] = { t: Date.now(), data: data, kind: kind }
      prune(c)
      cache = c
      var f = failures
      delete f[path]
      failures = f
    }
    touch()
  }

  function fail(path, message, status) {
    var f = failures
    f[path] = { t: Date.now(), message: message, status: status }
    failures = f
  }

  // A hundred answers is every screen of a long session; past that the
  // oldest go.
  function prune(c) {
    var keys = Object.keys(c)
    if (keys.length <= 100) return
    keys.sort(function (a, b) { return c[a].t - c[b].t })
    for (var i = 0; i < keys.length - 100; i++) delete c[keys[i]]
  }

  // Once per run, before anything else: which mirror to talk to.
  function pickServer() {
    if (serverPicked || recorded) return
    want(Api.serversPath(), "servers", 0, true)
  }

  // ------------------------------------------------------------ writes

  // A listen, counted: what makes "popular" and "trending" mean something.
  // The answer is not needed.
  function click(id) {
    if (!Api.uuid(id) || recorded) return
    request(server + Api.clickPath(id), false, function () {})
  }

  // One vote per station and address every ten minutes; the directory says
  // which, in words. done(ok, message)
  function vote(id, done) {
    if (!Api.uuid(id)) return
    if (recorded) { done(false, "This copy is running offline"); return }
    request(server + Api.votePath(id), false, function (status, text) {
      var j = null
      try { j = JSON.parse(text) } catch (e) { j = null }
      var ok = status === 200 && j && j.ok === true
      done(ok, j && typeof j.message === "string" ? Api.clean(j.message, 120) : "")
    })
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
      if (m.op === "shaped") root.shaped(m.path, m.kind, m.data)
      else if (m.op === "parsed" && m.entries) root.restore(m.entries)
    }
  }

  Timer { id: pumpTimer; onTriggered: root.pump() }

  // A request that has hung is given up, so its place frees.
  Timer {
    interval: 5000
    repeat: true
    running: root.inflightCount > 0
    onTriggered: {
      var t = Date.now()
      for (var path in root.inflight) {
        var f = root.inflight[path]
        if (t - f.t < 20000) continue
        delete root.inflight[path]
        root.inflightCount--
        f.req.abort()
        root.fail(path, "radio-browser.info took too long to answer", 0)
      }
      root.touch()
      root.pump()
    }
  }
}
