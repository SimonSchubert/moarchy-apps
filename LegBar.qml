import QtQuick
import "Api.mjs" as Api

// A journey at a glance, to scale: each ride a bar in its line's colour as
// long as the ride takes, walks as dots, and the gaps between them the time
// spent waiting. Two journeys side by side show at once which one waits on a
// cold platform for twenty minutes.
Item {
  id: root
  property var app
  property var journey: null
  property bool dim: false

  readonly property real t0: journey ? journey.start : 0
  readonly property real span: journey ? Math.max(60000, journey.end - journey.start) : 1

  implicitHeight: 22
  opacity: dim ? 0.45 : 1

  // The thread the legs hang on.
  Rectangle {
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    height: 2
    radius: 1
    color: root.app.ui.divider
  }

  Repeater {
    model: root.journey ? root.journey.legs : []
    delegate: Item {
      id: seg
      required property var modelData
      readonly property var leg: modelData
      readonly property real x0: Math.max(0, (leg.start - root.t0) / root.span * root.width)
      readonly property real x1: Math.min(root.width, (leg.end - root.t0) / root.span * root.width)
      x: x0
      width: Math.max(leg.transit ? 6 : 2, x1 - x0 - (leg.transit ? 2 : 0))
      height: root.height

      Rectangle {
        visible: seg.leg.transit
        anchors.fill: parent
        radius: 5
        color: root.app.lineFill(seg.leg)
        opacity: seg.leg.cancelled ? 0.4 : 1
        Text {
          anchors.centerIn: parent
          // Only when it fits: a squeezed name is worse than none.
          visible: implicitWidth + 8 < parent.width
          text: seg.leg.line
          color: root.app.lineOn(seg.leg)
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xs
          font.weight: Font.Bold
        }
      }

      Row {
        visible: !seg.leg.transit
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        Repeater {
          model: Math.max(1, Math.floor(seg.width / 7))
          delegate: Rectangle { width: 4; height: 4; radius: 2; color: root.app.ui.muted }
        }
      }
    }
  }
}
