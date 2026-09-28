import QtQuick
import "kit"

// A list of things that can be done, over the window: from the bottom on a
// phone, in the middle on a desktop. Back, Escape or a tap outside closes it.
// It takes the app's `dialog` slot as a kit Dialog does, so back() finds it.
//
//   actions: [{ glyph, text, destructive, run: function () {} }, ...]
Item {
  id: root
  property var app
  property string title: ""
  property var actions: []
  default property alias content: extra.data

  readonly property bool shown: app && app.dialog === root

  parent: app ? app.overlay : null
  anchors.fill: parent
  visible: shown
  z: 10

  function open() {
    app.resetFocus()
    app.dialog = root
  }
  function close() { if (app.dialog === root) app.dialog = null }
  // Enter, from the kit's key handler: nothing is the obvious one.
  function accept() {}
  function run(action) {
    close()
    if (action && typeof action.run === "function") action.run()
  }

  Rectangle {
    anchors.fill: parent
    color: root.app ? root.app.ui.scrim : "transparent"
    MouseArea { anchors.fill: parent; onClicked: root.close() }
  }

  Rectangle {
    id: sheet
    readonly property bool atBottom: root.app.compact
    width: atBottom ? parent.width : Math.min(340, parent.width - 48)
    height: col.implicitHeight + 24 + (atBottom ? root.app.bottomInset : 0)
    anchors.horizontalCenter: parent.horizontalCenter
    y: atBottom ? parent.height - height : (parent.height - height) / 2
    radius: root.app.ui.radius
    color: root.app.ui.bg
    border.width: 1
    border.color: root.app.ui.line
    MouseArea { anchors.fill: parent }

    Column {
      id: col
      x: 10
      y: 14
      width: parent.width - 20
      spacing: 2
      Text {
        visible: root.title !== ""
        x: 10
        width: parent.width - 20
        bottomPadding: 6
        text: root.title
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
        font.weight: Font.Bold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: root.app.ui.tracking
        elide: Text.ElideMiddle
      }
      Column {
        id: extra
        width: parent.width
        visible: children.length > 0
      }
      Repeater {
        model: root.actions
        delegate: Rectangle {
          id: item
          required property var modelData
          width: col.width
          height: root.app.ui.target + 4
          radius: root.app.ui.radius
          color: mouse.pressed ? root.app.ui.pressed : mouse.containsMouse ? root.app.ui.hover : "transparent"
          Accessible.role: Accessible.MenuItem
          Accessible.name: modelData.text
          Icon {
            id: glyph
            app: root.app
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            text: item.modelData.glyph || ""
            size: 18
            color: item.modelData.destructive ? root.app.ui.bad : item.modelData.current ? root.app.ui.accent : root.app.ui.text
          }
          Text {
            anchors.left: glyph.right
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: item.modelData.text
            color: item.modelData.destructive ? root.app.ui.bad : item.modelData.current ? root.app.ui.accent : root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.md
            font.weight: item.modelData.current ? Font.Bold : Font.Normal
          }
          MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: !root.app.compact
            cursorShape: Qt.PointingHandCursor
            onClicked: root.run(item.modelData)
          }
        }
      }
    }
  }
}
