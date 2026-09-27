import QtQuick
import "Api.mjs" as Api
import "Glyphs.js" as G

// A station as a square with its name under it, for a row that scrolls
// sideways. A tap plays it.
Item {
  id: root
  property var app
  property var station: ({})
  signal activated()

  readonly property bool playingThis: app.player.station !== null && app.player.station.id === station.id

  implicitWidth: app.compact ? 124 : 150
  implicitHeight: width + 50
  Accessible.role: Accessible.Button
  Accessible.name: station.name || ""

  Art {
    id: art
    width: root.width
    height: width
    app: root.app
    station: root.station
    radius: root.app.ui.radius + 6
    scale: mouse.pressed ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: 90 } }
  }

  // Hover: a play button rises over the art.
  Rectangle {
    anchors.right: art.right
    anchors.bottom: art.bottom
    anchors.margins: 8
    width: 38
    height: 38
    radius: 19
    color: root.app.ui.accent
    opacity: root.playingThis ? 1 : mouse.containsMouse ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 120 } }
    Icon {
      anchors.centerIn: parent
      visible: !root.playingThis || !root.app.player.active
      app: root.app
      text: G.play
      size: 20
      color: root.app.onAccent
    }
    Equalizer {
      anchors.centerIn: parent
      visible: root.playingThis && root.app.player.active
      app: root.app
      size: 16
      color: root.app.onAccent
      running: root.app.player.status === "playing"
    }
  }

  Column {
    anchors.top: art.bottom
    anchors.topMargin: 8
    width: parent.width
    spacing: 2
    Text {
      width: parent.width
      text: root.station.name || ""
      color: root.playingThis ? root.app.ui.accent : root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm + 1
      font.weight: Font.DemiBold
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      text: root.station.country || Api.quality(root.station)
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs + 1
      elide: Text.ElideRight
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: !root.app.compact
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }
}
