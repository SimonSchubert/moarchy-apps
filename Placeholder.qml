import QtQuick

// What a screen shows instead of nothing: loading, empty or failed, with a
// way forward when there is one.
Column {
  id: root
  property var app
  property string glyph: ""
  property string title: ""
  property string detail: ""
  property string action: ""
  signal triggered()

  spacing: 10
  padding: 24

  Icon {
    visible: root.glyph !== ""
    anchors.horizontalCenter: parent.horizontalCenter
    app: root.app
    text: root.glyph
    size: 34
    color: root.app.ui.muted
  }
  Text {
    width: parent.width - 48
    anchors.horizontalCenter: parent.horizontalCenter
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    text: root.title
    color: root.app.ui.text
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.md
    font.weight: Font.DemiBold
  }
  Text {
    visible: text !== ""
    width: parent.width - 48
    anchors.horizontalCenter: parent.horizontalCenter
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    text: root.detail
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.sm
  }
  Chip {
    visible: root.action !== ""
    anchors.horizontalCenter: parent.horizontalCenter
    app: root.app
    text: root.action
    onClicked: root.triggered()
  }
}
