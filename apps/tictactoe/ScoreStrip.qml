import QtQuick
import "Tictactoe.js" as T

// The sitting's score: seat A, the draws, seat B. Each seat shows the mark it
// holds this game, because a rematch swaps them, and the seat on move is lit.
Row {
  id: root
  property var app
  property var names: ({ a: "", b: "" })
  property var marks: ({ a: T.CROSS, b: T.NOUGHT })
  property var series: ({ a: 0, b: 0, drawn: 0 })
  // The mark on move, or -1 when the game is over.
  property int turn: -1

  spacing: 8
  readonly property real cellWidth: (width - spacing * 2) / 3

  Repeater {
    model: [
      { seat: "a", label: root.names.a, mark: root.marks.a, value: root.series.a },
      { seat: "", label: "Draws", mark: -1, value: root.series.drawn },
      { seat: "b", label: root.names.b, mark: root.marks.b, value: root.series.b }
    ]
    delegate: Rectangle {
      id: box
      required property var modelData
      readonly property bool live: modelData.mark >= 0 && modelData.mark === root.turn
      width: root.cellWidth
      height: col.implicitHeight + 20
      radius: root.app.ui.radius
      color: live ? root.app.ui.accentSoft : root.app.ui.surface
      border.width: 1
      border.color: live ? root.app.ui.accent : root.app.ui.line

      Column {
        id: col
        anchors.centerIn: parent
        width: parent.width - 12
        spacing: 2
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: box.modelData.value
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xl
          font.weight: Font.Bold
          font.features: ({ "tnum": 1 })
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          text: box.modelData.label + (box.modelData.mark >= 0 ? " · " + T.NAMES[box.modelData.mark] : "")
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
