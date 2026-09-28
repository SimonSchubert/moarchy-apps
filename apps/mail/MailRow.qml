import QtQuick
import "kit"
import "Address.js" as Address
import "Mailbox.js" as Mailbox
import "Glyphs.js" as G

// One message in a folder: who, when, the subject and the first line. Unread
// is bold with its initial in the accent; a star and a paperclip say the two
// things worth knowing before opening it. Held, or right-clicked, it offers
// what can be done to it.
Rectangle {
  id: root
  property var app
  property var row: ({})
  property bool selected: false
  signal opened()
  signal held()

  readonly property bool unread: !Mailbox.has(row, Mailbox.SEEN)
  readonly property bool outgoing: app.folderRole === "sent" || app.folderRole === "drafts"
  readonly property var person: outgoing ? (row.to && row.to[0] || null) : row.from
  readonly property string who: outgoing
    ? "To " + (Address.label(person) || "nobody")
    : (Address.label(person) || "Unknown sender")

  implicitHeight: app.compact ? 76 : 70
  radius: app.ui.radius
  color: selected ? app.ui.selected : mouse.pressed ? app.ui.pressed : mouse.containsMouse ? app.ui.hover : "transparent"
  Accessible.role: Accessible.ListItem
  Accessible.name: who + ", " + (row.subject || "No subject") + (unread ? ", unread" : "")

  Rectangle {
    id: disc
    x: 8
    anchors.verticalCenter: parent.verticalCenter
    width: 40
    height: 40
    radius: root.app.ui.radius
    color: root.unread ? root.app.ui.accentSoft : root.app.ui.surfaceHigh
    Text {
      anchors.centerIn: parent
      text: Address.initial(root.person)
      color: root.unread ? root.app.ui.accent : root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.lg
      font.weight: Font.Bold
    }
  }

  Column {
    anchors.left: disc.right
    anchors.leftMargin: 12
    anchors.right: parent.right
    anchors.rightMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2

    Row {
      width: parent.width
      spacing: 4
      Text {
        width: parent.width - when.implicitWidth - marks.width - 8
        text: root.who
        color: root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.md
        font.weight: root.unread ? Font.Bold : Font.Normal
        elide: Text.ElideRight
      }
      Row {
        id: marks
        spacing: 0
        Icon {
          visible: Mailbox.has(root.row, Mailbox.FLAGGED)
          app: root.app
          text: G.star
          size: 14
          color: root.app.ui.star
        }
        Icon {
          visible: !!root.row.attachment
          app: root.app
          text: G.attachment
          size: 14
          color: root.app.ui.muted
        }
      }
      Text {
        id: when
        text: Mailbox.when(root.row.at, root.app.now)
        color: root.unread ? root.app.ui.accent : root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
        anchors.verticalCenter: parent.verticalCenter
      }
    }
    Text {
      width: parent.width
      text: root.row.subject || "No subject"
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      font.weight: root.unread ? Font.Bold : Font.Normal
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      visible: !!root.row.preview
      text: root.row.preview || ""
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
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function (m) { if (m.button === Qt.RightButton) root.held(); else root.opened() }
    onPressAndHold: root.held()
  }
}
