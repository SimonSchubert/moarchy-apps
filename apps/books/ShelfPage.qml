import QtQuick
import "kit"
import "Glyphs.js" as G

// A whole shelf, from Discover's "See all" or a subject tapped on a book:
// the same books as a grid, a page at a time, as far as Open Library goes.
Item {
  id: root
  property var app
  property string key: ""
  property string label: ""
  property var feed: null
  signal bookOpened(var book)
  signal wantMore()
  signal retry()
  readonly property alias grid: grid

  onKeyChanged: grid.positionViewAtBeginning()

  PageHeader {
    id: head
    width: parent.width
    app: root.app
    title: root.label
    subtitle: root.key === "trending" ? "what Open Library's readers opened this week"
      : root.feed && root.feed.total > 0 ? root.app.countText(root.feed.total, "book") + ", most read first" : "most read first"
  }

  BookGrid {
    id: grid
    anchors.top: head.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    app: root.app
    items: root.feed ? root.feed.items : []
    loading: root.feed ? root.feed.loading : true
    more: root.feed ? root.feed.more : false
    error: root.feed ? root.feed.error : ""
    emptyGlyph: G.tag
    emptyTitle: "Nothing filed here"
    emptyText: "Open Library has no books under “" + root.label + "”."
    onOpened: function (book) { root.bookOpened(book) }
    onWantMore: root.wantMore()
    onRetry: root.retry()
  }
}
