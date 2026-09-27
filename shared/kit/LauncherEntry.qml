import QtQuick
import Quickshell
import Quickshell.Io

// A launcher entry, so the app can be found by name in Omarchy's app menu.
//
// Omarchy lists .desktop files and nothing else, and installing a plugin
// creates none. So the first time the plugin loads it writes one into
// ~/.local/share/applications -- once, and only if there is none by that
// name already. Deleting it by hand keeps it deleted; Settings can bring it
// back or hide it.
//
// The name and the X-Omarchy-Plugin marker are Omarchy Mobile's own: on a
// phone the shell keeps an entry per app plugin under exactly this name, so
// the two are one entry, never a duplicate, and the phone removes it with
// the plugin.
//
// Installed as a package, the app has an entry already --
// /usr/share/applications/<desktopId>.desktop, whose launcher asks the shell
// first -- and outside the shell there is nothing for `shell summon` to
// reach. Either way this writes nothing.
Item {
  id: root
  property var app
  property string pluginId: ""
  property string desktopId: ""
  property string name: ""
  property string genericName: ""
  property string comment: ""
  property string categories: ""
  property string keywords: ""
  // The app's own folder, where icon.svg is.
  property string appDir: ""

  readonly property string systemFile: desktopId ? "/usr/share/applications/" + desktopId + ".desktop" : ""
  property bool systemChecked: false
  property bool packaged: false
  readonly property bool active: !app.standalone && !packaged

  readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")
  readonly property string file: dataHome + "/applications/omarchy-plugin-" + pluginId + ".desktop"

  function content(show) {
    return [
      "[Desktop Entry]",
      "X-Omarchy-Plugin=" + pluginId,
      "Type=Application",
      "Name=" + name
    ].concat(genericName ? ["GenericName=" + genericName] : [])
     .concat(comment ? ["Comment=" + comment] : [])
     .concat([
      "Exec=omarchy-shell shell summon " + pluginId,
      "Icon=" + appDir + "/icon.svg",
      "Terminal=false",
      "StartupNotify=false"
    ]).concat(categories ? ["Categories=" + categories] : [])
      .concat(keywords ? ["Keywords=" + keywords] : [])
      .concat(show ? [] : ["NoDisplay=true"]).join("\n") + "\n"
  }

  // From Settings: the person asked, so our own entry is rewritten.
  function setShown(show) {
    write(show)
    app.store.set("launcher", show)
  }

  function write(show) {
    if (!/^[A-Za-z0-9._-]+$/.test(pluginId) || !name) return
    var w = writer.createObject(root, { path: root.file })
    // qmllint disable missing-property
    w.setText(content(show))
    // qmllint enable missing-property
    w.destroy()
  }

  // Once per install, after the preferences have loaded.
  function firstStart() {
    if (!systemChecked || !active) return
    if (!app.store.ready || app.store.prefs.launcherAdded) return
    app.store.set("launcherAdded", true)
    probe.path = root.file
  }

  Connections {
    target: root.app.store
    function onReadyChanged() { root.firstStart() }
  }
  Component.onCompleted: firstStart()

  FileView {
    path: root.systemFile
    preload: true
    printErrors: false
    onLoaded: { root.packaged = true; root.systemChecked = true }
    onLoadFailed: { root.systemChecked = true; root.firstStart() }
  }

  // Is there an entry by this name already? Then it stays as it is.
  FileView {
    id: probe
    preload: true
    printErrors: false
    onLoadFailed: root.write(true)
  }

  // Atomic: written beside the entry and renamed over it. Omarchy's app list
  // re-reads the directory when a file appears, goes or is renamed -- an
  // edit in place leaves a hidden entry listed until the next restart.
  Component {
    id: writer
    FileView {
      preload: false
      blockWrites: true
      atomicWrites: true
      printErrors: false
    }
  }
}
