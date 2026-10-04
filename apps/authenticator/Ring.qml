import QtQuick

// How long a code has left: an arc that empties as the period runs out, with
// the seconds in the middle. It turns the warning colour for the last few
// seconds, which is when copying the code is a race with the login form.
Item {
  id: root
  property var app
  property int remaining: 30
  property int period: 30
  property int size: 28
  readonly property bool late: remaining <= 5
  readonly property color tint: late ? app.ui.warn : app.ui.accent

  width: size
  height: size

  Canvas {
    id: canvas
    anchors.fill: parent
    // A repaint a second, and only of a ring that is on the screen.
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var r = width / 2 - 2
      ctx.lineWidth = 3
      ctx.strokeStyle = root.app.ui.divider
      ctx.beginPath()
      ctx.arc(width / 2, height / 2, r, 0, Math.PI * 2)
      ctx.stroke()
      var f = Math.max(0, Math.min(1, root.remaining / Math.max(1, root.period)))
      ctx.strokeStyle = root.tint
      ctx.beginPath()
      ctx.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + f * Math.PI * 2)
      ctx.stroke()
    }
  }
  onRemainingChanged: canvas.requestPaint()
  onTintChanged: canvas.requestPaint()

  Text {
    anchors.centerIn: parent
    text: root.remaining
    color: root.late ? root.tint : root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: Math.round(root.size * 0.36)
    font.weight: Font.Bold
  }
}
