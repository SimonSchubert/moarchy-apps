import QtQuick
import "Api.mjs" as Api
import "Glyphs.js" as G

// One episode on a show's page: still, number and title, when it aired, and
// whether you have watched it.
Item {
  id: root
  property var app
  property var show: ({})
  property var ep: ({})
  property var progress: null
  property bool canMark: false

  readonly property bool aired: !!ep.aired && new Date(ep.aired).getTime() <= app.clock
  readonly property bool watched: { app.library.rev; return canMark && app.library.episodeWatched(show.id, progress, ep) }
  // Spoilers: what has not been watched keeps its story to itself.
  readonly property bool veiled: app.store.prefs.hideSpoilers === true && canMark && !watched
  property bool expanded: false

  implicitHeight: Math.max(stillBox.height, info.implicitHeight) + 20

  MouseArea {
    anchors.fill: parent
    onClicked: root.expanded = !root.expanded
  }

  Item {
    id: stillBox
    x: 0
    y: 10
    width: root.app.compact ? 120 : 176
    height: Math.round(width * 9 / 16)
    Poster {
      anchors.fill: parent
      app: root.app
      source: root.veiled ? "" : root.ep.still || ""
      title: ""
      tint: root.show.tint || ""
      glyph: G.tv
      radius: root.app.ui.radius
      opacity: root.aired ? 1 : 0.5
    }
    Rectangle {
      visible: root.watched
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.35)
      Icon { anchors.centerIn: parent; app: root.app; text: G.checkCircle; size: 26; color: "white" }
    }
  }

  Column {
    id: info
    anchors.left: stillBox.right
    anchors.leftMargin: 12
    anchors.right: tick.left
    anchors.rightMargin: 4
    y: 10
    spacing: 3
    Text {
      width: parent.width
      text: root.ep.number + ".  " + (root.veiled ? "Episode " + root.ep.number : (root.ep.title || "Episode " + root.ep.number))
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md
      font.weight: Font.DemiBold
      wrapMode: Text.Wrap
      maximumLineCount: 2
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      text: [root.ep.aired ? (root.aired ? Api.date(root.ep.aired) : Api.date(root.ep.aired) + " · " + Api.until(root.ep.aired, root.app.clock)) : "Not scheduled",
        Api.runtime(root.ep.runtime), Api.percent(root.ep.rating) ? "♥\u00a0" + Api.percent(root.ep.rating) : "",
        root.ep.kind && root.ep.kind !== "standard" ? root.ep.kind.replace(/_/g, " ") : ""]
        .filter(function (s) { return s }).join("  ·  ")
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
      wrapMode: Text.Wrap
    }
    Text {
      visible: text !== "" && (root.expanded || !root.app.compact)
      width: parent.width
      text: root.veiled ? "" : root.ep.overview || ""
      color: root.app.alpha(root.app.ui.text, 0.75)
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      wrapMode: Text.Wrap
      maximumLineCount: root.expanded ? 40 : 2
      elide: Text.ElideRight
      lineHeight: 1.15
    }
  }

  Item {
    id: tick
    anchors.right: parent.right
    y: 10 + (stillBox.height - height) / 2
    width: root.canMark && root.aired ? 44 : 0
    height: 44
    visible: width > 0
    Rectangle {
      anchors.centerIn: parent
      width: 32
      height: 32
      radius: 16
      color: root.watched ? root.app.ui.good : "transparent"
      border.width: root.watched ? 0 : 2
      border.color: tickMouse.containsMouse ? root.app.ui.good : root.app.alpha(root.app.ui.text, 0.28)
      Behavior on color { ColorAnimation { duration: 150 } }
      Icon {
        anchors.centerIn: parent
        app: root.app
        text: G.check
        size: 18
        color: root.watched ? "white" : root.app.alpha(root.app.ui.text, 0.4)
      }
    }
    MouseArea {
      id: tickMouse
      anchors.fill: parent
      hoverEnabled: !root.app.compact
      cursorShape: Qt.PointingHandCursor
      onClicked: root.app.library.setEpisodes(root.show, [root.ep], !root.watched)
    }
  }

  Rectangle {
    anchors.bottom: parent.bottom
    width: parent.width
    height: 1
    color: root.app.ui.divider
  }
}
