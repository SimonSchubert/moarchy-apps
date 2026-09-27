import QtQuick
import "Api.mjs" as Api

// The coins you starred, in one request however many there are.
Item {
  id: root
  property var app

  readonly property var ids: app.store.watchlist
  readonly property string url: ids.length ? Api.idsUrl(app.currency, ids) : ""
  readonly property var rows: { app.gecko.revision; return url ? (app.gecko.peek(url) || []) : [] }
  readonly property bool loading: { app.gecko.revision; return app.gecko.busy(url) }
  readonly property string error: { app.gecko.revision; return app.gecko.error(url) }
  // Counted the way the badges print them: +0.0% is neither.
  readonly property int ups: rows.filter(function (r) { return r.ch24 >= 0.05 }).length
  readonly property int downs: rows.filter(function (r) { return r.ch24 <= -0.05 }).length

  // Rows follow the order the coins were starred in unless a column is sorted.
  readonly property var ordered: {
    var byId = {}
    for (var i = 0; i < rows.length; i++) byId[rows[i].id] = rows[i]
    var out = []
    for (var j = 0; j < ids.length; j++) if (byId[ids[j]]) out.push(byId[ids[j]])
    return out
  }

  function refresh(force) {
    if (url) app.gecko.want(url, "markets", force ? 0 : app.store.refreshSec * 1000, force)
  }
  onUrlChanged: refresh(false)

  property alias list: list

  CoinList {
    id: list
    anchors.fill: parent
    app: root.app
    rows: root.ordered
    sortKey: "custom"
    loading: root.loading
    error: root.rows.length ? "" : root.error
    emptyGlyph: "󰓒"
    emptyTitle: "Your watchlist is empty"
    emptyDetail: "Tap the star next to any coin to follow it here."
    emptyAction: "Browse markets"
    onEmptyTriggered: root.app.setTab("markets")
    footerText: root.rows.length ? root.rows.length + " coins · " + root.ups + " up, " + root.downs + " down today" : ""

    topContent: Component {
      Item {
        width: list.width
        height: root.rows.length ? 8 : 0
      }
    }
  }
}
