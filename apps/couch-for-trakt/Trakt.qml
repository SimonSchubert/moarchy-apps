import QtQuick
import Quickshell
import Quickshell.Io
import "Api.mjs" as Api
import "Keys.mjs" as Keys

// Every request to Trakt goes through here: reads through a small queue with a
// cache, writes straight away, and the sign-in.
//
// Views never hold a callback for a read. They ask for a URL with want() and
// read it back with peek(), which follows `revision`, so a page closed
// mid-request has nothing to be called back on. Trakt allows 1,000 reads per
// five minutes per app and user; three at a time, a little apart, stays well
// inside that and still fills a screen of posters in one round trip.
Item {
  id: root

  property var store: null

  // MOARCHY_COUCH_FOR_TRAKT_OFFLINE: never open a socket. A GET is answered
  // from fixture.json in MOARCHY_COUCH_FOR_TRAKT_DIR -- Trakt's answers by
  // URL, which dev/demo.py puts there for the screenshots -- or as not
  // found; anything else as Trakt having trouble, which keeps the sign-in.
  readonly property bool fixtureMode: (Quickshell.env("MOARCHY_COUCH_FOR_TRAKT_OFFLINE") || "") !== ""
  readonly property string fixtureDir: Quickshell.env("MOARCHY_COUCH_FOR_TRAKT_DIR") || ""
  property var fixture: null

  // The built-in app unless Settings names another one.
  readonly property string clientId: store && store.clientId ? store.clientId : Keys.CLIENT_ID
  readonly property string clientSecret: store && store.clientId ? store.clientSecret : Keys.CLIENT_SECRET
  readonly property bool configured: /^[A-Za-z0-9_-]{20,128}$/.test(clientId)
  readonly property string access: store && store.auth ? store.auth.access : ""
  readonly property bool signedIn: access !== ""

  property int revision: 0

  property real blockedUntil: 0
  property real now: Date.now()
  property bool offline: false
  readonly property int waitSeconds: Math.max(0, Math.ceil((blockedUntil - now) / 1000))
  readonly property string banner: waitSeconds > 0
    ? "Trakt asked to slow down · retrying in " + waitSeconds + " s"
    : offline ? "Can't reach Trakt · showing saved lists" : ""

  readonly property int parallel: 3
  readonly property int gap: 120

  property var cache: ({})      // url -> { t, data, kind, pages }
  property var failures: ({})   // url -> { t, message, status }
  property var queue: []        // [{ url, kind }]
  property var parsing: ({})    // url -> true while the worker shapes it
  property var inflight: ({})   // url -> { req, job, t }
  property int inflightCount: 0
  property var outbox: []
  property real lastSent: 0

  signal changed()
  // A personal answer arrived that was asked for at `sentAt`.
  signal landed(string url, real sentAt)

  function touch() { Qt.callLater(root.bump) }
  function bump() { revision++; changed() }

  function peek(url) { var e = cache[url]; return e ? e.data : null }
  function pages(url) { var e = cache[url]; return e && e.pages ? e.pages : 1 }
  function age(url) { var e = cache[url]; return e ? Date.now() - e.t : Infinity }

  function busy(url) {
    if (!url) return false
    if (inflight[url] || parsing[url]) return true
    for (var i = 0; i < queue.length; i++) if (queue[i].url === url) return true
    return false
  }

  function error(url) {
    var f = failures[url]
    return f && !cache[url] ? f.message : ""
  }

  // Ask for `url` unless a copy younger than `ttl` ms is cached. `urgent`
  // puts it at the front: what was just tapped beats a list behind it.
  function want(url, kind, ttl, urgent) {
    if (!url || !configured) return
    if (Api.personal(url) && !signedIn) return
    if (age(url) < ttl) return
    var f = failures[url]
    if (f && Date.now() - f.t < 15000 && !urgent) return
    if (inflight[url]) return
    for (var i = 0; i < queue.length; i++) {
      if (queue[i].url !== url) continue
      if (urgent && i > 0) {
        var q = queue.slice()
        q.unshift(q.splice(i, 1)[0])
        queue = q
      }
      return
    }
    var job = { url: url, kind: kind }
    var next = queue.slice()
    if (urgent) next.unshift(job); else next.push(job)
    queue = next
    touch()
    pump()
  }

  // A page closed before its turn came: nobody will read the answer.
  function forget(urls) {
    var keep = queue.filter(function (j) { return urls.indexOf(j.url) < 0 })
    if (keep.length !== queue.length) { queue = keep; touch() }
  }

  // Due again on the next want(), shown meanwhile: after a write that changes
  // what these answers would say.
  function stale(test) {
    for (var url in cache) if (test(url)) cache[url].t = 0
    touch()
  }

  // Lists worth keeping on disk, freshest first, so the file stays small.
  function snapshot(kinds, limit) {
    var keys = Object.keys(cache).filter(function (u) { return kinds.indexOf(cache[u].kind) >= 0 })
    keys.sort(function (a, b) { return cache[b].t - cache[a].t })
    var out = {}
    for (var i = 0; i < keys.length && i < limit; i++) out[keys[i]] = cache[keys[i]]
    return out
  }

  function clear() { cache = {}; failures = {}; touch() }

  function clearPersonal() {
    var c = {}
    for (var url in cache) if (!Api.personal(url)) c[url] = cache[url]
    cache = c
    failures = {}
    queue = queue.filter(function (j) { return !Api.personal(j.url) })
    touch()
  }

  function restoreText(text) { if (text) post({ op: "parse", text: text }) }

  function restore(entries) {
    var c = {}
    for (var url in entries) {
      var e = entries[url]
      if (!e || e.data === undefined || typeof e.t !== "number" || url.indexOf(Api.BASE + "/") !== 0) continue
      // Somebody's own lists come back only while they are signed in.
      if (Api.personal(url) && !signedIn) continue
      c[url] = e
    }
    for (var k in cache) c[k] = cache[k]
    cache = c
    touch()
  }

  function pump() {
    while (inflightCount < parallel && queue.length) {
      var t = Date.now()
      var wait = Math.max(blockedUntil - t, lastSent + gap - t)
      if (wait > 0) {
        pumpTimer.interval = Math.min(wait + 10, 120000)
        pumpTimer.restart()
        return
      }
      if (refreshing && Api.personal(queue[0].url)) return   // after the new token
      var q = queue.slice()
      var job = q.shift()
      queue = q
      sendGet(job)
    }
  }

  function headers(personal) {
    var h = { "Content-Type": "application/json", "trakt-api-version": "2", "trakt-api-key": clientId }
    if (personal && access) h["Authorization"] = "Bearer " + access
    return h
  }

  // How much of an answer is ever held. The largest real ones -- a big
  // watchlist, years of ratings -- are a few megabytes of JSON; a 250-title
  // page with everything is 430 KB. Pictures are 20 to 150 KB; a sign-in or a
  // write answers in a few hundred bytes.
  readonly property int maxJson: 8 * 1024 * 1024
  readonly property int maxBinary: 2 * 1024 * 1024
  readonly property int maxSmall: 256 * 1024

  // The app's only HTTP request. `binary` answers with an ArrayBuffer.
  // done(status, body, req); status -1 when the answer outgrew its limit.
  //
  // The limit holds while the answer arrives, not after: Qt reports every
  // chunk as a LOADING state change, so a body that passes the limit is
  // aborted there and its buffer dropped. A Content-Length over the limit
  // stops it before the first byte of the body.
  function request(method, url, hdrs, body, binary, done) {
    if (fixtureMode) return answerFromFixture(method, url, done)
    var limit = binary ? maxBinary : method === "GET" ? maxJson : maxSmall
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
    req.open(method, url)
    for (var h in hdrs) req.setRequestHeader(h, hdrs[h])
    req.send(body === undefined || body === null ? null : JSON.stringify(body))
    return req
  }

  function answerFromFixture(method, url, done) {
    if (fixture === null) {
      try { fixture = JSON.parse(fixtureView.text()) || {} } catch (e) { fixture = {} }
    }
    var saved = method === "GET" ? fixture[url] : undefined
    var req = { abort: function () {}, getResponseHeader: function () { return null } }
    Qt.callLater(function () {
      if (saved !== undefined) done(200, JSON.stringify(saved), req)
      else done(method === "GET" ? 404 : 503, "", req)
    })
    return req
  }

  FileView {
    id: fixtureView
    path: root.fixtureMode && root.fixtureDir ? root.fixtureDir + "/fixture.json" : ""
    blockLoading: true
    printErrors: false
  }

  function sendGet(job) {
    var personal = Api.personal(job.url)
    var sentAt = Date.now()
    lastSent = sentAt
    var req = request("GET", job.url, headers(personal), null, false, function (status, body, r) {
      var f = root.inflight[job.url]
      if (!f || f.req !== r) return
      delete root.inflight[job.url]
      root.inflightCount--
      root.finish(job, status, body, r, personal, sentAt)
    })
    inflight[job.url] = { req: req, job: job, t: sentAt }
    inflightCount++
    touch()
  }

  function finish(job, status, body, r, personal, sentAt) {
    if (status === 204) {
      // Nothing to say, which for a new account is the answer: an empty one.
      shaped(job.url, job.kind, 1, sentAt, job.kind === "stats" ? {} : [])
    } else if (status === 200) {
      var p = parsing
      p[job.url] = true
      parsing = p
      offline = false
      var pc = parseInt(r.getResponseHeader("x-pagination-page-count"), 10)
      post({ op: "shape", url: job.url, kind: job.kind, pages: isFinite(pc) && pc > 0 ? pc : 1, text: body, sentAt: sentAt })
    } else if (status === 429) {
      var secs = parseInt(r.getResponseHeader("retry-after"), 10)
      blockedUntil = Date.now() + (isFinite(secs) && secs > 0 ? Math.min(secs, 300) : 30) * 1000
      now = Date.now()
      requeue(job)
    } else if (status === 401 && personal && store.auth && store.auth.refresh && !job.renewed) {
      job.renewed = true
      requeue(job)
      renew()
    } else if (status === -1) {
      fail(job.url, "Trakt's answer was too large to use", status)
    } else if (status === 0) {
      offline = true
      fail(job.url, "Can't reach Trakt", status)
    } else if (status === 401 || status === 403) {
      fail(job.url, !configured ? "No Trakt app is set up" : personal ? "Trakt wants you to sign in again"
        : "Trakt refused the request (" + status + ")", status)
    } else if (status === 404) {
      fail(job.url, "Not found on Trakt", status)
    } else if (status >= 500) {
      fail(job.url, "Trakt is having trouble (" + status + ")", status)
    } else {
      fail(job.url, "Trakt error " + status, status)
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

  function shaped(url, kind, pageCount, sentAt, data) {
    var p = parsing
    delete p[url]
    parsing = p
    if (data === null) {
      fail(url, "Trakt sent something unreadable", 200)
    } else {
      var c = cache
      c[url] = { t: Date.now(), data: data, kind: kind, pages: pageCount }
      prune(c)
      cache = c
      var f = failures
      delete f[url]
      failures = f
      if (Api.personal(url)) landed(url, sentAt)
    }
    touch()
  }

  function fail(url, message, status) {
    var f = failures
    f[url] = { t: Date.now(), message: message, status: status }
    failures = f
  }

  // Ninety answers is every screen of a long session; past that the oldest go.
  function prune(c) {
    var keys = Object.keys(c)
    if (keys.length <= 90) return
    keys.sort(function (a, b) { return c[a].t - c[b].t })
    for (var i = 0; i < keys.length - 90; i++) delete c[keys[i]]
  }

  // ------------------------------------------------------------ writes

  // POST to the API as the signed-in person, now. done(ok, status, json).
  // A 401 renews the token once and tries again.
  function write(path, body, done, retried) {
    if (!signedIn) { if (done) done(false, 401, null); return }
    request("POST", Api.BASE + path, headers(true), body, false, function (status, text, r) {
      if (status === 401 && !retried && store.auth && store.auth.refresh) {
        root.renew(function (ok) {
          if (ok) root.write(path, body, done, true)
          else if (done) done(false, 401, null)
        })
        return
      }
      if (status === 429) {
        var secs = parseInt(r.getResponseHeader("retry-after"), 10)
        root.blockedUntil = Date.now() + (isFinite(secs) && secs > 0 ? Math.min(secs, 300) : 30) * 1000
        root.now = Date.now()
      }
      var json = null
      try { json = text ? JSON.parse(text) : null } catch (e) { json = null }
      if (done) done(status >= 200 && status < 300, status, json)
    })
  }

  // ------------------------------------------------------------ sign-in
  //
  // Trakt's device flow: ask for a code, show it, and poll until the person
  // has typed it in at trakt.tv/activate on any device. Nothing to paste back,
  // which on a phone is the difference between signing in and giving up.

  property string authState: ""      // "", "asking", "code", "waiting", "done", "failed"
  property string authMessage: ""
  property string userCode: ""
  property string verifyUrl: ""
  property string deviceCode: ""
  property real codeExpires: 0

  function beginSignIn() {
    if (!configured) { authState = "failed"; authMessage = "No Trakt app is set up. Add a client ID and secret below."; return }
    authState = "asking"
    authMessage = ""
    userCode = ""
    request("POST", Api.BASE + "/oauth/device/code", headers(false), { client_id: clientId }, false, function (status, text) {
      if (root.authState !== "asking") return
      var j = null
      try { j = JSON.parse(text) } catch (e) { j = null }
      if (status !== 200 || !j || typeof j.device_code !== "string" || typeof j.user_code !== "string") {
        root.authState = "failed"
        root.authMessage = status === 0 ? "Can't reach Trakt." : "Trakt didn't hand out a code (" + status + ")."
        return
      }
      root.deviceCode = j.device_code
      root.userCode = Api.str(j.user_code, 16).replace(/[^A-Za-z0-9]/g, "")
      var v = Api.httpsUrl(j.verification_url)
      root.verifyUrl = /^https:\/\/([a-z.]+\.)?trakt\.tv\//.test(v) ? v : "https://trakt.tv/activate"
      root.codeExpires = Date.now() + Math.max(60, Math.min(1800, Number(j.expires_in) || 600)) * 1000
      pollTimer.interval = Math.max(2, Math.min(30, Number(j.interval) || 5)) * 1000
      pollTimer.restart()
      root.authState = "code"
    })
  }

  function cancelSignIn() {
    pollTimer.stop()
    deviceCode = ""
    authState = ""
    authMessage = ""
  }

  function poll() {
    if (!deviceCode) return
    if (Date.now() > codeExpires) {
      cancelSignIn()
      authState = "failed"
      authMessage = "The code expired. Get a new one."
      return
    }
    var code = deviceCode
    request("POST", Api.BASE + "/oauth/device/token", headers(false),
      { code: code, client_id: clientId, client_secret: clientSecret }, false, function (status, text) {
      if (root.deviceCode !== code) return
      if (status === 200) {
        var j = null
        try { j = JSON.parse(text) } catch (e) { j = null }
        if (j && root.accept(j)) {
          root.cancelSignIn()
          root.authState = "done"
          return
        }
        status = -1
      }
      if (status === 400 || status === 0) { pollTimer.restart(); return }   // not yet
      if (status === 429) { pollTimer.interval += 1000; pollTimer.restart(); return }
      root.cancelSignIn()
      root.authState = "failed"
      root.authMessage = status === 418 ? "Sign-in was declined on Trakt."
        : status === 410 ? "The code expired. Get a new one."
        : status === 409 ? "That code was already used. Get a new one."
        : "Trakt didn't accept the sign-in (" + status + ")."
    })
  }

  // A token answer, from the device flow or a refresh. False if unusable.
  function accept(j) {
    if (typeof j.access_token !== "string" || typeof j.refresh_token !== "string" || !j.access_token) return false
    var created = Number(j.created_at) > 0 ? Number(j.created_at) * 1000 : Date.now()
    var life = Number(j.expires_in) > 0 ? Number(j.expires_in) * 1000 : 7 * 86400000
    store.setAuth({
      access: j.access_token.slice(0, 200),
      refresh: j.refresh_token.slice(0, 200),
      expires: created + life,
      user: store.auth && store.auth.user ? store.auth.user : null
    })
    touch()
    want(Api.settingsUrl(), "settings", 0, true)
    return true
  }

  // One refresh at a time, whoever asks. Refresh tokens are single-use: two
  // at once and the second would sign the person out.
  property bool refreshing: false
  property var waiters: []

  function renew(cb) {
    if (cb) waiters.push(cb)
    if (refreshing) return
    var a = store.auth
    if (!a || !a.refresh) { settle(false); return }
    refreshing = true
    request("POST", Api.BASE + "/oauth/token", headers(false), {
      refresh_token: a.refresh, client_id: clientId, client_secret: clientSecret,
      redirect_uri: "urn:ietf:wg:oauth:2.0:oob", grant_type: "refresh_token"
    }, false, function (status, text) {
      root.refreshing = false
      var j = null
      try { j = JSON.parse(text) } catch (e) { j = null }
      if (status === 200 && j && root.accept(j)) { root.settle(true); return }
      // Offline, Trakt down, or an answer too large to read: keep the
      // tokens, try again later.
      if (status <= 0 || status >= 500) { root.settle(false); return }
      root.forgetUser("Trakt signed you out. Sign in again to see your lists.")
      root.settle(false)
    })
  }

  function settle(ok) {
    var w = waiters
    waiters = []
    for (var i = 0; i < w.length; i++) w[i](ok)
    pump()
  }

  // Refreshed a day early rather than on the first 401: one round trip at a
  // quiet moment instead of a failed screen.
  function keepFresh() {
    var a = store ? store.auth : null
    if (a && a.refresh && Number(a.expires) - Date.now() < 86400000) renew()
  }

  property string signedOutMessage: ""

  function forgetUser(message) {
    store.setAuth(null)
    signedOutMessage = message || ""
    clearPersonal()
  }

  function signOut() {
    var a = store.auth
    if (a && a.access)
      request("POST", Api.BASE + "/oauth/revoke", headers(false),
        { token: a.access, client_id: clientId, client_secret: clientSecret }, false, function () {})
    forgetUser("")
  }

  // The name and avatar, once they arrive.
  Connections {
    target: root
    function onRevisionChanged() {
      if (!root.signedIn) return
      var s = root.peek(Api.settingsUrl())
      var a = root.store.auth
      if (s && a && (!a.user || a.user.username !== s.username || a.user.avatar !== s.avatar)) {
        var n = Object.assign({}, a)
        n.user = s
        root.store.set("auth", n)
      }
    }
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
      if (m.op === "shaped") root.shaped(m.url, m.kind, m.pages, m.sentAt, m.data)
      else if (m.op === "parsed" && m.entries) root.restore(m.entries)
    }
  }

  Timer { id: pumpTimer; onTriggered: root.pump() }

  Timer {
    id: pollTimer
    onTriggered: root.poll()
  }

  // A request that has hung is given up, so its place frees.
  Timer {
    interval: 5000
    repeat: true
    running: root.inflightCount > 0
    onTriggered: {
      var t = Date.now()
      for (var url in root.inflight) {
        var f = root.inflight[url]
        if (t - f.t < 20000) continue
        delete root.inflight[url]
        root.inflightCount--
        f.req.abort()
        root.fail(url, "Trakt took too long to answer", 0)
      }
      root.touch()
      root.pump()
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.blockedUntil > root.now
    onTriggered: root.now = Date.now()
  }

  Timer {
    interval: 3600000
    repeat: true
    running: root.signedIn
    triggeredOnStart: true
    onTriggered: root.keepFresh()
  }
}
