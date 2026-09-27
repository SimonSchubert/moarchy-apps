import QtQuick
import "kit"
import "Contacts.js" as Contacts

// One person: their initial in a disc, the name, and the number or email
// under it -- the two things a person opens Contacts to find.
Rectangle {
  id: root
  property var app
  property var contact: null
  property bool selected: false
  // Where the keyboard is, on a desktop.
  property bool current: false
  signal clicked()

  readonly property string name: contact ? (contact.name || contact.phone || contact.email || "Untitled") : ""
  readonly property string line: contact && contact.name ? Contacts.line(contact) : ""

  implicitHeight: app.compact ? 60 : 54
  radius: app.ui.radius
  color: selected ? app.ui.selected : mouse.pressed ? app.ui.pressed : mouse.containsMouse ? app.ui.hover : "transparent"
  border.width: current && !selected ? 1 : 0
  border.color: app.ui.border
  Accessible.role: Accessible.ListItem
  Accessible.name: name

  Avatar {
    id: disc
    x: 10
    anchors.verticalCenter: parent.verticalCenter
    app: root.app
    contact: root.contact
    size: root.app.compact ? 40 : 36
  }

  Column {
    anchors.left: disc.right
    anchors.leftMargin: 12
    anchors.right: parent.right
    anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2
    Text {
      width: parent.width
      text: root.name
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md
      font.weight: root.selected ? Font.DemiBold : Font.Normal
      elide: Text.ElideRight
    }
    Text {
      visible: root.line !== ""
      width: parent.width
      text: root.line
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      elide: Text.ElideRight
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
