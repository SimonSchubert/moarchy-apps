import QtQuick
import "kit"
import "Notes.js" as N
import "Glyphs.js" as G

// One note in the grid: its title, then its text or the first seven items of
// its list, in the note's own colour. A tap opens it; a long press, or a right
// click, is its menu -- pin, colour, delete -- without opening it.
Rectangle {
  id: root
  property var app
  property var note
  property bool selected: false
  signal opened()
  signal menu()

  readonly property var shown: note.kind === N.LIST ? N.preview(note) : null
  implicitHeight: col.implicitHeight + 28
  radius: app.ui.radius + 4
  color: app.noteFill(note.colour)
  border.width: selected ? 2 : note.colour === "default" ? 1 : 0
  border.color: selected ? app.ui.accent : app.ui.divider
  Accessible.role: Accessible.Button
  Accessible.name: note.title || "Note"

  Rectangle {
    anchors.fill: parent
    radius: parent.radius
    color: mouse.pressed ? root.app.ui.pressed : mouse.containsMouse ? root.app.ui.hover : "transparent"
  }

  Column {
    id: col
    x: 14
    y: 14
    width: parent.width - 28
    spacing: 6

    Item {
      visible: root.note.title !== "" || root.note.pinned
      width: parent.width
      height: Math.max(titleText.implicitHeight, 18)
      Text {
        id: titleText
        width: parent.width - (root.note.pinned ? 22 : 0)
        text: root.note.title
        wrapMode: Text.Wrap
        maximumLineCount: 3
        elide: Text.ElideRight
        color: root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.md + 1
        font.weight: Font.DemiBold
      }
      Icon {
        visible: root.note.pinned
        anchors.right: parent.right
        app: root.app
        text: G.pin
        size: 14
        width: 18
        height: 18
        color: root.app.ui.muted
      }
    }

    Text {
      visible: root.note.kind !== N.LIST && root.note.body !== ""
      width: parent.width
      text: root.note.body
      wrapMode: Text.Wrap
      maximumLineCount: 10
      elide: Text.ElideRight
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      lineHeight: 1.1
    }

    Repeater {
      model: root.shown ? root.shown.items : []
      delegate: Row {
        required property var modelData
        width: col.width
        spacing: 6
        Icon {
          app: root.app
          text: modelData.done ? G.checked : G.unchecked
          size: 14
          width: 16
          height: 18
          color: root.app.ui.muted
        }
        Text {
          width: parent.width - 22
          text: modelData.text
          elide: Text.ElideRight
          color: modelData.done ? root.app.ui.muted : root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
          font.strikeout: modelData.done
        }
      }
    }
    Text {
      visible: root.shown !== null && root.shown.more > 0
      text: root.shown ? "+" + root.shown.more + " more" : ""
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
    }
    Text {
      visible: root.note.title === "" && N.isEmpty(root.note)
      text: "Empty note"
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      font.italic: true
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: !root.app.compact
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function (event) {
      if (event.button === Qt.RightButton) root.menu()
      else root.opened()
    }
    onPressAndHold: root.menu()
  }
}
