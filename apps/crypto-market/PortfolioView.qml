import QtQuick
import "Api.mjs" as Api

// What you own, what it is worth now, and how that compares with what you
// paid. Prices for every holding come in one request.
Item {
  id: root
  property var app

  readonly property string cur: app.currency
  readonly property var holdings: app.store.holdings
  readonly property var ids: Object.keys(holdings)
  readonly property string url: ids.length ? Api.idsUrl(cur, ids) : ""
  readonly property var prices: { app.gecko.revision; return url ? (app.gecko.peek(url) || []) : [] }
  readonly property bool loading: { app.gecko.revision; return app.gecko.busy(url) }
  readonly property string error: { app.gecko.revision; return app.gecko.error(url) }

  readonly property var rows: {
    var byId = {}
    for (var i = 0; i < prices.length; i++) byId[prices[i].id] = prices[i]
    var out = []
    for (var j = 0; j < ids.length; j++) {
      var id = ids[j], h = holdings[id], p = byId[id]
      var pos = Api.position(h.txs, cur)
      var price = p ? p.price : NaN
      var value = pos.qty * price
      out.push({
        id: id, name: h.name || id, symbol: h.symbol || "", image: (p && p.image) || h.image || "",
        price: price, ch24: p ? p.ch24 : NaN, rank: p ? p.rank : NaN, spark: p ? p.spark : [],
        qty: pos.qty, value: value, cost: pos.cost, realized: pos.realized, foreign: pos.foreign,
        pnl: isNaN(pos.cost) ? NaN : value - pos.cost + pos.realized
      })
    }
    out.sort(function (a, b) { return (isNaN(b.value) ? -1 : b.value) - (isNaN(a.value) ? -1 : a.value) })
    return out
  }

  readonly property var totals: {
    var value = 0, before = 0, cost = 0, pnl = 0, priced = 0, partial = false
    for (var i = 0; i < rows.length; i++) {
      var r = rows[i]
      if (isNaN(r.value)) continue
      priced++
      value += r.value
      before += isNaN(r.ch24) ? r.value : r.value / (1 + r.ch24 / 100)
      if (isNaN(r.pnl)) partial = true
      else { cost += r.cost; pnl += r.pnl }
      if (r.foreign) partial = true
    }
    return { value: value, change: value - before, changePct: before > 0 ? (value - before) / before * 100 : NaN,
             cost: cost, pnl: pnl, pnlPct: cost > 0 ? pnl / cost * 100 : NaN, priced: priced, partial: partial }
  }

  readonly property var palette: [app.ui.accent, "#f7931a", "#627eea", "#14f195", "#e84142", "#8c8c8c"]

  // Largest five and everything else, for the allocation bar.
  readonly property var slices: {
    var t = totals.value
    if (!(t > 0)) return []
    var out = [], rest = 0
    for (var i = 0; i < rows.length; i++) {
      if (!(rows[i].value > 0)) continue
      if (out.length < 5) out.push({ label: rows[i].symbol, share: rows[i].value / t, color: palette[out.length] })
      else rest += rows[i].value
    }
    if (rest > 0) out.push({ label: "Other", share: rest / t, color: palette[5] })
    return out
  }

  function refresh(force) {
    if (url) app.gecko.want(url, "markets", force ? 0 : app.store.refreshSec * 1000, force)
  }
  onUrlChanged: refresh(false)

  property alias list: list

  ListView {
    id: list
    anchors.fill: parent
    clip: true
    model: root.rows
    property int cursor: -1

    function move(delta) {
      if (!count) return false
      cursor = Math.max(0, Math.min(count - 1, cursor + delta))
      positionViewAtIndex(cursor, ListView.Contain)
      return true
    }
    function activateCurrent() {
      if (cursor < 0) return false
      root.app.openCoin(root.rows[cursor])
      return true
    }
    function currentCoin() { return cursor >= 0 ? root.rows[cursor] : null }

    header: Column {
      width: list.width
      spacing: 12
      topPadding: 4
      bottomPadding: 8

      Rectangle {
        visible: root.rows.length > 0
        x: 12
        width: parent.width - 24
        height: summary.implicitHeight + 28
        radius: root.app.ui.radius + 2
        color: root.app.ui.surface

        Column {
          id: summary
          x: 14
          y: 14
          width: parent.width - 28
          spacing: 6

          Text {
            text: "Total balance"
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xs
          }
          Text {
            text: root.totals.priced ? Api.price(root.totals.value, root.cur) : (root.loading ? "Loading prices…" : Api.DASH)
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xxl
            font.weight: Font.Bold
            font.features: ({ "tnum": 1 })
          }
          Row {
            spacing: 6
            visible: root.totals.priced > 0
            Text {
              text: (root.totals.change >= 0 ? "+" : "") + Api.price(root.totals.change, root.cur)
              color: root.totals.change >= 0 ? root.app.ui.up : root.app.ui.down
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.sm
              font.weight: Font.Medium
            }
            Change {
              app: root.app
              badge: true
              value: root.totals.changePct
              font.pixelSize: root.app.ui.fs.xs
            }
            Text {
              text: "24h"
              color: root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.xs
              anchors.verticalCenter: parent.verticalCenter
            }
          }
          Row {
            spacing: 6
            visible: root.totals.priced > 0 && root.totals.cost > 0
            Text {
              text: "All-time profit"
              color: root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.sm
            }
            Text {
              text: (root.totals.pnl >= 0 ? "+" : "") + Api.price(root.totals.pnl, root.cur) + "  (" + Api.percent(root.totals.pnlPct) + ")"
              color: root.totals.pnl >= 0 ? root.app.ui.up : root.app.ui.down
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.sm
              font.weight: Font.DemiBold
            }
          }
          Text {
            visible: root.totals.partial
            width: parent.width
            wrapMode: Text.Wrap
            text: "Profit counts only trades entered in " + root.cur.toUpperCase() + "."
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xs
          }

          // Allocation.
          Item { width: 1; height: 4 }
          Row {
            width: parent.width
            height: 10
            spacing: 2
            visible: root.slices.length > 0
            Repeater {
              model: root.slices
              delegate: Rectangle {
                required property var modelData
                width: Math.max(3, (parent.width - 2 * (root.slices.length - 1)) * modelData.share)
                height: 10
                radius: 3
                color: modelData.color
              }
            }
          }
          Flow {
            width: parent.width
            spacing: 12
            visible: root.slices.length > 0
            Repeater {
              model: root.slices
              delegate: Row {
                required property var modelData
                spacing: 5
                Rectangle { width: 9; height: 9; radius: 5; color: modelData.color; anchors.verticalCenter: parent.verticalCenter }
                Text {
                  text: modelData.label + " " + Api.magnitude(modelData.share * 100)
                  color: root.app.ui.muted
                  font.family: root.app.ui.font
                  font.pixelSize: root.app.ui.fs.xs
                }
              }
            }
          }
        }
      }

      Item {
        x: 12
        width: parent.width - 24
        height: root.rows.length ? 40 : 0
        visible: root.rows.length > 0
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.rows.length + (root.rows.length === 1 ? " holding" : " holdings")
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.md
          font.weight: Font.DemiBold
        }
        Chip {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          app: root.app
          text: "+ Add transaction"
          onClicked: root.app.startPick()
        }
      }

      Placeholder {
        width: parent.width
        visible: root.rows.length === 0
        app: root.app
        glyph: "󰖄"
        title: "Start your portfolio"
        detail: "Add what you bought and when, and see what it is worth today, with profit and loss per coin."
        action: "Add a coin"
        onTriggered: root.app.startPick()
      }
    }

    delegate: Item {
      id: row
      required property var modelData
      required property int index
      width: list.width
      height: 62

      Rectangle {
        anchors.fill: parent
        color: row.index === list.cursor ? root.app.ui.selected : rowMouse.pressed ? root.app.ui.pressed
          : rowMouse.containsMouse ? root.app.ui.hover : "transparent"
      }
      MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.app.openCoin(row.modelData)
      }
      CoinLogo {
        id: logo
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        app: root.app
        size: 30
        source: row.modelData.image
        symbol: row.modelData.symbol
      }
      Column {
        anchors.left: logo.right
        anchors.leftMargin: 10
        anchors.right: figures.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Row {
          spacing: 6
          Text {
            text: row.modelData.symbol
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.md
            font.weight: Font.DemiBold
          }
          Change {
            anchors.baseline: parent.children[0].baseline
            app: root.app
            value: row.modelData.ch24
            font.pixelSize: root.app.ui.fs.xs
          }
        }
        Text {
          width: parent.width
          text: Api.plain(row.modelData.qty) + " · " + Api.price(row.modelData.price, root.cur)
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xs
          elide: Text.ElideRight
        }
      }
      Column {
        id: figures
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 128
        spacing: 2
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignRight
          text: Api.price(row.modelData.value, root.cur)
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.md
          font.weight: Font.Medium
          font.features: ({ "tnum": 1 })
          fontSizeMode: Text.HorizontalFit
          minimumPixelSize: root.app.ui.fs.xs
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignRight
          visible: !isNaN(row.modelData.pnl)
          text: (row.modelData.pnl >= 0 ? "+" : "") + Api.price(row.modelData.pnl, root.cur)
          color: row.modelData.pnl >= 0 ? root.app.ui.up : root.app.ui.down
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xs
          fontSizeMode: Text.HorizontalFit
          minimumPixelSize: 10
        }
      }
      Rectangle {
        anchors.bottom: parent.bottom
        x: 12
        width: parent.width - 24
        height: 1
        color: root.app.ui.divider
      }
    }

    footer: Item {
      width: list.width
      height: 44
      Text {
        anchors.centerIn: parent
        visible: root.error !== "" && root.rows.length > 0
        text: root.error
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
      }
    }
  }
}
