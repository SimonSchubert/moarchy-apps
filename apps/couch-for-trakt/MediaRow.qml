import QtQuick
import "Api.mjs" as Api
import "Glyphs.js" as G

// One line of a calendar or of your history: a time, the poster, the title,
// and the episode when there is one.
Item {
  id: root
  property var app
  property var media: ({})
  property var episode: null
  property string lead: ""
  property string note: ""
  property bool dim: false
  property bool current: false
  signal activated()

  readonly property bool spoilers: app.store.prefs.hideSpoilers === true
  implicitHeight: app.compact ? 72 : 76

  Rectangle {
    anchors.fill: parent
    color: root.current ? root.app.ui.selected : mouse.pressed ? root.app.ui.pressed : mouse.containsMouse ? root.app.ui.hover : "transparent"
  }
  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: !root.app.compact
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }

  Text {
    id: leadText
    x: 14
    width: root.app.compact ? 46 : 56
    anchors.verticalCenter: parent.verticalCenter
    text: root.lead
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.sm
    font.features: ({ "tnum": 1 })
  }

  Poster {
    id: pic
    anchors.left: leadText.right
    anchors.verticalCenter: parent.verticalCenter
    height: parent.height - 16
    width: Math.round(height * 2 / 3)
    app: root.app
    source: root.media.poster || ""
    title: ""
    tint: root.media.tint || ""
    glyph: root.media.type === "show" ? G.tv : G.movie
    radius: 5
    ground: root.app.ui.bg
    opacity: root.dim ? 0.6 : 1
  }

  Column {
    anchors.left: pic.right
    anchors.leftMargin: 12
    anchors.right: noteText.left
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    spacing: 3
    Text {
      width: parent.width
      text: root.media.title || ""
      color: root.dim ? root.app.ui.muted : root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md
      font.weight: Font.DemiBold
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      text: root.episode
        ? Api.epCode(root.episode) + (root.episode.title && !root.spoilers ? "  ·  " + root.episode.title : "")
        : [root.media.type === "show" ? "Show" : "Movie", Api.runtime(root.media.runtime), Api.percent(root.media.rating) ? "♥\u00a0" + Api.percent(root.media.rating) : ""]
            .filter(function (s) { return s }).join("  ·  ")
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      elide: Text.ElideRight
    }
  }

  Text {
    id: noteText
    anchors.right: parent.right
    anchors.rightMargin: 14
    anchors.verticalCenter: parent.verticalCenter
    width: Math.min(implicitWidth, root.width * 0.3)
    horizontalAlignment: Text.AlignRight
    text: root.note
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.xs
    elide: Text.ElideRight
  }

  Rectangle {
    anchors.bottom: parent.bottom
    anchors.left: pic.left
    anchors.right: parent.right
    height: 1
    color: root.app.ui.divider
  }
}
