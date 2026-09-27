import QtQuick
import QtQuick.Shapes

// Seven days of price as one line, green or red by where it ended.
//
// A Shape and not a Canvas: a Canvas repaints its line in JavaScript into a
// texture of its own, once per row, every time a row is made. The curve
// renderer draws the same anti-aliased stroke on the GPU from the points
// alone.
Shape {
  id: root
  property var app
  property var points: []
  property real lineWidth: 1.5

  readonly property bool rising: !!points && points.length > 1 && points[points.length - 1] >= points[0]

  readonly property var line: {
    var p = root.points
    if (!p || p.length < 2 || width <= 0 || height <= 0) return []
    var lo = Infinity, hi = -Infinity
    for (var i = 0; i < p.length; i++) { lo = Math.min(lo, p[i]); hi = Math.max(hi, p[i]) }
    var span = hi - lo || 1
    var pad = root.lineWidth
    var out = []
    for (var j = 0; j < p.length; j++)
      out.push(Qt.point(j / (p.length - 1) * width, pad + (1 - (p[j] - lo) / span) * (height - 2 * pad)))
    return out
  }

  preferredRendererType: Shape.CurveRenderer

  ShapePath {
    strokeColor: root.rising ? root.app.ui.up : root.app.ui.down
    strokeWidth: root.lineWidth
    fillColor: "transparent"
    joinStyle: ShapePath.RoundJoin
    capStyle: ShapePath.RoundCap
    PathPolyline { path: root.line }
  }
}
