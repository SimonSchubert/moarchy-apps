import QtQuick
import "Api.mjs" as Api
import "Glyphs.js" as G

// A show and its next episode: the still, where you are in the show, and a
// tick to say you watched it.
Rectangle {
  id: root
  property var app
  property var entry: ({})          // { show, next, aired, completed, lastWatched }
  property bool current: false
  signal activated()

  readonly property var show: entry.show || ({})
  readonly property var ep: entry.next || ({})
  readonly property bool done: { app.library.rev; return !!entry.next && app.library.episodeWatched(show.id, null, ep) }
  readonly property real share: entry.aired > 0 ? Math.min(1, (entry.completed + (done ? 1 : 0)) / entry.aired) : 0
  readonly property int remaining: Math.max(0, (entry.aired || 0) - (entry.completed || 0) - (done ? 1 : 0))
  readonly property bool spoilers: app.store.prefs.hideSpoilers === true

  radius: app.ui.radius + 2
  color: mouse.pressed ? app.ui.surfaceHigh : mouse.containsMouse ? Qt.tint(app.ui.surface, app.ui.hover) : app.ui.surface
  border.width: current ? 2 : 0
  border.color: app.ui.accent

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: !root.app.compact
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }

  Poster {
    id: still
    x: 8
    anchors.verticalCenter: parent.verticalCenter
    height: parent.height - 16
    width: Math.round(height * (root.app.compact ? 1.2 : 16 / 9))
    app: root.app
    source: root.ep.still || root.show.fanart || ""
    title: ""
    tint: root.show.tint || ""
    glyph: G.tv
    ground: root.color
    radius: root.app.ui.radius
    opacity: root.done ? 0.45 : 1
  }

  Column {
    anchors.left: still.right
    anchors.leftMargin: 12
    anchors.right: tick.left
    anchors.rightMargin: 6
    anchors.verticalCenter: parent.verticalCenter
    spacing: 3

    Text {
      width: parent.width
      text: root.show.title || ""
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md
      font.weight: Font.DemiBold
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      text: Api.epCode(root.ep) + (root.ep.title && !root.spoilers ? "  ·  " + root.ep.title : "")
      color: root.done ? root.app.ui.muted : root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      font.strikeout: root.done
      elide: Text.ElideRight
    }
    Item { width: 1; height: 3 }
    Rectangle {
      width: parent.width
      height: 4
      radius: 2
      color: root.app.ui.divider
      Rectangle {
        width: parent.width * root.share
        height: parent.height
        radius: 2
        color: root.app.ui.accent
        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
      }
    }
    Text {
      width: parent.width
      text: (root.entry.completed + (root.done ? 1 : 0)) + " of " + root.entry.aired
        + (root.remaining ? "  ·  " + root.remaining + " left" : "  ·  all caught up")
        + (root.ep.aired && !root.app.compact ? "  ·  aired " + Api.ago(root.ep.aired, root.app.clock) : "")
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
      elide: Text.ElideRight
    }
  }

  Item {
    id: tick
    anchors.right: parent.right
    anchors.rightMargin: 6
    anchors.verticalCenter: parent.verticalCenter
    width: 48
    height: 48
    Accessible.role: Accessible.CheckBox
    Accessible.name: "Watched " + Api.epCode(root.ep)
    Rectangle {
      anchors.centerIn: parent
      width: 36
      height: 36
      radius: 18
      color: root.done ? root.app.ui.good : tickMouse.pressed ? root.app.ui.pressed : "transparent"
      border.width: root.done ? 0 : 2
      border.color: tickMouse.containsMouse ? root.app.ui.good : root.app.alpha(root.app.ui.text, 0.3)
      scale: tickMouse.pressed ? 0.9 : 1
      Behavior on scale { NumberAnimation { duration: 100 } }
      Behavior on color { ColorAnimation { duration: 150 } }
      Icon {
        anchors.centerIn: parent
        app: root.app
        text: G.check
        size: 20
        color: root.done ? "white" : root.app.alpha(root.app.ui.text, 0.45)
      }
    }
    MouseArea {
      id: tickMouse
      anchors.fill: parent
      hoverEnabled: !root.app.compact
      cursorShape: Qt.PointingHandCursor
      onClicked: root.app.library.setEpisodes(root.show, [root.ep], !root.done)
    }
  }
}
