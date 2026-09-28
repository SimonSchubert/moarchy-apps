import QtQuick
import "Api.mjs" as Api

// A station's picture: its logo on a light card when it has one worth
// showing, and until then -- or when it has none -- a tile in the station's
// own colour with its initials. Most logos in the directory are favicons, so
// one smaller than a thumbnail counts as none: a 16-pixel icon blown up to a
// tile is worse than the letters.
//
// The logo is inset on its card, so the rounded corners need no mask: the
// card is a Rectangle with a radius, and nothing is drawn over its edge.
Item {
  id: root
  property var app
  property var station: null
  property int radius: Math.round(width * 0.18)
  // Initials are drawn at this share of the tile.
  property real letterScale: 0.36

  readonly property string name: station ? station.name || "" : ""
  readonly property real hue: station && station.hue !== undefined ? station.hue : Api.hue(name)
  readonly property bool ready: img.status === Image.Ready && (img.implicitWidth >= 40 || img.implicitHeight >= 40)

  // The tile: two tones of the station's hue, lighter at the top.
  Rectangle {
    anchors.fill: parent
    radius: root.radius
    visible: !root.ready || img.opacity < 1
    gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.hsla(root.hue / 360, 0.62, root.app.ui.dark ? 0.46 : 0.58, 1) }
      GradientStop { position: 1.0; color: Qt.hsla(((root.hue + 28) % 360) / 360, 0.7, root.app.ui.dark ? 0.3 : 0.4, 1) }
    }
    Text {
      anchors.centerIn: parent
      text: Api.initials(root.name)
      color: Qt.rgba(1, 1, 1, 0.92)
      font.family: root.app.ui.font
      font.pixelSize: Math.max(10, Math.round(root.height * root.letterScale))
      font.weight: Font.Bold
      font.letterSpacing: -0.5
    }
  }

  Rectangle {
    anchors.fill: parent
    radius: root.radius
    color: root.app.ui.logoCard
    opacity: img.opacity
    visible: root.ready
    border.width: root.app.ui.dark ? 0 : 1
    border.color: Qt.rgba(0, 0, 0, 0.06)
  }

  Image {
    id: img
    anchors.fill: parent
    anchors.margins: Math.round(Math.min(root.width, root.height) * 0.12)
    visible: root.ready
    source: {
      if (!root.station || !root.station.favicon || !root.app.images) return ""
      root.app.images.revision
      return root.app.images.source(root.station.favicon)
    }
    asynchronous: true
    cache: true
    smooth: true
    mipmap: true
    fillMode: Image.PreserveAspectFit
    // Decoded near the size it is drawn; a small favicon stays its own size,
    // which is how `ready` can tell it is too small.
    sourceSize.width: Math.min(512, Math.ceil(root.width * 2))
    sourceSize.height: Math.min(512, Math.ceil(root.height * 2))
    opacity: 0
    states: State {
      when: root.ready
      PropertyChanges { img.opacity: 1 }
    }
    // Offline, for the shots, a logo is simply there: a fade caught at a
    // different frame in two runs is two different pictures.
    transitions: Transition {
      enabled: !root.app.offline
      NumberAnimation { property: "opacity"; duration: 180; easing.type: Easing.OutCubic }
    }
    onStatusChanged: if (status === Image.Error && String(source).indexOf("file:") === 0 && root.app.images)
      root.app.images.invalidate(root.station.favicon)
  }
}
