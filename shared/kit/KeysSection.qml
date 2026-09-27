import QtQuick

// The keyboard, on a desktop: [["key", "what it does"], ...]. Not shown on a
// phone, which has none.
SettingsSection {
  id: root
  property var keys: []
  visible: !root.app.compact && keys.length > 0
  width: parent ? parent.width : implicitWidth
  title: "Keys"
  Column {
    spacing: 6
    Repeater {
      model: root.keys
      delegate: Row {
        required property var modelData
        Text {
          width: 110
          text: modelData[0]
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
          font.weight: Font.DemiBold
        }
        Text {
          text: modelData[1]
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
        }
      }
    }
  }
}
