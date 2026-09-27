import QtQuick
import "Api.mjs" as Api

// A percentage in the colour of its direction, with an arrow for anyone who
// cannot tell the two colours apart.
Text {
  id: root
  property var app
  property real value: NaN
  property bool badge: false
  property int digits: -1

  // A change that prints as 0.0% is no change: no colour, no arrow.
  readonly property int shownDigits: digits < 0 ? (Math.abs(value) >= 1000 ? 0 : 1) : digits
  readonly property bool flat: isNaN(value) || Number(Math.abs(value).toFixed(shownDigits)) === 0
  readonly property bool up: !flat && value > 0
  readonly property bool down: !flat && value < 0

  text: isNaN(value) ? Api.DASH : (up ? "▲ " : down ? "▼ " : "") + Api.magnitude(value, digits < 0 ? undefined : digits)
  color: up ? app.ui.up : down ? app.ui.down : app.ui.muted
  font.family: app.ui.font
  font.pixelSize: app.ui.fs.sm
  font.weight: Font.Medium
  font.features: ({ "tnum": 1 })
  leftPadding: badge ? 6 : 0
  rightPadding: badge ? 6 : 0
  topPadding: badge ? 2 : 0
  bottomPadding: badge ? 2 : 0

  Rectangle {
    visible: root.badge
    anchors.fill: parent
    z: -1
    radius: 6
    color: root.up ? root.app.ui.upSoft : root.down ? root.app.ui.downSoft : root.app.ui.surface
  }
}
