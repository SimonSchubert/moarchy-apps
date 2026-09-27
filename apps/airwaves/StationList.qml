import QtQuick
import "Glyphs.js" as G

// A scrolling list of stations with whatever sits above it, shared by every
// screen that lists them. One column, or two on a wide desktop; the keyboard
// cursor, pull-to-refresh, paging and the empty, loading and failed states
// live here once.
//
// The list is inset by `pad` on each side; the header is not, so a row of
// cards above it can scroll edge to edge.
Item {
  id: root
  property var app
  property var items: []
  property bool loading: false
  property string error: ""
  property bool more: false
  property string emptyGlyph: G.radio
  property string emptyTitle: "Nothing here yet"
  property string emptyDetail: ""
  property string emptyAction: ""
  property Component topContent: null
  // function (station, index) -> "" or a line to show under the name.
  property var detailFor: null
  signal endReached()
  signal emptyTriggered()
  signal activated(var station)

  readonly property int pad: app.compact ? 6 : 16
  readonly property int columns: width - pad * 2 >= 900 ? 2 : 1
  readonly property int rowHeight: app.compact ? 68 : 72
  property int cursor: -1
  property bool armed: false
  property alias grid: grid

  clip: true

  function move(dx, dy) {
    var n = grid.count
    if (!n) return false
    if (cursor < 0) cursor = 0
    else cursor = Math.max(0, Math.min(n - 1, cursor + dx + dy * columns))
    grid.positionViewAtIndex(cursor, GridView.Contain)
    return true
  }
  function activateCurrent() {
    if (cursor < 0 || cursor >= items.length) return false
    root.activated(items[cursor])
    return true
  }
  function currentItem() { return cursor >= 0 && cursor < items.length ? items[cursor] : null }
  function toTop() { grid.positionViewAtBeginning(); cursor = -1 }

  onItemsChanged: if (cursor >= items.length) cursor = -1

  Keyed { id: keyed; items: root.items }

  GridView {
    id: grid
    x: root.pad
    width: parent.width - root.pad * 2
    height: parent.height
    cellWidth: width / root.columns
    cellHeight: root.rowHeight + 4
    model: keyed
    reuseItems: true
    cacheBuffer: 600
    boundsBehavior: Flickable.DragOverBounds
    // Not clipped: the header runs past the list's sides into `pad`.
    clip: false

    // The header grows once its data arrives, after the rows are laid out,
    // and GridView keeps the first row where it was: the header would open
    // scrolled off the top. Until somebody scrolls, stay at the beginning.
    property bool touched: false
    onMovementStarted: touched = true
    onOriginYChanged: if (!touched) positionViewAtBeginning()
    onContentHeightChanged: if (!touched) positionViewAtBeginning()
    onContentYChanged: if (root.more && count > 0 && contentY + height > contentHeight + originY - cellHeight * 6) root.endReached()
    onCountChanged: if (count === 0) touched = false

    onVerticalOvershootChanged: if (dragging && verticalOvershoot < -72) root.armed = true
    onDraggingChanged: if (!dragging && root.armed) { root.armed = false; root.app.refresh(true) }

    header: Item {
      width: grid.width
      height: head.implicitHeight
      Column {
        id: head
        x: -root.pad
        width: grid.width + root.pad * 2

        Item {
          width: parent.width
          height: root.armed || grid.verticalOvershoot < -24 ? 28 : 0
          visible: height > 0
          Text {
            anchors.centerIn: parent
            text: root.armed ? "Release to refresh" : "Pull to refresh"
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xs
          }
        }
        Loader {
          width: parent.width
          active: root.topContent !== null
          sourceComponent: root.topContent
        }
        Placeholder {
          width: parent.width
          visible: keyed.count === 0
          app: root.app
          busy: root.loading && !root.error
          glyph: root.error ? G.alert : root.emptyGlyph
          title: root.error ? root.error : root.loading ? "Tuning in…" : root.emptyTitle
          detail: root.error ? "Saved lists are shown when there are any. Try again in a moment." : root.loading ? "" : root.emptyDetail
          action: root.error ? "Try again" : root.loading ? "" : root.emptyAction
          onTriggered: root.error ? root.app.refresh(true) : root.emptyTriggered()
        }
      }
    }

    delegate: Item {
      id: cell
      required property string key
      required property int index
      readonly property var modelData: keyed.at(key)
      width: grid.cellWidth
      height: grid.cellHeight
      StationRow {
        x: root.columns > 1 ? (cell.index % 2 ? 4 : 0) : 0
        width: grid.cellWidth - (root.columns > 1 ? 4 : 0)
        height: root.rowHeight
        app: root.app
        station: cell.modelData
        current: cell.index === root.cursor
        detail: root.detailFor ? root.detailFor(cell.modelData, cell.index) : ""
        onActivated: root.activated(cell.modelData)
      }
    }

    footer: Item {
      width: grid.width
      height: root.more && keyed.count > 0 ? 64 : 24
      Spinner {
        anchors.centerIn: parent
        app: root.app
        running: root.more && root.loading && keyed.count > 0
      }
    }
  }
}
