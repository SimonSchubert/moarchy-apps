import QtQuick
import "kit"
import "Store.js" as S

// Days played, days solved, the streak, and how many guesses each solved day
// took. The bar chart is the point: played and won are what every game here
// reports, and the spread is the one figure that says how somebody plays.
Column {
  id: root
  property var app
  property var store: S.fresh(0)
  readonly property var stats: store.stats
  readonly property int most: Math.max.apply(null, stats.spread)

  spacing: 14

  Row {
    width: parent.width
    spacing: 8
    Repeater {
      model: [["Played", root.stats.played], ["Solved", S.rate(root.store) + "%"],
              ["Streak", root.stats.streak], ["Best", root.stats.best]]
      delegate: Rectangle {
        required property var modelData
        width: (root.width - 24) / 4
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
    title: "Guesses"
    Repeater {
      model: root.stats.spread
      delegate: Row {
        id: bar
        required property int modelData
        required property int index
        width: parent.width
        spacing: 10
        Text {
          width: 14
          anchors.verticalCenter: parent.verticalCenter
          text: bar.index + 1
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
          font.weight: Font.DemiBold
        }
        // A bar with nothing in it still gets a sliver, so the chart reads as
        // six rows rather than however many have been used.
        Rectangle {
          readonly property real room: parent.width - 24
          width: Math.max(28, root.most ? room * bar.modelData / root.most : 0)
          height: 24
          radius: root.app.ui.radius / 2
          color: bar.modelData ? root.app.ui.correct : root.app.ui.well
          Text {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: bar.modelData
            color: bar.modelData ? root.app.ui.inkOnCorrect : root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
          }
        }
      }
    }
  }

  Text {
    width: parent.width
    wrapMode: Text.Wrap
    text: "A streak is days in a row. The day you skip ends it as surely as the day you miss. Practice words are not counted."
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.sm
  }
}
