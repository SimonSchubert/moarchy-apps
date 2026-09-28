import QtQuick
import "kit"

// The headline of a card: one big figure, a line under it, and optionally a
// second, smaller figure on the right.
Item {
  id: root
  property var app
  property string value: ""
  property color valueColor: app.ui.text
  property string caption: ""
  property string side: ""
  property string sideGlyph: ""
  property color sideColor: app.ui.muted

  implicitHeight: col.implicitHeight

  Column {
    id: col
    width: parent.width - (sideRow.visible ? sideRow.width + 12 : 0)
    spacing: 2
    Text {
      width: parent.width
      text: root.value
      color: root.valueColor
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xl
      font.weight: Font.Bold
      font.features: ({ "tnum": 1 })
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      visible: root.caption !== ""
      text: root.caption
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
      font.features: ({ "tnum": 1 })
      elide: Text.ElideRight
    }
  }

  Row {
    id: sideRow
    visible: root.side !== ""
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: 8
    spacing: 2
    Icon {
      visible: root.sideGlyph !== ""
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      text: root.sideGlyph
      size: 15
      width: 18
      color: root.sideColor
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.side
      color: root.sideColor
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.lg
      font.weight: Font.Bold
      font.features: ({ "tnum": 1 })
    }
  }
}
