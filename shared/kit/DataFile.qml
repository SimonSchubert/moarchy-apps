import QtQuick
import Quickshell
import Quickshell.Io
import "Json.js" as Json

// One JSON file of an app's own, which is never silently destroyed.
//
//   DataFile {
//     id: file
//     app: "tictactoe"                 // $XDG_DATA_HOME/moarchy-tictactoe/
//     name: "tictactoe.json"
//     onParsed: function (data) { ... }   // null: absent, empty or corrupt
//   }
//   ... file.save(JSON.stringify(state, null, 1))
//
// A file that fails to parse is moved aside as <stem>.broken-<epoch>.json
// before anything is written over it, and `quarantined` says where, so the
// app can say so rather than look as though it forgot. The directory is made
// on the first save. Writes are atomic: FileView renames a temp file into
// place. Something else writing the file is noticed and read again.
FileView {
  id: file

  required property string app
  required property string name
  // MOARCHY_<APP>_DIR, for the tests and the screenshots.
  readonly property string dir: Json.dataDir(app, Quickshell.env("HOME"), Quickshell.env("XDG_DATA_HOME"),
    Quickshell.env("MOARCHY_" + app.toUpperCase().replace(/-/g, "_") + "_DIR"))

  signal parsed(var data)
  signal quarantined(string movedTo)

  path: dir + "/" + name
  printErrors: false
  watchChanges: true

  onFileChanged: Qt.callLater(function () { file.reload() })
  onLoaded: file.handle(file.text())
  // Not there yet is the ordinary first run, and has to be said: `loaded`
  // never fires for it.
  onLoadFailed: file.parsed(null)

  function handle(raw) {
    var verdict = Json.classify(raw)
    if (verdict.state === Json.CORRUPT) {
      quarantine()
      parsed(null)
      return
    }
    parsed(verdict.state === Json.OK ? verdict.data : null)
  }

  function quarantine() {
    var dest = Json.brokenPath(path, Date.now() / 1000)
    // mv rather than a copy: a copy leaves the original to be overwritten by
    // the next save, which is the failure this exists to prevent.
    Quickshell.execDetached(["mv", "--", path, dest])
    quarantined(dest)
  }

  property bool dirMade: false
  property string pending: ""
  function save(text) {
    if (dirMade) { setText(text); return }
    pending = text
    if (!mkdir.running) mkdir.running = true
  }

  property Process mkdir: Process {
    command: ["mkdir", "-p", "--", file.dir]
    // qmllint disable signal-handler-parameters
    onExited: {
      file.dirMade = true
      if (file.pending !== "") { var t = file.pending; file.pending = ""; file.setText(t) }
    }
    // qmllint enable signal-handler-parameters
  }
}
