// Airwaves as its own Quickshell process, for a system without the Omarchy
// shell -- or with one that does not have the plugin installed.
//
//   quickshell -p /usr/share/airwaves/shell.qml
//
// Inside the shell this file is never read: the plugin host instantiates
// Panel.qml itself, keeps it loaded, and decides when the window is up. Here
// nothing does, so the window opens at startup and closing it ends the
// process, and the music with it -- a radio still playing with no window to
// stop it from is how an app becomes the thing somebody has to kill.
import QtQuick
import Quickshell

ShellRoot {
  Panel {
    id: app
    standalone: true
    Component.onCompleted: app.open("")

    onOpenedChanged: if (!opened) {
      app.player.shutdown()
      app.store.flush()
      quit.start()
    }
  }

  // Saves are asynchronous, and the first one of a file is followed by a
  // chmod 600; mpv is given the same moment to hear its quit. A second and a
  // half is enough for all of it.
  Timer {
    id: quit
    interval: 1500
    onTriggered: Qt.quit()
  }
}
