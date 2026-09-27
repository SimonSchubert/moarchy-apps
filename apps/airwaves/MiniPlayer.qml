import QtQuick
import "Api.mjs" as Api
import "Glyphs.js" as G

// On a phone: the station on air as a card above the tabs. A tap opens Now
// Playing; the button plays or stops without leaving the list.
Item {
  id: root
  property var app
  readonly property var player: app.player
  readonly property var station: player.station || ({})

  implicitHeight: 72

  Rectangle {
    id: card
    anchors.fill: parent
    anchors.leftMargin: 8
    anchors.rightMargin: 8
    anchors.bottomMargin: 6
    radius: root.app.ui.radius + 6
    color: Qt.tint(root.app.ui.surfaceHigh, Qt.hsla((root.station.hue || 0) / 360, 0.5, 0.5, root.app.ui.dark ? 0.14 : 0.1))
    border.width: 1
    border.color: root.app.ui.divider

    Art {
      id: art
      x: 8
      anchors.verticalCenter: parent.verticalCenter
      width: 46
      height: 46
      radius: 10
      app: root.app
      station: root.station
    }

    Column {
      anchors.left: art.right
      anchors.leftMargin: 12
      anchors.right: buttons.left
      anchors.rightMargin: 4
      anchors.verticalCenter: parent.verticalCenter
      spacing: 2
      Text {
        width: parent.width
        text: root.station.name || ""
        color: root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.md
        font.weight: Font.DemiBold
        elide: Text.ElideRight
      }
      Row {
        width: parent.width
        spacing: 5
        Equalizer {
          anchors.verticalCenter: parent.verticalCenter
          visible: root.player.status === "playing"
          app: root.app
          size: 11
          running: true
        }
        Text {
          width: parent.width - 16
          text: root.player.failure ? root.player.failure
            : root.player.status === "connecting" ? "Connecting…"
            : root.player.status === "buffering" ? "Buffering…"
            : root.player.song || (root.player.active ? "Live" : "Tap play to listen")
          color: root.player.failure ? root.app.ui.down : root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
          elide: Text.ElideRight
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      anchors.rightMargin: buttons.width
      onClicked: root.app.openPlayer()
    }

    Row {
      id: buttons
      anchors.right: parent.right
      anchors.rightMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      Item {
        width: 48
        height: 48
        Rectangle {
          anchors.centerIn: parent
          width: 42
          height: 42
          radius: 21
          color: playMouse.pressed ? Qt.darker(root.app.ui.accent, 1.15) : root.app.ui.accent
        }
        Spinner {
          anchors.centerIn: parent
          app: root.app
          size: 48
          running: root.player.status === "connecting" || root.player.status === "buffering"
        }
        Icon {
          anchors.centerIn: parent
          app: root.app
          text: root.player.active ? G.stop : G.play
          size: 22
          color: root.app.onAccent
        }
        MouseArea {
          id: playMouse
          anchors.fill: parent
          onClicked: root.player.toggle()
        }
        Accessible.role: Accessible.Button
        Accessible.name: root.player.active ? "Stop" : "Play"
      }
    }
  }
}
