import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G
import "OpenLibrary.js" as OL

// One author: their photo, their years, what Open Library says about them,
// and every book of theirs it has, most read first, a page at a time.
Item {
  id: root
  property var app
  // { id, name } as the page was opened with; `detail` fills in the rest.
  property var author: null
  property var detail: null
  property var feed: null
  property string error: ""
  signal bookOpened(var book)
  signal wantMore()
  signal retry()

  readonly property string name: detail ? detail.name : author ? author.name : ""
  property bool expanded: false
  readonly property alias grid: grid

  onAuthorChanged: { expanded = false; grid.positionViewAtBeginning() }

  PageHeader {
    id: head
    width: parent.width
    app: root.app
    title: "Author"
    subtitle: root.name
    IconButton {
      visible: root.detail !== null && root.detail.wikipedia !== ""
      app: root.app
      glyph: G.wikipedia
      label: "Wikipedia"
      onClicked: if (root.detail) Qt.openUrlExternally(root.detail.wikipedia)
    }
    IconButton {
      app: root.app
      glyph: G.copy
      label: "Copy the Open Library link"
      onClicked: root.app.copyLink(root.author ? OL.authorWeb(root.author.id) : "")
    }
    IconButton {
      app: root.app
      glyph: KG.open
      label: "Open on openlibrary.org"
      onClicked: if (root.author) Qt.openUrlExternally(OL.authorWeb(root.author.id))
    }
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
    emptyGlyph: G.book
    emptyTitle: "No books listed"
    emptyText: "Open Library has no works filed under " + root.name + "."
    onOpened: function (book) { root.bookOpened(book) }
    onWantMore: root.wantMore()
    onRetry: root.retry()

    header: Item {
      width: grid.rowWidth
      height: intro.height + 16

      Column {
        id: intro
        width: Math.min(parent.width, 820)
        y: 12
        spacing: 16

        Row {
          width: parent.width
          spacing: root.app.compact ? 16 : 22
          Portrait {
            id: face
            width: root.app.compact ? 96 : 128
            height: Math.round(width * 1.25)
            app: root.app
            name: root.name
            source: root.author ? root.app.authorPhotoSource(root.author.id, root.detail ? root.detail.photo : 0, "L") : ""
          }
          Column {
            width: parent.width - face.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Text {
              width: parent.width
              wrapMode: Text.Wrap
              text: root.name
              color: root.app.ui.text
              font.family: root.app.ui.font
              font.pixelSize: root.app.compact ? root.app.ui.fs.xl : root.app.ui.fs.xxl - 4
              font.weight: Font.Bold
              lineHeight: 1.05
            }
            Text {
              width: parent.width
              visible: text !== ""
              wrapMode: Text.Wrap
              text: OL.lifespan(root.detail || root.author)
              color: root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.sm
            }
            Badge {
              visible: root.feed !== null && root.feed.total > 0
              app: root.app
              text: root.feed ? OL.plural(root.feed.total, "book") : ""
            }
          }
        }

        Column {
          width: parent.width
          spacing: 8
          visible: bio.text !== ""
          Text {
            id: bio
            width: parent.width
            wrapMode: Text.Wrap
            text: root.detail ? root.detail.bio : ""
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.md
            lineHeight: 1.3
            maximumLineCount: root.expanded ? 400 : 5
            elide: Text.ElideRight
          }
          Button {
            visible: bio.truncated || root.expanded
            app: root.app
            text: root.expanded ? "Less" : "More"
            glyph: root.expanded ? KG.chevronDown : KG.chevronRight
            onClicked: root.expanded = !root.expanded
          }
        }
        Text {
          visible: root.error !== "" && !root.detail
          width: parent.width
          wrapMode: Text.Wrap
          text: root.error
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
        }

        SectionTitle {
          visible: grid.items.length > 0
          app: root.app
          text: "Books"
          note: "most read first"
        }
      }
    }
  }
}
