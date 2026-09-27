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
Item {
  id: root
  property var app
  property string pluginId: ""

  readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")
  readonly property string file: dataHome + "/applications/omarchy-plugin-" + pluginId + ".desktop"
  // This file's own folder is the plugin's, wherever it was installed.
  readonly property string iconPath: String(Qt.resolvedUrl("icon.svg")).replace(/^file:\/\//, "")

  function content(show) {
    return [
      "[Desktop Entry]",
      "X-Omarchy-Plugin=" + pluginId,
      "Type=Application",
      "Name=Transit",
      "GenericName=Public transport",
      "Comment=Journeys and live departures for buses, trains and trams worldwide",
      "Exec=omarchy-shell shell summon " + pluginId,
      "Icon=" + iconPath,
      "Terminal=false",
      "StartupNotify=false",
      "Categories=Utility;Maps;",
      "Keywords=transit;train;bus;tram;metro;departures;journey;timetable;bahn;"
    ].concat(show ? [] : ["NoDisplay=true"]).join("\n") + "\n"
  }

  // From Settings: the person asked, so our own entry is rewritten.
  function setShown(show) {
    write(show)
    app.store.set("launcher", show)
  }

  function write(show) {
    if (!/^[A-Za-z0-9._-]+$/.test(pluginId)) return
    var w = writer.createObject(root, { path: root.file })
    w.setText(content(show))
    w.destroy()
  }

  // Once per install, after the preferences have loaded.
  function firstStart() {
    if (!app.store.ready || app.store.prefs.launcherAdded) return
    app.store.set("launcherAdded", true)
    probe.path = root.file
  }

  Connections {
    target: root.app.store
    function onReadyChanged() { root.firstStart() }
  }
  Component.onCompleted: firstStart()

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
