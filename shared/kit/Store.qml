import QtQuick
import Quickshell
import Quickshell.Io

// How an app was left: its page, its sort order, its look. Not its data --
// notes, games and scores live in the app's own files under
// $XDG_DATA_HOME/moarchy-<app>, where the GTK versions kept them.
//
//   Store { id: store; name: "moarchy-vitals"; defaults: ({ lastTab: "overview" }) }
//
// ~/.local/state/<name>/prefs.json. Kept in a file of its own rather than
// shell.json: the host lets only bar widgets write their settings back.
//
// Every app gets three keys whether it names them or not: `appearance`
// (theme, system, light or dark), and `launcher` and `launcherAdded`, which
// LauncherEntry keeps.
Item {
  id: root

  required property string name
  property var defaults: ({})
  // Optional: function (prefs) -> prefs, to put a value from an older version
  // or a hand-edited file back in range. Runs after the kit's own checks.
  property var clean: null

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/" + name

  readonly property var base: ({ version: 1, appearance: "theme", launcher: true, launcherAdded: false })
  readonly property var all: Object.assign({}, base, defaults)

  property var prefs: all
  property bool ready: false

  function set(key, value) {
    if (prefs[key] === value) return
    var s = Object.assign({}, prefs)
    s[key] = value
    prefs = s
    saveTimer.restart()
  }

  function tidy(p) {
    if (["theme", "system", "light", "dark"].indexOf(p.appearance) < 0) p.appearance = "theme"
    p.launcher = p.launcher !== false
    p.launcherAdded = p.launcherAdded === true
    // A key whose default is a string, number or boolean keeps that type.
    for (var k in root.defaults) {
      var d = root.defaults[k]
      if (d !== null && typeof d !== "object" && typeof p[k] !== typeof d) p[k] = d
    }
    return typeof clean === "function" ? clean(p) : p
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
          root.prefs = root.tidy(Object.assign({}, root.all, s))
      } catch (e) {}
      root.ready = true
    }
    onLoadFailed: root.ready = true
  }

  Component.onCompleted: if (!home) ready = true
}
