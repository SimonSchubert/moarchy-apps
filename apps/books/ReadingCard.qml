import QtQuick
import "kit"
import "OpenLibrary.js" as OL

// A book you are reading, as Discover leads with it: the cover, the title,
// who wrote it, and how far you are -- a bar and the page -- with a step on
// from here, so the page you reached on the bus is one tap to keep.
Rectangle {
  id: root
  property var app
  property var entry: null
  signal opened()
  signal stepped(int pages)

  implicitHeight: 128
  radius: app.ui.radius
  color: mouse.pressed ? app.ui.pressed : mouse.containsMouse ? Qt.tint(app.ui.surface, app.ui.hover) : app.ui.surface
  border.width: 1
  border.color: app.ui.line

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: !root.app.compact
    cursorShape: Qt.PointingHandCursor
    onClicked: root.opened()
  }

  Cover {
    id: cover
    x: 12
    anchors.verticalCenter: parent.verticalCenter
    width: 68
    height: 102
    app: root.app
    book: root.entry
  }

  Column {
    anchors.left: cover.right
    anchors.leftMargin: 14
    anchors.right: parent.right
    anchors.rightMargin: 14
    anchors.top: cover.top
    spacing: 3
    Text {
      width: parent.width
      text: root.entry ? root.entry.title : ""
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md + 1
      font.weight: Font.Bold
      wrapMode: Text.Wrap
      maximumLineCount: 2
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      text: OL.names(root.entry, 1)
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      elide: Text.ElideRight
    }
  }

  Column {
    anchors.left: cover.right
    anchors.leftMargin: 14
    anchors.right: parent.right
    anchors.rightMargin: 14
    anchors.bottom: cover.bottom
    spacing: 7
    Item {
      width: parent.width
      height: Math.max(pageText.height, plus.height)
      Text {
        id: pageText
        anchors.left: parent.left
        anchors.right: plus.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        // The bar says the percentage; the words, the page.
        text: root.entry && root.entry.pages > 0 ? "Page " + OL.grouped(root.entry.page || 0) + " of " + OL.grouped(root.entry.pages)
          : OL.progressText(root.entry)
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
        font.features: ({ "tnum": 1 })
        elide: Text.ElideRight
      }
      // Ten pages on, without opening the book.
      Rectangle {
        id: plus
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: plusText.implicitWidth + 16
        height: root.app.compact ? 30 : 26
        radius: root.app.ui.radius
        color: plusMouse.pressed ? root.app.ui.pressed : plusMouse.containsMouse ? root.app.ui.hover : root.app.ui.surfaceHigh
        border.width: 1
        border.color: root.app.ui.line
        visible: !!root.entry && (!(root.entry.pages > 0) || root.entry.page < root.entry.pages)
        Text {
          id: plusText
          anchors.centerIn: parent
          text: "+10"
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xs
          font.weight: Font.Bold
        }
        MouseArea {
          id: plusMouse
          anchors.fill: parent
          anchors.margins: -6
          hoverEnabled: !root.app.compact
          cursorShape: Qt.PointingHandCursor
          onClicked: root.stepped(10)
        }
      }
    }
    Rectangle {
      width: parent.width
      height: 6
      radius: root.app.ui.radius > 0 ? 3 : 0
      color: root.app.ui.well
      Rectangle {
        width: parent.width * OL.progress(root.entry)
        height: parent.height
        radius: parent.radius
        color: root.app.ui.accent
        Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
      }
    }
  }
}
