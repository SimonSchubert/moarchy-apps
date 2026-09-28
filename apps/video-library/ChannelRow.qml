import QtQuick
import "kit"
import "Glyphs.js" as G
import "Lbry.js" as L

// A channel in a list: its face, its title, its @name and how much it has
// put up, and a follow button that is its own target.
Rectangle {
  id: root
  property var app
  property var channel: null
  property bool followed: false
  property bool current: false
  signal opened()
  signal followToggled()

  implicitHeight: app.compact ? 72 : 66
  radius: app.ui.radius
  color: mouse.pressed ? app.ui.pressed : mouse.containsMouse || (current && !app.compact) ? app.ui.hover : "transparent"
  Accessible.role: Accessible.ListItem
  Accessible.name: channel ? channel.title : ""

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: !root.app.compact
    cursorShape: Qt.PointingHandCursor
    onClicked: root.opened()
  }

  Thumb {
    id: face
    x: 8
    anchors.verticalCenter: parent.verticalCenter
    width: root.app.compact ? 48 : 44
    height: width
    app: root.app
    glyph: G.channel
    glyphSize: 20
    source: root.channel ? root.app.art(root.channel.id, root.channel.thumb, 96, 96) : ""
  }

  Column {
    anchors.left: face.right
    anchors.leftMargin: 12
    anchors.right: follow.left
    anchors.rightMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2
    Text {
      width: parent.width
      text: root.channel ? root.channel.title : ""
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md + 1
      font.weight: Font.Bold
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      text: root.channel ? [L.handle(root.channel), L.uploadsText(root.channel)].filter(function (s) { return s !== "" }).join(" · ") : ""
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      elide: Text.ElideRight
    }
  }

  Button {
    id: follow
    anchors.right: parent.right
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    app: root.app
    glyph: root.followed ? G.followed : G.follow
    text: root.app.compact ? "" : root.followed ? "Following" : "Follow"
    active: root.followed
    onClicked: root.followToggled()
  }
}
