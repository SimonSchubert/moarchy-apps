import QtQuick
import Quickshell
import Quickshell.Io
import "Api.mjs" as Api

// Coin logos on disk, so a logo is downloaded once rather than once per
// shell start: Qt keeps network images in memory only.
//
//     source: app.logos.revision, app.logos.source(url)
//
// source() answers a file:// URL when the logo is on disk, and "" while it is
// being fetched (CoinLogo draws initials meanwhile), then the file once it is
// written. Each logo is fetched once, straight to disk, and read from there.
//
// FileView can write a file but not delete one, so the cache is a fixed ring
// of `slots` places reused in turn, and it never grows past twice that many
// files. Qt caches decoded images by URL, so a reused slot must not reuse the
// URL: each slot alternates between two file names, and the logo it held last
// keeps its own. (A query string would have done it, but Qt opens file URLs
// with the query as part of the name.) 1,500 slots hold the top 1,000 with
// room to spare, so a slot comes round again rarely within a session.
//
// Each file is written by a FileView of its own, synchronously. One FileView
// pointed at file after file drops every write after the first, and an
// asynchronous write reports `saved` before the bytes are there to open. A
// 3 KB logo written on the spot costs well under a millisecond.
Item {
  id: root
  property var app
  property string dir: ""
  readonly property int slots: 1500
  readonly property int parallel: 4

  // { version, next, gen: [per slot], urls: { url: slot }, owners: [url per slot] }
  property var index: ({ version: 1, next: 0, gen: [], urls: {}, owners: [] })
  property bool loaded: false
  property int revision: 0

  property var queue: []
  property var active: ({})     // url -> { req, t }, mutated in place
  property int activeCount: 0
  property var failed: ({})     // url -> true, for this session
  property var healed: ({})     // url -> true once re-fetched this session

  function extension(url) {
    var m = /\.(png|jpe?g|webp|gif)(\?|$)/i.exec(url)
    return m ? m[1].toLowerCase() : "png"
  }

  function fileOf(slot, gen, url) { return root.dir + "/" + slot + "-" + (gen % 2) + "." + extension(url) }

  function source(url) {
    if (!url || !loaded) return ""
    var slot = index.urls[url]
    if (slot !== undefined) return "file://" + fileOf(slot, index.gen[slot] || 0, url)
    // A logo that could not be cached is not loaded some other way: an
    // Image would fetch it with no size limit. The initials stand in.
    if (failed[url]) return ""
    fetch(url)
    return ""
  }

  // A cached file that would not open -- the directory was cleared behind
  // our back -- is forgotten and fetched again, once per logo and session;
  // after that the network, not a loop.
  function invalidate(url) {
    if (index.urls[url] === undefined) return
    if (healed[url]) failed[url] = true
    healed[url] = true
    delete index.urls[url]
    saveIndex.restart()
    revision++
  }

  function fetch(url) {
    if (!Api.imageUrl(url)) { failed[url] = true; return }
    if (active[url] || queue.indexOf(url) >= 0) return
    // Newest first: the logos of the rows on screen now, not of a list
    // scrolled past a second ago.
    queue.unshift(url)
    if (queue.length > 200) queue.length = 200
    Qt.callLater(root.pump)
  }

  function pump() {
    while (queue.length && activeCount < parallel) {
      var url = queue.shift()
      if (index.urls[url] !== undefined || active[url]) continue
      start(url)
    }
  }

  function start(url) {
    var req = app.gecko.get(url, {}, true, function (status, body, r) {
      var a = root.active
      if (!a[url] || a[url].req !== r) return
      delete a[url]
      root.activeCount--
      // An image, and a small one: nothing else goes to disk.
      var type = status > 0 ? String(r.getResponseHeader("content-type") || "") : ""
      if (status === 200 && body && body.byteLength > 0 && /^image\//.test(type))
        root.store(url, body)
      else
        root.failed[url] = true
      root.revision++
      Qt.callLater(root.pump)
    }, app.gecko.maxImage)
    active[url] = { req: req, t: Date.now() }
    activeCount++
  }

  property bool writeOk: true

  function store(url, data) {
    var ix = index
    var slot = ix.next
    var gen = (ix.gen[slot] || 0) + 1
    writeOk = true
    var w = writer.createObject(root, { path: fileOf(slot, gen, url) })
    w.setData(data)
    w.destroy()
    if (!writeOk) { failed[url] = true; return }
    var old = ix.owners[slot]
    if (old !== undefined && ix.urls[old] === slot) delete ix.urls[old]
    ix.owners[slot] = url
    ix.urls[url] = slot
    ix.gen[slot] = gen
    ix.next = (slot + 1) % slots
    index = ix
    saveIndex.restart()
  }

  Component {
    id: writer
    FileView {
      preload: false
      blockWrites: true
      atomicWrites: false
      printErrors: false
      onSaveFailed: root.writeOk = false
    }
  }

  // A request that has hung is given up, so its place in `parallel` frees.
  Timer {
    interval: 5000
    repeat: true
    running: root.activeCount > 0
    onTriggered: {
      var now = Date.now()
      for (var url in root.active) {
        var a = root.active[url]
        if (now - a.t < 20000) continue
        delete root.active[url]
        root.activeCount--
        root.failed[url] = true
        a.req.abort()
        root.revision++
      }
      root.pump()
    }
  }

  Timer {
    id: saveIndex
    interval: 2000
    onTriggered: indexFile.setText(JSON.stringify(root.index))
  }

  FileView {
    id: indexFile
    path: root.dir ? root.dir + "/index.json" : ""
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        var ix = JSON.parse(text())
        if (ix && ix.version === 1 && ix.urls && Array.isArray(ix.owners) && Array.isArray(ix.gen)) {
          ix.next = Math.max(0, Math.min(root.slots - 1, Number(ix.next) || 0))
          root.index = ix
        }
      } catch (e) {}
      root.loaded = true
      root.revision++
    }
    onLoadFailed: { root.loaded = true; root.revision++ }
  }
}
