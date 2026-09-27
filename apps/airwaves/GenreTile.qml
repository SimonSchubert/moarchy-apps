import QtQuick

// A genre as a coloured tile: its name, and its glyph large and tilted in
// the corner.
Rectangle {
  id: root
  property var app
  property string label: ""
  property string glyph: ""
  property real hue: 0
  signal clicked()

  implicitWidth: app.compact ? 132 : 164
  implicitHeight: app.compact ? 76 : 88
  radius: app.ui.radius + 4
  clip: true
  scale: mouse.pressed ? 0.97 : 1
  Behavior on scale { NumberAnimation { duration: 90 } }
  gradient: Gradient {
    orientation: Gradient.Horizontal
    GradientStop { position: 0.0; color: Qt.hsla(root.hue / 360, 0.66, root.app.ui.dark ? 0.42 : 0.52, 1) }
    GradientStop { position: 1.0; color: Qt.hsla(((root.hue + 24) % 360) / 360, 0.72, root.app.ui.dark ? 0.3 : 0.4, 1) }
  }
  Accessible.role: Accessible.Button
  Accessible.name: label

  Text {
    x: parent.width - width * 0.72
    y: parent.height - height * 0.8
    rotation: -18
    text: root.glyph
    color: Qt.rgba(1, 1, 1, 0.28)
    font.family: "JetBrainsMono Nerd Font"
    font.pixelSize: Math.round(root.height * 0.72)
  }

  Text {
    x: 14
    y: 12
    width: parent.width - 28
    text: root.label
    color: "white"
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.md + 2
    font.weight: Font.Bold
    elide: Text.ElideRight
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: !root.app.compact
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
