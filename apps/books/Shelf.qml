import QtQuick
import "kit"
import "kit/Glyphs.js" as KG

// A shelf: a heading, "See all" at the end of it, and a row of covers that
// scrolls sideways. Discover is a stack of these; so is the foot of a book's
// page ("More by ...").
Item {
  id: root
  property var app
  property string title: ""
  property string note: ""
  property var items: []
  property bool loading: false
  property string error: ""
  property real coverWidth: app.compact ? 104 : 136
  property bool seeAll: true
  signal opened(var book)
  signal seeAllClicked()
  signal retry()

  readonly property real rowHeight: Math.round(coverWidth * 3 / 2) + 8 + Math.ceil(app.ui.fs.md * 1.3) * 2 + app.ui.fs.sm + 8
  implicitHeight: head.height + 10 + rowHeight

  Item {
    id: head
    x: root.app.ui.gutter
    width: parent.width - root.app.ui.gutter * 2
    height: 30
    SectionTitle {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      text: root.title
      note: root.note
    }
    // "See all", as a word and a chevron rather than a button: the shelf is
    // the thing, this is a way further along it.
    Rectangle {
      visible: root.seeAll && root.items.length > 0
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: allRow.implicitWidth + 16
      height: root.app.ui.chip
      radius: root.app.ui.radius
      color: allMouse.pressed ? root.app.ui.pressed : allMouse.containsMouse ? root.app.ui.hover : "transparent"
      Row {
        id: allRow
        anchors.centerIn: parent
        spacing: 2
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "See all"
          color: root.app.ui.accent
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xs
          font.weight: Font.Bold
          font.capitalization: Font.AllUppercase
          font.letterSpacing: root.app.ui.tracking
        }
        Icon { anchors.verticalCenter: parent.verticalCenter; app: root.app; text: KG.chevronRight; size: 15; color: root.app.ui.accent }
      }
      MouseArea {
        id: allMouse
        anchors.fill: parent
        hoverEnabled: !root.app.compact
        cursorShape: Qt.PointingHandCursor
        onClicked: root.seeAllClicked()
      }
    }
  }

  ListView {
    id: row
    anchors.top: head.bottom
    anchors.topMargin: 10
    width: parent.width
    height: root.rowHeight
    orientation: ListView.Horizontal
    spacing: root.app.compact ? 14 : 22
    leftMargin: root.app.ui.gutter
    rightMargin: root.app.ui.gutter
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    cacheBuffer: 400
    model: Keyed { id: keyed; items: root.items }
    delegate: BookCard {
      required property string key
      width: root.coverWidth
      app: root.app
      book: keyed.at(key).id ? keyed.at(key) : null
      entry: root.app.shelved[key] || null
      onOpened: if (book) root.opened(book)
    }

    // While the shelf is empty: the outlines of the books it will hold, so
    // Discover does not jump when they land.
    Row {
      visible: root.items.length === 0
      x: root.app.ui.gutter
      spacing: row.spacing
      Repeater {
        model: root.items.length === 0 ? Math.ceil(row.width / (root.coverWidth + row.spacing)) : 0
        delegate: Rectangle {
          width: root.coverWidth
          height: Math.round(root.coverWidth * 3 / 2)
          radius: root.app.ui.radius > 0 ? 3 : 0
          color: root.app.ui.well
          border.width: 1
          border.color: root.app.ui.line
          opacity: root.loading ? pulse.value : 0.6
        }
      }
    }
    Column {
      visible: root.items.length === 0 && !root.loading && root.error !== ""
      x: root.app.ui.gutter + 12
      y: Math.round(root.coverWidth * 3 / 4) - height / 2
      width: Math.min(row.width - 2 * root.app.ui.gutter - 24, 420)
      spacing: 10
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: root.error
        color: root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.sm
      }
      Button { app: root.app; text: "Try again"; onClicked: root.retry() }
    }
  }

  // One slow breath for every placeholder at once.
  QtObject {
    id: pulse
    property real value: 0.9
  }
  SequentialAnimation {
    running: root.loading && root.items.length === 0 && root.visible
    loops: Animation.Infinite
    NumberAnimation { target: pulse; property: "value"; to: 0.45; duration: 700; easing.type: Easing.InOutSine }
    NumberAnimation { target: pulse; property: "value"; to: 0.9; duration: 700; easing.type: Easing.InOutSine }
  }
}
