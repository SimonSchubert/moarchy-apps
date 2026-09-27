import QtQuick

// Vitals' mark: four bars at four heights on a tile, the way the processor
// page draws its cores. The same shape as icon.svg, drawn rather than loaded
// so it is sharp at every size.
Rectangle {
  id: root
  property int size: 28
  width: size
  height: size
  radius: Math.round(size * 0.23)
  gradient: Gradient {
    GradientStop { position: 0.0; color: "#1e293b" }
    GradientStop { position: 1.0; color: "#0f172a" }
  }

  readonly property var bars: [
    { h: 0.38, c: "#3584e4" },
    { h: 0.62, c: "#33d17a" },
    { h: 0.48, c: "#00b8c4" },
    { h: 0.72, c: "#f5c211" }
  ]

  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Math.round(root.size * 0.16)
    spacing: Math.max(1, Math.round(root.size * 0.06))
    Repeater {
      model: root.bars
      delegate: Rectangle {
        required property var modelData
        width: Math.max(2, Math.round(root.size * 0.13))
        height: Math.round(root.size * 0.68 * modelData.h)
        anchors.bottom: parent.bottom
        radius: width / 2
        color: modelData.c
      }
    }
  }
}
