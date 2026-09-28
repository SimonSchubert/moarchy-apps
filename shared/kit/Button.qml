import QtQuick

// A labelled action: a square box with its words in capitals, as Omarchy's
// own buttons are. `primary` fills it with the accent; otherwise it is a
// raised fill, and `active` is a toggle that is on.
Rectangle {
  id: root
  property var app
  property string text: ""
  property string glyph: ""
  property bool primary: false
  property bool active: false       // a toggle that is on
  property color tint: app.ui.accent
  signal clicked()

  implicitHeight: app.compact ? 40 : 34
  implicitWidth: row.implicitWidth + (text ? 28 : 18)
  radius: app.ui.radius
  opacity: enabled ? 1 : 0.45
  color: primary ? (mouse.pressed ? Qt.darker(tint, 1.15) : mouse.containsMouse ? Qt.lighter(tint, 1.08) : tint)
    : active ? app.ui.alpha(tint, mouse.pressed ? 0.3 : 0.2)
    : mouse.pressed ? Qt.tint(app.ui.surfaceHigh, app.ui.pressed) : mouse.containsMouse ? Qt.tint(app.ui.surfaceHigh, app.ui.hover) : app.ui.surfaceHigh
  border.width: active ? 1 : 0
  border.color: tint
  Accessible.role: Accessible.Button
  Accessible.name: text

  Row {
    id: row
    anchors.centerIn: parent
    spacing: 7
    Icon {
      visible: root.glyph !== ""
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      text: root.glyph
      size: 15
      width: 18
      color: label.color
    }
    Text {
      id: label
      visible: root.text !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: root.text
      color: root.primary ? root.app.ui.inkOnAccent : root.active ? root.tint : root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      font.weight: Font.Bold
      font.capitalization: Font.AllUppercase
      font.letterSpacing: root.app.ui.tracking
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
