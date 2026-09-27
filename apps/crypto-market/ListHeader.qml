import QtQuick
import "Cols.js" as Cols

// Column titles over a wide coin list. Pressing one sorts by it; pressing it
// again turns the order round.
Item {
  id: root
  property var app
  property bool showStar: true
  property string sortKey: "rank"
  property bool descending: false
  property bool sortable: true
  signal sortRequested(string key)

  readonly property var cols: Cols.layout(width)
  readonly property real nameWidth: line.width - (showStar ? app.ui.target : 0) - (cols.rank ? 40 : 0)
    - cols.price - cols.pct
    - (cols.h1 ? cols.pct : 0) - (cols.d7 ? cols.pct : 0)
    - (cols.vol ? cols.money : 0) - (cols.mcap ? cols.money : 0)
    - (cols.spark ? cols.sparkW + 12 : 0)

  // In the order CoinRow draws them; `show: false` columns take no room.
  readonly property var heads: [
    { key: "rank", title: "#", width: 40, show: cols.rank, right: false },
    { key: "name", title: "Coin", width: nameWidth, show: true, right: false },
    { key: "price", title: "Price", width: cols.price, show: true, right: true },
    { key: "ch1h", title: "1h", width: cols.pct, show: cols.h1, right: true },
    { key: "ch24", title: "24h", width: cols.pct, show: true, right: true },
    { key: "ch7d", title: "7d", width: cols.pct, show: cols.d7, right: true },
    { key: "vol", title: "24h volume", width: cols.money, show: cols.vol, right: true },
    { key: "mcap", title: "Market cap", width: cols.money, show: cols.mcap, right: true },
    { key: "", title: "Last 7 days", width: cols.sparkW + 12, show: cols.spark, right: true }
  ]

  visible: !cols.compact
  implicitHeight: cols.compact ? 0 : 34

  Row {
    id: line
    anchors.fill: parent
    anchors.leftMargin: root.showStar ? 0 : 12
    anchors.rightMargin: 12

    Item { visible: root.showStar; width: root.app.ui.target; height: 1 }

    Repeater {
      model: root.heads
      delegate: HeadCell {
        required property var modelData
        visible: modelData.show
        width: modelData.width
        app: root.app
        key: modelData.key
        title: modelData.title
        alignRight: modelData.right
        sortKey: root.sortKey
        descending: root.descending
        sortable: root.sortable
        onPicked: function (k) { root.sortRequested(k) }
      }
    }
  }

  Rectangle {
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    height: 1
    color: root.app.ui.divider
  }
}
