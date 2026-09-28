import QtQuick
import "kit"
import "kit/Glyphs.js" as KG

// The file's menu: a short column of actions under the button that opened it.
// A tap outside or Back puts it away. `items` is [{ key, label, glyph,
// checked, enabled }]; `picked(key)` says which.
Item {
  id: root
  property var app
  property bool open: false
  property var items: []
  signal picked(string key)
  signal dismissed()

  parent: app ? app.overlay : null
  anchors.fill: parent
  visible: open
  z: 9

  MouseArea { anchors.fill: parent; onClicked: root.dismissed() }

  Rectangle {
    id: box
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.rightMargin: 8
    anchors.topMargin: root.app.compact ? 52 : 58
    width: 240
    height: col.implicitHeight + 12
    radius: root.app.ui.radius
    color: root.app.ui.surfaceHigh
    border.width: 1
    border.color: root.app.ui.line
    MouseArea { anchors.fill: parent }

    Column {
      id: col
      x: 6
      y: 6
      width: parent.width - 12
      Repeater {
        model: root.items
        delegate: Rectangle {
          id: row
          required property var modelData
          readonly property bool usable: modelData.enabled !== false
          width: col.width
          height: root.app.ui.target
          radius: root.app.ui.radius
          opacity: usable ? 1 : 0.45
          color: mouse.pressed ? root.app.ui.pressed : mouse.containsMouse ? root.app.ui.hover : "transparent"
          Accessible.role: Accessible.MenuItem
          Accessible.name: modelData.label
          Row {
            anchors.verticalCenter: parent.verticalCenter
            x: 8
            spacing: 10
            Icon {
              app: root.app
              anchors.verticalCenter: parent.verticalCenter
              text: row.modelData.checked === true ? KG.check : row.modelData.glyph
              size: 18
              color: row.modelData.checked === true ? root.app.ui.accent : root.app.ui.text
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: row.modelData.label
              color: row.modelData.checked === true ? root.app.ui.accent : root.app.ui.text
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.md
            }
          }
          MouseArea {
            id: mouse
            anchors.fill: parent
            enabled: row.usable
            hoverEnabled: !root.app.compact
            cursorShape: Qt.PointingHandCursor
            onClicked: root.picked(row.modelData.key)
          }
        }
      }
    }
  }
}
