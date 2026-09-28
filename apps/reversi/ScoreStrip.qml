import QtQuick
import "Reversi.js" as R

// Discs on the board, each side's: a swatch of the disc, the count, and who is
// playing it. The side on move is lit. The swatch is the answer to "which am
// I" by looking rather than by reading.
Row {
  id: root
  property var app
  property var counts: [2, 2]
  property var names: ({ 0: "Dark", 1: "Light" })
  // The side on move, or -1 when the game is over.
  property int turn: -1

  spacing: 8

  Repeater {
    model: [R.DARK, R.LIGHT]
    delegate: Rectangle {
      id: box
      required property int modelData
      readonly property bool live: root.turn === modelData
      width: (root.width - root.spacing) / 2
      height: 64
      radius: root.app.ui.radius
      color: live ? root.app.ui.accentSoft : root.app.ui.surface
      border.width: 1
      border.color: live ? root.app.ui.accent : root.app.ui.line

      Rectangle {
        id: swatch
        x: 14
        anchors.verticalCenter: parent.verticalCenter
        width: 28
        height: 28
        radius: 14
        color: box.modelData === R.DARK ? root.app.ui.darkDisc : root.app.ui.lightDisc
        border.width: 1
        border.color: box.modelData === R.DARK ? root.app.ui.darkRim : root.app.ui.lightRim
      }
      Column {
        anchors.left: swatch.right
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        Text {
          text: root.counts[box.modelData]
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
