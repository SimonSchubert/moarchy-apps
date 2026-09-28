import QtQuick
import "Pegs.js" as P

// The board, drawn as one cross-shaped plank with holes in it: a tall rounded
// rectangle and a wide one filled with the same colour, whose union is a cross
// with rounded outer corners and square inner ones -- what a wooden solitaire
// board looks like.
//
// The tap target is the whole cell, not the peg. A peg is thirty percent of a
// cell across and the hole under it twenty; there is no row of other pegs in
// the way, so a finger aimed at one lands on it.
//
// A jump is drawn as a hop: the peg rises over the one it takes, which shrinks
// out as it passes, and lands. 240 ms, slower than a disc turning over in
// Reversi, because it travels two cells, and an arc that is over before the
// eye finds it is a peg that teleported.
Item {
  id: root
  property var app
  property var position: P.start(P.figureFor("english"))
  // The peg picked up, and the holes it can reach, when it has more than one.
  property int picked: -1
  property var drops: []
  // [peg, hole] the hint points along, or [].
  property var hint: []
  // The keyboard's hole, on a desktop, or -1.
  property int cursor: -1
  signal tapped(int cell)
  signal settled()

  readonly property real side: Math.min(width, height)
  readonly property real cell: side / P.SIZE
  readonly property bool busy: hop !== null

  function centreX(c) { return (P.columnOf(c) + 0.5) * cell }
  function centreY(c) { return (P.rowOf(c) + 0.5) * cell }

  // One jump, drawn. The position has already moved on; this is the picture
  // catching up with it.
  property var hop: null
  property real progress: 1
  function animate(move) {
    var d = P.decode(move)
    var l = P.landing(move)
    hop = { from: d[0], over: l[0], to: l[1] }
    progress = 0
    hopAnimation.restart()
  }
  NumberAnimation {
    id: hopAnimation
    target: root
    property: "progress"
    from: 0
    to: 1
    duration: 240
    easing.type: Easing.InOutQuad
    onFinished: { root.hop = null; root.settled() }
  }

  Item {
    id: board
    anchors.centerIn: parent
    width: root.side
    height: root.side

    // The plank: square, as everything in the app is, unless the theme rounds.
    readonly property real pad: root.cell * 0.06
    readonly property real corner: root.app.ui.radius > 0 ? root.cell * 0.34 : 0
    Rectangle {
      x: root.cell * 2 + board.pad
      y: board.pad
      width: root.cell * 3 - board.pad * 2
      height: root.cell * 7 - board.pad * 2
      radius: board.corner
      color: root.app.ui.wood
    }
    Rectangle {
      x: board.pad
      y: root.cell * 2 + board.pad
      width: root.cell * 7 - board.pad * 2
      height: root.cell * 3 - board.pad * 2
      radius: board.corner
      color: root.app.ui.wood
    }

    Repeater {
      model: P.CELLS
      delegate: Item {
        id: hole
        required property int index
        readonly property bool onBoard: P.has(root.position.holes, index)
        readonly property bool pegged: P.has(root.position.pegs, index)
          && !(root.hop && root.hop.to === index)
        visible: onBoard
        x: P.columnOf(index) * root.cell
        y: P.rowOf(index) * root.cell
        width: root.cell
        height: root.cell

        Accessible.role: Accessible.Button
        Accessible.name: P.notation(P.encode(index, 0)).split(" ")[0] + (pegged ? ", peg" : ", empty")

        // A lip on the low side, which is all it takes to make a flat dark
        // circle read as a hole rather than as a black counter.
        Rectangle {
          width: root.cell * 0.40
          height: width
          radius: width / 2
          anchors.centerIn: parent
          anchors.verticalCenterOffset: 0.8
          color: root.app.ui.holeRim
        }
        Rectangle {
          width: root.cell * 0.40
          height: width
          radius: width / 2
          anchors.centerIn: parent
          color: root.app.ui.hole
        }
        Peg {
          visible: hole.pegged
          app: root.app
          radius: root.cell * 0.30
          anchors.centerIn: parent
        }

        MouseArea {
          anchors.fill: parent
          enabled: hole.onBoard
          cursorShape: hole.pegged ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.tapped(hole.index)
        }
      }
    }

    // The peg taken, going out as the jumping one passes it: the only thing on
    // screen saying which peg was taken.
    Peg {
      visible: root.hop !== null && scale > 0
      app: root.app
      radius: root.cell * 0.30
      x: root.hop ? root.centreX(root.hop.over) - radius : 0
      y: root.hop ? root.centreY(root.hop.over) - radius : 0
      scale: Math.max(1 - root.progress * 1.8, 0)
      opacity: scale
    }
    // The peg in the air.
    Peg {
      visible: root.hop !== null
      app: root.app
      radius: root.cell * 0.30
      z: 2
      readonly property real fx: root.hop ? root.centreX(root.hop.from) : 0
      readonly property real fy: root.hop ? root.centreY(root.hop.from) : 0
      readonly property real tx: root.hop ? root.centreX(root.hop.to) : 0
      readonly property real ty: root.hop ? root.centreY(root.hop.to) : 0
      x: fx + (tx - fx) * root.progress - radius
      y: fy + (ty - fy) * root.progress - Math.sin(Math.PI * root.progress) * root.cell * 0.42 - radius
    }

    // The rings: yellow round the peg picked up (and the peg a hint names),
    // green round the holes it can reach.
    Repeater {
      model: {
        var out = []
        if (root.picked >= 0) out.push({ at: root.picked, pick: true })
        for (var i = 0; i < root.drops.length; i++) out.push({ at: root.drops[i], pick: false })
        if (root.hint.length === 2) out.push({ at: root.hint[0], pick: true })
        return out
      }
      delegate: Rectangle {
        required property var modelData
        visible: root.hop === null
        width: root.cell * 0.80
        height: width
        radius: width / 2
        x: root.centreX(modelData.at) - width / 2
        y: root.centreY(modelData.at) - height / 2
        color: "transparent"
        border.width: Math.max(root.cell * 0.085, 2.5)
        border.color: modelData.pick ? root.app.ui.pick : root.app.ui.drop
      }
    }

    // The hint is an arrow rather than two more rings, because two rings is
    // what a selection looks like, and somebody who asked for help should not
    // have to work out which of the things on the board is the answer.
    Canvas {
      id: arrow
      anchors.fill: parent
      visible: root.hint.length === 2 && root.hop === null
      onVisibleChanged: requestPaint()
      onWidthChanged: requestPaint()
      Connections {
        target: root
        function onHintChanged() { arrow.requestPaint() }
      }
      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        if (root.hint.length !== 2) return
        var c = root.cell
        var fx = root.centreX(root.hint[0]), fy = root.centreY(root.hint[0])
        var tx = root.centreX(root.hint[1]), ty = root.centreY(root.hint[1])
        var angle = Math.atan2(ty - fy, tx - fx)
        var start = c * 0.40 + 2
        var stop = Math.sqrt((tx - fx) * (tx - fx) + (ty - fy) * (ty - fy)) - c * 0.32
        var ink = root.app.ui.pick
        ctx.strokeStyle = ink
        ctx.fillStyle = ink
        ctx.lineWidth = Math.max(c * 0.085, 2.5)
        ctx.lineCap = "round"
        ctx.beginPath()
        ctx.moveTo(fx + Math.cos(angle) * start, fy + Math.sin(angle) * start)
        ctx.lineTo(fx + Math.cos(angle) * stop, fy + Math.sin(angle) * stop)
        ctx.stroke()
        var head = c * 0.22
        var hx = fx + Math.cos(angle) * (stop + head), hy = fy + Math.sin(angle) * (stop + head)
        ctx.beginPath()
        ctx.moveTo(hx, hy)
        ctx.lineTo(hx - Math.cos(angle - 0.5) * head, hy - Math.sin(angle - 0.5) * head)
        ctx.lineTo(hx - Math.cos(angle + 0.5) * head, hy - Math.sin(angle + 0.5) * head)
        ctx.closePath()
        ctx.fill()
      }
    }

    // The keyboard's hole.
    Rectangle {
      visible: root.cursor >= 0 && !root.app.compact && root.hop === null
      width: root.cell * 0.92
      height: width
      radius: root.app.ui.radius
      x: root.cursor >= 0 ? root.centreX(root.cursor) - width / 2 : 0
      y: root.cursor >= 0 ? root.centreY(root.cursor) - height / 2 : 0
      color: "transparent"
      border.width: 2
      border.color: root.app.ui.accent
    }
  }
}
