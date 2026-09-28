import QtQuick
import "kit"
import "Trivia.js" as T

// One category: its mark in its colour, its name, and how you do at it, as a
// figure and as a bar along the foot. A tap plays it.
Rectangle {
  id: root
  property var app
  property var category: T.CATEGORIES[0]
  // { answered, right } -- nothing answered is "Not played yet".
  property var tally: ({ answered: 0, right: 0 })
  property bool current: false
  readonly property color tone: app.tone(category.id)
  readonly property real share: tally.answered ? tally.right / tally.answered : 0
  signal clicked()

  implicitHeight: app.compact ? 96 : 104
  radius: app.ui.radius
  color: mouse.pressed ? Qt.tint(app.ui.surface, app.ui.pressed)
    : mouse.containsMouse ? Qt.tint(app.ui.surface, app.ui.hover) : app.ui.surface
  border.width: 1
  border.color: current ? tone : app.ui.line
  Accessible.role: Accessible.Button
  Accessible.name: category.name

  Rectangle {
    x: 12
    y: 12
    width: 34
    height: 34
    radius: root.app.ui.radius
    color: root.app.ui.alpha(root.tone, 0.16)
    Icon {
      anchors.centerIn: parent
      app: root.app
      text: root.category.glyph
      size: 18
      color: root.tone
    }
  }

  Text {
    anchors.right: parent.right
    anchors.rightMargin: 12
    y: 14
    visible: root.tally.answered > 0
    text: T.percent(root.tally.right, root.tally.answered) + "%"
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.xs
    font.features: ({ "tnum": 1 })
  }

  Text {
    x: 12
    y: 54
    width: parent.width - 24
    text: root.category.name
    color: root.app.ui.text
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.md
    font.weight: Font.Bold
    elide: Text.ElideRight
  }
  Text {
    x: 12
    y: 72
    width: parent.width - 24
    text: root.tally.answered ? root.tally.right + " of " + root.tally.answered + " right"
      : root.category.id === T.ANY ? "Every category" : "Not played yet"
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.xs
    elide: Text.ElideRight
  }

  // How much of it you get right, along the foot.
  Rectangle {
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: 1
    height: 3
    color: root.app.ui.well
    visible: root.tally.answered > 0
    Rectangle {
      width: parent.width * root.share
      height: parent.height
      color: root.tone
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
