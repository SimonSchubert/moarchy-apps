import QtQuick

// One direction of a network: an arrow in its colour, the rate, its name.
Row {
  id: root
  property var app
  property string glyph: ""
  property color color: app.ui.accent
  property string label: ""
  property string value: ""
  property string note: ""

  spacing: 8

  Rectangle {
    width: 32
    height: 32
    radius: 16
    anchors.verticalCenter: parent.verticalCenter
    color: root.app.alpha(root.color, 0.16)
    Icon {
      anchors.centerIn: parent
      app: root.app
      text: root.glyph
      size: 16
      color: root.color
    }
  }
  Column {
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width - 40
    Text {
      width: parent.width
      text: root.value
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.lg
      font.weight: Font.DemiBold
      font.features: ({ "tnum": 1 })
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      text: root.note !== "" ? root.label + " · " + root.note : root.label
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
      elide: Text.ElideRight
    }
  }
}
