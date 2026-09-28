import QtQuick
import "Glyphs.js" as KG

// The top of a page pushed over a tab: a way back, the page's name in the
// header's own capitals, and actions on the right. The page is drawn over
// the app's header, so it brings the same bar.
Item {
  id: root
  property var app
  property string title: ""
  property string subtitle: ""
  // IconButtons, laid in a Row at the right.
  default property alias actions: actionRow.data

  implicitHeight: app.compact ? 48 : 52

  IconButton {
    id: backButton
    x: 2
    anchors.verticalCenter: parent.verticalCenter
    app: root.app
    glyph: KG.back
    label: "Back"
    onClicked: root.app.back()
  }
  Row {
    anchors.left: backButton.right
    anchors.leftMargin: 2
    anchors.right: actionRow.left
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    spacing: 10
    clip: true
    Text {
      id: name
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, parent.width)
      text: root.title
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md
      font.weight: Font.Bold
      font.capitalization: Font.AllUppercase
      font.letterSpacing: root.app.ui.tracking
      elide: Text.ElideRight
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - name.width - 10
      visible: root.subtitle !== "" && width > 40
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
    anchors.rightMargin: root.app.compact ? 4 : 12
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2
  }
  Rectangle {
    anchors.bottom: parent.bottom
    width: parent.width
    height: 1
    color: root.app.ui.line
  }
}
