import QtQuick
import "Game.js" as G

// One key of the app's keyboard, coloured by what is known about its letter.
Rectangle {
  id: key
  property var app
  property string label: ""
  property bool wide: false
  // -1 unknown, else a mark from Game.js.
  property int mark: -1
  signal tapped()

  radius: app.ui.radius
  readonly property color base: mark === G.CORRECT ? app.ui.correct
    : mark === G.PRESENT ? app.ui.present
    : mark === G.ABSENT ? app.ui.keyAbsent : app.ui.key
  color: mouse.pressed ? Qt.tint(base, app.ui.pressed) : mouse.containsMouse ? Qt.tint(base, app.ui.hover) : base
  Accessible.role: Accessible.Button
  Accessible.name: label

  Text {
    anchors.centerIn: parent
    text: key.label
    color: key.mark === G.CORRECT ? key.app.ui.inkOnCorrect
      : key.mark === G.PRESENT ? key.app.ui.inkOnPresent
      : key.mark === G.ABSENT ? key.app.ui.keyAbsentText : key.app.ui.text
    font.family: key.app.ui.font
    font.pixelSize: key.wide ? key.app.ui.fs.xs : key.app.ui.fs.lg
    font.weight: Font.DemiBold
    font.letterSpacing: key.wide ? 0.6 : 0
  }
  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: !key.app.compact
    onClicked: key.tapped()
  }
}
