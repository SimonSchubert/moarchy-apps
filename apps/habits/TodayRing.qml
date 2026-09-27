import QtQuick
import QtQuick.Shapes

// Today's completion as an arc, with the count inside it. A ring rather than
// a bar because this is the one number the app is about, and a bar beside the
// level bar would read as two halves of one measurement, which they are not.
Item {
  id: root
  property var app
  property int done: 0
  property int due: 0
  readonly property real fraction: due > 0 ? done / due : 0

  implicitWidth: 64
  implicitHeight: 64

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeWidth: 6
      strokeColor: root.app.ui.well
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      PathAngleArc { centerX: root.width / 2; centerY: root.height / 2; radiusX: root.width / 2 - 4; radiusY: radiusX; startAngle: -90; sweepAngle: 360 }
    }
    ShapePath {
      strokeWidth: 6
      strokeColor: root.done === root.due && root.due > 0 ? root.app.ui.good : root.app.ui.accent
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      PathAngleArc { centerX: root.width / 2; centerY: root.height / 2; radiusX: root.width / 2 - 4; radiusY: radiusX; startAngle: -90; sweepAngle: 360 * root.fraction }
    }
  }
  Text {
    anchors.centerIn: parent
    text: root.done + "/" + root.due
    color: root.app.ui.text
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.md
    font.weight: Font.Bold
    font.features: ({ "tnum": 1 })
  }
}
