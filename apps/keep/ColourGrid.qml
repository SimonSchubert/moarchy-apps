import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Notes.js" as N

// The nine note colours as circles, a finger wide. Not a colour dialog and not
// a submenu: picking one is the most common thing done to a note after
// typing, so it is one tap.
Flow {
  id: root
  property var app
  property string selected: "default"
  signal picked(string key)

  spacing: 8

  Repeater {
    model: N.COLOURS
    delegate: Item {
      id: swatch
      required property var modelData
      readonly property bool current: root.selected === modelData.key
      width: root.app.ui.target
      height: root.app.ui.target
      Accessible.role: Accessible.RadioButton
      Accessible.name: modelData.label
      Accessible.checked: current

      Rectangle {
        anchors.fill: parent
        anchors.margins: 3
        radius: root.app.ui.radius
        color: root.app.noteFill(swatch.modelData.key)
        border.width: swatch.current ? 2 : 1
        border.color: swatch.current ? root.app.ui.accent : root.app.ui.line
      }
      Icon {
        anchors.centerIn: parent
        visible: swatch.current
        app: root.app
        text: KG.check
        size: 16
        color: root.app.ui.text
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.picked(swatch.modelData.key)
      }
    }
  }
}
