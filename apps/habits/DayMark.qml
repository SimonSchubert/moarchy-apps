import QtQuick

// One day of one habit: a rounded square whose fill says how much of the day
// was done. Pressable when `onTapped` is wanted; the history grid only reads.
Item {
  id: root
  property var app
  property var habit: null
  property string day: ""
  property int size: 30
  property bool isToday: false
  property bool interactive: true
  signal tapped()

  implicitWidth: interactive ? app.ui.target : size
  implicitHeight: interactive ? Math.max(size + 4, 34) : size

  Accessible.role: interactive ? Accessible.Button : Accessible.Graphic
  Accessible.name: day + (root.habit && root.app.revision >= 0 && root.app.isKept(root.habit, root.day) ? ", done" : "")

  Rectangle {
    id: face
    anchors.centerIn: parent
    width: root.size
    height: root.size
    // A square, as a day on Omarchy is; rounded only where the theme rounds.
    radius: root.app.ui.radius > 0 ? Math.max(3, Math.round(root.size * 0.28)) : 0
    color: root.habit && root.day ? root.app.markColour(root.habit, root.day, root.app.revision) : "transparent"
    border.width: root.isToday ? 2 : 0
    border.color: root.app.ui.accent
    scale: tap.pressed ? 0.86 : 1.0
    Behavior on scale { NumberAnimation { duration: 90 } }
    Behavior on color { ColorAnimation { duration: 160 } }
  }

  // The halo a tick leaves, so a thumb is told it landed.
  Rectangle {
    id: halo
    anchors.centerIn: face
    width: face.width
    height: face.height
    radius: face.radius
    color: "transparent"
    border.width: 3
    border.color: root.app.ui.accent
    opacity: 0
    ParallelAnimation {
      id: pop
      NumberAnimation { target: halo; property: "opacity"; from: 0.7; to: 0; duration: 320 }
      NumberAnimation { target: halo; property: "scale"; from: 1; to: 1.5; duration: 320; easing.type: Easing.OutQuad }
    }
  }
  function celebrate() { pop.restart() }

  MouseArea {
    id: tap
    anchors.fill: parent
    enabled: root.interactive
    cursorShape: Qt.PointingHandCursor
    onClicked: root.tapped()
  }
}
