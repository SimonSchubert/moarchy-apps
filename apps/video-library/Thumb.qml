import QtQuick
import "kit"

// A picture from the CDN, in a box drawn with the theme's line: a thumbnail,
// a channel's face, a banner. Until it arrives -- or when there is none, or
// no network -- the box holds a glyph, so a grid on a slow connection is a
// grid of boxes rather than a grid of holes.
Rectangle {
  id: root
  property var app
  property string source: ""
  property string glyph: ""
  property int glyphSize: 26
  readonly property bool ready: img.status === Image.Ready

  radius: app.ui.radius
  color: app.ui.well
  border.width: 1
  border.color: app.ui.line
  clip: true

  Icon {
    anchors.centerIn: parent
    visible: !root.ready && root.glyph !== ""
    app: root.app
    text: root.glyph
    size: root.glyphSize
    color: root.app.ui.alpha(root.app.ui.muted, 0.6)
  }

  Image {
    id: img
    anchors.fill: parent
    anchors.margins: 1
    source: root.source
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: true
    opacity: root.ready ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 180 } }
  }
}
