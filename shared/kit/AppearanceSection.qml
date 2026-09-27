import QtQuick

// Omarchy's theme, the desktop's light or dark, or one of the two by hand.
// "Omarchy theme" is offered only where there is one to follow.
SettingsSection {
  id: root
  width: parent ? parent.width : implicitWidth
  title: "Appearance"
  note: root.app.hostTheme.hasTheme
    ? "Omarchy's theme, as the shell draws it, and it changes when the theme does. Light or dark sets a plain palette instead."
    : "No Omarchy theme here, so it follows the desktop's light or dark preference, unless you pick one."

  Flow {
    width: parent.width
    spacing: 8
    Repeater {
      model: (root.app.hostTheme.hasTheme ? [{ k: "theme", l: "Omarchy theme" }] : [])
        .concat([{ k: "system", l: "System" }, { k: "light", l: "Light" }, { k: "dark", l: "Dark" }])
      delegate: Chip {
        required property var modelData
        app: root.app
        text: modelData.l
        // "theme" with no theme to follow is the desktop's preference.
        selected: {
          var a = root.app.store.prefs.appearance || "theme"
          if (a === "theme" && !root.app.hostTheme.hasTheme) a = "system"
          return a === modelData.k
        }
        onClicked: root.app.store.set("appearance", modelData.k)
      }
    }
  }
}
