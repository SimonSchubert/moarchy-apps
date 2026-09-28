import QtQuick
import "kit"

// Books as a grid of covers: three across a phone, as many as fit at a
// desktop's width. It asks for the next page itself, a screen before the end,
// and says why it is empty when it is.
//
// `header` scrolls with the books (an author's picture and life); a filter
// that should stay put belongs above the grid, not in it.
GridView {
  id: root
  property var app
  property var items: []
  property bool loading: false
  property bool more: false
  property string error: ""
  property int current: -1
  property string emptyGlyph: ""
  property string emptyTitle: ""
  property string emptyText: ""
  property string emptyAction: ""
  signal opened(var book)
  signal wantMore()
  signal retry()
  signal emptyActed()

  readonly property int gap: app.compact ? 14 : 24
  readonly property int minCard: app.compact ? 96 : 138
  // Every cell carries a gap on its right, the last one's in the margin: the
  // cells tile the width exactly, and GridView never drops a column for a
  // fraction of a pixel.
  readonly property real avail: width - leftMargin - rightMargin
  readonly property int columns: Math.max(2, Math.floor(avail / (minCard + gap)))
  readonly property real cardWidth: Math.floor(avail / columns) - gap
  readonly property real rowWidth: Math.floor(avail / columns) * columns - gap

  // A header that grows as its page arrives (an author's biography) would
  // otherwise leave the grid scrolled past it. Until somebody scrolls, the
  // top stays the top.
  property bool touched: false
  onMovementStarted: touched = true
  onItemsChanged: if (!items.length) touched = false
  onOriginYChanged: if (!touched) Qt.callLater(positionViewAtBeginning)

  function show(index) { if (index >= 0) positionViewAtIndex(index, GridView.Contain) }

  leftMargin: app.ui.gutter
  rightMargin: Math.max(0, app.ui.gutter - gap)
  topMargin: 8
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  cellWidth: Math.floor(avail / columns)
  // The cover, two lines of title, the author, the rating, and the gap.
  cellHeight: Math.round(cardWidth * 3 / 2) + 8 + Math.ceil(app.ui.fs.md * 1.45) * 2 + Math.ceil(app.ui.fs.sm * 1.5) + 24 + gap
  cacheBuffer: 800
  model: Keyed { id: keyed; items: root.items }

  delegate: Item {
    id: cell
    required property string key
    required property int index
    width: root.cellWidth
    height: root.cellHeight
    BookCard {
      width: root.cardWidth
      app: root.app
      book: keyed.at(cell.key).id ? keyed.at(cell.key) : null
      entry: root.app.shelved[cell.key] || null
      details: true
      current: cell.index === root.current
      onOpened: if (book) root.opened(book)
    }
  }

  // Later, not now: a new page lands while the list's own model is being
  // reset, and asking for the next one then is a binding that feeds itself.
  onContentYChanged: Qt.callLater(nearEnd)
  onContentHeightChanged: Qt.callLater(nearEnd)
  function nearEnd() {
    if (root.more && !root.loading && root.items.length && root.contentY + root.height * 2 > root.contentHeight)
      root.wantMore()
  }

  footer: Item {
    width: root.rowWidth
    height: root.items.length && (root.loading || root.error !== "") ? 72 : 24
    Spinner {
      anchors.centerIn: parent
      visible: root.loading && root.items.length > 0
      running: visible
      app: root.app
    }
    Button {
      anchors.centerIn: parent
      visible: !root.loading && root.error !== "" && root.items.length > 0
      app: root.app
      text: "Try again"
      onClicked: root.retry()
    }
  }

  EmptyState {
    parent: root
    anchors.horizontalCenter: parent.horizontalCenter
    readonly property real above: root.headerItem ? root.headerItem.height + root.topMargin : 0
    y: above + Math.max(16, (root.height - above - implicitHeight) / 2)
    visible: root.items.length === 0
    app: root.app
    busy: root.loading
    glyph: root.emptyGlyph
    title: root.loading ? "" : root.error !== "" ? "Could not load this" : root.emptyTitle
    text: root.loading ? "" : root.error !== "" ? root.error : root.emptyText
    actionText: root.loading ? "" : root.error !== "" ? "Try again" : root.emptyAction
    onAction: root.error !== "" ? root.retry() : root.emptyActed()
  }
}
