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
  property bool busy: false
  signal triggered()

  spacing: 10
  padding: 24
  topPadding: 40

  Item {
    visible: root.busy
    anchors.horizontalCenter: parent.horizontalCenter
    width: 34
    height: 34
    Spinner { anchors.centerIn: parent; app: root.app; running: root.busy && root.visible }
  }
  Icon {
    visible: root.glyph !== "" && !root.busy
    anchors.horizontalCenter: parent.horizontalCenter
    app: root.app
    text: root.glyph
    size: 38
    color: root.app.ui.muted
  }
  Text {
    width: Math.min(parent.width - 48, 420)
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
    width: Math.min(parent.width - 48, 420)
    anchors.horizontalCenter: parent.horizontalCenter
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    text: root.detail
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.sm
    lineHeight: 1.2
  }
  Item { width: 1; height: 4; visible: root.action !== "" }
  Button {
    visible: root.action !== ""
    anchors.horizontalCenter: parent.horizontalCenter
    app: root.app
    text: root.action
    primary: true
    onClicked: root.triggered()
  }
}
