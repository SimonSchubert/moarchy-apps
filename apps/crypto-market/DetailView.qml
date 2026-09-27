import QtQuick
import "Api.mjs" as Api

// One coin: price and chart, the figures CoinGecko puts beside them, what you
// hold of it, a converter, and what the project says about itself.
//
// Painted at once from the list row that opened it (`seed`), then filled in
// as the coin's own page arrives, so tapping a coin never shows an empty
// screen while CoinGecko thinks.
Item {
  id: root
  property var app
  property string coinId: ""
  property var seed: null
  property bool pane: false          // the right half of a split, not a page

  property string days: "7"
  readonly property var ranges: [
    { days: "1", label: "24h" }, { days: "7", label: "7d" }, { days: "30", label: "1M" },
    { days: "90", label: "3M" }, { days: "365", label: "1Y" }, { days: "max", label: "Max" }
  ]

  readonly property string cur: app.currency
  readonly property string coinUrl: Api.coinUrl(coinId)
  readonly property string chartUrl: Api.chartUrl(coinId, cur, days)
  readonly property var full: { app.gecko.revision; return app.gecko.peek(coinUrl) }
  readonly property var coin: full || seed || { id: coinId, name: "", symbol: "" }
  readonly property var points: { app.gecko.revision; return app.gecko.peek(chartUrl) || [] }
  readonly property bool loading: { app.gecko.revision; return app.gecko.busy(coinUrl) }
  readonly property bool chartLoading: { app.gecko.revision; return app.gecko.busy(chartUrl) }
  readonly property string error: { app.gecko.revision; return full ? "" : app.gecko.error(coinUrl) }
  readonly property string chartError: { app.gecko.revision; return app.gecko.error(chartUrl) }
  readonly property bool starred: { app.store.prefs; return app.store.starred(coinId) }
  readonly property var txs: { app.store.prefs; var h = app.store.holdings[coinId]; return h ? (h.txs || []) : [] }
  readonly property var pos: Api.position(txs, cur)

  // A detail page's price is its own, but a list row refreshed since may be
  // newer; show whichever is younger.
  readonly property real price: coin.price

  readonly property bool wide: width >= 620
  readonly property int pad: app.compact ? 14 : 20

  function refresh(force) {
    app.gecko.want(coinUrl, "coin", force ? 0 : 120000, true)
    app.gecko.want(chartUrl, "chart", force ? 0 : (days === "1" ? 300000 : 1800000), true)
  }
  onChartUrlChanged: app.gecko.want(chartUrl, "chart", days === "1" ? 300000 : 1800000, true)
  onCoinIdChanged: { flick.contentY = 0; refresh(false) }
  Component.onCompleted: refresh(false)
  Component.onDestruction: if (app && app.gecko) app.gecko.forget([coinUrl, chartUrl])

  function stepRange(delta) {
    var i = 0
    for (var k = 0; k < ranges.length; k++) if (ranges[k].days === days) i = k
    days = ranges[Math.max(0, Math.min(ranges.length - 1, i + delta))].days
  }

  function openLink(url) {
    if (/^https:\/\//i.test(url)) Qt.openUrlExternally(url)
  }

  // Opaque when the page covers the list. Beside the list it needs no ground
  // of its own.
  Rectangle {
    visible: !root.pane
    anchors.fill: parent
    color: root.app.ui.bg
  }

  // ---------------------------------------------------------------- top bar
  Item {
    id: topBar
    width: parent.width
    height: 56
    z: 2

    IconButton {
      id: backBtn
      x: 4
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      glyph: "󰁍"
      label: root.pane ? "Close coin" : "Back"
      onClicked: if (!root.app.back()) root.app.dismiss()
    }
    CoinLogo {
      id: headLogo
      anchors.left: backBtn.right
      anchors.leftMargin: 4
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      size: 30
      source: root.coin.image || ""
      symbol: root.coin.symbol || ""
    }
    Column {
      anchors.left: headLogo.right
      anchors.leftMargin: 10
      anchors.right: actions.left
      anchors.rightMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      Text {
        width: parent.width
        text: root.coin.name || "Loading…"
        color: root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.lg
        font.weight: Font.DemiBold
        elide: Text.ElideRight
      }
      Text {
        text: (root.coin.symbol || "") + (isNaN(root.coin.rank) || root.coin.rank === undefined ? "" : "  ·  Rank #" + root.coin.rank)
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
      }
    }
    Row {
      id: actions
      anchors.right: parent.right
      anchors.rightMargin: 4
      anchors.verticalCenter: parent.verticalCenter
      IconButton {
        app: root.app
        glyph: "󰐕"
        label: "Add transaction"
        onClicked: root.app.startTx(root.coin)
      }
      IconButton {
        app: root.app
        glyph: root.starred ? "󰓎" : "󰓒"
        label: root.starred ? "Remove from watchlist" : "Add to watchlist"
        color: root.starred ? root.app.ui.star : root.app.ui.text
        onClicked: root.app.store.toggleStar(root.coinId)
      }
    }
    Rectangle {
      anchors.bottom: parent.bottom
      width: parent.width
      height: 1
      color: root.app.ui.divider
      opacity: flick.contentY > 4 ? 1 : 0
    }
  }

  // ---------------------------------------------------------------- body
  Flickable {
    id: flick
    anchors.top: topBar.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentWidth: width
    contentHeight: body.implicitHeight + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick

    Column {
      id: body
      x: root.pad
      width: flick.width - root.pad * 2
      spacing: 18
      topPadding: 6

      // Price.
      Column {
        width: parent.width
        spacing: 4
        Row {
          spacing: 10
          Text {
            id: bigPrice
            text: Api.price(root.price, root.cur)
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xxl
            font.weight: Font.Bold
            font.features: ({ "tnum": 1 })
          }
          Change {
            anchors.verticalCenter: bigPrice.verticalCenter
            app: root.app
            badge: true
            value: root.coin.ch24
            font.pixelSize: root.app.ui.fs.sm
          }
        }
        Text {
          visible: text !== ""
          text: root.error ? root.error
            : root.loading && !root.full ? "Loading details…"
            : !isNaN(root.coin.watchers) ? Api.compact(root.coin.watchers) + " CoinGecko users watch " + (root.coin.symbol || "this coin") : ""
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xs
        }
      }

      // Chart and its ranges.
      Column {
        width: parent.width
        spacing: 10
        Row {
          id: rangeRow
          width: parent.width
          spacing: 6
          Repeater {
            model: root.ranges
            delegate: Chip {
              required property var modelData
              app: root.app
              width: (rangeRow.width - rangeRow.spacing * (root.ranges.length - 1)) / root.ranges.length
              text: modelData.label
              selected: root.days === modelData.days
              onClicked: root.days = modelData.days
            }
          }
        }
        PriceChart {
          width: parent.width
          height: root.app.compact ? 210 : 260
          app: root.app
          points: root.points
          days: root.days
          currency: root.cur
          loading: root.chartLoading
          error: root.points.length ? "" : root.chartError
        }
      }

      // Change over each period.
      Rectangle {
        width: parent.width
        height: 58
        radius: root.app.ui.radius
        color: root.app.ui.surface
        Row {
          anchors.fill: parent
          Repeater {
            model: [
              { label: "1h", value: root.coin.ch1h }, { label: "24h", value: root.coin.ch24 },
              { label: "7d", value: root.coin.ch7d }, { label: "30d", value: root.coin.ch30d },
              { label: "1y", value: root.coin.ch1y }
            ]
            delegate: Column {
              required property var modelData
              width: parent.width / 5
              anchors.verticalCenter: parent.verticalCenter
              spacing: 3
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: modelData.label
                color: root.app.ui.muted
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.xs
              }
              Change {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 4
                app: root.app
                value: modelData.value === undefined ? NaN : modelData.value
                font.pixelSize: root.app.ui.fs.xs
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 10
                horizontalAlignment: Text.AlignHCenter
              }
            }
          }
        }
      }

      RangeBar {
        width: parent.width
        app: root.app
        low: root.coin.low24
        high: root.coin.high24
        value: root.price
        currency: root.cur
      }

      // Figures.
      Grid {
        id: stats
        width: parent.width
        columns: root.wide ? 3 : 2
        columnSpacing: 8
        rowSpacing: 8
        readonly property real cell: (width - columnSpacing * (columns - 1)) / columns
        readonly property var c: root.coin

        StatTile {
          width: stats.cell; app: root.app
          label: "Market cap"
          value: Api.money(stats.c.mcap, root.cur)
          sub: isNaN(stats.c.rank) || stats.c.rank === undefined ? "" : "Rank #" + stats.c.rank
        }
        StatTile {
          width: stats.cell; app: root.app
          label: "Diluted valuation"
          value: Api.money(stats.c.fdv, root.cur)
        }
        StatTile {
          width: stats.cell; app: root.app
          label: "24h trading volume"
          value: Api.money(stats.c.vol, root.cur)
          sub: stats.c.mcap > 0 && !isNaN(stats.c.vol) ? "Vol / Mkt cap " + (stats.c.vol / stats.c.mcap).toFixed(4) : ""
        }
        StatTile {
          width: stats.cell; app: root.app
          label: "Circulating supply"
          value: Api.supply(stats.c.circ, stats.c.symbol)
          sub: stats.c.max > 0 && stats.c.circ > 0 ? Api.magnitude(stats.c.circ / stats.c.max * 100) + " of max supply" : ""
        }
        StatTile {
          width: stats.cell; app: root.app
          label: "Total supply"
          value: Api.supply(stats.c.total, stats.c.symbol)
        }
        StatTile {
          width: stats.cell; app: root.app
          label: "Max supply"
          value: Api.supply(stats.c.max, stats.c.symbol)
        }
        StatTile {
          width: stats.cell; app: root.app
          label: "All-time high"
          value: Api.price(stats.c.ath, root.cur)
          sub: isNaN(stats.c.athChange) || stats.c.athChange === undefined ? ""
            : Api.percent(stats.c.athChange) + " · " + Api.date(stats.c.athDate)
          subColor: stats.c.athChange < 0 ? root.app.ui.down : root.app.ui.up
        }
        StatTile {
          width: stats.cell; app: root.app
          label: "All-time low"
          value: Api.price(stats.c.atl, root.cur)
          sub: isNaN(stats.c.atlChange) || stats.c.atlChange === undefined ? ""
            : Api.percent(stats.c.atlChange) + " · " + Api.date(stats.c.atlDate)
          subColor: stats.c.atlChange < 0 ? root.app.ui.down : root.app.ui.up
        }
        StatTile {
          visible: !!(stats.c.genesis || stats.c.algorithm)
          width: stats.cell; app: root.app
          label: stats.c.algorithm ? "Hashing algorithm" : "Launched"
          value: stats.c.algorithm || Api.date(stats.c.genesis)
          sub: stats.c.algorithm && stats.c.genesis ? "Launched " + Api.date(stats.c.genesis) : ""
        }
      }

      // What you hold.
      Rectangle {
        width: parent.width
        height: holdCol.implicitHeight + 24
        radius: root.app.ui.radius
        color: root.app.ui.surface

        Column {
          id: holdCol
          x: 12
          y: 12
          width: parent.width - 24
          spacing: 8

          Item {
            width: parent.width
            height: 40
            Column {
              anchors.verticalCenter: parent.verticalCenter
              Text {
                text: "Your holdings"
                color: root.app.ui.text
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.md
                font.weight: Font.DemiBold
              }
              Text {
                text: root.txs.length ? Api.plain(root.pos.qty) + " " + (root.coin.symbol || "") + " · " + Api.price(root.pos.qty * root.price, root.cur)
                  : "Track what you own of " + (root.coin.symbol || "this coin")
                color: root.app.ui.muted
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.xs
              }
            }
            Chip {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              app: root.app
              text: "Add"
              onClicked: root.app.startTx(root.coin)
            }
          }

          Row {
            visible: root.txs.length > 0 && !isNaN(root.pos.cost)
            spacing: 8
            Text {
              text: "Profit / loss"
              color: root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.sm
            }
            Text {
              readonly property real pnl: root.pos.qty * root.price - root.pos.cost + root.pos.realized
              text: (pnl >= 0 ? "+" : "") + Api.price(pnl, root.cur) + (root.pos.cost > 0 ? "  (" + Api.percent(pnl / root.pos.cost * 100) + ")" : "")
              color: pnl >= 0 ? root.app.ui.up : root.app.ui.down
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.sm
              font.weight: Font.DemiBold
            }
          }

          Repeater {
            model: root.txs.slice().sort(function (a, b) { return b.ts - a.ts })
            delegate: Item {
              id: txRow
              required property var modelData
              width: holdCol.width
              height: 44
              Column {
                anchors.verticalCenter: parent.verticalCenter
                Text {
                  text: (txRow.modelData.side === "sell" ? "Sold " : "Bought ") + Api.plain(Number(txRow.modelData.amount)) + " " + (root.coin.symbol || "")
                  color: txRow.modelData.side === "sell" ? root.app.ui.down : root.app.ui.up
                  font.family: root.app.ui.font
                  font.pixelSize: root.app.ui.fs.sm
                }
                Text {
                  text: "at " + Api.price(Number(txRow.modelData.price), txRow.modelData.cur) + " · " + Api.date(Number(txRow.modelData.ts))
                  color: root.app.ui.muted
                  font.family: root.app.ui.font
                  font.pixelSize: root.app.ui.fs.xs
                }
              }
              IconButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                app: root.app
                glyph: "󰧧"
                label: "Delete transaction"
                size: 18
                color: root.app.ui.muted
                onClicked: root.app.store.removeTx(root.coinId, txRow.modelData.ts)
              }
            }
          }
        }
      }

      Converter {
        width: parent.width
        app: root.app
        symbol: root.coin.symbol || ""
        price: root.price
        currency: root.cur
      }

      // Categories.
      Flow {
        visible: (root.coin.categories || []).length > 0
        width: parent.width
        spacing: 6
        Repeater {
          model: root.coin.categories || []
          delegate: Rectangle {
            required property string modelData
            height: 26
            width: catText.implicitWidth + 18
            radius: 13
            color: root.app.ui.surface
            Text {
              id: catText
              anchors.centerIn: parent
              text: parent.modelData
              color: root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.xs
            }
          }
        }
      }

      // About.
      Column {
        visible: (root.coin.about || "") !== ""
        width: parent.width
        spacing: 6
        property bool expanded: false
        Text {
          text: "About " + (root.coin.name || "")
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.md
          font.weight: Font.DemiBold
        }
        Text {
          id: about
          width: parent.width
          text: root.coin.about || ""
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          maximumLineCount: parent.expanded ? 400 : 6
          elide: Text.ElideRight
          color: root.app.ui.text
          lineHeight: 1.25
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
        }
        Chip {
          visible: about.truncated || parent.expanded
          app: root.app
          text: parent.expanded ? "Show less" : "Read more"
          onClicked: parent.expanded = !parent.expanded
        }
      }

      // Links.
      Flow {
        width: parent.width
        spacing: 8
        visible: linkRepeater.count > 0
        Repeater {
          id: linkRepeater
          model: [
            { label: "Website", url: root.coin.homepage || "" },
            { label: "Explorer", url: (root.coin.explorers || [])[0] || "" },
            { label: "GitHub", url: root.coin.github || "" },
            { label: "Reddit", url: root.coin.reddit || "" },
            { label: "CoinGecko", url: root.coinId ? "https://www.coingecko.com/en/coins/" + root.coinId : "" }
          ].filter(function (l) { return l.url !== "" })
          delegate: Chip {
            required property var modelData
            app: root.app
            text: modelData.label + " ↗"
            onClicked: root.openLink(modelData.url)
          }
        }
      }

      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "Market data by CoinGecko" + (root.full ? " · updated " + root.app.agoText((root.app.clock, root.app.gecko.revision, root.app.gecko.age(root.coinUrl))) : "")
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
      }
    }
  }
}
