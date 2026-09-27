import QtQuick

// A question over the window: a sheet from the bottom on a phone, a card in
// the middle on a desktop. Back, Escape or a tap outside cancels; Enter is the
// primary action.
//
//   Dialog {
//     id: confirm
//     app: root
//     title: "Delete this note?"
//     text: "It is gone for good."
//     acceptText: "Delete"
//     destructive: true
//     onAccepted: root.deleteNote()
//   }
//   ... confirm.open()
//
// Anything placed inside goes under the text, above the buttons.
Item {
  id: root
  property var app
  property string title: ""
  property string text: ""
  property string acceptText: "OK"
  property string rejectText: "Cancel"
  property string acceptGlyph: ""
  // The primary action in the theme's red: something is lost by it.
  property bool destructive: false
  property bool canAccept: true
  // What the dialog is about, for the caller to read in onAccepted.
  property var subject: null
  default property alias content: extra.data

  signal accepted()
  signal rejected()

  readonly property bool shown: app && app.dialog === root

  parent: app ? app.overlay : null
  anchors.fill: parent
  visible: shown
  z: 10

  function open(what) {
    if (what !== undefined) subject = what
    app.resetFocus()
    app.dialog = root
  }
  function close() {
    if (app.dialog === root) app.dialog = null
    rejected()
  }
  function accept() {
    if (!canAccept) return
    if (app.dialog === root) app.dialog = null
    accepted()
  }

  Rectangle {
    anchors.fill: parent
    color: root.app ? root.app.ui.scrim : "transparent"
    MouseArea { anchors.fill: parent; onClicked: root.close() }
  }

  Rectangle {
    id: sheet
    readonly property bool atBottom: root.app.compact
    width: atBottom ? parent.width : Math.min(440, parent.width - 48)
    height: col.implicitHeight + 44
    anchors.horizontalCenter: parent.horizontalCenter
    y: atBottom ? parent.height - height : (parent.height - height) / 2
    radius: root.app.ui.radius + 6
    color: root.app.ui.bg
    border.width: 1
    border.color: root.app.ui.border
    MouseArea { anchors.fill: parent }

    Column {
      id: col
      x: 22
      y: 22
      width: parent.width - 44
      spacing: 14
      Text {
        visible: root.title !== ""
        width: parent.width
        wrapMode: Text.Wrap
        text: root.title
        color: root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.lg + 2
        font.weight: Font.Bold
      }
      Text {
        visible: root.text !== ""
        width: parent.width
        wrapMode: Text.Wrap
        lineHeight: 1.15
        text: root.text
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.sm
      }
      Column {
        id: extra
        width: parent.width
        spacing: 10
        visible: children.length > 0
      }
      Row {
        anchors.right: parent.right
        spacing: 10
        Button {
          visible: root.rejectText !== ""
          app: root.app
          text: root.rejectText
          onClicked: root.close()
        }
        Button {
          app: root.app
          primary: true
          enabled: root.canAccept
          tint: root.destructive ? root.app.ui.bad : root.app.ui.accent
          glyph: root.acceptGlyph
          text: root.acceptText
          onClicked: root.accept()
        }
      }
      Item { width: 1; height: sheet.atBottom ? 8 + root.app.bottomInset : 0 }
    }
  }
}
