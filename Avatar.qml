import QtQuick

// A round picture of a person, or their initial until it arrives.
Item {
  id: root
  property var app
  property string source: ""
  property string name: ""
  property int size: 32
  property color ground: app.ui.surface

  width: size
  height: size

  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: root.app.ui.accentSoft
    visible: !pic.ready
    Text {
      anchors.centerIn: parent
      text: root.name ? root.name.charAt(0).toUpperCase() : "?"
      color: root.app.ui.accent
      font.family: root.app.ui.font
      font.pixelSize: Math.round(root.size * 0.45)
      font.weight: Font.Bold
    }
  }
  Poster {
    id: pic
    anchors.fill: parent
    visible: root.source !== ""
    app: root.app
    source: root.source
    showTitle: false
    radius: root.size / 2
    ground: root.ground
    opacity: ready ? 1 : 0
  }
}
