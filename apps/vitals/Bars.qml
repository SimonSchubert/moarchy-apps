import QtQuick

// A history as bars, oldest on the left, newest on the right, empty slots
// before the first reading drawn faint rather than not at all: a graph that
// opens on nothing looks like one that failed rather than one still counting.
//
// Rectangles and not a Canvas: the scene graph batches them into one draw and
// repaints nothing when nothing changed, where a Canvas would re-upload a
// texture every tick -- and a PinePhone has no GL to do that with.
//
// `values` are 0..1. With `load` on, each bar takes the load ramp's colour for
// its own height; otherwise every bar is `color`.
Item {
  id: root
  property var app
  property var values: []
  property int slots: 60
  property color color: app.ui.accent
  property bool load: false
  property real gap: width / slots > 5 ? 2 : 1

  implicitHeight: 64

  Rectangle {
    anchors.fill: parent
    radius: Math.min(8, root.app.ui.radius)
    color: root.app.ui.well
  }

  // Quarter lines, so a height can be read without an axis.
  Repeater {
    model: 3
    delegate: Rectangle {
      required property int index
      x: 0
      width: root.width
      height: 1
      y: Math.round(root.height * (index + 1) / 4)
      color: root.app.ui.divider
    }
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
        readonly property int at: index - (root.slots - root.values.length)
        readonly property bool has: at >= 0 && at < root.values.length
        readonly property real value: has ? Math.max(0, Math.min(1, root.values[at])) : 0
        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          height: parent.has ? Math.max(2, parent.height * parent.value) : 2
          radius: Math.min(2, width / 2)
          color: root.load ? root.app.loadColor(parent.value) : root.color
          opacity: parent.has ? 1 : 0.25
        }
      }
    }
  }
}
