import QtQuick
import "kit"
import "Glyphs.js" as G

// The channels you follow, as a row of faces, and everything they put up,
// newest first. Following is a list in a file on this machine: no account,
// nothing sent anywhere but the question "what is new from these?".
Item {
  id: root
  property var app
  readonly property var feed: app.feeds["following"] || app.emptyFeed
  readonly property alias grid: grid
  property int current: -1

  EmptyState {
    anchors.centerIn: parent
    visible: root.app.follows.length === 0
    app: root.app
    glyph: G.following
    title: "Nobody followed yet"
    text: "Follow a channel from one of its videos, or find one by name, and what it puts up lands here, newest first."
    actionText: "Find channels"
    onAction: root.app.findChannels()
  }

  VideoGrid {
    id: grid
    anchors.fill: parent
    visible: root.app.follows.length > 0
    app: root.app
    items: root.feed.items
    now: root.app.nowSec
    savedIds: root.app.savedIds
    loading: root.feed.loading
    more: root.feed.more
    error: root.feed.error
    current: root.current
    emptyGlyph: G.video
    emptyTitle: "Nothing new"
    emptyText: "The channels you follow have not put anything up that this app can play."
    onOpened: function (item) { root.app.openVideo(item) }
    onChannelOpened: function (ch) { root.app.openChannel(ch) }
    onWantMore: root.app.loadMore("following")
    onRetry: root.app.load("following", 1)

    header: Item {
      width: grid.rowWidth
      height: faces.height + 18

      ListView {
        id: faces
        width: parent.width
        height: root.app.compact ? 96 : 100
        orientation: ListView.Horizontal
        spacing: 4
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.app.follows
        delegate: Rectangle {
          id: face
          required property var modelData
          width: 84
          height: faces.height
          radius: root.app.ui.radius
          color: faceMouse.pressed ? root.app.ui.pressed : faceMouse.containsMouse ? root.app.ui.hover : "transparent"
          MouseArea {
            id: faceMouse
            anchors.fill: parent
            hoverEnabled: !root.app.compact
            cursorShape: Qt.PointingHandCursor
            onClicked: root.app.openChannel(face.modelData)
          }
          Thumb {
            id: pic
            anchors.horizontalCenter: parent.horizontalCenter
            y: 8
            width: 56
            height: 56
            app: root.app
            glyph: G.channel
            glyphSize: 22
            source: root.app.art(face.modelData.id, face.modelData.thumb, 112, 112)
          }
          Text {
            anchors.top: pic.bottom
            anchors.topMargin: 6
            x: 4
            width: parent.width - 8
            horizontalAlignment: Text.AlignHCenter
            text: face.modelData.title
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xs
            elide: Text.ElideRight
          }
        }
      }
      Rectangle { anchors.bottom: parent.bottom; anchors.bottomMargin: 8; width: parent.width; height: 1; color: root.app.ui.line }
    }
  }
}
