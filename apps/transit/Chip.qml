import QtQuick

// A pill that is either chosen or not: tabs inside a screen, ranges, filters.
Rectangle {
  id: root
  property var app
  property string text: ""
  property bool selected: false
  property int hpad: 24
  signal clicked()

  implicitHeight: app.ui.chip
  implicitWidth: Math.max(app.ui.chip + 8, label.implicitWidth + hpad)
  radius: height / 2
  color: selected ? app.ui.accentSoft : mouse.pressed ? app.ui.pressed : mouse.containsMouse ? app.ui.hover : app.ui.surface
  border.width: 1
  border.color: selected ? app.ui.accent : app.ui.border
  Accessible.role: Accessible.Button
  Accessible.name: text

  Text {
    id: label
    anchors.centerIn: parent
    width: Math.min(implicitWidth, parent.width - 12)
    text: root.text
    color: root.selected ? root.app.ui.accent : root.app.ui.text
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.sm
    font.weight: root.selected ? Font.DemiBold : Font.Normal
    horizontalAlignment: Text.AlignHCenter
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
