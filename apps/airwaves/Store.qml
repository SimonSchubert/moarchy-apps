import QtQuick
import Quickshell
import Quickshell.Io
import "Api.mjs" as Api

// What Airwaves remembers: preferences, favourites and what you listened to
// in ~/.local/state, and the last lists it saw in ~/.cache so the first screen
// is never empty, even offline.
//
// Kept in files of its own rather than shell.json: the host lets only bar
// widgets write their settings back, and a favourite is not a setting.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/airwaves"
  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/airwaves"

  readonly property int maxRecent: 50
  readonly property int maxFavorites: 500

  readonly property var defaults: ({
    version: 1,
    lastTab: "discover",
    // Stations as Api.station() shapes them, so both lists open offline.
    favorites: [],
    // [{ s: station, t: ms }], newest first.
    recent: [],
    lastStation: null,
    volume: 80,
    muted: false,
    // "" follows the computer's locale; otherwise a two-letter code.
    country: "",
    browse: "tags",
    order: "clickcount",
    logos: true,
    appearance: "system",
    launcher: true,
    launcherAdded: false
  })

  property var prefs: defaults
  property bool ready: false

  readonly property var favorites: prefs.favorites || []
  readonly property var recent: prefs.recent || []

  // The saved snapshot as text; RadioBrowser.qml parses it on its worker.
  signal snapshotLoaded(string text)

  function set(key, value) {
    var s = Object.assign({}, prefs)
    s[key] = value
    prefs = s
    saveTimer.restart()
  }

  // ------------------------------------------------------------ stations

  function isFavorite(id) {
    var f = favorites
    for (var i = 0; i < f.length; i++) if (f[i].id === id) return true
    return false
  }

  // True when it is a favourite now.
  function toggleFavorite(s) {
    if (!s || !s.id) return false
    var f = favorites.slice()
    for (var i = 0; i < f.length; i++) {
      if (f[i].id !== s.id) continue
      f.splice(i, 1)
      set("favorites", f)
      return false
    }
    f.unshift(s)
    if (f.length > maxFavorites) f.length = maxFavorites
    set("favorites", f)
    return true
  }

  // A newer copy of a station from the directory -- a new logo, a new stream
  // address -- replaces the saved one, wherever it is kept.
  function refreshStation(s) {
    if (!s || !s.id) return
    var f = favorites
    for (var i = 0; i < f.length; i++) {
      if (f[i].id !== s.id) continue
      if (JSON.stringify(f[i]) === JSON.stringify(s)) break
      var nf = f.slice()
      nf[i] = s
      set("favorites", nf)
      break
    }
  }

  function pushRecent(s) {
    if (!s || !s.id) return
    var r = recent.filter(function (e) { return e.s.id !== s.id })
    r.unshift({ s: s, t: Date.now() })
    if (r.length > maxRecent) r.length = maxRecent
    set("recent", r)
    set("lastStation", s)
  }

  function forgetRecent(id) { set("recent", recent.filter(function (e) { return e.s.id !== id })) }
  function clearRecent() { set("recent", []) }

  function clean(p) {
    var favs = []
    var seen = {}
    var list = Array.isArray(p.favorites) ? p.favorites : []
    for (var i = 0; i < list.length && favs.length < maxFavorites; i++) {
      var s = Api.saved(list[i])
      if (s && !seen[s.id]) { seen[s.id] = true; favs.push(s) }
    }
    var rec = []
    seen = {}
    var rl = Array.isArray(p.recent) ? p.recent : []
    for (var j = 0; j < rl.length && rec.length < maxRecent; j++) {
      var e = rl[j]
      var r = e ? Api.saved(e.s) : null
      if (r && !seen[r.id]) { seen[r.id] = true; rec.push({ s: r, t: Number(e.t) || 0 }) }
    }
    p.favorites = favs
    p.recent = rec
    p.lastStation = Api.saved(p.lastStation)
    var v = Number(p.volume)
    p.volume = isFinite(v) ? Math.max(0, Math.min(100, Math.round(v))) : 80
    p.muted = p.muted === true
    p.country = Api.cc(p.country)
    p.logos = p.logos !== false
    p.appearance = ["system", "light", "dark"].indexOf(p.appearance) >= 0 ? p.appearance : "system"
    return p
  }

  // ------------------------------------------------------------ files

  // The saved lists are at most a few of the cached answers, each of which
  // is capped; past 16 MB something is wrong and nothing is written.
  readonly property int maxSnapshot: 16 * 1024 * 1024

  function saveSnapshot(entries) {
    if (!secured) return
    try {
      var text = JSON.stringify({ version: 1, entries: entries })
      if (text.length <= maxSnapshot) snapshotFile.setText(text)
    } catch (e) {}
  }

  function clearSnapshot() { saveSnapshot({}) }

  // A change still waiting out saveTimer is written now. For the standalone
  // app, which ends its process when the window closes.
  function flush() {
    if (!saveTimer.running) return
    saveTimer.stop()
    saveTimer.triggered()
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
  // prefs.json lists what somebody listens to and when. FileView has no say
  // in permissions: it creates a missing directory 0755 and a file 0644,
  // which any other account can read. So nothing is written until both
  // folders have been made private -- created 0700, as the XDG spec asks, or
  // tightened if something left them open -- and the files that already
  // exist are 0600. A file created later is made 0600 right after its first
  // save; atomic saves then keep the mode.
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
      else root.fail("Couldn't make Airwaves' files private (" + j.args[0] + " failed).")
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
      root.fail("Couldn't check that Airwaves' files are private.")
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
        if (s && typeof s === "object" && s.version === 1) root.prefs = root.clean(Object.assign({}, root.defaults, s))
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
      var t = text()
      if (t.length <= root.maxSnapshot) root.snapshotLoaded(t)
      root.lockExisting()
    }
    onLoadFailed: {
      root.snapshotChecked = true
      root.lockExisting()
    }
    onSaved: root.lockAfterSave(root.snapshotPath)
  }
}
