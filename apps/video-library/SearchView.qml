import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G

// Search, through Odysee's own index: videos or channels, as you type. A
// pasted odysee.com link, an lbry:// URL or an @channel opens what it names.
Item {
  id: root
  property var app
  property string kind: "videos"
  property alias query: search.text
  property int current: -1
  readonly property string term: query.trim()
  readonly property bool isLink: app.isLink(term)
  readonly property string key: "search:" + kind + ":" + term
  readonly property var feed: term.length >= 2 && !isLink ? (app.feeds[key] || app.emptyFeed) : app.emptyFeed
  readonly property alias grid: grid

  function focusField() { search.input.forceActiveFocus() }
  function run() {
    typing.stop()
    if (term === "") return
    if (isLink) { app.openLink(term); return }
    if (term.length >= 2) app.search(kind, term)
  }

  onKindChanged: { current = -1; run() }
  onTermChanged: { current = -1; typing.restart() }

  // Half a second after the last key, not on every one.
  Timer { id: typing; interval: 450; onTriggered: if (!root.isLink) root.run() }

  SearchField {
    id: search
    app: root.app
    x: root.app.ui.gutter
    y: 6
    width: parent.width - root.app.ui.gutter * 2
    placeholder: "Search videos, channels, or paste a link"
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
    Chip { app: root.app; text: "Videos"; glyph: G.video; selected: root.kind === "videos"; onClicked: root.kind = "videos" }
    Chip { app: root.app; text: "Channels"; glyph: G.channel; selected: root.kind === "channels"; onClicked: root.kind = "channels" }
  }

  // Before anything is typed: somewhere to start.
  Column {
    visible: root.term === ""
    anchors.top: kinds.bottom
    anchors.topMargin: 28
    x: root.app.ui.gutter
    width: parent.width - root.app.ui.gutter * 2
    spacing: 12
    SectionTitle { app: root.app; text: "Try"; note: "or paste an odysee.com link" }
    Flow {
      width: parent.width
      spacing: 6
      Repeater {
        model: ["linux", "science", "history", "documentary", "music", "cooking", "chess", "space", "retro gaming", "woodworking", "philosophy", "open source"]
        delegate: Chip {
          required property string modelData
          app: root.app
          text: modelData
          glyph: KG.search
          hpad: 18
          onClicked: { root.query = modelData; root.run() }
        }
      }
    }
  }

  EmptyState {
    visible: root.isLink
    anchors.centerIn: parent
    app: root.app
    glyph: G.library
    title: "A link"
    text: "Press Enter to open it."
    actionText: "Open"
    onAction: root.app.openLink(root.term)
  }

  VideoGrid {
    id: grid
    visible: root.kind === "videos" && root.term !== "" && !root.isLink
    anchors.top: kinds.bottom
    anchors.topMargin: 12
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    app: root.app
    items: visible ? root.feed.items : []
    now: root.app.nowSec
    savedIds: root.app.savedIds
    loading: root.feed.loading || typing.running
    more: root.feed.more
    error: root.feed.error
    current: root.current
    emptyGlyph: KG.search
    emptyTitle: root.term.length < 2 ? "Keep typing" : "No match"
    emptyText: root.term.length < 2 ? "" : "Nothing on Odysee is called “" + root.term + "”."
    onOpened: function (item) { root.app.openVideo(item) }
    onChannelOpened: function (ch) { root.app.openChannel(ch) }
    onWantMore: root.app.loadMore(root.key)
    onRetry: root.app.load(root.key, 1)
  }

  ListView {
    id: channelList
    visible: root.kind === "channels" && root.term !== "" && !root.isLink
    anchors.top: kinds.bottom
    anchors.topMargin: 12
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: root.app.compact ? 4 : root.app.ui.gutter - 8
    anchors.rightMargin: anchors.leftMargin
    clip: true
    spacing: 2
    boundsBehavior: Flickable.StopAtBounds
    model: visible ? root.feed.items : []
    delegate: ChannelRow {
      required property var modelData
      required property int index
      width: channelList.width
      app: root.app
      channel: modelData
      current: index === root.current
      followed: !!root.app.followIds[modelData.id]
      onOpened: root.app.openChannel(modelData)
      onFollowToggled: root.app.toggleFollow(modelData)
    }
    onContentYChanged: if (root.feed.more && !root.feed.loading && contentY + height * 2 > contentHeight) root.app.loadMore(root.key)
    footer: Item { width: 1; height: 16 }

    EmptyState {
      anchors.centerIn: parent
      visible: channelList.count === 0
      app: root.app
      busy: root.feed.loading || typing.running
      glyph: G.channels
      title: root.feed.error !== "" ? "Could not search" : "No channel by that name"
      text: root.feed.error
    }
  }
}
