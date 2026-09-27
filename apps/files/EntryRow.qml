import QtQuick
import "kit"
import "Glyphs.js" as G
import "Listing.js" as Listing

// One thing in a directory: a glyph, a name, a line about it, and a way in.
//
// A ListView delegate, built and destroyed as a thumb moves, so it computes
// nothing Listing.js has not already worked out.
//
// On a phone a tap goes in and the dots (or a hold) ask what else can be done
// with it. On a desktop a click picks it, which shows it in the pane beside
// the list, and a double click or Enter goes in; the size and the date have
// columns of their own, and the right button is the menu.
Rectangle {
  id: root
  property var app
  property var entry: null
  property real now: 0
  property bool selected: false
  // A desktop's row: one line, and the size and the date in columns.
  property bool details: false
  property int sizeWidth: 96
  property int whenWidth: 120

  signal activated()
  signal picked()
  signal menuWanted()

  readonly property bool folder: entry !== null && entry.folder
  readonly property bool broken: entry !== null && entry.broken

  implicitHeight: details ? 40 : 60
  radius: app.ui.radius
  color: selected ? app.ui.selected : mouse.pressed ? app.ui.pressed
    : mouse.containsMouse ? app.ui.hover : "transparent"

  Accessible.role: Accessible.ListItem
  Accessible.name: entry ? entry.name : ""
  Accessible.onPressAction: root.activated()

  Icon {
    id: lead
    app: root.app
    x: 8
    anchors.verticalCenter: parent.verticalCenter
    text: root.entry ? G.of(Listing.glyphs(root.entry)) : ""
    size: root.details ? 18 : 22
    // A folder is the row that leads somewhere, so it is the row that carries
    // the colour. Twenty tinted file types would be a fruit salad.
    color: root.folder ? root.app.ui.accent : root.app.ui.muted
  }

  Column {
    anchors.left: lead.right
    anchors.leftMargin: 8
    anchors.right: tail.left
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2
    Text {
      width: parent.width
      text: root.entry ? root.entry.name : ""
      // A broken link is drawn dim and says so, rather than hidden: it is a
      // thing on the disk, and hiding it is how a directory becomes
      // impossible to tidy up.
      color: root.broken ? root.app.ui.muted : root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md
      elide: Text.ElideMiddle
    }
    Text {
      visible: !root.details
      width: parent.width
      text: root.entry ? Listing.note(root.entry, root.now) : ""
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      elide: Text.ElideRight
    }
  }

  Row {
    id: tail
    anchors.right: parent.right
    anchors.rightMargin: root.details ? 12 : 0
    anchors.verticalCenter: parent.verticalCenter
    Text {
      visible: root.details
      width: root.sizeWidth
      horizontalAlignment: Text.AlignRight
      text: !root.entry ? "" : root.broken ? "Link to nothing" : root.folder ? "—" : Listing.human(root.entry.size)
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      font.features: ({ "tnum": 1 })
    }
    Text {
      visible: root.details
      width: root.whenWidth
      horizontalAlignment: Text.AlignRight
      text: root.entry ? Listing.when(root.entry.modified, root.now) : ""
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
    }
    IconButton {
      visible: !root.details
      app: root.app
      glyph: G.more
      size: 18
      color: root.app.ui.muted
      label: "What can be done with " + (root.entry ? root.entry.name : "this")
      onClicked: root.menuWanted()
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    // The dots are on top of this and take their own clicks.
    z: -1
    hoverEnabled: !root.app.compact
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function (event) {
      if (event.button === Qt.RightButton) { root.picked(); root.menuWanted(); return }
      if (root.details) root.picked()
      else root.activated()
    }
    onDoubleClicked: function (event) { if (root.details && event.button === Qt.LeftButton) root.activated() }
    onPressAndHold: root.menuWanted()
  }
}
