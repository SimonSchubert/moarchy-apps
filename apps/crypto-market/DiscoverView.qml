import QtQuick
import "Api.mjs" as Api

// What is moving: trending searches, the day's biggest gainers and losers
// among the top 250, and every category by market cap.
Item {
  id: root
  property var app
  property string section: "trending"

  readonly property string cur: app.currency
  readonly property string top250: Api.marketsUrl(cur, 1, 250, "")
  readonly property var trending: { app.gecko.revision; return app.gecko.peek(Api.trendingUrl()) || [] }
  readonly property string trendingPricesUrl: trending.length
    ? Api.idsUrl(cur, trending.map(function (t) { return t.id })) : ""

  // Trending names come without prices in your currency; a second request for
  // them, by id, fills the rows in.
  readonly property var trendingRows: {
    app.gecko.revision
    var priced = trendingPricesUrl ? (app.gecko.peek(trendingPricesUrl) || []) : []
    var byId = {}
    for (var i = 0; i < priced.length; i++) byId[priced[i].id] = priced[i]
    return trending.map(function (t) {
      var p = byId[t.id]
      return p ? p : { id: t.id, name: t.name, symbol: t.symbol, image: t.image, rank: t.rank, price: NaN, ch24: NaN }
    })
  }

  // Gainers and losers leave out coins too thin to trade: a 900% day on
  // $3,000 of volume is noise, not news.
  readonly property var movers: {
    app.gecko.revision
    var all = app.gecko.peek(top250) || []
    return all.filter(function (r) { return !isNaN(r.ch24) && r.vol >= 50000 })
  }
  readonly property var gainers: movers.slice().sort(function (a, b) { return b.ch24 - a.ch24 }).slice(0, 30)
  readonly property var losers: movers.slice().sort(function (a, b) { return a.ch24 - b.ch24 }).slice(0, 30)
  readonly property var categories: { app.gecko.revision; return app.gecko.peek(Api.categoriesUrl()) || [] }

  readonly property string sectionUrl: section === "trending" ? Api.trendingUrl()
    : section === "categories" ? Api.categoriesUrl() : top250
  readonly property bool loading: { app.gecko.revision; return app.gecko.busy(sectionUrl) || (section === "trending" && app.gecko.busy(trendingPricesUrl)) }
  readonly property string error: { app.gecko.revision; return app.gecko.error(sectionUrl) }

  function refresh(force) {
    var g = app.gecko
    if (section === "trending") {
      g.want(Api.trendingUrl(), "trending", force ? 60000 : 600000, force)
      if (trendingPricesUrl) g.want(trendingPricesUrl, "markets", force ? 0 : app.store.refreshSec * 1000, false)
    } else if (section === "categories") {
      g.want(Api.categoriesUrl(), "categories", force ? 60000 : 600000, force)
    } else {
      g.want(top250, "markets", force ? 0 : 300000, force)
    }
  }
  onSectionChanged: { refresh(false); list.positionViewAtBeginning() }
  onTrendingPricesUrlChanged: if (trendingPricesUrl) app.gecko.want(trendingPricesUrl, "markets", app.store.refreshSec * 1000, false)

  property alias list: list

  readonly property var sections: [
    { key: "trending", label: "Trending" },
    { key: "gainers", label: "Gainers" },
    { key: "losers", label: "Losers" },
    { key: "categories", label: "Categories" }
  ]

  Component {
    id: tabs
    Column {
      width: list.width
      topPadding: 4
      bottomPadding: 8
      spacing: 8
      Row {
        id: chipRow
        x: 12
        width: parent.width - 24
        spacing: 6
        Repeater {
          model: root.sections
          delegate: Chip {
            required property var modelData
            app: root.app
            hpad: root.app.compact ? 16 : 24
            text: modelData.label
            selected: root.section === modelData.key
            onClicked: root.section = modelData.key
          }
        }
      }
      Text {
        x: 12
        width: parent.width - 24
        wrapMode: Text.Wrap
        text: root.section === "trending" ? "Most searched coins on CoinGecko in the last 24 hours."
          : root.section === "gainers" ? "Biggest 24h risers among the top 250, with at least $50K of volume."
          : root.section === "losers" ? "Biggest 24h fallers among the top 250, with at least $50K of volume."
          : "Sectors by total market cap, in US dollars."
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
      }
    }
  }

  CoinList {
    id: list
    anchors.fill: parent
    visible: root.section !== "categories"
    app: root.app
    rows: root.section === "trending" ? root.trendingRows : root.section === "gainers" ? root.gainers : root.losers
    sortKey: "custom"
    loading: root.loading
    error: rows.length ? "" : root.error
    emptyGlyph: "󰈸"
    emptyTitle: "Nothing moving yet"
    topContent: tabs
  }

  ListView {
    id: cats
    anchors.fill: parent
    visible: root.section === "categories"
    clip: true
    model: root.section === "categories" ? root.categories : []
    header: Column {
      width: cats.width
      Loader { width: parent.width; sourceComponent: tabs }
      Placeholder {
        width: parent.width
        visible: cats.count === 0
        app: root.app
        glyph: root.error ? "󰗖" : ""
        title: root.error ? root.error : "Loading categories…"
        action: root.error ? "Try again" : ""
        onTriggered: root.app.refresh(true)
      }
    }
    delegate: Item {
      id: cat
      required property var modelData
      required property int index
      width: cats.width
      height: 60

      Rectangle {
        anchors.fill: parent
        color: catMouse.pressed ? root.app.ui.pressed : catMouse.containsMouse ? root.app.ui.hover : "transparent"
      }
      MouseArea {
        id: catMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.app.openCategory(cat.modelData.id, cat.modelData.name)
      }
      Row {
        id: logos
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: -8
        width: 64
        Repeater {
          model: cat.modelData.logos
          delegate: Rectangle {
            required property string modelData
            width: 26
            height: 26
            radius: 13
            color: root.app.ui.bg
            CoinLogo { anchors.centerIn: parent; app: root.app; size: 22; source: parent.modelData; symbol: "" }
          }
        }
      }
      Column {
        anchors.left: logos.right
        anchors.leftMargin: 8
        anchors.right: figures.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text {
          width: parent.width
          text: cat.modelData.name
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
          font.weight: Font.DemiBold
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }
        Text {
          text: "Vol " + Api.money(cat.modelData.vol, "usd")
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xs
        }
      }
      Column {
        id: figures
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 92
        spacing: 2
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignRight
          text: Api.money(cat.modelData.mcap, "usd")
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
          font.weight: Font.Medium
        }
        Change {
          anchors.right: parent.right
          app: root.app
          value: cat.modelData.ch24
          font.pixelSize: root.app.ui.fs.xs
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
  }
}
