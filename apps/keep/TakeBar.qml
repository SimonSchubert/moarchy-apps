import QtQuick
import "kit"
import "Notes.js" as N
import "Glyphs.js" as G

// "Take a note…", and the tick box for a list beside it.
Rectangle {
  id: bar
  property var app

  height: bar.app.ui.target + 8
  radius: height / 2
  color: bar.app.ui.surface
  border.width: 1
  border.color: bar.app.ui.divider
  Text {
    anchors.left: parent.left
    anchors.leftMargin: 18
    anchors.verticalCenter: parent.verticalCenter
    text: "Take a note…"
    color: bar.app.ui.muted
    font.family: bar.app.ui.font
    font.pixelSize: bar.app.ui.fs.md
  }
  MouseArea {
    anchors.fill: parent
    anchors.rightMargin: listButton.width + 8
    cursorShape: Qt.PointingHandCursor
    onClicked: bar.app.newNote(N.TEXT)
  }
  IconButton {
    id: listButton
    anchors.right: parent.right
    anchors.rightMargin: 4
    anchors.verticalCenter: parent.verticalCenter
    app: bar.app
    glyph: G.list
    label: "New list"
    onClicked: bar.app.newNote(N.LIST)
  }
}
