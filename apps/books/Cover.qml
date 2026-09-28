import QtQuick
import "kit"
import "OpenLibrary.js" as OL

// A book's cover, at 2:3. Until the picture arrives -- or when Open Library
// has none, or there is no network -- the book is bound in plain cloth with
// its title and author set on it, so a shelf on a slow connection is a shelf
// of books rather than a row of grey boxes, and one with no picture at all
// still says what it is.
Rectangle {
  id: root
  property var app
  property var book: null
  // M for a shelf, L for a book's own page.
  property string size: "M"
  readonly property bool ready: img.status === Image.Ready
  readonly property int coverId: book ? (book.cover || 0) : 0
  readonly property color cloth: app.ui.cloth[OL.hash(book ? book.id + book.title : "") % app.ui.cloth.length]

  implicitWidth: 120
  implicitHeight: Math.round(width * 3 / 2)
  radius: app.ui.radius > 0 ? 3 : 0
  color: cloth
  border.width: 1
  border.color: app.ui.line
  clip: true

  // ------------------------------------------------ the cloth
  Item {
    anchors.fill: parent
    visible: !root.ready
    Rectangle {
      anchors.fill: parent
      anchors.margins: Math.max(4, Math.round(root.width * 0.06))
      color: "transparent"
      border.width: 1
      border.color: root.app.ui.alpha(root.app.ui.clothInk, 0.35)
    }
    Column {
      anchors.centerIn: parent
      width: parent.width - Math.max(14, root.width * 0.2)
      spacing: Math.max(4, root.width * 0.05)
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: root.book ? root.book.title : ""
        color: root.app.ui.clothInk
        font.family: root.app.ui.font
        font.pixelSize: Math.max(8, Math.round(root.width * 0.1))
        font.weight: Font.Bold
        wrapMode: Text.Wrap
        maximumLineCount: 5
        elide: Text.ElideRight
        lineHeight: 1.05
      }
      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width * 0.3
        height: 1
        color: root.app.ui.alpha(root.app.ui.clothInk, 0.5)
        visible: author.text !== ""
      }
      Text {
        id: author
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: OL.names(root.book, 1)
        color: root.app.ui.alpha(root.app.ui.clothInk, 0.8)
        font.family: root.app.ui.font
        font.pixelSize: Math.max(7, Math.round(root.width * 0.075))
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
      }
    }
  }

  // ------------------------------------------------ the picture
  Image {
    id: img
    anchors.fill: parent
    anchors.margins: 1
    // A large cover that will not come: the medium one, which the shelf
    // has usually fetched already.
    property bool fellBack: false
    source: root.coverId > 0 ? root.app.coverSource(root.coverId, fellBack ? "M" : root.size) : ""
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: true
    smooth: true
    mipmap: root.size === "L"
    sourceSize.width: root.size === "L" ? 500 : 240
    opacity: root.ready ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 200 } }
    onStatusChanged: if (status === Image.Error && !fellBack && root.size !== "M") fellBack = true
  }
  onCoverIdChanged: img.fellBack = false

  // The fold of a hardback, down the left edge: a hairline of light.
  Rectangle {
    x: Math.max(3, Math.round(root.width * 0.035))
    width: 1
    height: parent.height
    color: root.app.ui.alpha(root.app.ui.clothInk, root.ready ? 0.18 : 0.12)
  }
}
