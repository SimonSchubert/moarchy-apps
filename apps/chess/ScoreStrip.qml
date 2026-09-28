import QtQuick
import "Chess.js" as C

// Both players: a king in their colour, their name, how far ahead they are,
// and the men they have taken -- overlapping when there are many, sorted by
// what they are worth so the row reads as "a queen and two pawns". The side
// on move is lit. The two boxes are mirrors, hanging off the outside edges.
Row {
  id: root
  property var app
  property var names: ({ 0: "White", 1: "Black" })
  // Every captured piece code, in the order taken.
  property var taken: []
  // Material on the board from White's side.
  property int balance: 0
  // The side on move, or -1 when the game is over.
  property int turn: -1

  spacing: 8

  Repeater {
    model: [C.WHITE, C.BLACK]
    delegate: Rectangle {
      id: box
      required property int modelData
      readonly property bool live: root.turn === modelData
      readonly property bool mirrored: modelData === C.BLACK
      // What this side has taken: the other side's men.
      readonly property var won: root.taken
        .filter(function (c) { return (c >> 3) !== box.modelData })
        .sort(function (a, b) { return (b & 7) - (a & 7) })
      readonly property int edge: modelData === C.WHITE ? Math.max(root.balance, 0) : Math.max(-root.balance, 0)
      width: (root.width - root.spacing) / 2
      height: 64
      radius: root.app.ui.radius
      color: live ? root.app.ui.accentSoft : root.app.ui.surface
      border.width: 1
      border.color: live ? root.app.ui.accent : root.app.ui.line

      Piece {
        id: king
        app: root.app
        code: (box.modelData << 3) | C.KING
        size: 34
        share: 0.9
        x: box.mirrored ? box.width - width - 10 : 10
        anchors.verticalCenter: parent.verticalCenter
      }
      Column {
        x: box.mirrored ? 10 : king.x + king.width + 8
        width: box.width - king.width - 28
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Row {
          layoutDirection: box.mirrored ? Qt.RightToLeft : Qt.LeftToRight
          width: parent.width
          spacing: 6
          Text {
            text: root.names[box.modelData]
            color: box.live ? root.app.ui.accent : root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
            font.weight: Font.Bold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: root.app.ui.tracking
          }
          Text {
            visible: box.edge > 0
            text: "+" + box.edge
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
            font.features: ({ "tnum": 1 })
          }
        }
        // The men taken: at their own size while they fit, then overlapping
        // by exactly as much as it takes.
        Item {
          id: row
          width: parent.width
          height: 18
          readonly property real step: box.won.length > 1 ? Math.min(13, (width - 18) / (box.won.length - 1)) : 13
          Repeater {
            model: box.won
            delegate: Piece {
              required property var modelData
              required property int index
              app: root.app
              code: modelData
              size: 18
              share: 0.9
              x: box.mirrored ? row.width - size - index * row.step : index * row.step
            }
          }
        }
      }
    }
  }
}
