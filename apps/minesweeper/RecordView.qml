import QtQuick
import "kit"
import "Store.js" as S
import "Minesweeper.js" as M

// Games played, by board, with the fastest clear on each.
//
// A best time and not a win percentage at the top, because a win percentage
// in this game is mostly a report on how often somebody guessed: every board
// has positions where nothing can be deduced, and the only honest thing to say
// about losing one of those is that it happened.
Column {
  id: root
  property var app
  property var game: S.fresh()
  readonly property var totals: S.totals(game)

  spacing: 14

  Row {
    width: parent.width
    spacing: 8
    Repeater {
      model: [["Played", root.totals.played], ["Cleared", root.totals.won], ["In a row", root.totals.longest]]
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
    app: root.app
    width: parent.width
    title: "Fastest clear"
    Repeater {
      model: M.LEVELS
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
              ? row.entry.won + " of " + row.entry.played + " cleared · best run " + row.entry.longest
              : row.modelData.width + " × " + row.modelData.height + ", " + row.modelData.mines + " mines"
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
          }
        }
        Text {
          id: best
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: row.entry.best ? M.clock(row.entry.best) : "—"
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
          font.features: ({ "tnum": 1 })
        }
      }
    }
  }

  Text {
    width: parent.width
    wrapMode: Text.Wrap
    text: "The clock only runs while the game is open. A board left open in a pocket is not a slow game."
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.sm
  }
}
