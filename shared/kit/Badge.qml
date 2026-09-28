import QtQuick

// A word in a small filled box: a status, a count, a source. HOT, 16, PACMAN.
// `tint` colours it; without one it is the raised fill and the muted text.
Rectangle {
  id: root
  property var app
  property string text: ""
  property color tint: "transparent"
  readonly property bool tinted: tint.a > 0

  implicitHeight: 18
  implicitWidth: label.implicitWidth + 12
  radius: app.ui.radius > 0 ? 3 : 0
  color: tinted ? app.ui.alpha(tint, 0.2) : app.ui.surfaceHigh
  border.width: 1
  border.color: tinted ? app.ui.alpha(tint, 0.55) : app.ui.line

  Text {
    id: label
    anchors.centerIn: parent
    text: root.text
    color: root.tinted ? root.tint : root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: 10
    font.weight: Font.Bold
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 0.8
  }
}
