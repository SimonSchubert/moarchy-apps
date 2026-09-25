import QtQuick
import "Api.mjs" as Api

// The app's own mark: a tram on a tile that runs from a signal green into a
// night blue. The same drawing as icon.svg, in QML so it follows the size.
Rectangle {
  id: root
  property var app
  property int size: 28
  width: size
  height: size
  radius: Math.round(size * 0.26)
  gradient: Gradient {
    orientation: Gradient.Vertical
    GradientStop { position: 0; color: "#10b981" }
    GradientStop { position: 1; color: "#2563eb" }
  }
  Icon {
    anchors.centerIn: parent
    app: root.app
    text: Api.GLYPH.tram
    size: Math.round(root.size * 0.62)
    color: "white"
  }
}
