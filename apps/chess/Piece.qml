import QtQuick
import QtQuick.Shapes
import "Pieces.js" as Pieces

// One man, filled and rimmed, inside a square of `size`.
//
// The rim is not decoration: a white piece on a light square and a black one
// on a dark square are each a shape of nearly the board's own colour, and at
// 43 px the outline is most of what separates them.
Item {
  id: root
  property var app
  // colour * 8 + kind, as Chess.js writes a piece.
  property int code: 0
  property real size: 40
  // A piece takes up this share of its square, so a rank of them is not a bar.
  property real share: 0.78

  readonly property int kind: code & 7
  readonly property bool white: (code >> 3) === 0
  readonly property var source: Pieces.SOURCES[kind] || Pieces.SOURCES[1]
  readonly property real drawn: size * share
  readonly property real scaleBy: drawn / Pieces.HEIGHT

  width: size
  height: size
  visible: kind > 0

  Shape {
    id: shape
    // The outline lives in 512-high piece units; scaled into the square and
    // centred on the width it does not fill.
    x: (root.size - root.source.width * root.scaleBy) / 2
    y: (root.size - root.drawn) / 2
    width: root.source.width
    height: Pieces.HEIGHT
    transformOrigin: Item.TopLeft
    scale: root.scaleBy
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: root.white ? root.app.ui.pieceWhite : root.app.ui.pieceBlack
      strokeColor: root.white ? root.app.ui.pieceWhiteRim : root.app.ui.pieceBlackRim
      strokeWidth: Math.max(1, root.size * 0.028) / Math.max(0.001, root.scaleBy)
      joinStyle: ShapePath.RoundJoin
      fillRule: ShapePath.WindingFill
      PathSvg { path: root.source.path }
    }
  }
}
