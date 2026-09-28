import QtQuick
import "kit"
import "OpenLibrary.js" as OL

// Discover: what you are reading, if anything, then shelves -- what Open
// Library's readers are opening this week, and the most-read books in
// fifteen subjects. A shelf asks for its books when it scrolls near the
// screen, not before, so opening the app is two or three questions rather
// than sixteen.
ListView {
  id: root
  property var app

  readonly property var sections: [{ key: "trending", label: "Trending", note: "this week" }]
    .concat(OL.SUBJECTS.map(function (s) { return { key: "subject:" + s.key, label: s.label, note: "most read" } }))

  clip: true
  boundsBehavior: Flickable.StopAtBounds
  cacheBuffer: 300
  spacing: root.app.compact ? 22 : 30
  topMargin: 10
  bottomMargin: 24
  model: sections

  // Reading now arrives after the list is laid out; until somebody scrolls,
  // the top stays the top.
  property bool touched: false
  onMovementStarted: touched = true
  onOriginYChanged: if (!touched) Qt.callLater(positionViewAtBeginning)

  header: Column {
    width: root.width
    visible: root.app.readingNow.length > 0
    height: visible ? implicitHeight + root.spacing : 0
    spacing: 10
    Item {
      x: root.app.ui.gutter
      width: parent.width - root.app.ui.gutter * 2
      height: 30
      SectionTitle {
        anchors.verticalCenter: parent.verticalCenter
        app: root.app
        text: "Reading now"
        note: root.app.readingNow.length > 1 ? String(root.app.readingNow.length) : ""
      }
    }
    // One across a phone, peeking at the next; side by side on a desktop.
    ListView {
      id: reading
      readonly property real cardWidth: root.app.compact
        ? (root.app.readingNow.length > 1 ? width - 2 * root.app.ui.gutter - 36 : width - 2 * root.app.ui.gutter)
        : Math.min(440, (width - 2 * root.app.ui.gutter - 16) / Math.min(2, root.app.readingNow.length))
      width: parent.width
      height: 128
      orientation: ListView.Horizontal
      spacing: root.app.compact ? 10 : 16
      leftMargin: root.app.ui.gutter
      rightMargin: root.app.ui.gutter
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      snapMode: root.app.compact ? ListView.SnapToItem : ListView.NoSnap
      model: Keyed { id: readingKeyed; items: root.app.readingNow }
      delegate: ReadingCard {
        required property string key
        width: reading.cardWidth
        height: 128
        app: root.app
        entry: readingKeyed.at(key).id ? readingKeyed.at(key) : null
        onOpened: if (entry) root.app.openBook(entry)
        onStepped: function (n) { if (entry) root.app.setPage(entry.id, (entry.page || 0) + n) }
      }
    }
  }

  delegate: Shelf {
    id: shelf
    required property var modelData
    required property int index
    readonly property var feed: root.app.feeds[modelData.key] || root.app.emptyFeed
    width: root.width
    app: root.app
    title: modelData.label
    note: modelData.note
    items: feed.items
    loading: feed.loading || (!feed.items.length && !feed.error && !root.app.offline)
    error: feed.error
    coverWidth: index === 0 ? (root.app.compact ? 128 : 156) : (root.app.compact ? 100 : 128)
    onOpened: function (book) { root.app.openBook(book) }
    onSeeAllClicked: root.app.openShelf(modelData.key, modelData.label)
    onRetry: root.app.load(modelData.key, 1)
    // Asked for when the shelf is made -- which the list does as it nears
    // the screen -- and only once the window has been opened.
    readonly property bool live: root.app.started
    function want() { if (live) root.app.want(modelData.key) }
    onLiveChanged: want()
    Component.onCompleted: want()
  }

  footer: Item {
    width: root.width
    height: 64
    Text {
      anchors.centerIn: parent
      width: parent.width - 2 * root.app.ui.gutter
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: "Books and covers from Open Library, the Internet Archive's open catalogue."
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
    }
  }
}
