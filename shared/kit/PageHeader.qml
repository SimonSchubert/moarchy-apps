import QtQuick
import "Glyphs.js" as KG

// The top of a page pushed over a tab: a way back, a title, and actions on
// the right. The page is drawn over the app's own header, so it brings this.
Item {
  id: root
  property var app
  property string title: ""
  property string subtitle: ""
  // IconButtons, laid in a Row at the right.
  default property alias actions: actionRow.data

  implicitHeight: app.compact ? 60 : 68

  IconButton {
    id: backButton
    x: 4
    anchors.verticalCenter: parent.verticalCenter
    app: root.app
    glyph: KG.back
    label: "Back"
    onClicked: root.app.back()
  }
  Column {
    anchors.left: backButton.right
    anchors.leftMargin: 4
    anchors.right: actionRow.left
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    Text {
      width: parent.width
      text: root.title
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.compact ? 20 : 22
      font.weight: Font.Bold
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      visible: root.subtitle !== ""
      text: root.subtitle
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
      elide: Text.ElideRight
    }
  }
  Row {
    id: actionRow
    anchors.right: parent.right
    anchors.rightMargin: root.app.compact ? 4 : 16
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2
  }
}
