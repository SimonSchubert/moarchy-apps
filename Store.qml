import QtQuick
import Quickshell
import Quickshell.Io

// What Couch remembers: preferences and the Trakt sign-in in ~/.local/state,
// and the last lists it saw in ~/.cache so the first screen is never empty,
// even offline.
//
// Kept in files of its own rather than shell.json: the host lets only bar
// widgets write their settings back, and a sign-in is not a setting.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/couch"
  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/couch"

  readonly property var defaults: ({
    version: 1,
    lastTab: "discover",
    mediaType: "movie",
    section: "trending",
    watchlistType: "movie",
    calendar: "shows",
    // { access, refresh, expires (ms), user: { username, slug, name, avatar, vip } }
    auth: null,
    // Your own Trakt app, if you would rather not use the built-in one.
    clientId: "",
    clientSecret: "",
    hideSpoilers: false,
    launcher: true,
    launcherAdded: false
  })

  property var prefs: defaults
  property bool ready: false

  readonly property var auth: prefs.auth && typeof prefs.auth === "object" && typeof prefs.auth.access === "string"
    && prefs.auth.access ? prefs.auth : null
  readonly property bool signedIn: auth !== null
  readonly property var user: auth && auth.user ? auth.user : null
  readonly property string clientId: typeof prefs.clientId === "string" ? prefs.clientId : ""
  readonly property string clientSecret: typeof prefs.clientSecret === "string" ? prefs.clientSecret : ""

  // The saved snapshot as text; Trakt.qml parses it on its worker thread.
  signal snapshotLoaded(string text)

  function set(key, value) {
    var s = Object.assign({}, prefs)
    s[key] = value
    prefs = s
    saveTimer.restart()
  }

  // Tokens are written at once, not after the usual pause: a refresh token
  // is single-use, and one lost to a crash in the next 400 ms is a sign-out.
  function setAuth(a) {
    set("auth", a)
    saveTimer.stop()
    saveTimer.triggered()
  }

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
  // prefs.json holds the Trakt sign-in (an access and a refresh token), and
  // the snapshot lists what somebody watches. FileView has no say in permissions: it creates a missing
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
      else root.fail("Couldn't make Couch's files private (" + j.args[0] + " failed).")
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
      root.fail("Couldn't check that Couch's files are private.")
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
