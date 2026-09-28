import QtQuick
import "kit"

// A feed of videos as a grid of cards: one column on a phone, as many as fit
// at a desktop's width. It asks for the next page itself, a screen before
// the end, and says why it is empty when it is.
//
// `header` scrolls with the cards (a channel's banner); a filter that should
// stay put belongs above the grid, not in it.
GridView {
  id: root
  property var app
  property var items: []
  property real now: 0
  property var savedIds: ({})
  property bool loading: false
  property bool more: false
  property string error: ""
  property int current: -1
  property string emptyGlyph: ""
  property string emptyTitle: ""
  property string emptyText: ""
  signal opened(var item)
  signal channelOpened(var channel)
  signal wantMore()
  signal retry()

  readonly property int gap: app.compact ? 12 : 20
  readonly property int minCard: app.compact ? 290 : 250
  // Every cell carries a gap on its right, the last one's in the margin: the
  // cells tile the width exactly, and GridView never drops a column for a
  // fraction of a pixel.
  readonly property real avail: width - leftMargin - rightMargin
  readonly property int columns: Math.max(1, Math.floor(avail / (minCard + gap)))
  readonly property real cardWidth: Math.floor(avail / columns) - gap
  // From the first card's left edge to the last one's right: what a header
  // lines up with.
  readonly property real rowWidth: Math.floor(avail / columns) * columns - gap

  function show(index) { if (index >= 0) positionViewAtIndex(index, GridView.Contain) }

  leftMargin: app.ui.gutter
  rightMargin: Math.max(0, app.ui.gutter - gap)
  topMargin: 6
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  cellWidth: Math.floor(avail / columns)
  cellHeight: Math.round(cardWidth * 9 / 16) + (app.compact ? 94 : 88)
  cacheBuffer: 600
  model: Keyed { id: keyed; items: root.items }

  delegate: Item {
    id: cell
    required property string key
    required property int index
    width: root.cellWidth
    height: root.cellHeight
    VideoCard {
      width: root.cardWidth
      height: parent.height - root.gap
      app: root.app
      item: keyed.at(cell.key).id ? keyed.at(cell.key) : null
      now: root.now
      saved: !!root.savedIds[cell.key]
      current: cell.index === root.current
      onOpened: if (item) root.opened(item)
      onChannelOpened: if (item && item.channel) root.channelOpened(item.channel)
    }
  }

  // A screen before the end, the next page.
  onContentYChanged: nearEnd()
  onContentHeightChanged: nearEnd()
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
    actionText: !root.loading && root.error !== "" ? "Try again" : ""
    onAction: root.retry()
  }
}
