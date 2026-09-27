import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Store.js" as S

// Games played, the best score, and how far the wall has gone. Three numbers
// and no more: this is an arcade game, and the only things anybody has ever
// wanted to know about one are what they scored and how far they got.
Column {
  id: root
  property var app
  property var stats: ({ played: 0, best: 0, furthest: 0, cleared: 0 })

  spacing: 14

  Row {
    width: parent.width
    spacing: 8
    Repeater {
      model: [["Played", root.stats.played], ["Best", root.stats.best],
              ["Furthest", root.stats.furthest + "/" + S.levelCount()]]
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
    title: "Walls"
    Repeater {
      model: S.levelCount()
      delegate: Item {
        id: row
        required property int index
        readonly property bool reached: root.stats.furthest > index
        width: parent.width
        height: 40
        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: 2
          Text {
            text: (row.index + 1) + ". " + S.levelName(row.index)
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.md
            font.weight: Font.DemiBold
          }
          Text {
            text: row.reached ? "Reached" : "Not reached yet"
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
          }
        }
        Icon {
          visible: row.reached
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          app: root.app
          text: KG.check
          size: 18
          color: root.app.ui.good
        }
      }
    }
  }

  Text {
    width: parent.width
    wrapMode: Text.Wrap
    text: "Past the last wall it starts again, faster. The game gets harder because the ball does, not because somebody wrote a hundred walls."
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.sm
  }
}
