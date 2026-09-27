// Keep as its own Quickshell process, for a system without the Omarchy shell
// -- or with one that does not have the plugin installed.
//
//   quickshell -p /usr/share/moarchy-keep/shell.qml
//
// Inside the shell this file is never read: the plugin host instantiates
// Panel.qml itself. Here `standalone` opens the window at startup, and closing
// it ends the process (kit/App.qml).
import Quickshell

ShellRoot {
  Panel { standalone: true }
}
