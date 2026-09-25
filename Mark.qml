import QtQuick

// Couch's mark: a white sofa on a teal-to-indigo tile. The same shape as
// icon.svg, whose path is this very glyph taken from the font.
Rectangle {
  id: root
  property int size: 28
  width: size
  height: size
  radius: Math.round(size * 0.23)
  gradient: Gradient {
    orientation: Gradient.Horizontal
    GradientStop { position: 0.0; color: "#14b8a6" }
    GradientStop { position: 1.0; color: "#4f46e5" }
  }
  Text {
    anchors.centerIn: parent
    text: String.fromCodePoint(0xF04B9)   // md-sofa
    color: "white"
    font.family: "JetBrainsMono Nerd Font"
    font.pixelSize: Math.round(root.size * 0.62)
  }
}
