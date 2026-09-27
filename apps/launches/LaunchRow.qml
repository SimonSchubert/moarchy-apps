import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Launches.js" as L

// One launch: its status, what and where, when, and a star. The row opens
// the launch; the star is its own target, 44 px of it on a phone.
Rectangle {
  id: root
  property var app
  property var item: null
  property bool starred: false
  property bool selected: false
  property bool current: false
  property real now: 0
  signal opened()
  signal starToggled()

  implicitHeight: Math.max(app.compact ? 72 : 64, body.implicitHeight + 16)
  radius: app.ui.radius
  color: selected ? app.ui.selected : mouse.pressed ? app.ui.pressed
    : mouse.containsMouse || (current && !app.compact) ? app.ui.hover : "transparent"
  Accessible.role: Accessible.ListItem
  Accessible.name: item ? item.name + ", " + L.headline(item, now) : ""

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: !root.app.compact
    cursorShape: Qt.PointingHandCursor
    onClicked: root.opened()
  }

  // The keyboard's place in the list, on a desktop.
  Rectangle {
    visible: root.current && !root.app.compact && !root.selected
    x: 0
    width: 3
    height: parent.height - 16
    anchors.verticalCenter: parent.verticalCenter
    radius: 1.5
    color: root.app.ui.accent
  }

  Badge {
    id: badge
    app: root.app
    item: root.item
    x: 10
    anchors.verticalCenter: parent.verticalCenter
  }

  Column {
    id: body
    anchors.left: badge.right
    anchors.leftMargin: 12
    anchors.right: when.left
    anchors.rightMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    spacing: 1
    Text {
      width: parent.width
      text: root.item ? root.item.name : ""
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md + 1
      font.weight: Font.DemiBold
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      text: root.item ? (L.note(root.item) || root.item.vehicle || root.item.agency) : ""
      visible: text !== ""
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm - 1
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      text: root.item ? (root.item.location || root.item.pad) : ""
      visible: text !== ""
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm - 1
      elide: Text.ElideRight
    }
  }

  Text {
    id: when
    anchors.right: star.left
    anchors.rightMargin: 2
    anchors.verticalCenter: parent.verticalCenter
    text: root.item ? L.headline(root.item, root.now) : ""
    color: root.app.ui.tone(L.tone(root.item, root.now))
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.md + 1
    font.weight: Font.DemiBold
    font.features: ({ "tnum": 1 })
  }

  IconButton {
    id: star
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    app: root.app
    glyph: root.starred ? KG.star : KG.starOutline
    color: root.starred ? root.app.ui.star : root.app.ui.muted
    label: root.item ? (root.starred ? "Unstar " : "Star ") + root.item.name : ""
    onClicked: root.starToggled()
  }
}
