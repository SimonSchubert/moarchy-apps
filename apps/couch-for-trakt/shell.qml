// Couch as its own Quickshell process, for a system without the Omarchy shell
// -- or with one that does not have the plugin installed.
//
//   quickshell -p /usr/share/couch-for-trakt/shell.qml
//
// Inside the shell this file is never read: the plugin host instantiates
// Panel.qml itself, keeps it loaded, and decides when the window is up. Here
// nothing does, so the window opens at startup and closing it ends the
// process -- a window that is gone with a process still running is how an app
// becomes a battery bug.
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

  // Saves are asynchronous, and the first one of a file is followed by a
  // chmod 600. A second is enough for both to reach the disk.
  Timer {
    id: quit
    interval: 1000
    onTriggered: Qt.quit()
  }
}
