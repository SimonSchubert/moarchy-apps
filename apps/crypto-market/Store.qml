import QtQuick
import Quickshell
import Quickshell.Io
import "Api.mjs" as Api

// What the app remembers: preferences, the watchlist and the portfolio in
// ~/.local/state, and the last prices it saw in ~/.cache so the first screen
// is never empty, even offline.
//
// Kept in files of its own rather than shell.json: the host lets only bar
// widgets write their settings back, and a watchlist is not a setting.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/crypto-market"
  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/crypto-market"

  readonly property var defaults: ({
    version: 1,
    currency: "usd",
    apiKey: "",
    topN: 100,
    refreshSec: 120,
    watchlist: ["bitcoin", "ethereum", "solana"],
    holdings: {},
    lastTab: "markets",
    launcher: true,
    launcherAdded: false
  })

  property var prefs: defaults
  property bool ready: false

  readonly property string currency: Api.validCurrency(prefs.currency) ? prefs.currency : "usd"
  readonly property string apiKey: typeof prefs.apiKey === "string" ? prefs.apiKey : ""
  readonly property int topN: [100, 250, 500, 1000].indexOf(prefs.topN) >= 0 ? prefs.topN : 100
  readonly property int refreshSec: Math.max(60, Math.min(3600, Number(prefs.refreshSec) || 120))
  readonly property var watchlist: Array.isArray(prefs.watchlist) ? prefs.watchlist : []
  readonly property var holdings: prefs.holdings && typeof prefs.holdings === "object" ? prefs.holdings : ({})

  // The saved snapshot as text; Gecko parses it on its worker thread.
  signal snapshotLoaded(string text)

  function set(key, value) {
    var s = Object.assign({}, prefs)
    s[key] = value
    prefs = s
    saveTimer.restart()
  }

  function starred(id) { return watchlist.indexOf(id) >= 0 }

  function toggleStar(id) {
    if (!Api.safeId(id)) return
    var w = watchlist.slice()
    var i = w.indexOf(id)
    if (i >= 0) w.splice(i, 1); else w.push(id)
    set("watchlist", w)
  }

  // Holdings are kept per coin with the name and logo beside them, so the
  // portfolio can draw a row before the prices for it have arrived.
  function addTx(coin, tx) {
    if (!coin || !Api.safeId(coin.id)) return
    var h = Object.assign({}, holdings)
    var entry = h[coin.id] ? Object.assign({}, h[coin.id]) : { txs: [] }
    entry.name = coin.name
    entry.symbol = coin.symbol
    entry.image = coin.image || entry.image || ""
    entry.txs = (entry.txs || []).concat([tx])
    h[coin.id] = entry
    set("holdings", h)
  }

  function removeTx(id, ts) {
    var h = Object.assign({}, holdings)
    if (!h[id]) return
    var entry = Object.assign({}, h[id])
    entry.txs = (entry.txs || []).filter(function (t) { return t.ts !== ts })
    if (entry.txs.length) h[id] = entry; else delete h[id]
    set("holdings", h)
  }

  function saveSnapshot(entries) {
    if (!secured) return
    try { snapshotFile.setText(JSON.stringify({ version: 1, entries: entries })) } catch (e) {}
  }

  function clearSnapshot() { saveSnapshot({}) }

  // A change still waiting out saveTimer is written now. For the standalone
  // app, which ends its process when the window closes.
  function flush() {
    if (!saveTimer.running) return
    saveTimer.stop()
    if (root.ready && root.secured) stateFile.setText(JSON.stringify(root.prefs, null, 1))
  }

  Timer {
    id: saveTimer
    interval: 400
    onTriggered: {
      if (!root.ready) { restart(); return }
      // Not yet private: try again shortly. Failed: changes stay in memory.
      if (!root.secured) { if (!root.warning) restart(); return }
      stateFile.setText(JSON.stringify(root.prefs, null, 1))
    }
  }

  // ------------------------------------------------------------ privacy
  //
  // prefs.json holds the API key and the portfolio, and the snapshot names
  // the coins in it. FileView has no say in permissions: it creates a missing
  // directory 0755 and a file 0644, which any other account can read. So
  // nothing is written until both folders have been made private -- created
  // 0700, as the XDG spec asks, or tightened if an older version left them
  // open -- and the files that already exist are 0600. A file created later
  // is made 0600 right after its first save; atomic saves then keep the mode.
  //
  // It fails closed. Every command must exit 0. If one does not, or they
  // cannot run at all, saving stops for the session, what was changed stays
  // in memory, and `warning` says so on screen. No shell: argument lists
  // with fixed paths.
  property bool secured: false
  property string warning: ""
  property bool dirsPrivate: false
  property bool prefsChecked: false
  property bool prefsExists: false
  property bool snapshotChecked: false
  property bool snapshotExists: false
  property var madePrivate: ({})   // file -> true once chmod 600 succeeded

  readonly property string prefsPath: stateDir + "/prefs.json"
  readonly property string snapshotPath: cacheDir + "/snapshot.json"

  function fail(why) {
    secured = false
    warning = why + " Nothing is being saved."
  }

  property var jobs: []
  property var job: null

  function run(args, onOk) {
    jobs.push({ args: args, onOk: onOk })
    next()
  }

  function next() {
    if (job || !jobs.length) return
    job = jobs.shift()
    lock.command = job.args
    watchdog.restart()
    lock.running = true
  }

  Process {
    id: lock
    onExited: function (exitCode, exitStatus) {
      watchdog.stop()
      var j = root.job
      root.job = null
      if (!j) return
      if (exitCode === 0 && exitStatus === 0) j.onOk()
      else root.fail("Couldn't make Crypto Market's files private (" + j.args[0] + " failed).")
      root.next()
    }
  }

  // A command that never ran, or never came back, counts as failed.
  Timer {
    id: watchdog
    interval: 10000
    onTriggered: {
      root.job = null
      root.jobs = []
      root.fail("Couldn't check that Crypto Market's files are private.")
    }
  }

  function secure() {
    if (!home) { fail("No home directory."); return }
    run(["install", "-d", "-m", "700", stateDir, cacheDir], function () {
      root.dirsPrivate = true
      root.lockExisting()
    })
  }

  // Once the folders are private and both files have been looked for.
  function lockExisting() {
    if (!dirsPrivate || !prefsChecked || !snapshotChecked || secured || warning) return
    var files = []
    if (prefsExists) files.push(prefsPath)
    if (snapshotExists) files.push(snapshotPath)
    if (!files.length) { secured = true; return }
    run(["chmod", "600"].concat(files), function () {
      for (var i = 0; i < files.length; i++) root.madePrivate[files[i]] = true
      root.secured = true
    })
  }

  function lockAfterSave(file) {
    if (madePrivate[file]) return
    madePrivate[file] = true
    run(["chmod", "600", file], function () {})
  }

  Component.onCompleted: secure()

  FileView {
    id: stateFile
    path: root.prefsPath
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        var s = JSON.parse(text())
        if (s && typeof s === "object" && s.version === 1) root.prefs = Object.assign({}, root.defaults, s)
      } catch (e) {}
      root.prefsExists = true
      root.prefsChecked = true
      root.ready = true
      root.lockExisting()
    }
    onLoadFailed: {
      root.prefsChecked = true
      root.ready = true
      root.lockExisting()
    }
    onSaved: root.lockAfterSave(root.prefsPath)
  }

  FileView {
    id: snapshotFile
    path: root.snapshotPath
    atomicWrites: true
    printErrors: false
    onLoaded: {
      root.snapshotExists = true
      root.snapshotChecked = true
      root.snapshotLoaded(text())
      root.lockExisting()
    }
    onLoadFailed: {
      root.snapshotChecked = true
      root.lockExisting()
    }
    onSaved: root.lockAfterSave(root.snapshotPath)
  }
}
