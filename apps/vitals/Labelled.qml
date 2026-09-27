import QtQuick

// A name, a figure on the right, and a bar under both: a filesystem, swap.
Column {
  id: root
  property var app
  property string label: ""
  property string glyph: ""
  property string value: ""
  property real fraction: 0
  property color color: app.ui.accent

  spacing: 6

  Item {
    width: parent.width
    height: 18
    Row {
      anchors.left: parent.left
      anchors.right: valueText.left
      anchors.rightMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      spacing: 4
      Icon {
        visible: root.glyph !== ""
        anchors.verticalCenter: parent.verticalCenter
        app: root.app
        text: root.glyph
        size: 14
        width: 18
        color: root.app.ui.muted
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - (root.glyph !== "" ? 22 : 0)
        text: root.label
        color: root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.sm
        elide: Text.ElideMiddle
      }
    }
    Text {
      id: valueText
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: root.value
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
      font.features: ({ "tnum": 1 })
    }
  }
  Meter {
    app: root.app
    width: parent.width
    implicitHeight: 8
    value: root.fraction
    fill: root.color
  }
}
