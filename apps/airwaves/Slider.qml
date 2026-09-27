import QtQuick

// A horizontal slider from 0 to 100: a track, its filled part and a knob.
// Dragged, clicked, or turned with the mouse wheel; `moved` fires as it goes.
Item {
  id: root
  property var app
  property real value: 0
  property color tint: app.ui.accent
  signal moved(real value)

  implicitWidth: 140
  implicitHeight: app.ui.target
  Accessible.role: Accessible.Slider
  Accessible.name: "Volume"

  readonly property real frac: Math.max(0, Math.min(1, value / 100))

  Rectangle {
    id: track
    anchors.verticalCenter: parent.verticalCenter
    x: 8
    width: parent.width - 16
    height: 4
    radius: 2
    color: root.app.alpha(root.app.ui.text, 0.14)
    Rectangle {
      width: parent.width * root.frac
      height: parent.height
      radius: 2
      color: root.tint
    }
  }

  Rectangle {
    x: track.x + track.width * root.frac - width / 2
    anchors.verticalCenter: parent.verticalCenter
    width: mouse.pressed ? 18 : 14
    height: width
    radius: width / 2
    color: root.app.ui.dark ? "#ffffff" : root.tint
    border.width: root.app.ui.dark ? 0 : 2
    border.color: root.app.ui.bg
    Behavior on width { NumberAnimation { duration: 90 } }
  }

  function at(x) { return Math.round(Math.max(0, Math.min(1, (x - track.x) / track.width)) * 100) }

  MouseArea {
    id: mouse
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    preventStealing: true
    onPressed: function (e) { root.moved(root.at(e.x)) }
    onPositionChanged: function (e) { if (pressed) root.moved(root.at(e.x)) }
    onWheel: function (w) { root.moved(Math.max(0, Math.min(100, root.value + (w.angleDelta.y > 0 ? 5 : -5)))) }
  }
}
