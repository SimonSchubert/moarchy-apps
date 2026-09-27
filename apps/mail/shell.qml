// Mail as its own Quickshell process, for a system without the Omarchy shell
// -- or with one that does not have the plugin installed.
//
//   quickshell -p /usr/share/moarchy-mail/shell.qml
//
// Inside the shell this file is never read: the host keeps Panel.qml loaded,
// and it looks at the Inbox every fifteen minutes with its window closed. Here
// `standalone` opens the window at startup and closing it ends the process
// (kit/App.qml) -- and with it, the looking.
import Quickshell

ShellRoot {
  Panel { standalone: true }
}
