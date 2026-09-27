import QtQuick
import "Cols.js" as Cols

// A scrolling list of coins with whatever sits above it, shared by every
// screen that lists coins. Sorting, the keyboard cursor, pull-to-refresh and
// the empty/loading/failed states live here once.
ListView {
  id: list
  property var app
  property var rows: []
  property string sortKey: "rank"
  property bool descending: false
  property bool sortable: true
  property bool loading: false
  property string error: ""
  property string emptyGlyph: ""
  property string emptyTitle: "Nothing here yet"
  property string emptyDetail: ""
  property string emptyAction: ""
  property string footerText: ""
  property Component topContent: null
  signal endReached()
  signal emptyTriggered()

  readonly property var shown: Cols.sorted(rows, sortKey, descending)
  property bool armed: false
  // The keyboard cursor. Not currentIndex: ListView moves that to the first
  // row on its own, and a row that looks chosen before anyone chose it is a
  // lie on a touch screen.
  property int cursor: -1

  model: shown
  clip: true
  boundsBehavior: Flickable.DragOverBounds
  reuseItems: true
  cacheBuffer: 240

  function setSort(key) {
    if (sortKey === key) {
      descending = !descending
    } else {
      sortKey = key
      descending = key !== "rank" && key !== "name"
    }
  }

  // Keyboard: arrows move a cursor, Enter opens it. Returns whether the key
  // was the list's.
  function move(delta) {
    if (!count) return false
    cursor = Math.max(0, Math.min(count - 1, (cursor < 0 ? (delta > 0 ? -1 : count) : cursor) + delta))
    positionViewAtIndex(cursor, ListView.Contain)
    return true
  }
  function activateCurrent() {
    if (cursor < 0 || cursor >= shown.length) return false
    app.openCoin(shown[cursor])
    return true
  }
  function currentCoin() {
    return cursor >= 0 && cursor < shown.length ? shown[cursor] : null
  }

  onRowsChanged: if (cursor >= count) cursor = -1

  // The header (global figures, chips) grows once its data arrives, after the
  // rows are laid out, and ListView keeps the first row where it was: the
  // header would open scrolled off the top. Until somebody scrolls, the list
  // stays at its very beginning.
  property bool touched: false
  onMovementStarted: touched = true
  onOriginYChanged: if (!touched) positionViewAtBeginning()
  onContentHeightChanged: if (!touched) positionViewAtBeginning()
  onAtYEndChanged: if (atYEnd && count > 0 && !dragging) endReached()
  onMovementEnded: if (atYEnd && count > 0) endReached()

  // Pull down past the top and let go to refresh.
  onVerticalOvershootChanged: if (dragging && verticalOvershoot < -72) armed = true
  onDraggingChanged: if (!dragging && armed) { armed = false; app.refresh(true) }

  header: Column {
    width: list.width

    Item {
      width: parent.width
      height: list.armed || list.verticalOvershoot < -24 ? 28 : 0
      visible: height > 0
      Text {
        anchors.centerIn: parent
        text: list.armed ? "Release to refresh" : "Pull to refresh"
        color: list.app.ui.muted
        font.family: list.app.ui.font
        font.pixelSize: list.app.ui.fs.xs
      }
    }

    Loader {
      width: parent.width
      active: list.topContent !== null
      sourceComponent: list.topContent
    }

    ListHeader {
      width: parent.width
      app: list.app
      visible: list.count > 0 && !cols.compact
      sortKey: list.sortKey
      descending: list.descending
      sortable: list.sortable
      onSortRequested: function (key) { list.setSort(key) }
    }

    Placeholder {
      width: parent.width
      visible: list.count === 0
      app: list.app
      glyph: list.error ? "󰗖" : list.loading ? "" : list.emptyGlyph
      title: list.error ? list.error : list.loading ? "Loading…" : list.emptyTitle
      detail: list.error ? "Saved prices are shown when there are any. Try again in a moment." : list.loading ? "" : list.emptyDetail
      action: list.error ? "Try again" : list.loading ? "" : list.emptyAction
      onTriggered: list.error ? list.app.refresh(true) : list.emptyTriggered()
    }
  }

  delegate: CoinRow {
    required property var modelData
    required property int index
    width: list.width
    app: list.app
    coin: modelData
    selected: index === list.cursor || (list.app.split && list.app.openCoinId === modelData.id)
    onActivated: list.app.openCoin(modelData)
  }

  footer: Item {
    width: list.width
    height: list.footerText && list.count > 0 ? 44 : 12
    Text {
      anchors.centerIn: parent
      visible: list.count > 0
      text: list.footerText
      color: list.app.ui.muted
      font.family: list.app.ui.font
      font.pixelSize: list.app.ui.fs.xs
    }
  }
}
