import QtQuick

// A turning arc, drawn once and rotated: no repaint per frame.
Item {
  id: root
  property var app
  property bool running: true
  property int size: 26
  width: size
  height: size
  visible: running

  // Drawn once, so a theme that arrives or changes draws it again.
  readonly property color tint: app.ui.accent
  onTintChanged: arc.requestPaint()

  Canvas {
    id: arc
    anchors.fill: parent
    renderStrategy: Canvas.Cooperative
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.lineWidth = Math.max(2, root.size / 10)
      ctx.lineCap = "round"
      ctx.strokeStyle = root.tint
      ctx.beginPath()
      ctx.arc(width / 2, height / 2, width / 2 - ctx.lineWidth, 0, Math.PI * 1.4)
      ctx.stroke()
    }
    RotationAnimator on rotation {
      from: 0
      to: 360
      duration: 900
      loops: Animation.Infinite
      running: root.running && root.visible
    }
  }
}
