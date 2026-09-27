import QtQuick
import "kit"
import "Store.js" as S
import "Ai.js" as Ai

// Games played against the computer, by difficulty. Two people passing a
// phone across a table are not playing against the app, and a tally that
// counted those would be counting both of them at once.
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
      model: [["Played", root.totals.played], ["Won", root.totals.won],
              ["Best win", root.totals.best ? root.totals.best : "—"]]
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
    title: "By difficulty"
    Repeater {
      model: Ai.LEVELS
      delegate: Item {
        id: row
        required property var modelData
        readonly property var entry: S.recordFor(root.game, modelData.key)
        width: parent.width
        height: 44
        Column {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - share.implicitWidth - 8
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
              ? row.entry.won + " won · " + row.entry.lost + " lost · " + row.entry.drawn + " drawn"
              : row.modelData.blurb
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
          }
        }
        Text {
          id: share
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: row.entry.played ? Math.round(100 * row.entry.won / row.entry.played) + "%" : "—"
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
    text: "Best win is how many pieces you had left. Winning with eight and winning with three are the same result and different games."
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.sm
  }
}
