import QtQuick
import "Mill.js" as M

// Three squares and four spokes, and twenty-four points on them.
//
// A Morris board is not a grid: the points are the corners and midpoints of
// three squares, and the spaces between them are board with nothing on it. So
// a tap is answered by the nearest point, not by a cell -- the points are 52 px
// apart at 360 px wide, and a finger anywhere within half that is unambiguous.
//
// The geometry is 0.1.0's: the rings at 1, 0.66 and 0.33 of the half-width,
// solved so that a piece on the outer ring is not clipped by the edge.
//
// Rings round points say what a tap will do: the piece picked up, where it may
// go, the pieces a mill has earned the right to take, and the last move made.
Item {
  id: root
  property var app
  property var position: M.OPENING
  property int picked: -1
  property var drops: []
  property var takeable: []
  property int last: -1
  // The keyboard's point, or -1 when no arrow key has been pressed.
  property int cursor: -1
  signal tapped(int spot)
  // Everything that was moving has stopped.
  signal settled()

  // Where the three rings sit, as fractions of the board's half-width, and
  // which way each place lies from the middle, clockwise from the top-left.
  readonly property var rings: [1.0, 0.66, 0.33]
  readonly property var offsets: [[-1, -1], [0, -1], [1, -1], [1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0]]
  // A piece, a point and a ring, as fractions of the gap between two rings;
  // how far from a point a tap may land and still mean it; the edge margin.
  readonly property real manShare: 0.66
  readonly property real spotShare: 0.13
  readonly property real ringShare: 0.86
  readonly property real reach: 0.62
  readonly property real pad: 18
  readonly property real spread: 1.0 + manShare * (rings[0] - rings[1]) / 2

  readonly property real side: Math.min(width, height)
  readonly property real half: Math.max(side / 2 - pad, 1) / spread
  readonly property real gap: half * (rings[0] - rings[1])
  readonly property real man: gap * manShare
  readonly property real line: Math.max(gap * 0.045, 1.5)

  function at(spot) {
    var o = offsets[M.placeOf(spot)]
    var r = half * rings[M.ringOf(spot)]
    return { x: side / 2 + o[0] * r, y: side / 2 + o[1] * r }
  }

  // ------------------------------------------------------------ motion

  // What is moving: 0.1.0's timings. A placement grows, a piece slides, the
  // line through a mill draws after it, and a piece taken shrinks.
  readonly property int placeMs: 150
  readonly property int slideMs: 210
  readonly property int millMs: 260
  readonly property int takeMs: 240
  property var play: null
  readonly property bool busy: play !== null

  function animate(what) {
    play = what
    var ms = what.removed >= 0 ? takeMs : (what.src >= 0 ? slideMs : placeMs) + (what.mill.length ? millMs : 0)
    if (what.src >= 0) {
      var a = at(what.src), b = at(what.dst)
      slider.x = a.x - man / 2
      slider.y = a.y - man / 2
      slide.xTo = b.x - man / 2
      slide.yTo = b.y - man / 2
      slide.restart()
    }
    if (what.mill.length) millDraw.restart()
    settle.interval = ms
    settle.restart()
  }

  Timer {
    id: settle
    onTriggered: { root.play = null; root.settled() }
  }

  Item {
    id: board
    anchors.centerIn: parent
    width: root.side
    height: root.side

    // The wood.
    Rectangle {
      x: root.side / 2 - root.half - root.gap * 0.5
      y: x
      width: (root.half + root.gap * 0.5) * 2
      height: width
      radius: root.gap * 0.5
      color: root.app.ui.wood
    }

    // The three squares.
    Repeater {
      model: root.rings
      delegate: Rectangle {
        required property real modelData
        readonly property real r: root.half * modelData
        x: root.side / 2 - r - root.line / 2
        y: x
        width: r * 2 + root.line
        height: width
        color: "transparent"
        border.width: root.line
        border.color: root.app.ui.boardLine
      }
    }

    // The four spokes, from the outer ring's midpoints to the inner ring's.
    Repeater {
      model: [1, 3, 5, 7]
      delegate: Rectangle {
        required property int modelData
        readonly property var a: root.at(modelData)
        readonly property var b: root.at(16 + modelData)
        readonly property bool upright: modelData === 1 || modelData === 5
        x: Math.min(a.x, b.x) - (upright ? root.line / 2 : 0)
        y: Math.min(a.y, b.y) - (upright ? 0 : root.line / 2)
        width: upright ? root.line : Math.abs(a.x - b.x)
        height: upright ? Math.abs(a.y - b.y) : root.line
        color: root.app.ui.boardLine
      }
    }

    // The points, and what is on them.
    Repeater {
      model: M.POINTS
      delegate: Item {
        id: spot
        required property int index
        readonly property var c: root.at(index)
        readonly property int owner: (root.position.white >> index) & 1 ? M.WHITE
          : (root.position.black >> index) & 1 ? M.BLACK : -1
        // The colour a piece had, kept while it shrinks away.
        property int held: -1
        onOwnerChanged: if (owner >= 0) held = owner
        Component.onCompleted: if (owner >= 0) held = owner
        // A piece arriving by a slide is drawn by the slider until it lands;
        // one leaving by a slide goes at once rather than shrinking.
        readonly property bool arriving: root.play !== null && root.play.src >= 0 && root.play.dst === index
        readonly property bool leaving: root.play !== null && root.play.src === index

        x: c.x
        y: c.y
        Accessible.role: Accessible.Button
        Accessible.name: M.notation(index) + (owner === M.WHITE ? ", white" : owner === M.BLACK ? ", black" : ", empty")

        Rectangle {
          x: -width / 2
          y: -height / 2
          width: root.gap * root.spotShare * 2
          height: width
          radius: width / 2
          color: root.app.ui.boardSpot
        }

        Item {
          id: piece
          opacity: spot.arriving ? 0 : 1
          scale: spot.owner >= 0 ? 1 : 0
          Behavior on scale {
            enabled: !spot.leaving
            NumberAnimation { duration: spot.owner >= 0 ? root.placeMs : root.takeMs; easing.type: Easing.OutCubic }
          }
          // A shadow under the piece rather than a gradient on it: one more
          // flat fill, and it is what stops eighteen circles reading as print.
          Rectangle {
            x: -root.man / 2
            y: -root.man / 2 + root.man * 0.06
            width: root.man
            height: width
            radius: width / 2
            color: root.app.ui.shadow
          }
          Rectangle {
            x: -root.man / 2
            y: -root.man / 2
            width: root.man
            height: width
            radius: width / 2
            color: spot.held === M.BLACK ? root.app.ui.blackMan : root.app.ui.whiteMan
            border.width: 1.2
            border.color: spot.held === M.BLACK ? root.app.ui.blackRim : root.app.ui.whiteRim
          }
        }

        // What a tap on this point would do, as a ring round it.
        Rectangle {
          readonly property string kind: root.picked === spot.index ? "pick"
            : root.drops.indexOf(spot.index) >= 0 ? "drop"
            : root.takeable.indexOf(spot.index) >= 0 ? "take"
            : root.cursor === spot.index ? "cursor"
            : root.last === spot.index && root.picked < 0 && !root.takeable.length ? "last"
            : ""
          readonly property color ink: kind === "pick" ? root.app.ui.pick
            : kind === "drop" ? root.app.ui.drop
            : kind === "take" ? root.app.ui.take
            : kind === "cursor" ? root.app.ui.text
            : root.app.ui.accent
          readonly property bool thin: kind === "last" || kind === "cursor"
          visible: !root.busy && kind !== ""
          x: -width / 2
          y: -height / 2
          width: root.gap * root.ringShare
          height: width
          radius: width / 2
          color: "transparent"
          border.width: thin ? Math.max(root.gap * 0.05, 1.5) : Math.max(root.gap * 0.07, 2)
          border.color: ink
        }
      }
    }

    // The piece in flight.
    Item {
      id: slider
      visible: root.play !== null && root.play.src >= 0 && slide.running
      width: root.man
      height: root.man
      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: root.play && root.play.colour === M.BLACK ? root.app.ui.blackMan : root.app.ui.whiteMan
        border.width: 1.2
        border.color: root.play && root.play.colour === M.BLACK ? root.app.ui.blackRim : root.app.ui.whiteRim
      }
    }
    ParallelAnimation {
      id: slide
      property real xTo: 0
      property real yTo: 0
      NumberAnimation { target: slider; property: "x"; to: slide.xTo; duration: root.slideMs; easing.type: Easing.OutCubic }
      NumberAnimation { target: slider; property: "y"; to: slide.yTo; duration: root.slideMs; easing.type: Easing.OutCubic }
    }

    // The line drawn through three in a row as it closes: the whole reward of
    // the move, in the moment between the mill and the piece it takes.
    Rectangle {
      id: millLine
      readonly property var mill: root.play && root.play.mill.length ? root.play.mill : []
      readonly property var a: mill.length ? root.at(mill[0]) : ({ x: 0, y: 0 })
      readonly property var b: mill.length ? root.at(mill[2]) : ({ x: 0, y: 0 })
      readonly property real full: Math.sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y))
      property real share: 0
      visible: mill.length > 0 && share > 0
      height: Math.max(root.gap * 0.09, 2.5)
      width: full * share
      radius: height / 2
      x: a.x
      y: a.y - height / 2
      transformOrigin: Item.Left
      rotation: Math.atan2(b.y - a.y, b.x - a.x) * 180 / Math.PI
      color: root.app.ui.accent
      antialiasing: true
    }
    SequentialAnimation {
      id: millDraw
      PropertyAction { target: millLine; property: "share"; value: 0 }
      PauseAnimation { duration: root.play && root.play.src >= 0 ? root.slideMs : root.placeMs }
      NumberAnimation { target: millLine; property: "share"; from: 0; to: 1; duration: root.millMs }
    }

    // A tap is the nearest point, within reach of it.
    MouseArea {
      anchors.fill: parent
      onClicked: function (mouse) {
        var best = -1, distance = root.gap * root.reach
        for (var s = 0; s < M.POINTS; s++) {
          var c = root.at(s)
          var d = Math.sqrt((mouse.x - c.x) * (mouse.x - c.x) + (mouse.y - c.y) * (mouse.y - c.y))
          if (d < distance) { best = s; distance = d }
        }
        if (best >= 0) root.tapped(best)
      }
    }
  }
}
