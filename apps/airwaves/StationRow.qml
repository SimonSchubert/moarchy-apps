import QtQuick
import "Api.mjs" as Api
import "Glyphs.js" as G

// One station in a list: its picture, its name, where it is and what it
// plays, and a star. A tap plays it; a tap on the one already playing opens
// Now Playing.
Rectangle {
  id: root
  property var app
  property var station: ({})
  property bool current: false
  // A line to show instead of the usual one.
  property string detail: ""
  signal activated()

  readonly property bool playingThis: app.player.station !== null && app.player.station.id === station.id
  readonly property bool favorite: { app.store.prefs; return app.store.isFavorite(station.id) }

  implicitHeight: app.compact ? 68 : 72
  radius: app.ui.radius + 2
  color: current ? app.ui.selected : mouse.pressed ? app.ui.pressed : mouse.containsMouse ? app.ui.hover : "transparent"
  border.width: current ? 1 : 0
  border.color: app.ui.accent
  Accessible.role: Accessible.Button
  Accessible.name: station.name || ""

  Art {
    id: art
    x: 8
    anchors.verticalCenter: parent.verticalCenter
    width: root.app.compact ? 50 : 54
    height: width
    app: root.app
    station: root.station
  }

  // The one on air: its art under the accent, with the bars over it.
  Rectangle {
    anchors.fill: art
    radius: art.radius
    color: root.app.alpha(root.app.ui.accent, 0.82)
    visible: root.playingThis && root.app.player.active
    Equalizer {
      anchors.centerIn: parent
      app: root.app
      size: 18
      color: root.app.onAccent
      running: root.app.player.status === "playing"
    }
  }

  Column {
    anchors.left: art.right
    anchors.leftMargin: 14
    anchors.right: trail.left
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    spacing: 3

    Text {
      width: parent.width
      text: root.station.name || ""
      color: root.playingThis ? root.app.ui.accent : root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md + 1
      font.weight: Font.DemiBold
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      text: root.playingThis && root.app.player.song ? root.app.player.song
        : root.detail || Api.subtitle(root.station) || Api.quality(root.station)
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      elide: Text.ElideRight
    }
  }

  Row {
    id: trail
    anchors.right: parent.right
    anchors.rightMargin: 2
    anchors.verticalCenter: parent.verticalCenter
    spacing: 0

    Text {
      visible: !root.app.compact && root.station.bitrate > 0
      anchors.verticalCenter: parent.verticalCenter
      rightPadding: 8
      text: root.station.bitrate + " kbps"
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
      font.features: ({ "tnum": 1 })
    }
    IconButton {
      app: root.app
      glyph: root.favorite ? G.star : G.starOutline
      color: root.favorite ? root.app.ui.star : root.app.ui.muted
      label: root.favorite ? "Remove from favourites" : "Add to favourites"
      size: 20
      onClicked: root.app.toggleFavorite(root.station)
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    anchors.rightMargin: trail.width
    hoverEnabled: !root.app.compact
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }
}
