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
        spacing: 12
        // The keys, each in a box, as a keyboard shortcut is written.
        Item {
          width: 120
          height: keyRow.implicitHeight
          Row {
            id: keyRow
            spacing: 4
            Repeater {
              model: String(modelData[0]).split(/\s{2,}/).filter(function (k) { return k !== "" })
              delegate: Rectangle {
                required property string modelData
                width: Math.max(22, keyText.implicitWidth + 10)
                height: 22
                radius: root.app.ui.radius > 0 ? 3 : 0
                color: root.app.ui.surfaceHigh
                border.width: 1
                border.color: root.app.ui.line
                Text {
                  id: keyText
                  anchors.centerIn: parent
                  text: parent.modelData
                  color: root.app.ui.text
                  font.family: root.app.ui.font
                  font.pixelSize: root.app.ui.fs.xs
                  font.weight: Font.Bold
                }
              }
            }
          }
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: modelData[1]
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
        }
      }
    }
  }
}
