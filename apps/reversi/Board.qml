import QtQuick
import "Bits.js" as Bits
import "Reversi.js" as R

// The board: felt, a grid, sixty-four squares. a1 is the top-left, as 0.1.0
// drew it and as reversi.py numbers it.
//
// Sixty-four Items rather than one drawn surface. A Rectangle is one
// scene-graph node, sixty-four of the same material batch into one draw call,
// and a frame in which nothing changed submits nothing at all. What it buys is
// that the square drawn and the square tapped are the same object.
//
// A disc that changes hands turns over -- squashed to its edge and opened
// again in the other colour -- in order of its distance from the move, so a
// line of flips reads as a line.
Item {
  id: root
  property var app
  property var position: R.OPENING
  // Where the person may play right now, as a board, or Bits.ZERO.
  property var hints: Bits.ZERO
  // The last square played, or -1.
  property int last: -1
  // The keyboard's square, or -1 when there is no keyboard to show it for.
  property int cursor: -1
  signal tapped(int cell)

  readonly property real side: Math.floor(Math.min(width, height) / 8) * 8
  readonly property real square: side / 8

  Rectangle {
    id: felt
    anchors.centerIn: parent
    width: root.side
    height: root.side
    radius: root.app.ui.radius
    color: root.app.ui.felt
    border.width: 1
    border.color: root.app.ui.line
    clip: true

    // The grid: seven lines each way, inside the felt's own edge.
    Repeater {
      model: 7
      delegate: Rectangle {
        required property int index
        x: root.square * (index + 1) - 0.5
        width: 1
        height: felt.height
        color: root.app.ui.feltLine
      }
    }
    Repeater {
      model: 7
      delegate: Rectangle {
        required property int index
        y: root.square * (index + 1) - 0.5
        height: 1
        width: felt.width
        color: root.app.ui.feltLine
      }
    }
    // The four dots a printed board has, at the corners of the centre.
    Repeater {
      model: [[2, 2], [2, 6], [6, 2], [6, 6]]
      delegate: Rectangle {
        required property var modelData
        width: Math.max(4, root.square * 0.1)
        height: width
        radius: width / 2
        x: root.square * modelData[1] - width / 2
        y: root.square * modelData[0] - height / 2
        color: root.app.ui.feltLine
      }
    }

    Repeater {
      model: 64
      delegate: Item {
        id: cell
        required property int index
        readonly property int row: Math.floor(index / 8)
        readonly property int column: index % 8
        x: column * root.square
        y: row * root.square
        width: root.square
        height: root.square

        readonly property int owner: Bits.test(root.position.dark, index) ? R.DARK
          : Bits.test(root.position.light, index) ? R.LIGHT : -1
        readonly property bool hint: Bits.test(root.hints, index)

        // What is drawn, which trails `owner` by half a flip.
        property int shown: owner
        property int was: owner
        onOwnerChanged: {
          if (was >= 0 && owner >= 0 && was !== owner) {
            var d = root.last >= 0
              ? Math.max(Math.abs(row - Math.floor(root.last / 8)), Math.abs(column - root.last % 8)) : 1
            flip.delay = Math.max(0, d - 1) * 45
            flip.restart()
          } else {
            flip.stop()
            squash.xScale = 1
            shown = owner
          }
          was = owner
        }

        Accessible.role: Accessible.Button
        Accessible.name: R.notation(index) + (owner === R.DARK ? ", dark" : owner === R.LIGHT ? ", light" : hint ? ", a move" : ", empty")

        Rectangle {
          id: disc
          anchors.centerIn: parent
          width: parent.width * 0.8
          height: width
          radius: width / 2
          visible: cell.shown >= 0
          color: cell.shown === R.DARK ? root.app.ui.darkDisc : root.app.ui.lightDisc
          border.width: 1
          border.color: cell.shown === R.DARK ? root.app.ui.darkRim : root.app.ui.lightRim
          transform: Scale { id: squash; origin.x: disc.width / 2; xScale: 1 }
          scale: cell.shown >= 0 ? 1 : 0
          Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
        }

        SequentialAnimation {
          id: flip
          property int delay: 0
          PauseAnimation { duration: flip.delay }
          NumberAnimation { target: squash; property: "xScale"; to: 0; duration: 90; easing.type: Easing.InQuad }
          ScriptAction { script: cell.shown = cell.owner }
          NumberAnimation { target: squash; property: "xScale"; to: 1; duration: 90; easing.type: Easing.OutQuad }
        }

        // Where you may play, as a small dot on the felt: 0.1.0's mark, and
        // one a thumb aims at without reading it as a disc. It grows under a
        // cursor.
        Rectangle {
          anchors.centerIn: parent
          visible: cell.hint && cell.owner < 0
          width: Math.max(6, parent.width * (mouse.containsMouse ? 0.28 : 0.16))
          height: width
          radius: width / 2
          color: root.app.ui.feltLine
        }

        // The last move, outlined in the accent.
        Rectangle {
          anchors.fill: parent
          anchors.margins: parent.width * 0.06
          visible: root.last === cell.index && cell.shown >= 0
          color: "transparent"
          radius: root.app.ui.radius
          border.width: 2
          border.color: root.app.ui.accent
        }

        // The keyboard's square.
        Rectangle {
          anchors.fill: parent
          anchors.margins: 2
          visible: root.cursor === cell.index
          color: "transparent"
          radius: root.app.ui.radius
          border.width: 3
          border.color: root.app.ui.text
        }

        MouseArea {
          id: mouse
          anchors.fill: parent
          hoverEnabled: !root.app.compact
          cursorShape: cell.hint ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.tapped(cell.index)
        }
      }
    }
  }

  // The files and ranks, where there is room beside the felt for them.
  Repeater {
    model: root.app.compact ? 0 : 8
    delegate: Text {
      required property int index
      x: felt.x + root.square * (index + 0.5) - width / 2
      y: felt.y + felt.height + 4
      text: "abcdefgh".charAt(index)
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
    }
  }
  Repeater {
    model: root.app.compact ? 0 : 8
    delegate: Text {
      required property int index
      x: felt.x - width - 6
      y: felt.y + root.square * (index + 0.5) - height / 2
      text: index + 1
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
    }
  }
}
