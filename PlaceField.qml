import QtQuick
import "Api.mjs" as Api

// One end of a search: a dot (hollow for the start, filled for the end), what
// it is, and the place, or a prompt when there is none yet.
Item {
  id: root
  property var app
  property string label: ""
  property var place: null
  property string dot: "start"
  signal clicked()

  implicitHeight: 60
  Accessible.role: Accessible.Button
  Accessible.name: label + ": " + (place ? place.name : "not set")

  Rectangle {
    anchors.fill: parent
    radius: root.app.ui.radius
    color: mouse.pressed ? root.app.ui.pressed : mouse.containsMouse ? root.app.ui.hover : "transparent"
  }

  Rectangle {
    x: 20
    anchors.verticalCenter: parent.verticalCenter
    width: 14
    height: 14
    radius: root.dot === "end" ? 3 : 7
    color: root.dot === "end" ? root.app.ui.accent : "transparent"
    border.width: root.dot === "end" ? 0 : 3
    border.color: root.app.ui.accent
  }

  Column {
    x: 46
    width: parent.width - 52
    anchors.verticalCenter: parent.verticalCenter
    spacing: 1
    Text {
      text: root.label
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
    }
    Text {
      width: parent.width
      text: root.place ? root.place.name : root.dot === "end" ? "Where to?" : "Where from?"
      color: root.place ? root.app.ui.text : root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.lg
      font.weight: root.place ? Font.DemiBold : Font.Normal
      elide: Text.ElideRight
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: !root.app.compact
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
