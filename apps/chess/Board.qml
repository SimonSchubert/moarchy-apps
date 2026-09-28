import QtQuick
import "Chess.js" as C

// The board: two tones of the theme's brown, the men, and what the board has
// to say between two taps -- which piece is up, where it may go (a dot on an
// empty square, a ring round a piece that can be taken), the last move, and a
// king in check.
//
// Nothing is dragged. Dragging on a 43 px square with a thumb over it ends
// where the finger was, not where the eye was; a move is two taps.
//
// The men are rebuilt from the board after every move, and the one that just
// moved -- and a castling rook with it -- starts on the square it left and
// slides to the one it reached, so a move is seen rather than inferred.
Item {
  id: root
  property var app
  property var position: C.start()
  // Black at the bottom: when Black is the person, or turned by hand.
  property bool flipped: false
  property int selected: -1
  // Where the piece in hand may go: an array of squares.
  property var targets: []
  // The last move played, as a move code, or -1.
  property int last: -1
  // The keyboard's square, or -1.
  property int cursor: -1
  signal tapped(int cell)

  readonly property real side: Math.floor(Math.min(width, height) / 8) * 8
  readonly property real square: side / 8
  readonly property int check: C.inCheck(position) ? position.kings[position.turn] : -1

  // A square as the column and row it is drawn in.
  function column(cell) { return flipped ? 7 - (cell & 7) : (cell & 7) }
  function row(cell) { return flipped ? (cell >> 3) : 7 - (cell >> 3) }
  function cellAt(col, rw) { return flipped ? (rw * 8 + 7 - col) : ((7 - rw) * 8 + col) }

  Rectangle {
    id: board
    anchors.centerIn: parent
    width: root.side
    height: root.side
    // Square: `clip` cuts children to the rectangle and not to its radius,
    // so a rounded frame round square-cornered squares is two shapes.
    radius: 0
    color: root.app.ui.lightSquare
    border.width: 1
    border.color: root.app.ui.boardLine
    clip: true

    // The squares, and everything that is a wash over one.
    Repeater {
      model: 64
      delegate: Item {
        id: sq
        required property int index
        readonly property int col: index % 8
        readonly property int rw: Math.floor(index / 8)
        readonly property int cell: root.cellAt(col, rw)
        readonly property bool dark: (col + rw) % 2 === 1
        x: col * root.square
        y: rw * root.square
        width: root.square
        height: root.square

        Rectangle {
          anchors.fill: parent
          visible: sq.dark
          color: root.app.ui.darkSquare
        }
        Rectangle {
          anchors.fill: parent
          visible: root.last >= 0 && (C.moveFrom(root.last) === sq.cell || C.moveTo(root.last) === sq.cell)
          color: root.app.ui.alpha(root.app.ui.accent, 0.38)
        }
        Rectangle {
          anchors.fill: parent
          visible: root.selected === sq.cell
          color: root.app.ui.alpha(root.app.ui.accent, 0.48)
        }
        // A wash rather than an outline: the king is standing on it.
        Rectangle {
          anchors.fill: parent
          visible: root.check === sq.cell
          color: root.app.ui.alpha(root.app.ui.bad, 0.55)
        }
        Rectangle {
          anchors.fill: parent
          anchors.margins: 1
          visible: root.cursor === sq.cell
          color: "transparent"
          border.width: 3
          border.color: root.app.ui.accent
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.tapped(sq.cell)
        }
      }
    }

    // The men.
    Repeater {
      model: {
        var out = []
        for (var cell = 0; cell < 64; cell++)
          if (root.position.squares[cell]) out.push({ cell: cell, code: root.position.squares[cell] })
        return out
      }
      delegate: Piece {
        id: man
        required property var modelData
        app: root.app
        code: modelData.code
        size: root.square
        z: 1
        readonly property real homeX: root.column(modelData.cell) * root.square
        readonly property real homeY: root.row(modelData.cell) * root.square
        // Where it came from, when it is the piece that just moved.
        readonly property int came: {
          if (root.last < 0) return -1
          if (C.moveTo(root.last) === modelData.cell) return C.moveFrom(root.last)
          // The rook that castled with the king.
          var frm = C.moveFrom(root.last), to = C.moveTo(root.last)
          if ((root.position.squares[to] & 7) === C.KING && Math.abs(to - frm) === 2) {
            var rookTo = to > frm ? frm + 1 : frm - 1
            if (modelData.cell === rookTo) return to > frm ? frm + 3 : frm - 4
          }
          return -1
        }
        property real slide: 1
        x: came >= 0 ? root.column(came) * root.square + (homeX - root.column(came) * root.square) * slide : homeX
        y: came >= 0 ? root.row(came) * root.square + (homeY - root.row(came) * root.square) * slide : homeY
        Component.onCompleted: if (came >= 0 && root.animate) { slide = 0; slider.start() }
        NumberAnimation {
          id: slider
          target: man
          property: "slide"
          from: 0
          to: 1
          duration: 190
          easing.type: Easing.OutCubic
        }
      }
    }

    // A letter along the bottom and a number up the side, in the colour of
    // the other square, in the corner of the square and on top of the men: a
    // piece stands on a plinth that fills the bottom of its square, and a
    // label underneath it is a label the back rank has eaten.
    Repeater {
      model: 8
      delegate: Item {
        id: edge
        required property int index
        z: 4
        readonly property int fileCell: root.cellAt(index, 7)
        readonly property int rankCell: root.cellAt(0, index)
        Text {
          x: (edge.index + 1) * root.square - width - root.square * 0.08
          y: root.side - height - root.square * 0.02
          text: String.fromCharCode(97 + (edge.fileCell & 7))
          color: (edge.index + 7) % 2 === 1 ? root.app.ui.lightSquare : root.app.ui.darkSquare
          opacity: 0.9
          font.family: root.app.ui.font
          font.pixelSize: Math.max(8, root.square * 0.21)
          font.weight: Font.Bold
        }
        Text {
          x: root.square * 0.08
          y: edge.index * root.square + root.square * 0.02
          text: (edge.rankCell >> 3) + 1
          color: edge.index % 2 === 1 ? root.app.ui.lightSquare : root.app.ui.darkSquare
          opacity: 0.9
          font.family: root.app.ui.font
          font.pixelSize: Math.max(8, root.square * 0.21)
          font.weight: Font.Bold
        }
      }
    }

    // Where the piece in hand may go.
    Repeater {
      model: root.targets
      delegate: Item {
        id: hint
        required property var modelData
        readonly property bool take: !!root.position.squares[modelData] || (root.selected >= 0
          && (root.position.squares[root.selected] & 7) === C.PAWN && modelData === root.position.ep)
        x: root.column(modelData) * root.square
        y: root.row(modelData) * root.square
        width: root.square
        height: root.square
        z: 3
        Rectangle {
          anchors.centerIn: parent
          width: hint.take ? root.square * 0.88 : root.square * 0.30
          height: width
          radius: width / 2
          color: hint.take ? "transparent" : root.app.ui.alpha(root.app.ui.accent, 0.6)
          border.width: hint.take ? root.square * 0.07 : 0
          border.color: root.app.ui.alpha(root.app.ui.accent, 0.85)
        }
      }
    }
  }

  // Whether a move should slide: off for the first frame after a game is
  // loaded, when "the last move" is history and not something happening now.
  property bool animate: true
}
