import QtQuick

// A titled row that scrolls sideways: cast, related titles.
Column {
  id: root
  property var app
  property string title: ""
  property var model: []
  property Component delegate: null
  property int rowHeight: 200
  property int pad: 16
  spacing: 12
  visible: model && model.length > 0

  Text {
    x: root.pad
    text: root.title
    color: root.app.ui.text
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.lg
    font.weight: Font.Bold
  }
  ListView {
    width: parent.width
    height: root.rowHeight
    orientation: ListView.Horizontal
    spacing: root.app.compact ? 10 : 16
    leftMargin: root.pad
    rightMargin: root.pad
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: root.model
    delegate: root.delegate
    cacheBuffer: 400
  }
}
