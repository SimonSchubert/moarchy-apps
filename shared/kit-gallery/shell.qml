// The kit, every piece of it on one app, for looking at rather than reasoning
// about: at a phone's width and a desktop's, in every theme.
//
//   quickshell -p shared/kit-gallery/shell.qml
//   SHOTS=... scripts/app-shot.sh is for apps; scripts/check.sh runs this once
//   offscreen so a kit change that breaks a widget fails before an app does.
//
// Not an app and not packaged: nothing installs it.
import Quickshell

ShellRoot {
  Gallery { standalone: true }
}
