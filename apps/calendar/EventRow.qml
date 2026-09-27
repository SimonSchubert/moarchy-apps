import QtQuick
import "kit"
import "Glyphs.js" as G
import "Events.js" as Events

// One event as a card: washed in its own colour, a bar of it down the left,
// the name, and when and where under it.
Rectangle {
  id: root

  property var app
  property var entry: null
  property bool selected: false

  signal clicked

  readonly property color hue: app.eventColour(entry ? entry.colour : "blue")
  readonly property string meta: entry ? Events.line(entry) : ""

  implicitHeight: Math.max(app.ui.target + 8, text.height + 18)
  height: implicitHeight
  radius: app.ui.radius + 2
  color: app.eventWash(entry ? entry.colour : "blue")
  border.width: selected ? 2 : 0
  border.color: hue

  Accessible.role: Accessible.Button
  Accessible.name: (root.entry ? root.entry.title : "") + ", " + root.meta
  Accessible.onPressAction: root.clicked()

  Rectangle {
    id: bar
    anchors.left: parent.left
    anchors.leftMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    width: 4
    height: parent.height - 18
    radius: 2
    color: root.hue
  }

  Column {
    id: text
    anchors.left: bar.right
    anchors.leftMargin: 12
    anchors.right: repeatGlyph.left
    anchors.rightMargin: 6
    anchors.verticalCenter: parent.verticalCenter
    spacing: 1

    Text {
      width: parent.width
      text: root.entry ? root.entry.title : ""
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md
      font.weight: Font.DemiBold
      elide: Text.ElideRight
      maximumLineCount: 1
    }

    // The event's own colour, one step towards the text so it stays legible
    // on its own wash: the one thing that tells these rows apart at a glance.
    Text {
      width: parent.width
      visible: root.meta.length > 0
      text: root.meta
      color: Qt.tint(root.hue, root.app.ui.alpha(root.app.ui.text, root.app.ui.dark ? 0.55 : 0.7))
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      elide: Text.ElideRight
      maximumLineCount: 1
    }
  }

  // A repeating event says so here rather than in the line above, where it
  // would push out the place it is at.
  Icon {
    id: repeatGlyph
    app: root.app
    anchors.right: parent.right
    anchors.rightMargin: 4
    anchors.verticalCenter: parent.verticalCenter
    visible: !!root.entry && root.entry.repeat !== "none"
    width: visible ? Math.round(size * 1.4) : 0
    text: G.repeat
    size: 15
    color: Qt.tint(root.hue, root.app.ui.alpha(root.app.ui.text, 0.5))
  }

  Rectangle {
    anchors.fill: parent
    radius: parent.radius
    color: tap.pressed ? root.app.ui.pressed : tap.containsMouse ? root.app.ui.hover : "transparent"
  }

  MouseArea {
    id: tap
    anchors.fill: parent
    hoverEnabled: !root.app.compact
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
