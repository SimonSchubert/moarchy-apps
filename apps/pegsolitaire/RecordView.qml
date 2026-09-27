import QtQuick
import "kit"
import "Pegs.js" as P
import "Store.js" as S

// Every figure and the fewest pegs it has been left at. Fewest pegs rather
// than wins, because peg solitaire is a puzzle and not a contest: what
// somebody gets better at is finishing with three instead of five, and a win
// column would be a column of zeroes for a week and then a single one.
Column {
  id: root
  property var app
  property var game: S.fresh()
  readonly property var totals: S.totals(game)
  // The per-figure rows. The desktop's figure list carries them already.
  property bool perFigure: true

  spacing: 14

  Row {
    width: parent.width
    spacing: 8
    Repeater {
      model: [["Played", String(root.totals.played)],
              ["Figures", root.totals.best + "/" + P.FIGURES.length],
              ["In the middle", String(root.totals.perfect)]]
      delegate: Rectangle {
        required property var modelData
        width: (root.width - 16) / 3
        height: 72
        radius: root.app.ui.radius + 2
        color: root.app.ui.surface
        border.width: 1
        border.color: root.app.ui.divider
        Column {
          anchors.centerIn: parent
          spacing: 2
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: modelData[1]
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xl
            font.weight: Font.Bold
            font.features: ({ "tnum": 1 })
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: modelData[0]
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xs
          }
        }
      }
    }
  }

  Card {
    visible: root.perFigure
    app: root.app
    width: parent.width
    title: "Fewest pegs left"
    Repeater {
      model: P.FIGURES
      delegate: Item {
        id: row
        required property var modelData
        readonly property var entry: S.recordFor(root.game, modelData.key)
        width: parent.width
        height: 44
        Column {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - best.implicitWidth - 8
          spacing: 2
          Text {
            text: row.modelData.label
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.md
            font.weight: Font.DemiBold
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: row.entry.played
              ? row.entry.played + " played · " + row.entry.solved + " finished"
                + (row.modelData.centre ? " · " + row.entry.perfect + " in the middle" : "")
              : "Not played yet"
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
          }
        }
        Text {
          id: best
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: row.entry.best ? String(row.entry.best) : "—"
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.md
          font.features: ({ "tnum": 1 })
        }
      }
    }
  }

  Text {
    width: parent.width
    wrapMode: Text.Wrap
    text: "Only a board that will not move again is counted. Starting a figure over is how this game is played, not a defeat."
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.sm
  }
}
