import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G
import "OpenLibrary.js" as OL

// Search, through Open Library's own index: books by title, author or
// anything in them, or authors by name, as you type. An ISBN, an
// openlibrary.org link or a bare OL...W opens the book it names.
Item {
  id: root
  property var app
  property string kind: "books"
  property alias query: search.text
  property int current: -1
  readonly property string term: query.trim()
  readonly property var named: OL.link(term)
  readonly property string key: "search:" + kind + ":" + term
  readonly property var feed: term.length >= 2 && !named ? (app.feeds[key] || app.emptyFeed) : app.emptyFeed
  readonly property alias grid: grid

  function focusField() { search.input.forceActiveFocus() }
  function run() {
    typing.stop()
    if (term === "") return
    if (named) { app.openLink(term); return }
    if (term.length >= 2) app.search(kind, term)
  }

  onKindChanged: { current = -1; run() }
  onTermChanged: { current = -1; typing.restart() }

  // Half a second after the last key, not on every one.
  Timer { id: typing; interval: 450; onTriggered: if (!root.named) root.run() }

  SearchField {
    id: search
    app: root.app
    x: root.app.ui.gutter
    y: 8
    width: Math.min(parent.width - root.app.ui.gutter * 2, 720)
    placeholder: "Title, author, subject or ISBN"
    onEscaped: root.app.resetFocus()
  }
  Connections {
    target: search.input
    function onAccepted() { root.run() }
  }

  Row {
    id: kinds
    x: root.app.ui.gutter
    anchors.top: search.bottom
    anchors.topMargin: 10
    spacing: 6
    Chip { app: root.app; text: "Books"; glyph: G.book; selected: root.kind === "books"; onClicked: root.kind = "books" }
    Chip { app: root.app; text: "Authors"; glyph: G.author; selected: root.kind === "authors"; onClicked: root.kind = "authors" }
  }
  Text {
    anchors.right: parent.right
    anchors.rightMargin: root.app.ui.gutter
    anchors.verticalCenter: kinds.verticalCenter
    visible: root.feed.total > 0 && root.term !== ""
    text: OL.grouped(root.feed.total) + (root.feed.total === 1 ? " match" : " matches")
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.xs
  }

  // Before anything is typed: somewhere to start.
  Flickable {
    visible: root.term === ""
    anchors.top: kinds.bottom
    anchors.topMargin: 20
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentHeight: start.height + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    Column {
      id: start
      x: root.app.ui.gutter
      width: Math.min(parent.width - root.app.ui.gutter * 2, 760)
      spacing: 12
      SectionTitle { app: root.app; text: "Browse"; note: "a subject, most read first" }
      Flow {
        width: parent.width
        spacing: 6
        Repeater {
          model: OL.SUBJECTS
          delegate: Chip {
            required property var modelData
            app: root.app
            text: modelData.label
            glyph: G.tag
            hpad: 18
            onClicked: root.app.openShelf("subject:" + modelData.key, modelData.label)
          }
        }
      }
      Item { width: 1; height: 8 }
      SectionTitle { app: root.app; text: "Try"; note: "an ISBN works too" }
      Flow {
        width: parent.width
        spacing: 6
        Repeater {
          model: ["the lord of the rings", "ursula k le guin", "stoicism", "dune", "agatha christie", "sourdough", "9780141439518"]
          delegate: Chip {
            required property string modelData
            app: root.app
            text: modelData
            glyph: /^\d+$/.test(modelData) ? G.barcode : KG.search
            hpad: 18
            onClicked: { root.query = modelData; root.run() }
          }
        }
      }
    }
  }

  EmptyState {
    visible: root.named !== null
    anchors.centerIn: parent
    app: root.app
    glyph: root.named && root.named.kind === "isbn" ? G.barcode : G.book
    title: root.named && root.named.kind === "isbn" ? "An ISBN" : root.named && root.named.kind === "author" ? "An author" : "A book"
    text: "Press Enter to open it."
    actionText: "Open"
    onAction: root.app.openLink(root.term)
  }

  BookGrid {
    id: grid
    visible: root.kind === "books" && root.term !== "" && !root.named
    anchors.top: kinds.bottom
    anchors.topMargin: 12
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    app: root.app
    items: visible ? root.feed.items : []
    loading: root.feed.loading || typing.running
    more: root.feed.more
    error: root.feed.error
    current: root.current
    emptyGlyph: KG.search
    emptyTitle: root.term.length < 2 ? "Keep typing" : "No match"
    emptyText: root.term.length < 2 ? "" : "Nothing in Open Library matches “" + root.term + "”."
    onOpened: function (book) { root.app.openBook(book) }
    onWantMore: root.app.loadMore(root.key)
    onRetry: root.app.load(root.key, 1)
  }

  ListView {
    id: authorList
    visible: root.kind === "authors" && root.term !== "" && !root.named
    anchors.top: kinds.bottom
    anchors.topMargin: 12
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: root.app.compact ? 4 : root.app.ui.gutter - 8
    anchors.rightMargin: anchors.leftMargin
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: visible ? root.feed.items : []
    delegate: AuthorRow {
      required property var modelData
      width: Math.min(authorList.width, 760)
      app: root.app
      author: modelData
      onOpened: root.app.openAuthor(modelData)
    }
    onContentYChanged: Qt.callLater(nearEnd)
    function nearEnd() { if (root.feed.more && !root.feed.loading && contentY + height * 2 > contentHeight) root.app.loadMore(root.key) }
    footer: Item { width: 1; height: 16 }

    EmptyState {
      anchors.centerIn: parent
      visible: authorList.count === 0
      app: root.app
      busy: root.feed.loading || typing.running
      glyph: G.authors
      title: root.feed.error !== "" ? "Could not search" : root.term.length < 2 ? "Keep typing" : "Nobody by that name"
      text: root.feed.error
    }
  }
}
