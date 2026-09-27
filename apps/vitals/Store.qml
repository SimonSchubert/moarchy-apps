import QtQuick
import Quickshell
import Quickshell.Io

// What Vitals remembers, which is how it was left and nothing about the
// machine: the page, the task list's mode and order, the clock, the palette.
// ~/.local/state/moarchy-vitals/prefs.json.
//
// Kept in a file of its own rather than shell.json: the host lets only bar
// widgets write their settings back.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/moarchy-vitals"

  readonly property var tabs: ["overview", "processor", "memory", "tasks", "network"]
  readonly property var intervals: [1000, 2000, 5000]

  readonly property var defaults: ({
    version: 1,
    lastTab: "overview",
    // "apps" groups processes of one name into one row; "all" is every pid.
    taskMode: "apps",
    // "cpu", "memory" or "name".
    taskSort: "cpu",
    interval: 2000,
    // "theme" follows Omarchy's; "system", "light" and "dark" do not.
    appearance: "theme",
    launcher: true,
    launcherAdded: false
  })

  property var prefs: defaults
  property bool ready: false

  function set(key, value) {
    if (prefs[key] === value) return
    var s = Object.assign({}, prefs)
    s[key] = value
    prefs = s
    saveTimer.restart()
  }

  function clean(p) {
    if (tabs.indexOf(p.lastTab) < 0) p.lastTab = "overview"
    if (["apps", "all"].indexOf(p.taskMode) < 0) p.taskMode = "apps"
    if (["cpu", "memory", "name"].indexOf(p.taskSort) < 0) p.taskSort = "cpu"
    if (intervals.indexOf(p.interval) < 0) p.interval = 2000
    if (["theme", "system", "light", "dark"].indexOf(p.appearance) < 0) p.appearance = "theme"
    p.launcher = p.launcher !== false
    p.launcherAdded = p.launcherAdded === true
    return p
  }

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
      if (!root.home) return
      file.setText(JSON.stringify(root.prefs, null, 1) + "\n")
    }
  }

  FileView {
    id: file
    path: root.home ? root.stateDir + "/prefs.json" : ""
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        var s = JSON.parse(text())
        if (s && typeof s === "object" && s.version === 1)
          root.prefs = root.clean(Object.assign({}, root.defaults, s))
      } catch (e) {}
      root.ready = true
    }
    onLoadFailed: root.ready = true
  }

  Component.onCompleted: if (!home) ready = true
}
