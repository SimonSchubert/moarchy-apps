import QtQuick
import "Tictactoe.js" as T

// The board, drawn the way a person draws it: a hash of four rules that
// overshoot their crossings, and no box around it. A bordered three by three
// is a chessboard with most of the squares missing.
//
// A ring for O, two strokes for X: shape before colour, because the two are
// told apart by anyone, where two hues are not. A won game is struck through,
// and every mark not in the line fades.
Item {
  id: root
  property var app
  property var position: T.EMPTY
  // The winning three, in order, or [].
  property var line: []
  signal tapped(int cell)

  readonly property real side: Math.min(width, height)
  readonly property real square: side / 3
  readonly property real rule: Math.max(3, Math.round(side * 0.014))
  readonly property color pencil: app.ui.alpha(app.ui.text, 0.28)

  Item {
    id: board
    anchors.centerIn: parent
    width: root.side
    height: root.side

    // The hash. Each rule stops short of the edge, so the ends are rounded
    // strokes rather than the sides of a box.
    Repeater {
      model: [1, 2]
      delegate: Rectangle {
        required property int modelData
        x: root.square * modelData - root.rule / 2
        y: root.side * 0.04
        width: root.rule
        height: root.side * 0.92
        radius: width / 2
        color: root.pencil
      }
    }
    Repeater {
      model: [1, 2]
      delegate: Rectangle {
        required property int modelData
        y: root.square * modelData - root.rule / 2
        x: root.side * 0.04
        height: root.rule
        width: root.side * 0.92
        radius: height / 2
        color: root.pencil
      }
    }

    Repeater {
      model: 9
      delegate: Item {
        id: cell
        required property int index
        x: (index % 3) * root.square
        y: Math.floor(index / 3) * root.square
        width: root.square
        height: root.square

        readonly property int owner: (root.position.x >> index) & 1 ? T.CROSS
          : (root.position.o >> index) & 1 ? T.NOUGHT : -1
        readonly property bool faded: root.line.length > 0 && root.line.indexOf(index) < 0

        Accessible.role: Accessible.Button
        Accessible.name: "Square " + (index + 1) + (owner === T.CROSS ? ", X" : owner === T.NOUGHT ? ", O" : ", empty")

        // Where a cursor is, on an empty square: the only box on the board.
        Rectangle {
          anchors.fill: parent
          anchors.margins: root.rule * 2.5
          radius: root.app.ui.radius
          visible: cell.owner < 0 && root.line.length === 0 && (mouse.containsMouse || mouse.pressed)
          color: mouse.pressed ? root.app.ui.pressed : root.app.ui.hover
        }

        Item {
          anchors.fill: parent
          opacity: cell.faded ? 0.3 : 1
          // Faded as one picture: without a layer the two strokes of an X
          // each fade, and where they cross is twice as dark.
          layer.enabled: opacity < 1
          Behavior on opacity { NumberAnimation { duration: 220 } }

          Rectangle {
            anchors.centerIn: parent
            visible: cell.owner === T.NOUGHT
            width: parent.width * 0.52
            height: width
            radius: width / 2
            color: "transparent"
            border.width: Math.max(3, parent.width * 0.09)
            border.color: root.app.ui.nought
            scale: cell.owner === T.NOUGHT ? 1 : 0
            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
          }

          Item {
            anchors.centerIn: parent
            visible: cell.owner === T.CROSS
            width: parent.width * 0.48
            height: width
            scale: cell.owner === T.CROSS ? 1 : 0
            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
            Repeater {
              model: [45, -45]
              delegate: Rectangle {
                required property var modelData
                anchors.centerIn: parent
                width: parent.width * 1.28
                height: Math.max(3, parent.width * 0.18)
                radius: height / 2
                color: root.app.ui.cross
                rotation: modelData
              }
            }
          }
        }

        // The square's number, for the keyboard, where there is one.
        Text {
          visible: !root.app.compact && cell.owner < 0 && root.line.length === 0
          x: root.rule * 3
          y: root.rule * 2
          text: cell.index + 1
          color: root.app.ui.muted
          opacity: 0.55
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xs
        }

        MouseArea {
          id: mouse
          anchors.fill: parent
          hoverEnabled: !root.app.compact
          cursorShape: cell.owner < 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.tapped(cell.index)
        }
      }
    }

    // Three in a row, struck through from the first square to the last and a
    // little past both, in the colour of the mark that made it.
    Rectangle {
      id: strike
      visible: root.line.length === 3
      readonly property var a: visible ? centre(root.line[0]) : ({ x: 0, y: 0 })
      readonly property var b: visible ? centre(root.line[2]) : ({ x: 0, y: 0 })
      readonly property real dx: b.x - a.x
      readonly property real dy: b.y - a.y
      readonly property real length: Math.sqrt(dx * dx + dy * dy) + root.square * 0.7
      function centre(i) { return { x: (i % 3 + 0.5) * root.square, y: (Math.floor(i / 3) + 0.5) * root.square } }
      readonly property bool crossWon: visible && ((root.position.x >> root.line[0]) & 1) === 1

      width: length
      height: Math.max(4, root.square * 0.07)
      radius: height / 2
      x: (a.x + b.x) / 2 - width / 2
      y: (a.y + b.y) / 2 - height / 2
      rotation: Math.atan2(dy, dx) * 180 / Math.PI
      color: crossWon ? root.app.ui.cross : root.app.ui.nought
      antialiasing: true
    }
  }
}
