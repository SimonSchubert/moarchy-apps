import QtQuick
import "Glyphs.js" as G

// A scrolling grid of posters with whatever sits above it, shared by every
// screen that shows movies and shows. Columns follow the width, and the
// keyboard cursor, pull-to-refresh, paging and the empty, loading and failed
// states live here once.
//
// The grid is inset by `pad` on each side; the header is not, so a backdrop
// above the posters can run edge to edge. The clip is this item's, not the
// grid's, for the same reason.
Item {
  id: root
  property var app
  property var items: []
  property bool loading: false
  property string error: ""
  property bool more: false
  property string emptyGlyph: G.movie
  property string emptyTitle: "Nothing here yet"
  property string emptyDetail: ""
  property string emptyAction: ""
  property Component topContent: null
  // function (item, index) -> "" or a short badge for the poster's corner.
  property var badgeFor: null
  // function (item, index) -> "" or a line to show instead of the year.
  property var subtitleFor: null
  signal endReached()
  signal emptyTriggered()
  signal activated(var item)

  readonly property int pad: app.compact ? 10 : 22
  readonly property int hgap: app.compact ? 10 : 18
  readonly property int vgap: app.compact ? 14 : 20
  readonly property int columns: Math.max(3, Math.floor((width - pad * 2) / (app.compact ? 116 : 172)))
  readonly property real cardWidth: Math.floor((width - pad * 2) / columns) - hgap

  property alias grid: grid
  property int cursor: -1
  property bool armed: false

  clip: true

  function step(dx, dy) {
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
  function picked() { return cursor >= 0 && cursor < items.length ? items[cursor] : null }
  function toTop() { grid.positionViewAtBeginning(); cursor = -1 }

  onItemsChanged: if (cursor >= items.length) cursor = -1

  Keyed { id: keyed; items: root.items }

  GridView {
    id: grid
    x: root.pad
    width: parent.width - root.pad * 2
    height: parent.height
    cellWidth: width / root.columns
    cellHeight: Math.round(root.cardWidth * 1.5) + 52 + root.vgap
    model: keyed
    reuseItems: true
    cacheBuffer: Math.max(400, cellHeight * 2)
    boundsBehavior: Flickable.DragOverBounds
    // Not clipped: the header runs past the grid's sides into `pad`.
    clip: false

    // The header grows once its data arrives, after the cards are laid out,
    // and GridView keeps the first card where it was: the header would open
    // scrolled off the top. Until somebody scrolls, stay at the beginning.
    property bool touched: false
    onMovementStarted: touched = true
    onOriginYChanged: if (!touched) positionViewAtBeginning()
    onContentHeightChanged: if (!touched) positionViewAtBeginning()
    onContentYChanged: if (root.more && count > 0 && contentY + height > contentHeight + originY - cellHeight * 2) root.endReached()
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
          title: root.error ? root.error : root.loading ? "Loading…" : root.emptyTitle
          detail: root.error ? "Saved lists are shown when there are any. Try again in a moment." : root.loading ? "" : root.emptyDetail
          action: root.error ? "Try again" : root.loading ? "" : root.emptyAction
          onTriggered: root.error ? root.app.refresh(true) : root.emptyTriggered()
        }
        Item { width: 1; height: keyed.count > 0 ? 4 : 0 }
      }
    }

    delegate: Item {
      id: cell
      required property string key
      required property int index
      readonly property var modelData: keyed.at(key)
      width: grid.cellWidth
      height: grid.cellHeight
      PosterCard {
        x: root.hgap / 2
        width: root.cardWidth
        app: root.app
        item: cell.modelData
        current: cell.index === root.cursor
        badge: root.badgeFor ? root.badgeFor(cell.modelData, cell.index) : ""
        badgeGlyph: badge !== "" && badge === cell.modelData.stat
          ? (cell.modelData.statKind === "watching" ? G.eye : cell.modelData.statKind === "lists" ? G.bookmarked : "") : ""
        subtitle: root.subtitleFor ? root.subtitleFor(cell.modelData, cell.index) : ""
        onActivated: root.activated(cell.modelData)
      }
    }

    footer: Item {
      width: grid.width
      height: root.more && keyed.count > 0 ? 64 : 16
      Spinner {
        anchors.centerIn: parent
        app: root.app
        running: root.more && root.loading && keyed.count > 0
      }
    }
  }
}
