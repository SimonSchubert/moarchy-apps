import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G
import "Lbry.js" as L

// A channel: its banner and face, its follow button, what it says about
// itself, and everything it has put up, newest first, a page at a time.
Item {
  id: root
  property var app
  property var channel: null
  property var feed: ({ items: [], loading: false, more: false, error: "" })
  property real now: 0
  property var savedIds: ({})
  property bool followed: false
  signal followToggled()
  signal videoOpened(var item)
  signal wantMore()
  signal retry()

  property bool expanded: false
  onChannelChanged: { expanded = false; grid.positionViewAtBeginning() }

  PageHeader {
    id: head
    width: parent.width
    app: root.app
    title: root.channel ? root.channel.title : "Channel"
    subtitle: root.channel ? L.handle(root.channel) : ""
    IconButton {
      app: root.app
      glyph: G.copy
      label: "Copy the Odysee link"
      onClicked: root.app.copyLink(root.channel ? root.channel.url : "")
    }
    IconButton {
      app: root.app
      glyph: KG.open
      label: "Open on odysee.com"
      onClicked: root.app.openWeb(root.channel ? root.channel.url : "")
    }
  }

  VideoGrid {
    id: grid
    anchors.top: head.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    app: root.app
    items: root.feed.items
    now: root.now
    savedIds: root.savedIds
    loading: root.feed.loading
    more: root.feed.more
    error: root.feed.error
    emptyGlyph: G.video
    emptyTitle: "Nothing here yet"
    emptyText: "This channel has not put up anything this app can play."
    onOpened: function (item) { root.videoOpened(item) }
    onWantMore: root.wantMore()
    onRetry: root.retry()

    header: Item {
      width: grid.rowWidth
      height: hero.implicitHeight + (root.feed.items.length || root.feed.loading ? 22 : 140)

      Column {
        id: hero
        width: parent.width
        spacing: 14

        // The banner, with the face over its bottom edge.
        Item {
          width: parent.width
          height: banner.height + face.height / 2
          Thumb {
            id: banner
            width: parent.width
            height: Math.round(Math.min(width / 4.5, 220))
            app: root.app
            glyph: G.library
            glyphSize: 34
            source: root.channel && root.channel.cover ? root.app.art(root.channel.id + "-cover", root.channel.cover, 1280, 284) : ""
          }
          Thumb {
            id: face
            x: root.app.compact ? 12 : 20
            anchors.bottom: parent.bottom
            width: root.app.compact ? 72 : 96
            height: width
            app: root.app
            color: root.app.ui.bg
            glyph: G.channel
            glyphSize: 30
            source: root.channel ? root.app.art(root.channel.id, root.channel.thumb, 192, 192) : ""
          }
          Button {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            app: root.app
            primary: !root.followed
            active: root.followed
            glyph: root.followed ? G.followed : G.follow
            text: root.followed ? "Following" : "Follow"
            onClicked: root.followToggled()
          }
        }

        Column {
          width: parent.width
          spacing: 4
          Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: root.channel ? root.channel.title : ""
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xl - 2
            font.weight: Font.Bold
          }
          Text {
            width: parent.width
            text: root.channel ? [L.handle(root.channel), L.uploadsText(root.channel)].filter(function (s) { return s !== "" }).join(" · ") : ""
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
            elide: Text.ElideRight
          }
        }

        Text {
          id: about
          width: Math.min(parent.width, 820)
          visible: text !== ""
          wrapMode: Text.Wrap
          text: root.channel ? root.channel.description : ""
          maximumLineCount: root.expanded ? 200 : 3
          elide: Text.ElideRight
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.md
          lineHeight: 1.2
          MouseArea {
            anchors.fill: parent
            enabled: about.truncated || root.expanded
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expanded = !root.expanded
          }
        }

        Rectangle { width: parent.width; height: 1; color: root.app.ui.line }

        SectionTitle {
          app: root.app
          text: "Uploads"
          note: "newest first"
        }
      }
    }
  }
}
