import QtQuick

// Download above the line and upload below it, on one scale. A graph that
// rescales to its own peak is always full and never comparable, so the scale
// is a round number at or above the peak, and it is printed.
Item {
  id: root
  property var app
  property var down: []
  property var up: []
  property int slots: 60
  property real range: 1
  property color downColor: app.ui.down
  property color upColor: app.ui.up
  property real gap: width / slots > 5 ? 2 : 1

  implicitHeight: 88

  Rectangle {
    anchors.fill: parent
    radius: Math.min(8, root.app.ui.radius)
    color: root.app.ui.well
  }
  Rectangle {
    width: parent.width
    height: 1
    y: Math.round(parent.height / 2)
    color: root.app.ui.divider
  }

  Row {
    anchors.fill: parent
    anchors.margins: 3
    spacing: root.gap
    Repeater {
      model: root.slots
      delegate: Item {
        required property int index
        width: (root.width - 6 - (root.slots - 1) * root.gap) / root.slots
        height: root.height - 6
        readonly property int at: index - (root.slots - root.down.length)
        readonly property bool has: at >= 0 && at < root.down.length
        readonly property real d: has ? Math.min(1, root.down[at] / root.range) : 0
        readonly property real u: has && at < root.up.length ? Math.min(1, root.up[at] / root.range) : 0
        readonly property real half: height / 2
        Rectangle {
          y: parent.half - height
          width: parent.width
          height: parent.has ? Math.max(1, parent.half * parent.d) : 1
          radius: Math.min(2, width / 2, root.app.ui.radius)
          color: root.downColor
          opacity: parent.has ? 1 : 0.25
        }
        Rectangle {
          y: parent.half + 1
          width: parent.width
          height: parent.has ? Math.max(1, parent.half * parent.u) : 1
          radius: Math.min(2, width / 2, root.app.ui.radius)
          color: root.upColor
          opacity: parent.has ? 1 : 0.25
        }
      }
    }
  }
}
