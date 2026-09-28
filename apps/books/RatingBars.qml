import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "OpenLibrary.js" as OL

// How Open Library's readers rated a book: five bars, fives at the top, each
// as long as its share of the most common rating, with the count after it.
Column {
  id: root
  property var app
  // [ones, twos, threes, fours, fives]
  property var counts: [0, 0, 0, 0, 0]
  readonly property real most: Math.max(1, Math.max.apply(null, counts))

  spacing: 5

  Repeater {
    model: 5
    delegate: Row {
      id: bar
      required property int index
      readonly property int stars: 5 - index
      readonly property real n: root.counts[stars - 1] || 0
      width: root.width
      spacing: 8
      Row {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        width: 24
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: bar.stars
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xs
          font.weight: Font.Bold
        }
        Icon { anchors.verticalCenter: parent.verticalCenter; app: root.app; text: KG.star; size: 10; color: root.app.ui.muted }
      }
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: root.width - label.width - count.width - 16
        height: 8
        radius: root.app.ui.radius > 0 ? 2 : 0
        color: root.app.ui.well
        Rectangle {
          width: Math.max(bar.n > 0 ? 2 : 0, parent.width * bar.n / root.most)
          height: parent.height
          radius: parent.radius
          color: root.app.ui.alpha(root.app.ui.warn, 0.35 + 0.13 * bar.stars)
        }
      }
      Text {
        id: count
        anchors.verticalCenter: parent.verticalCenter
        width: 40
        horizontalAlignment: Text.AlignRight
        text: OL.count(bar.n)
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
        font.features: ({ "tnum": 1 })
      }
    }
  }
}
