import QtQuick
import "Minesweeper.js" as M

// The two numbers over the board -- the mines not yet accounted for, and the
// clock -- with the flag button between them, which is the one control that
// changes what a tap means and so says so by staying lit.
Item {
  id: root
  property var app

  implicitHeight: 64

  component Reading: Rectangle {
    id: box
    property string value: ""
    property string label: ""
    property bool low: false
    property var app
    width: 92
    height: parent.height
    radius: app.ui.radius + 2
    color: app.ui.surface
    border.width: 1
    border.color: app.ui.divider
    Column {
      anchors.centerIn: parent
      spacing: 1
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: box.value
        color: box.low ? box.app.ui.bad : box.app.ui.text
        font.family: box.app.ui.font
        font.pixelSize: box.app.ui.fs.xl - 4
        font.weight: Font.Bold
        font.features: ({ "tnum": 1 })
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: box.label
        color: box.app.ui.muted
        font.family: box.app.ui.font
        font.pixelSize: box.app.ui.fs.xs
      }
    }
  }

  // The count can go negative, and it is allowed to: it is the most useful
  // thing it ever says -- one of the flags is wrong.
  Reading {
    app: root.app
    anchors.left: parent.left
    value: String(root.app.remaining)
    label: "Mines"
    low: root.app.remaining < 0
  }

  FlagButton {
    app: root.app
    anchors.centerIn: parent
  }

  Reading {
    app: root.app
    anchors.right: parent.right
    value: M.clock(root.app.seconds)
    label: "Time"
  }
}
