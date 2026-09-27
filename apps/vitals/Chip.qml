import QtQuick

// A pill that is either chosen or not: sections inside a screen, seasons,
// filters. An optional glyph leads the label.
Rectangle {
  id: root
  property var app
  property string text: ""
  property string glyph: ""
  property bool selected: false
  property int hpad: 24
  property color tint: app.ui.accent
  signal clicked()

  implicitHeight: app.ui.chip
  implicitWidth: Math.max(app.ui.chip + 8, content.implicitWidth + hpad)
  radius: height / 2
  color: selected ? app.alpha(tint, 0.16) : mouse.pressed ? app.ui.pressed : mouse.containsMouse ? app.ui.hover : app.ui.surface
  border.width: 1
  border.color: selected ? tint : app.ui.border
  Accessible.role: Accessible.Button
  Accessible.name: text

  Row {
    id: content
    anchors.centerIn: parent
    spacing: 4
    Icon {
      visible: root.glyph !== ""
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      text: root.glyph
      size: 15
      width: 18
      color: root.selected ? root.tint : root.app.ui.text
    }
    Text {
      id: label
      anchors.verticalCenter: parent.verticalCenter
      text: root.text
      color: root.selected ? root.tint : root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      font.weight: root.selected ? Font.DemiBold : Font.Normal
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: !root.app.compact
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
