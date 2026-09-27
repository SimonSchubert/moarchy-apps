import QtQuick

// Airwaves' mark: a white radio on an orange-to-pink tile. The same shape as
// icon.svg, whose path is this very glyph taken from the font.
Rectangle {
  id: root
  property int size: 28
  width: size
  height: size
  radius: Math.round(size * 0.23)
  gradient: Gradient {
    orientation: Gradient.Horizontal
    GradientStop { position: 0.0; color: "#fb923c" }
    GradientStop { position: 1.0; color: "#db2777" }
  }
  Text {
    anchors.centerIn: parent
    anchors.verticalCenterOffset: -Math.round(root.size * 0.02)
    text: String.fromCodePoint(0xF0439)   // md-radio
    color: "white"
    font.family: "JetBrainsMono Nerd Font"
    font.pixelSize: Math.round(root.size * 0.6)
  }
}
