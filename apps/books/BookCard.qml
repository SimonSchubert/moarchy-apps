import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G
import "OpenLibrary.js" as OL

// One book on a shelf or in a grid: the cover, then the title in two lines
// and who wrote it. A book on your list says which shelf on its cover, and
// one you are reading how far through you are, along its foot.
Item {
  id: root
  property var app
  property var book: null
  // The book's entry on the reading list, or null.
  property var entry: null
  property bool current: false
  // The third line: the rating and the year, in a grid with room for it.
  property bool details: false
  signal opened()

  readonly property real coverHeight: Math.round(width * 3 / 2)
  implicitHeight: coverHeight + 8 + titleText.height + 2 + authorText.height + (details ? 18 : 0)

  Accessible.role: Accessible.ListItem
  Accessible.name: book ? book.title + ", " + OL.byline(book) : ""

  Rectangle {
    anchors.fill: parent
    anchors.margins: -5
    radius: root.app.ui.radius
    color: mouse.pressed ? root.app.ui.pressed : mouse.containsMouse ? root.app.ui.hover : "transparent"
    border.width: root.current && !root.app.compact ? 1 : 0
    border.color: root.app.ui.accent
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    anchors.margins: -5
    hoverEnabled: !root.app.compact
    cursorShape: Qt.PointingHandCursor
    onClicked: root.opened()
  }

  Cover {
    id: cover
    width: parent.width
    height: root.coverHeight
    app: root.app
    book: root.book

    // Which shelf, top right.
    Rectangle {
      visible: root.entry !== null
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 5
      width: 22; height: 22
      radius: root.app.ui.radius > 0 ? 3 : 0
      color: root.entry && root.entry.shelf === "read" ? root.app.ui.good : root.app.ui.accent
      Icon {
        anchors.centerIn: parent
        app: root.app
        size: 13
        text: !root.entry ? "" : root.entry.shelf === "read" ? KG.check : root.entry.shelf === "reading" ? G.reading : G.wanted
        color: root.entry && root.entry.shelf === "read" ? root.app.ui.inkOnGood : root.app.ui.inkOnAccent
      }
    }

    // How far through, along the foot.
    Rectangle {
      visible: root.entry !== null && root.entry.shelf === "reading" && root.entry.pages > 0
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: 1
      height: 5
      color: root.app.ui.scrimStrong
      Rectangle {
        width: parent.width * OL.progress(root.entry)
        height: parent.height
        color: root.app.ui.accent
      }
    }
  }

  Text {
    id: titleText
    anchors.top: cover.bottom
    anchors.topMargin: 8
    width: parent.width
    text: root.book ? root.book.title : ""
    color: root.app.ui.text
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.md
    font.weight: Font.Bold
    wrapMode: Text.Wrap
    maximumLineCount: 2
    elide: Text.ElideRight
    lineHeight: 1.05
  }
  Text {
    id: authorText
    anchors.top: titleText.bottom
    anchors.topMargin: 2
    width: parent.width
    text: OL.names(root.book, 1)
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.sm
    elide: Text.ElideRight
  }
  Row {
    visible: root.details
    anchors.top: authorText.bottom
    anchors.topMargin: 3
    spacing: 6
    Row {
      visible: root.book && root.book.rating > 0
      spacing: 3
      anchors.verticalCenter: parent.verticalCenter
      Icon { app: root.app; text: KG.star; size: 11; color: root.app.ui.warn; anchors.verticalCenter: parent.verticalCenter }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.book ? OL.rating(root.book.rating) : ""
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
        font.weight: Font.Bold
      }
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: text !== ""
      text: root.entry && root.entry.shelf === "read" && root.entry.stars > 0 ? "yours " + root.entry.stars + "/5"
        : root.book && root.book.year > 0 ? String(root.book.year) : ""
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
    }
  }
}
