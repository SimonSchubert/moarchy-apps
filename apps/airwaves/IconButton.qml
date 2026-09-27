import QtQuick

// A glyph you can press. 40 px square at least: a finger, not a cursor.
Item {
  id: root
  property var app
  property string glyph: ""
  property string label: ""
  property color color: app.ui.text
  property int size: 20
  property bool active: false
  signal clicked()

  implicitWidth: app.ui.target
  implicitHeight: app.ui.target
  Accessible.role: Accessible.Button
  Accessible.name: label

  Rectangle {
    anchors.fill: parent
    anchors.margins: 2
    radius: width / 2
    color: root.active ? root.app.ui.accentSoft : mouse.pressed ? root.app.ui.pressed
      : mouse.containsMouse ? root.app.ui.hover : "transparent"
  }

  Icon {
    app: root.app
    anchors.centerIn: parent
    text: root.glyph
    size: root.size
    color: root.active ? root.app.ui.accent : root.color
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
