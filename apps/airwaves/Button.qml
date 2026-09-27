import QtQuick

// A labelled action. `primary` fills it with the accent; otherwise it is an
// outlined pill like a chip.
Rectangle {
  id: root
  property var app
  property string text: ""
  property string glyph: ""
  property bool primary: false
  property bool active: false       // a toggle that is on
  property color tint: app.ui.accent
  signal clicked()

  implicitHeight: app.compact ? 42 : 38
  implicitWidth: row.implicitWidth + (text ? 32 : 20)
  radius: height / 2
  opacity: enabled ? 1 : 0.5
  color: primary ? (mouse.pressed ? Qt.darker(tint, 1.15) : tint)
    : active ? app.alpha(tint, mouse.pressed ? 0.26 : 0.18)
    : mouse.pressed ? app.ui.pressed : mouse.containsMouse ? app.ui.hover : app.ui.surface
  border.width: primary ? 0 : 1
  border.color: active ? tint : app.ui.border
  Accessible.role: Accessible.Button
  Accessible.name: text

  Row {
    id: row
    anchors.centerIn: parent
    spacing: 6
    Icon {
      visible: root.glyph !== ""
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      text: root.glyph
      size: 17
      width: 20
      color: root.primary ? root.app.onAccent : root.active ? root.tint : root.app.ui.text
    }
    Text {
      visible: root.text !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: root.text
      color: root.primary ? root.app.onAccent : root.active ? root.tint : root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      font.weight: Font.DemiBold
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.enabled
    hoverEnabled: !root.app.compact
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
