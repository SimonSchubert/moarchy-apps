import QtQuick
import "Glyphs.js" as G

// A search box. Focus only when pressed, so the phone's keyboard comes up
// because somebody asked for it, and Escape hands the keys back to the page.
Rectangle {
  id: root
  property var app
  property alias text: input.text
  property alias input: input
  property string placeholder: "Search"
  signal escaped()

  implicitHeight: app.compact ? 42 : 36
  radius: height / 2
  color: app.ui.bg
  border.width: 1
  border.color: input.activeFocus ? app.ui.accent : app.ui.border

  Icon {
    id: lens
    x: 8
    anchors.verticalCenter: parent.verticalCenter
    app: root.app
    text: G.search
    size: 16
    color: root.app.ui.muted
  }

  TextInput {
    id: input
    anchors.left: lens.right
    anchors.leftMargin: 4
    anchors.right: clear.visible ? clear.left : parent.right
    anchors.rightMargin: 10
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    verticalAlignment: TextInput.AlignVCenter
    color: root.app.ui.text
    selectionColor: root.app.ui.accent
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.md
    clip: true
    inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
    Keys.onEscapePressed: function (event) { root.escaped(); event.accepted = true }
    Keys.onDownPressed: function (event) { root.escaped(); event.accepted = false }

    Text {
      anchors.fill: parent
      verticalAlignment: Text.AlignVCenter
      visible: !input.text && !input.activeFocus
      text: root.placeholder
      color: root.app.ui.muted
      font: input.font
      elide: Text.ElideRight
    }
  }

  IconButton {
    id: clear
    visible: input.text !== ""
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    implicitWidth: root.height
    implicitHeight: root.height
    app: root.app
    glyph: G.close
    size: 15
    label: "Clear"
    onClicked: input.text = ""
  }
}
