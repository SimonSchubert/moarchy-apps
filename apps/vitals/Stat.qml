import QtQuick
import "kit"

// A label over a figure, in a tile. Two across fits a number and its name on
// 360px without either being abbreviated.
Rectangle {
  id: root
  property var app
  property string label: ""
  property string value: ""
  property string note: ""
  property string glyph: ""
  property color valueColor: app.ui.text

  implicitHeight: col.implicitHeight + 22
  radius: app.ui.radius
  color: app.ui.well
  border.width: 1
  border.color: app.ui.line

  Column {
    id: col
    x: 12
    y: 11
    width: parent.width - 24
    spacing: 3
    Row {
      spacing: 4
      width: parent.width
      Icon {
        visible: root.glyph !== ""
        anchors.verticalCenter: parent.verticalCenter
        app: root.app
        text: root.glyph
        size: 13
        width: 16
        color: root.app.ui.muted
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - (root.glyph !== "" ? 20 : 0)
        text: root.label
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
        font.capitalization: Font.AllUppercase
        font.letterSpacing: root.app.ui.tracking
        elide: Text.ElideRight
      }
    }
    Text {
      width: parent.width
      text: root.value
      color: root.valueColor
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.lg
      font.weight: Font.Bold
      font.features: ({ "tnum": 1 })
      elide: Text.ElideRight
    }
    Text {
      visible: root.note !== ""
      width: parent.width
      text: root.note
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
      elide: Text.ElideRight
    }
  }
}
