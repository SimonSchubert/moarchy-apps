// Vitals as its own Quickshell process, for a system without the Omarchy
// shell -- or with one that does not have the plugin installed.
//
//   quickshell -p /usr/share/moarchy-vitals/shell.qml
//
// Inside the shell this file is never read: the plugin host instantiates
// Panel.qml itself, keeps it loaded, and decides when the window is up. Here
// nothing does, so `standalone` opens the window at startup and closing it
// ends the process (kit/App.qml) -- a monitor still sampling with no window
// to show it in is the battery bug this app is for finding.
import Quickshell

ShellRoot {
  Panel { standalone: true }
}
