import QtQuick

// What a list says when it has nothing in it: a glyph, a line, what to do
// about it, and optionally the button that does it.
Column {
  id: root
  property var app
  property string glyph: ""
  property string title: ""
  property string text: ""
  property string actionText: ""
  property bool busy: false
  signal action()

  width: Math.min(parent ? parent.width - 48 : 320, 360)
  spacing: 10

  Spinner {
    visible: root.busy
    running: root.busy
    app: root.app
    anchors.horizontalCenter: parent.horizontalCenter
  }
  Icon {
    visible: !root.busy && root.glyph !== ""
    app: root.app
    anchors.horizontalCenter: parent.horizontalCenter
    text: root.glyph
    size: 40
    color: root.app.ui.muted
  }
  Text {
    visible: root.title !== ""
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    text: root.title
    color: root.app.ui.text
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.lg
    font.weight: Font.DemiBold
  }
  Text {
    visible: root.text !== ""
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    text: root.text
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.sm
  }
  Item { width: 1; height: 4; visible: root.actionText !== "" }
  Button {
    visible: root.actionText !== ""
    anchors.horizontalCenter: parent.horizontalCenter
    app: root.app
    primary: true
    text: root.actionText
    onClicked: root.action()
  }
}
