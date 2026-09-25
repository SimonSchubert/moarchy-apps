import QtQuick

// A small heading over a group of cards, with an optional action on the right.
Item {
  id: root
  property var app
  property string text: ""
  property string action: ""
  signal triggered()

  implicitHeight: 32
  Text {
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    text: root.text.toUpperCase()
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.xs
    font.weight: Font.DemiBold
    font.letterSpacing: 0.8
  }
  Text {
    visible: root.action !== ""
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    text: root.action
    color: root.app.ui.accent
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.sm
    font.weight: Font.DemiBold
    MouseArea {
      anchors.fill: parent
      anchors.margins: -10
      cursorShape: Qt.PointingHandCursor
      onClicked: root.triggered()
    }
  }
}
