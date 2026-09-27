import QtQuick
import "kit"
import "Klondike.js" as K
import "Store.js" as S

// Games played, by how many cards a tap on the stock turns over. Two tallies
// and not one: draw one is winnable about four times in five with good play
// and draw three is not, so a single win percentage across both would mostly
// report which setting somebody had been using that month.
Column {
  id: root
  property var app
  property var game: S.fresh()
  readonly property var totals: S.totals(game)
  readonly property var names: ({ 1: "Draw one", 3: "Draw three" })

  spacing: 14

  Row {
    width: parent.width
    spacing: 8
    Repeater {
      model: [["Played", root.totals.played], ["Won", root.totals.won], ["Fewest", root.totals.best || "—"]]
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
    title: "By deal"
    Repeater {
      model: K.DRAWS
      delegate: Item {
        id: row
        required property int modelData
        readonly property var entry: S.recordFor(root.game, modelData)
        width: parent.width
        height: 44
        Column {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - share.implicitWidth - 8
          spacing: 2
          Text {
            text: root.names[row.modelData]
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.md
            font.weight: Font.DemiBold
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: row.entry.played
              ? row.entry.won + " won · longest run " + row.entry.longest + (row.entry.best ? " · fewest " + row.entry.best + " moves" : "")
              : "Not played yet"
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
    text: "A deal you walk away from counts as a loss. A deal you look at and replace without playing does not."
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.sm
  }
}
