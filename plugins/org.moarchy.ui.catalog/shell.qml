// The chrome catalog as its own Quickshell process.
//
//   quickshell -p plugins/org.moarchy.ui.catalog/shell.qml
//
// This is how the kit gets reviewed on a machine that is not the phone: same
// components, same file, no plugin host. Colours fall back to the built-in
// palette when colors.toml is not staged, which is itself worth looking at --
// it is what the kit looks like on somebody else's system.
import Quickshell

ShellRoot {
  Catalog {
    id: app
    Component.onCompleted: app.open("{}")

    Connections {
      target: app.appWindow
      function onUnmapped() { Qt.callLater(Qt.quit) }
    }
  }
}
