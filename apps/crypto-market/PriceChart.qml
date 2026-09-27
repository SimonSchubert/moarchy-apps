import QtQuick
import "Api.mjs" as Api

// A coin's price over a range, filled under the line, with a crosshair that
// follows the pointer on a desktop and the finger on a phone.
//
// The finger case matters: the chart sits in a page that scrolls up and down,
// so a mostly-sideways drag is the chart's and a mostly-vertical one is the
// page's. The MouseArea does not prevent stealing; the Flickable takes the
// vertical ones and the crosshair goes away with them.
Item {
  id: root
  property var app
  property var points: []      // [[ms, price]]
  property string days: "7"
  property string currency: "usd"
  property bool loading: false
  property string error: ""

  readonly property bool ready: points && points.length > 1
  readonly property real lo: ready ? minOf(points) : 0
  readonly property real hi: ready ? maxOf(points) : 0
  readonly property bool rising: ready && points[points.length - 1][1] >= points[0][1]
  readonly property color ink: rising ? app.ui.up : app.ui.down

  // Where the plot is, inside the item: the price labels take the right.
  readonly property real plotTop: 14
  readonly property real plotBottom: height - 26
  readonly property real plotRight: width - labelWidth - 6
  readonly property real labelWidth: Math.max(hiLabel.implicitWidth, loLabel.implicitWidth)

  property int hover: -1

  function minOf(p) { var m = Infinity; for (var i = 0; i < p.length; i++) m = Math.min(m, p[i][1]); return m }
  function maxOf(p) { var m = -Infinity; for (var i = 0; i < p.length; i++) m = Math.max(m, p[i][1]); return m }

  function xAt(i) { return points.length < 2 ? 0 : i / (points.length - 1) * plotRight }
  function yAt(v) {
    var span = hi - lo || 1
    return plotTop + (1 - (v - lo) / span) * (plotBottom - plotTop)
  }
  function indexAt(x) {
    if (!ready) return -1
    return Math.max(0, Math.min(points.length - 1, Math.round(x / plotRight * (points.length - 1))))
  }

  onPointsChanged: { hover = -1; canvas.requestPaint() }
  onWidthChanged: canvas.requestPaint()
  onHeightChanged: canvas.requestPaint()
  onInkChanged: canvas.requestPaint()

  Canvas {
    id: canvas
    anchors.fill: parent
    renderStrategy: Canvas.Cooperative
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      if (!root.ready) return
      var p = root.points
      var ink = String(root.ink)

      // Faint guides at the high and the low.
      ctx.strokeStyle = String(root.app.ui.border)
      ctx.lineWidth = 1
      ctx.setLineDash ? ctx.setLineDash([3, 4]) : null
      ctx.beginPath()
      ctx.moveTo(0, Math.round(root.yAt(root.hi)) + 0.5)
      ctx.lineTo(root.plotRight, Math.round(root.yAt(root.hi)) + 0.5)
      ctx.moveTo(0, Math.round(root.yAt(root.lo)) + 0.5)
      ctx.lineTo(root.plotRight, Math.round(root.yAt(root.lo)) + 0.5)
      ctx.stroke()
      ctx.setLineDash ? ctx.setLineDash([]) : null

      ctx.beginPath()
      for (var i = 0; i < p.length; i++) {
        var x = root.xAt(i), y = root.yAt(p[i][1])
        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
      }
      ctx.lineWidth = 2
      ctx.lineJoin = "round"
      ctx.strokeStyle = ink
      ctx.stroke()

      ctx.lineTo(root.plotRight, root.plotBottom)
      ctx.lineTo(0, root.plotBottom)
      ctx.closePath()
      var g = ctx.createLinearGradient(0, root.plotTop, 0, root.plotBottom)
      var rgb = Math.round(root.ink.r * 255) + "," + Math.round(root.ink.g * 255) + "," + Math.round(root.ink.b * 255)
      g.addColorStop(0, "rgba(" + rgb + ",0.28)")
      g.addColorStop(1, "rgba(" + rgb + ",0)")
      ctx.fillStyle = g
      ctx.fill()
    }
  }

  Text {
    id: hiLabel
    x: root.width - width
    y: Math.max(0, root.yAt(root.hi) - height / 2)
    visible: root.ready
    text: Api.price(root.hi, root.currency)
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.xs
  }
  Text {
    id: loLabel
    x: root.width - width
    y: Math.min(root.plotBottom - height, root.yAt(root.lo) - height / 2)
    visible: root.ready
    text: Api.price(root.lo, root.currency)
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.xs
  }
  Text {
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    visible: root.ready
    text: root.ready ? Api.stamp(root.points[0][0], root.days) : ""
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.xs
  }
  Text {
    x: root.plotRight - width
    anchors.bottom: parent.bottom
    visible: root.ready
    text: root.ready ? Api.stamp(root.points[root.points.length - 1][0], root.days) : ""
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.xs
  }

  // Crosshair.
  Rectangle {
    visible: root.hover >= 0
    x: root.hover >= 0 ? Math.round(root.xAt(root.hover)) : 0
    y: root.plotTop - 6
    width: 1
    height: root.plotBottom - root.plotTop + 6
    color: root.app.ui.muted
  }
  Rectangle {
    visible: root.hover >= 0
    width: 10
    height: 10
    radius: 5
    x: root.hover >= 0 ? root.xAt(root.hover) - 5 : 0
    y: root.hover >= 0 ? root.yAt(root.points[root.hover][1]) - 5 : 0
    color: root.ink
    border.width: 2
    border.color: root.app.ui.bg
  }
  Rectangle {
    id: bubble
    visible: root.hover >= 0
    radius: 8
    color: root.app.ui.surfaceHigh
    border.width: 1
    border.color: root.app.ui.border
    width: bubbleCol.implicitWidth + 16
    height: bubbleCol.implicitHeight + 10
    y: 0
    x: root.hover < 0 ? 0 : Math.max(0, Math.min(root.plotRight - width, root.xAt(root.hover) - width / 2))
    z: 2
    Column {
      id: bubbleCol
      anchors.centerIn: parent
      Text {
        text: root.hover >= 0 ? Api.price(root.points[root.hover][1], root.currency) : ""
        color: root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.sm
        font.weight: Font.DemiBold
      }
      Text {
        text: root.hover >= 0 ? Api.stamp(root.points[root.hover][0], root.days) : ""
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
      }
    }
  }

  Text {
    anchors.centerIn: parent
    visible: !root.ready
    width: parent.width - 24
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    text: root.error ? root.error : root.loading ? "Loading chart…" : "No price history"
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.sm
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    preventStealing: false
    onPositionChanged: function (mouse) { if (root.ready && (pressed || containsMouse)) root.hover = root.indexAt(mouse.x) }
    onPressed: function (mouse) { if (root.ready) root.hover = root.indexAt(mouse.x) }
    onReleased: if (!containsMouse) root.hover = -1
    onExited: root.hover = -1
    onCanceled: root.hover = -1
  }
}
