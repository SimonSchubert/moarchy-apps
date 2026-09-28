import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "OpenLibrary.js" as OL

// An author in a list: their face, their name, their years and best-known
// book, and how many they wrote.
Rectangle {
  id: root
  property var app
  property var author: null
  signal opened()

  implicitHeight: app.compact ? 72 : 66
  radius: app.ui.radius
  color: mouse.pressed ? app.ui.pressed : mouse.containsMouse ? app.ui.hover : "transparent"
  Accessible.role: Accessible.ListItem
  Accessible.name: author ? author.name : ""

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: !root.app.compact
    cursorShape: Qt.PointingHandCursor
    onClicked: root.opened()
  }

  Portrait {
    id: face
    x: 8
    anchors.verticalCenter: parent.verticalCenter
    width: 48
    height: 48
    app: root.app
    name: root.author ? root.author.name : ""
    source: root.author ? root.app.authorPhotoSource(root.author.id, root.author.photo || 0, "S") : ""
  }

  Column {
    anchors.left: face.right
    anchors.leftMargin: 14
    anchors.right: count.left
    anchors.rightMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    spacing: 3
    Text {
      width: parent.width
      text: root.author ? root.author.name : ""
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md + 1
      font.weight: Font.Bold
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      visible: text !== ""
      text: root.author ? [OL.lifespan(root.author), root.author.topWork].filter(function (s) { return s !== "" }).join("  ·  ") : ""
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      elide: Text.ElideRight
    }
  }

  Row {
    id: count
    anchors.right: parent.right
    anchors.rightMargin: 6
    anchors.verticalCenter: parent.verticalCenter
    spacing: 6
    Badge {
      visible: root.author && root.author.works > 0
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      text: root.author ? OL.count(root.author.works) + " books" : ""
    }
    Icon { anchors.verticalCenter: parent.verticalCenter; app: root.app; text: KG.chevronRight; size: 18; color: root.app.ui.muted }
  }

  Rectangle {
    anchors.bottom: parent.bottom
    x: face.x + face.width + 14
    width: parent.width - x
    height: 1
    color: root.app.ui.divider
  }
}
