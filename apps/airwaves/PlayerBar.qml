import QtQuick
import "Api.mjs" as Api
import "Glyphs.js" as G

// On the desktop: the station on air along the foot of the window -- what
// it is and what it plays on the left, the controls in the middle, volume on
// the right. The left half opens Now Playing.
Rectangle {
  id: root
  property var app
  readonly property var player: app.player
  readonly property var station: player.station || ({})
  readonly property bool favorite: { app.store.prefs; return app.store.isFavorite(station.id) }

  implicitHeight: 80
  color: root.app.ui.surface

  Rectangle { width: parent.width; height: 1; color: root.app.ui.divider }

  // Where it is: left.
  Item {
    id: left
    x: 16
    width: Math.min(parent.width * 0.36, parent.width / 2 - controls.width / 2 - 24)
    height: parent.height

    Art {
      id: art
      anchors.verticalCenter: parent.verticalCenter
      width: 54
      height: 54
      radius: 10
      app: root.app
      station: root.station
    }
    Column {
      anchors.left: art.right
      anchors.leftMargin: 14
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: 3
      Text {
        width: parent.width
        text: root.station.name || ""
        color: root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.md + 1
        font.weight: Font.DemiBold
        elide: Text.ElideRight
      }
      Row {
        width: parent.width
        spacing: 6
        Equalizer {
          anchors.verticalCenter: parent.verticalCenter
          visible: root.player.status === "playing"
          app: root.app
          size: 12
          running: true
        }
        Text {
          width: parent.width - 18
          text: root.player.failure ? root.player.failure
            : root.player.status === "connecting" ? "Connecting…"
            : root.player.status === "buffering" ? "Buffering…"
            : root.player.song || (root.player.active ? Api.place(root.station) || "Live" : Api.subtitle(root.station))
          color: root.player.failure ? root.app.ui.down : root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
          elide: Text.ElideRight
        }
      }
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.app.openPlayer()
    }
  }

  // The controls: middle.
  Row {
    id: controls
    anchors.centerIn: parent
    spacing: 14
    IconButton {
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      glyph: root.favorite ? G.star : G.starOutline
      color: root.favorite ? root.app.ui.star : root.app.ui.muted
      label: root.favorite ? "Remove from favourites" : "Add to favourites"
      onClicked: root.app.toggleFavorite(root.station)
    }
    Item {
      anchors.verticalCenter: parent.verticalCenter
      width: 52
      height: 52
      Rectangle {
        anchors.centerIn: parent
        width: 46
        height: 46
        radius: 23
        color: playMouse.pressed ? Qt.darker(root.app.ui.accent, 1.15) : root.app.ui.accent
        scale: playMouse.containsMouse ? 1.05 : 1
        Behavior on scale { NumberAnimation { duration: 90 } }
      }
      Spinner {
        anchors.centerIn: parent
        app: root.app
        size: 52
        running: root.player.status === "connecting" || root.player.status === "buffering"
      }
      Icon {
        anchors.centerIn: parent
        app: root.app
        text: root.player.active ? G.stop : G.play
        size: 24
        color: root.app.onAccent
      }
      MouseArea {
        id: playMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.player.toggle()
      }
      Accessible.role: Accessible.Button
      Accessible.name: root.player.active ? "Stop" : "Play"
    }
    IconButton {
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      glyph: G.sleep
      active: root.player.sleepAt > 0
      label: "Sleep timer"
      onClicked: root.app.openPlayer()
    }
  }

  // Volume: right.
  Row {
    anchors.right: parent.right
    anchors.rightMargin: 16
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2
    visible: root.width >= 760
    IconButton {
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      glyph: root.player.muted || root.player.volume === 0 ? G.volumeOff
        : root.player.volume < 34 ? G.volumeLow : root.player.volume < 67 ? G.volumeMedium : G.volumeHigh
      label: root.player.muted ? "Unmute" : "Mute"
      size: 19
      color: root.app.ui.muted
      onClicked: root.player.setMuted(!root.player.muted)
    }
    Slider {
      anchors.verticalCenter: parent.verticalCenter
      width: 130
      app: root.app
      value: root.player.muted ? 0 : root.player.volume
      onMoved: function (v) { root.player.setVolume(v) }
    }
  }
}
