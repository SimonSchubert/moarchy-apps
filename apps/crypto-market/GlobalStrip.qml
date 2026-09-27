import QtQuick
import "Api.mjs" as Api

// The whole market in four figures, the line CoinGecko opens every page with.
Item {
  id: root
  property var app
  property var stats: null

  readonly property string cur: app.currency
  readonly property bool narrow: width < 560
  readonly property var tiles: [
    { label: "Market cap", value: stats ? Api.money(stats.mcap[cur], cur) : Api.DASH, change: stats ? stats.ch24 : NaN },
    { label: "24h volume", value: stats ? Api.money(stats.vol[cur], cur) : Api.DASH, change: NaN },
    { label: "BTC dominance", value: stats ? Api.magnitude(stats.btc) : Api.DASH, change: NaN },
    { label: "ETH dominance", value: stats ? Api.magnitude(stats.eth) : Api.DASH, change: NaN }
  ]

  implicitHeight: grid.implicitHeight

  Grid {
    id: grid
    width: parent.width
    columns: root.narrow ? 2 : 4
    columnSpacing: 8
    rowSpacing: 8

    Repeater {
      model: root.tiles
      delegate: Rectangle {
        required property var modelData
        width: (grid.width - grid.columnSpacing * (grid.columns - 1)) / grid.columns
        height: 58
        radius: root.app.ui.radius
        color: root.app.ui.surface
        Column {
          anchors.left: parent.left
          anchors.leftMargin: 12
          anchors.right: parent.right
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          spacing: 2
          Text {
            text: modelData.label
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xs
          }
          Row {
            spacing: 6
            Text {
              text: modelData.value
              color: root.app.ui.text
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.md
              font.weight: Font.DemiBold
              font.features: ({ "tnum": 1 })
            }
            Change {
              visible: !isNaN(modelData.change)
              anchors.baseline: parent.children[0].baseline
              app: root.app
              value: modelData.change
              font.pixelSize: root.app.ui.fs.xs
            }
          }
        }
      }
    }
  }
}
