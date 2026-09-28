import QtQuick
import "Mill.js" as M

// Each side: a swatch of its piece, a count, and who is playing it. The count
// is "on the board plus in the hand" -- 7+2 -- because in the first half of
// this game those are two different things and both matter: three on the
// board and six to come is not trouble, three and none to come is about to
// fly. The side on move is lit.
Row {
  id: root
  property var app
  property var position: M.OPENING
  property var names: ({ 0: "White", 1: "Black" })
  // The side on move, or -1 when the game is over.
  property int turn: -1

  spacing: 8

  Repeater {
    model: [M.WHITE, M.BLACK]
    delegate: Rectangle {
      id: box
      required property int modelData
      readonly property bool live: root.turn === modelData
      readonly property int onBoard: M.count(root.position, modelData)
      readonly property int inHand: M.left(root.position, modelData)
      width: (root.width - root.spacing) / 2
      height: 64
      radius: root.app.ui.radius
      color: live ? root.app.ui.accentSoft : root.app.ui.surface
      border.width: 1
      border.color: live ? root.app.ui.accent : root.app.ui.line
      Accessible.name: root.names[modelData] + ": " + onBoard + " on the board" + (inHand ? ", " + inHand + " to place" : "")

      Rectangle {
        id: swatch
        x: 14
        anchors.verticalCenter: parent.verticalCenter
        width: 28
        height: 28
        radius: 14
        color: box.modelData === M.BLACK ? root.app.ui.blackMan : root.app.ui.whiteMan
        border.width: 1
        border.color: box.modelData === M.BLACK ? root.app.ui.blackRim : root.app.ui.whiteRim
      }
      Column {
        anchors.left: swatch.right
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        Text {
          text: box.inHand ? box.onBoard + "+" + box.inHand : box.onBoard
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xl
          font.weight: Font.Bold
          font.features: ({ "tnum": 1 })
        }
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: root.names[box.modelData]
          color: box.live ? root.app.ui.accent : root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xs
          font.weight: box.live ? Font.Bold : Font.Normal
          font.capitalization: Font.AllUppercase
          font.letterSpacing: root.app.ui.tracking
        }
      }
    }
  }
}
