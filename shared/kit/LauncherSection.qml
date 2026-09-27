import QtQuick

// Whether the entry the plugin wrote for itself is in the app menu. Only
// shown where it wrote one: in the shell, installed without its package.
SettingsSection {
  id: root
  visible: root.app.launcher.active
  width: parent ? parent.width : implicitWidth
  title: "App menu"
  note: "An entry in the app launcher that opens " + root.app.title + " in this shell."
  Row {
    spacing: 8
    Chip { app: root.app; text: "Shown"; selected: root.app.store.prefs.launcher !== false; onClicked: root.app.launcher.setShown(true) }
    Chip { app: root.app; text: "Hidden"; selected: root.app.store.prefs.launcher === false; onClicked: root.app.launcher.setShown(false) }
  }
}
