import QtQuick

// One peg: a shadow under it, the peg, its rim and a highlight. The shadow
// and the highlight are what stop thirty-two flat circles reading as stickers.
Item {
  id: root
  property var app
  property real radius: 10
  width: radius * 2
  height: radius * 2

  Rectangle {
    x: 0
    y: root.radius * 0.14
    width: parent.width
    height: parent.height
    radius: width / 2
    color: root.app.ui.shadow
  }
  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: root.app.ui.peg
    border.width: 1.2
    border.color: root.app.ui.pegRim
  }
  Rectangle {
    width: root.radius * 0.68
    height: width
    radius: width / 2
    x: root.radius - root.radius * 0.26 - width / 2
    y: root.radius - root.radius * 0.30 - height / 2
    color: root.app.ui.pegTop
  }
}
