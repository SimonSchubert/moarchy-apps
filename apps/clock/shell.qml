// Clock as its own Quickshell process, for a system without the Omarchy shell
// -- or with one that does not have the plugin installed.
//
//   quickshell -p /usr/share/moarchy-clock/shell.qml
//
// Inside the shell this file is never read: the plugin host instantiates
// Panel.qml itself and keeps it loaded, which is what lets an alarm ring with
// the window shut. Here `standalone` opens the window at startup and closing it
// ends the process (kit/App.qml), and its alarms with it.
import Quickshell

ShellRoot {
  Panel { standalone: true }
}
