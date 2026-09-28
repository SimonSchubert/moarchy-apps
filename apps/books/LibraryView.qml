import QtQuick
import "kit"
import "Glyphs.js" as G
import "OpenLibrary.js" as OL

// Your books: what you are reading, what you want to, and what you have read,
// on this machine and nowhere else. Over the shelves, the year so far against
// the number you meant to read in it.
Item {
  id: root
  property var app
  property string shelf: "reading"
  property int current: -1
  readonly property var items: OL.onShelf(app.books, shelf)
  readonly property var counts: OL.counts(app.books)
  readonly property var year: OL.yearStats(app.books, app.nowSec)
  readonly property int goal: app.goal
  readonly property alias grid: grid

  onShelfChanged: { current = -1; grid.positionViewAtBeginning() }

  // ------------------------------------------------ the year
  Rectangle {
    id: yearCard
    x: root.app.ui.gutter
    y: 8
    width: Math.min(parent.width - root.app.ui.gutter * 2, 720)
    height: root.app.compact ? 76 : 72
    radius: root.app.ui.radius
    color: root.app.ui.surface
    border.width: 1
    border.color: root.app.ui.line

    Icon {
      id: trophy
      x: 14
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      text: G.goal
      size: 26
      color: root.year.books >= root.goal && root.goal > 0 ? root.app.ui.warn : root.app.ui.accent
    }
    Column {
      anchors.left: trophy.right
      anchors.leftMargin: 14
      anchors.right: parent.right
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      spacing: 7
      Item {
        width: parent.width
        height: yearLine.height
        Text {
          id: yearLine
          anchors.left: parent.left
          anchors.right: yearPages.left
          anchors.rightMargin: 8
          text: root.year.books + (root.goal > 0 ? " of " + root.goal : "") + " read in " + root.year.year
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.md + 1
          font.weight: Font.Bold
          elide: Text.ElideRight
        }
        Text {
          id: yearPages
          anchors.right: parent.right
          anchors.baseline: yearLine.baseline
          visible: root.year.pages > 0
          text: OL.plural(root.year.pages, "page")
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xs
        }
      }
      Rectangle {
        width: parent.width
        height: 6
        radius: root.app.ui.radius > 0 ? 3 : 0
        color: root.app.ui.well
        visible: root.goal > 0
        Rectangle {
          width: parent.width * Math.min(1, root.goal > 0 ? root.year.books / root.goal : 0)
          height: parent.height
          radius: parent.radius
          color: root.year.books >= root.goal ? root.app.ui.good : root.app.ui.accent
        }
      }
    }
  }

  // ------------------------------------------------ the shelves
  Flickable {
    id: chipScroll
    anchors.top: yearCard.bottom
    anchors.topMargin: 12
    x: 0
    width: parent.width
    height: root.app.ui.chip
    contentWidth: shelves.width + 2 * root.app.ui.gutter
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    Row {
      id: shelves
      x: root.app.ui.gutter
      spacing: 6
      Repeater {
        model: OL.SHELVES
        delegate: Chip {
          required property var modelData
          app: root.app
          glyph: modelData.key === "reading" ? G.reading : modelData.key === "want" ? G.want : G.read
          text: (root.app.compact && modelData.key === "want" ? "Want" : modelData.label) + (root.counts[modelData.key] ? "  " + root.counts[modelData.key] : "")
          selected: root.shelf === modelData.key
          onClicked: root.shelf = modelData.key
        }
      }
    }
  }

  BookGrid {
    id: grid
    anchors.top: chipScroll.bottom
    anchors.topMargin: 12
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    app: root.app
    items: root.items
    current: root.current
    emptyGlyph: root.shelf === "reading" ? G.reading : root.shelf === "want" ? G.want : G.read
    emptyTitle: root.shelf === "reading" ? "Not reading anything" : root.shelf === "want" ? "Nothing to read next" : "Nothing read yet"
    emptyText: root.shelf === "reading" ? "Start a book from its page, and it waits for you here and at the top of Discover with the page you reached."
      : root.shelf === "want" ? "The bookmark on a book's page keeps it here for later."
      : "A book marked Read lands here, with the day you finished it and your stars."
    emptyAction: "Discover"
    onEmptyActed: root.app.setTab("discover")
    onOpened: function (book) { root.app.openBook(book) }
  }
}
