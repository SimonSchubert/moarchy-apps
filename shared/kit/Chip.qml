import QtQuick

// One of a set: a filter, a section, a level. Drawn as Omarchy draws its tabs:
// words on the page, and the chosen one in a filled box. An optional glyph
// leads the label.
Rectangle {
  id: root
  property var app
  property string text: ""
  property string glyph: ""
  property bool selected: false
  property int hpad: 22
  property color tint: app.ui.accent
  signal clicked()

  implicitHeight: app.ui.chip
  implicitWidth: Math.max(app.ui.chip + 8, content.implicitWidth + hpad)
  radius: app.ui.radius
  color: selected ? app.ui.surfaceHigh : mouse.pressed ? app.ui.pressed : mouse.containsMouse ? app.ui.hover : "transparent"
  border.width: selected ? 0 : 1
  border.color: app.ui.line
  Accessible.role: Accessible.Button
  Accessible.name: text

  Row {
    id: content
    anchors.centerIn: parent
    spacing: 5
    Icon {
      visible: root.glyph !== ""
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      text: root.glyph
      size: 14
      width: 17
      color: label.color
    }
    Text {
      id: label
      anchors.verticalCenter: parent.verticalCenter
      text: root.text
      color: root.selected ? root.tint : root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      font.weight: root.selected ? Font.Bold : Font.Normal
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
