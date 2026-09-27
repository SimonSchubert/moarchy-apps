// Vitals as its own Quickshell process, for a system without the Omarchy
// shell -- or with one that does not have the plugin installed.
//
//   quickshell -p /usr/share/moarchy-vitals/shell.qml
//
// Inside the shell this file is never read: the plugin host instantiates
// Panel.qml itself, keeps it loaded, and decides when the window is up. Here
// nothing does, so the window opens at startup and closing it ends the
// process -- a monitor still sampling with no window to show it in is the
// battery bug this app is for finding.
//
// QtQuick is imported for Timer. An unresolved type fails the whole document
// at load, which is how two shell.qml files in this repo once shipped unable
// to start at all.
import QtQuick
import Quickshell

ShellRoot {
  Panel {
    id: app
    standalone: true
    Component.onCompleted: app.open("")

    onOpenedChanged: if (!opened) {
      app.store.flush()
      quit.start()
    }
  }

  // Saves are asynchronous; a moment is enough for the last one to land.
  Timer {
    id: quit
    interval: 500
    onTriggered: Qt.quit()
  }

  // MOARCHY_VITALS_QUIT_AFTER=6 -- for headless runs: a run that does not end
  // is a run that hangs CI.
  Timer {
    interval: 1000 * parseInt(Quickshell.env("MOARCHY_VITALS_QUIT_AFTER") || "0", 10)
    running: interval > 0
    onTriggered: Qt.quit()
  }
}
