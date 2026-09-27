import QtQuick
import QtQuick.Shapes

// One suit symbol, as a path: four shapes, no font, no SVG file. A pip drawn
// from a font is a font question, and a card whose suit renders as a box is a
// card nobody can play. The same drawing at 8 px and at 30 -- 0.1.0's cairo
// paths, in a unit box.
Item {
  id: root
  // 0 clubs, 1 diamonds, 2 hearts, 3 spades.
  property int suit: 0
  // Half the height of the symbol, as in 0.1.0.
  property real size: 8
  property color color: "black"

  width: size * 2
  height: size * 2

  readonly property var paths: [
    // Clubs: three lobes and the stem.
    "M -0.46 -0.42 A 0.46 0.46 0 1 0 0.46 -0.42 A 0.46 0.46 0 1 0 -0.46 -0.42 Z " +
    "M -1.04 0.34 A 0.46 0.46 0 1 0 -0.12 0.34 A 0.46 0.46 0 1 0 -1.04 0.34 Z " +
    "M 0.12 0.34 A 0.46 0.46 0 1 0 1.04 0.34 A 0.46 0.46 0 1 0 0.12 0.34 Z " +
    "M -0.4 1 C -0.12 0.55 0.12 0.55 0.4 1 Z M -0.1 0.2 L 0.1 0.2 L 0.14 0.9 L -0.14 0.9 Z",
    "M 0 -1 L 0.74 0 L 0 1 L -0.74 0 Z",
    "M 0 1 C -1.3 -0.2 -0.55 -1.25 0 -0.35 C 0.55 -1.25 1.3 -0.2 0 1 Z",
    // Spades: an upturned heart and the stem -- the one thing that stops it
    // being an upside-down heart at 8 px.
    "M 0 -1 C 1.3 0.2 0.55 1.05 0 0.3 C -0.55 1.05 -1.3 0.2 0 -1 Z M -0.4 1 C -0.12 0.55 0.12 0.55 0.4 1 Z"
  ]

  Shape {
    x: root.size
    y: root.size
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      scale: Qt.size(root.size, root.size)
      strokeWidth: -1
      fillColor: root.color
      fillRule: ShapePath.WindingFill
      PathSvg { path: root.paths[Math.max(0, Math.min(3, root.suit))] }
    }
  }
}
