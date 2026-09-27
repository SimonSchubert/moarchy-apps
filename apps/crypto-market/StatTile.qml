import QtQuick

// A labelled figure in the detail page's grid.
Rectangle {
  id: root
  property var app
  property string label: ""
  property string value: ""
  property string sub: ""
  property color subColor: app.ui.muted

  implicitHeight: col.implicitHeight + 20
  radius: app.ui.radius
  color: app.ui.surface

  Column {
    id: col
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: 12
    anchors.rightMargin: 12
    spacing: 3

    Text {
      width: parent.width
      text: root.label
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
      wrapMode: Text.Wrap
    }
    Text {
      width: parent.width
      text: root.value
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md
      font.weight: Font.DemiBold
      font.features: ({ "tnum": 1 })
      wrapMode: Text.Wrap
    }
    Text {
      width: parent.width
      visible: text !== ""
      text: root.sub
      color: root.subColor
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
      wrapMode: Text.Wrap
    }
  }
}
