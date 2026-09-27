import QtQuick
import "Api.mjs" as Api

// Every coin CoinGecko lists, by name or ticker. Also how a coin is chosen
// for a new portfolio entry, when `picking` is set.
Item {
  id: root
  property var app
  property string query: ""
  property bool picking: false

  readonly property string trimmed: query.trim()
  readonly property string url: trimmed.length >= 2 ? Api.searchUrl(trimmed.toLowerCase()) : ""
  readonly property var found: { app.gecko.revision; return url ? (app.gecko.peek(url) || []) : [] }

  // Search answers with names only; the first twenty are priced with a second
  // request so a result reads like every other coin row.
  readonly property string pricesUrl: found.length
    ? Api.idsUrl(app.currency, found.slice(0, 20).map(function (c) { return c.id })) : ""
  readonly property var results: {
    app.gecko.revision
    var priced = pricesUrl ? (app.gecko.peek(pricesUrl) || []) : []
    var byId = {}
    for (var i = 0; i < priced.length; i++) byId[priced[i].id] = priced[i]
    return found.map(function (c) { return byId[c.id] || { id: c.id, name: c.name, symbol: c.symbol, image: c.image, rank: c.rank, price: NaN, ch24: NaN } })
  }
  onPricesUrlChanged: if (pricesUrl) app.gecko.want(pricesUrl, "markets", app.store.refreshSec * 1000, true)
  readonly property bool loading: { app.gecko.revision; return !!url && (debounce.running || app.gecko.busy(url)) }
  readonly property string error: { app.gecko.revision; return url ? app.gecko.error(url) : "" }

  // With nothing typed: the top coins already on hand, so the screen is a
  // shortcut rather than a blank page.
  readonly property var suggestions: {
    app.gecko.revision
    var top = app.gecko.peek(Api.marketsUrl(app.currency, 1, 100, "")) || app.gecko.peek(Api.marketsUrl(app.currency, 1, 250, "")) || []
    return top.slice(0, 12)
  }

  function refresh(force) { if (url) app.gecko.want(url, "search", 3600000, true) }
  function focusField() { field.forceActiveFocus() }

  onQueryChanged: debounce.restart()
  Timer { id: debounce; interval: 450; onTriggered: root.refresh(false) }

  function choose(coin) {
    if (root.picking) root.app.startTx(coin)
    else root.app.openCoin(coin)
  }

  Column {
    id: bar
    width: parent.width
    topPadding: 8
    spacing: 8

    Rectangle {
      x: 12
      width: parent.width - 24
      height: 44
      radius: 22
      color: root.app.ui.surface
      border.width: 1
      border.color: field.activeFocus ? root.app.ui.accent : root.app.ui.border

      Icon {
        id: lens
        app: root.app
        x: 8
        anchors.verticalCenter: parent.verticalCenter
        text: "󰍉"
        color: root.app.ui.muted
      }
      TextInput {
        id: field
        anchors.left: lens.right
        anchors.leftMargin: 4
        anchors.right: clearBtn.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        verticalAlignment: TextInput.AlignVCenter
        text: root.query
        onTextEdited: root.query = text
        color: root.app.ui.text
        selectionColor: root.app.ui.accent
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.md
        clip: true
        inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
        Keys.onEscapePressed: function (event) {
          if (root.query) { root.query = ""; event.accepted = true }
          else { field.focus = false; event.accepted = false }
        }
        Keys.onReturnPressed: if (root.results.length) root.choose(root.results[0])
        Keys.onDownPressed: { list.forceActiveFocus(); list.move(1) }

        Text {
          anchors.fill: parent
          verticalAlignment: Text.AlignVCenter
          visible: !field.text
          text: root.picking ? "Which coin did you buy?" : "Search coins"
          color: root.app.ui.muted
          font: field.font
        }
      }
      IconButton {
        id: clearBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: root.query !== ""
        width: visible ? implicitWidth : 8
        app: root.app
        glyph: "󰅖"
        label: "Clear search"
        size: 16
        onClicked: { root.query = ""; field.forceActiveFocus() }
      }
    }

    Text {
      x: 16
      width: parent.width - 32
      text: root.picking ? "Pick the coin for your new portfolio entry."
        : root.url ? (root.loading && !root.results.length ? "Searching…" : root.results.length + " results")
        : "Top coins"
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
    }
  }

  CoinList {
    id: list
    anchors.top: bar.bottom
    anchors.topMargin: 4
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    app: root.app
    rows: root.url ? root.results : root.suggestions
    sortKey: "custom"
    sortable: false
    loading: root.loading
    error: root.error
    emptyGlyph: "󰍉"
    emptyTitle: root.url ? "No coins match “" + root.trimmed + "”" : "Type a name or ticker"
    emptyDetail: root.url ? "Try the ticker, like BTC, or the full name." : ""
    delegate: CoinRow {
      required property var modelData
      required property int index
      width: list.width
      app: root.app
      coin: modelData
      showStar: !root.picking
      selected: index === list.cursor
      onActivated: root.choose(modelData)
    }
    Keys.onReturnPressed: { var c = list.currentCoin(); if (c) root.choose(c) }
    Keys.onUpPressed: { if (list.cursor <= 0) field.forceActiveFocus(); else list.move(-1) }
    Keys.onDownPressed: list.move(1)
  }
}
