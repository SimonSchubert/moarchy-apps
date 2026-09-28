import QtQuick
import Quickshell
import Quickshell.Io
import "Api.mjs" as Api

// What the app remembers: home, work, favourite stops, saved and recent
// trips and the preferences in ~/.local/state, and the last boards and
// journeys it saw in ~/.cache so the first screen is never empty, even
// offline.
//
// Kept in files of its own rather than shell.json: the host lets only bar
// widgets write their settings back, and a list of trips is not a setting.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/transit"
  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/transit"

  readonly property var defaults: ({
    version: 1,
    homePlace: null,
    workPlace: null,
    stops: [],        // favourite stops, for the departure board
    trips: [],        // saved trips: [{ from, to }]
    recents: [],      // searched trips, newest first: [{ from, to }]
    board: null,      // the stop the board showed last
    groups: Api.GROUP_KEYS,
    wheelchair: false,
    walk: "normal",
    maxTransfers: -1,
    clock24: true,
    lastTab: "journey",
    launcher: true,
    launcherAdded: false
  })

  property var prefs: defaults
  property bool ready: false

  function places(list, max) {
    if (!Array.isArray(list)) return []
    var out = []
    for (var i = 0; i < list.length && out.length < max; i++) {
      var p = Api.cleanPlace(list[i])
      if (p) out.push(p)
    }
    return out
  }
  function pairs(list, max) {
    if (!Array.isArray(list)) return []
    var out = []
    for (var i = 0; i < list.length && out.length < max; i++) {
      var x = list[i]
      var f = x ? Api.cleanPlace(x.from) : null, t = x ? Api.cleanPlace(x.to) : null
      if (f && t) out.push({ from: f, to: t })
    }
    return out
  }

  readonly property var homePlace: Api.cleanPlace(prefs.homePlace)
  readonly property var workPlace: Api.cleanPlace(prefs.workPlace)
  readonly property var stops: places(prefs.stops, 20)
  readonly property var trips: pairs(prefs.trips, 20)
  readonly property var recents: pairs(prefs.recents, 12)
  readonly property var board: Api.cleanPlace(prefs.board)
  readonly property var groups: {
    var g = Array.isArray(prefs.groups) ? prefs.groups.filter(function (k) { return Api.GROUP_KEYS.indexOf(k) >= 0 }) : []
    return g.length ? g : Api.GROUP_KEYS
  }
  readonly property bool wheelchair: prefs.wheelchair === true
  readonly property string walk: ["slow", "normal", "fast"].indexOf(prefs.walk) >= 0 ? prefs.walk : "normal"
  readonly property int maxTransfers: [-1, 0, 1, 2, 3].indexOf(prefs.maxTransfers) >= 0 ? prefs.maxTransfers : -1
  readonly property bool clock24: prefs.clock24 !== false
  readonly property var routing: ({ groups: groups, wheelchair: wheelchair, walk: walk, maxTransfers: maxTransfers })
  // Changes only when a routing setting does: `routing` is a new object on
  // every save of anything.
  readonly property string routingKey: groups.join(",") + "|" + wheelchair + "|" + walk + "|" + maxTransfers

  // The saved snapshot as text; Motis parses it on its worker thread.
  signal snapshotLoaded(string text)

  function set(key, value) {
    var s = Object.assign({}, prefs)
    s[key] = value
    prefs = s
    saveTimer.restart()
  }

  function isStop(p) {
    return stops.some(function (s) { return Api.samePlace(s, p) })
  }
  function toggleStop(p) {
    var c = Api.cleanPlace(p)
    if (!c) return
    var list = stops.filter(function (s) { return !Api.samePlace(s, c) })
    if (list.length === stops.length) list.push(c)
    set("stops", list)
  }

  function sameTrip(a, b) { return Api.samePlace(a.from, b.from) && Api.samePlace(a.to, b.to) }
  function isTrip(from, to) {
    var t = { from: from, to: to }
    return trips.some(function (x) { return root.sameTrip(x, t) })
  }
  function toggleTrip(from, to) {
    var f = Api.cleanPlace(from), t = Api.cleanPlace(to)
    if (!f || !t) return
    var pair = { from: f, to: t }
    var list = trips.filter(function (x) { return !root.sameTrip(x, pair) })
    if (list.length === trips.length) list.push(pair)
    set("trips", list)
  }
  function moveTrip(i, by) {
    var list = trips.slice()
    var j = i + by
    if (i < 0 || j < 0 || i >= list.length || j >= list.length) return
    var x = list[i]; list[i] = list[j]; list[j] = x
    set("trips", list)
  }

  function remember(from, to) {
    var f = Api.cleanPlace(from), t = Api.cleanPlace(to)
    if (!f || !t) return
    var pair = { from: f, to: t }
    var list = [pair].concat(recents.filter(function (x) { return !root.sameTrip(x, pair) }))
    set("recents", list.slice(0, 12))
  }
  function forget(i) {
    var list = recents.slice()
    list.splice(i, 1)
    set("recents", list)
  }

  function toggleGroup(key) {
    var g = groups.slice()
    var i = g.indexOf(key)
    if (i >= 0) { if (g.length > 1) g.splice(i, 1) } else g.push(key)
    set("groups", g)
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
  // prefs.json holds where the person lives and works and the trips they
  // make, and the snapshot names the stops they looked at. FileView has no say in permissions: it creates a missing
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
    // qmllint disable signal-handler-parameters
    onExited: function (exitCode, exitStatus) {
      watchdog.stop()
      var j = root.job
      root.job = null
      if (!j) return
      if (exitCode === 0 && exitStatus === 0) j.onOk()
      else root.fail("Couldn't make Transit's files private (" + j.args[0] + " failed).")
      root.next()
    }
    // qmllint enable signal-handler-parameters
  }

  // A command that never ran, or never came back, counts as failed.
  Timer {
    id: watchdog
    interval: 10000
    onTriggered: {
      root.job = null
      root.jobs = []
      root.fail("Couldn't check that Transit's files are private.")
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
