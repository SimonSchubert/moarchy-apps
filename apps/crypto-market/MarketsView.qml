import QtQuick
import "Api.mjs" as Api

// The top N coins by market cap, CoinGecko's front page. Also the page a
// category opens into, with the category in the query and no global strip.
Item {
  id: root
  property var app
  property string category: ""
  property string categoryName: ""

  readonly property string cur: app.currency
  readonly property int topN: category ? 250 : app.store.topN
  readonly property int perPage: topN === 100 ? 100 : 250
  readonly property int maxPages: Math.max(1, Math.ceil(topN / perPage))
  property int pages: 1

  function url(p) { return Api.marketsUrl(cur, p, perPage, category) }

  readonly property var rows: {
    app.gecko.revision
    var out = []
    for (var p = 1; p <= pages; p++) {
      var page = app.gecko.peek(url(p))
      if (!page) break
      out = out.concat(page)
    }
    return out.slice(0, topN)
  }
  readonly property bool loading: { app.gecko.revision; return app.gecko.busy(url(1)) || (pages > 1 && app.gecko.busy(url(pages))) }
  readonly property string error: { app.gecko.revision; return app.gecko.error(url(1)) }
  readonly property var stats: { app.gecko.revision; return app.gecko.peek(Api.globalUrl()) }
  readonly property real updated: { app.gecko.revision; app.clock; return app.gecko.age(url(1)) }

  onCurChanged: pages = 1
  onTopNChanged: pages = 1

  function refresh(force) {
    var ttl = force ? 0 : app.store.refreshSec * 1000
    for (var p = 1; p <= pages; p++) app.gecko.want(url(p), "markets", ttl, force && p === 1)
    if (!category) app.gecko.want(Api.globalUrl(), "global", force ? 60000 : 300000, false)
  }

  function more() {
    if (pages >= maxPages) return
    var last = app.gecko.peek(url(pages))
    if (!last || last.length < perPage) return
    pages++
    app.gecko.want(url(pages), "markets", app.store.refreshSec * 1000, true)
  }

  readonly property var sorts: [
    { key: "rank", desc: false, label: "Market cap" },
    { key: "ch24", desc: true, label: "24h gainers" },
    { key: "ch24", desc: false, label: "24h losers" },
    { key: "vol", desc: true, label: "Volume" },
    { key: "ch7d", desc: true, label: "7d gainers" }
  ]
  function sortLabel() {
    for (var i = 0; i < sorts.length; i++)
      if (sorts[i].key === list.sortKey && sorts[i].desc === list.descending) return sorts[i].label
    return "Custom"
  }
  function nextSort() {
    var at = -1
    for (var i = 0; i < sorts.length; i++)
      if (sorts[i].key === list.sortKey && sorts[i].desc === list.descending) at = i
    var s = sorts[(at + 1) % sorts.length]
    list.sortKey = s.key
    list.descending = s.desc
    list.positionViewAtBeginning()
  }

  property alias list: list

  CoinList {
    id: list
    anchors.fill: parent
    app: root.app
    rows: root.rows
    loading: root.loading
    error: root.rows.length ? "" : root.error
    emptyGlyph: "󰄔"
    emptyTitle: root.category ? "No coins in this category" : "No market data yet"
    footerText: root.rows.length === 0 ? ""
      : root.loading && root.pages > 1 ? "Loading more…"
      : (root.category ? root.rows.length + " coins" : "Top " + root.rows.length + " by market cap")
        + (isFinite(root.updated) ? " · updated " + root.app.agoText(root.updated) : "")
    onEndReached: root.more()

    topContent: Component {
      Column {
        width: list.width
        topPadding: 4
        bottomPadding: 8
        spacing: 10

        GlobalStrip {
          visible: !root.category
          x: 12
          width: parent.width - 24
          app: root.app
          stats: root.stats
        }

        Item {
          x: 12
          width: parent.width - 24
          height: chips.height

          Row {
            id: chips
            spacing: 8
            Chip {
              visible: !root.category
              app: root.app
              text: "Top " + root.app.store.topN
              onClicked: {
                var steps = [100, 250, 500, 1000]
                root.app.store.set("topN", steps[(steps.indexOf(root.app.store.topN) + 1) % steps.length])
              }
            }
            Chip {
              app: root.app
              text: "Sort: " + root.sortLabel()
              onClicked: root.nextSort()
            }
          }

          IconButton {
            visible: !root.app.compact
            anchors.right: parent.right
            anchors.verticalCenter: chips.verticalCenter
            app: root.app
            glyph: "󰑐"
            label: "Refresh"
            size: 18
            onClicked: root.app.refresh(true)
          }
        }
      }
    }
  }
}
