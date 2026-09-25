import QtQuick
import "Glyphs.js" as G

// Wide cards in one column, or two on a wide desktop, with the same keyboard
// and pull-to-refresh behaviour as the poster grid. The delegate is the
// caller's: `modelData`, `index` and `current` are what it gets.
Item {
  id: root
  property var app
  property var items: []
  property bool loading: false
  property string error: ""
  property bool more: false
  property string emptyGlyph: ""
  property string emptyTitle: "Nothing here yet"
  property string emptyDetail: ""
  property string emptyAction: ""
  property Component topContent: null
  property Component delegate: null
  property int cardHeight: app.compact ? 96 : 112
  signal endReached()
  signal emptyTriggered()
  signal activated(var item)

  readonly property int pad: app.compact ? 10 : 22
  readonly property int columns: width - pad * 2 >= 980 ? 2 : 1
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
  function currentItem() { return null }
  function toTop() { grid.positionViewAtBeginning(); cursor = -1 }

  onItemsChanged: if (cursor >= items.length) cursor = -1

  GridView {
    id: grid
    x: root.pad
    width: parent.width - root.pad * 2
    height: parent.height
    cellWidth: width / root.columns
    cellHeight: root.cardHeight + (root.app.compact ? 8 : 12)
    model: root.items
    reuseItems: true
    cacheBuffer: 600
    boundsBehavior: Flickable.DragOverBounds
    clip: false

    property bool touched: false
    onMovementStarted: touched = true
    onOriginYChanged: if (!touched) positionViewAtBeginning()
    onContentHeightChanged: if (!touched) positionViewAtBeginning()
    onContentYChanged: if (root.more && count > 0 && contentY + height > contentHeight + originY - cellHeight * 3) root.endReached()
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
          visible: grid.count === 0
          app: root.app
          busy: root.loading && !root.error
          glyph: root.error ? G.alert : root.emptyGlyph
          title: root.error ? root.error : root.loading ? "Loading…" : root.emptyTitle
          detail: root.error ? "Try again in a moment." : root.loading ? "" : root.emptyDetail
          action: root.error ? "Try again" : root.loading ? "" : root.emptyAction
          onTriggered: root.error ? root.app.refresh(true) : root.emptyTriggered()
        }
      }
    }

    delegate: Item {
      id: cell
      required property var modelData
      required property int index
      width: grid.cellWidth
      height: grid.cellHeight
      Loader {
        x: root.columns > 1 ? (cell.index % 2 ? 6 : 0) : 0
        width: grid.cellWidth - (root.columns > 1 ? 6 : 0)
        height: root.cardHeight
        sourceComponent: root.delegate
        onLoaded: {
          item.modelData = Qt.binding(function () { return cell.modelData })
          item.index = Qt.binding(function () { return cell.index })
          item.current = Qt.binding(function () { return cell.index === root.cursor })
        }
      }
    }

    footer: Item {
      width: grid.width
      height: root.more && grid.count > 0 ? 64 : 16
      Spinner { anchors.centerIn: parent; app: root.app; running: root.more && root.loading && grid.count > 0 }
    }
  }
}
