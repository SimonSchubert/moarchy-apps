import QtQuick
import "kit"
import "Glyphs.js" as G

// The front page: Odysee's own categories along the top, each a list of
// channels somebody there chose, and the videos those channels are talked
// about for, most first.
Item {
  id: root
  property var app
  readonly property string key: "home:" + app.cat
  readonly property var feed: app.feeds[key] || app.emptyFeed
  property int current: -1
  readonly property alias grid: grid

  onKeyChanged: { current = -1; grid.positionViewAtBeginning() }

  ListView {
    id: chips
    x: 0
    y: 6
    width: parent.width
    height: root.app.ui.chip
    orientation: ListView.Horizontal
    spacing: 6
    leftMargin: root.app.ui.gutter
    rightMargin: root.app.ui.gutter
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: root.app.cats
    delegate: Chip {
      required property var modelData
      required property int index
      app: root.app
      text: modelData.label
      glyph: index === 0 ? G.trending : ""
      hpad: 20
      selected: modelData.key === root.app.cat
      onClicked: root.app.setCat(modelData.key)
    }
    // Keep the chosen one in view: it can be the last of fifteen.
    onCountChanged: Qt.callLater(showCurrent)
    function showCurrent() {
      for (var i = 0; i < root.app.cats.length; i++)
        if (root.app.cats[i].key === root.app.cat) { positionViewAtIndex(i, ListView.Contain); return }
    }
  }

  VideoGrid {
    id: grid
    anchors.top: chips.bottom
    anchors.topMargin: 10
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    app: root.app
    items: root.feed.items
    now: root.app.nowSec
    savedIds: root.app.savedIds
    loading: root.feed.loading || (root.app.catsLoading && !root.app.cats.length)
    more: root.feed.more
    error: root.feed.error !== "" ? root.feed.error : root.app.catsError
    current: root.current
    emptyGlyph: root.app.offline ? G.offline : G.video
    emptyTitle: root.app.offline ? "Offline" : "Nothing in this category"
    emptyText: root.app.offline ? "This copy is running offline and has nothing saved to show."
      : "None of its channels put anything up lately."
    onOpened: function (item) { root.app.openVideo(item) }
    onChannelOpened: function (ch) { root.app.openChannel(ch) }
    onWantMore: root.app.loadMore(root.key)
    onRetry: root.app.cats.length ? root.app.load(root.key, 1) : root.app.fetchHomepage()
  }
}
