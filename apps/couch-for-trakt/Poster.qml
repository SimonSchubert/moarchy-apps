import QtQuick
import "Glyphs.js" as G

// A picture from Trakt, from the disk cache, with rounded corners -- or,
// until it arrives (and when there is none), a card in the poster's own
// colour with the title on it.
//
// Corners are cut by a frame in the colour of whatever the picture sits on
// (`ground`), not by a mask: a mask is a texture per poster, and a grid has
// dozens of them. A frame is one more rectangle in the same batch.
Item {
  id: root
  property var app
  property string source: ""
  property string title: ""
  property string tint: ""
  property string glyph: G.movie
  property int radius: app.ui.radius
  property color ground: app.ui.bg
  property bool fade: true
  property bool showTitle: true
  readonly property bool ready: img.status === Image.Ready
  // The corner frame reaches past the edges; unclipped, it would paint over
  // whatever sits right beside -- the next slide of a carousel.
  clip: radius > 0

  Rectangle {
    anchors.fill: parent
    visible: !root.ready || img.opacity < 1
    color: root.tint ? Qt.tint(root.app.ui.surfaceHigh, root.app.alpha(root.tint, 0.55)) : root.app.ui.surfaceHigh

    Column {
      anchors.centerIn: parent
      width: parent.width - 16
      spacing: 6
      visible: root.showTitle && root.height > 60
      Icon {
        anchors.horizontalCenter: parent.horizontalCenter
        app: root.app
        text: root.glyph
        size: Math.min(28, root.width / 4)
        color: root.app.alpha(root.app.ui.text, 0.35)
      }
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        visible: root.title !== "" && root.height > 90
        text: root.title
        color: root.app.alpha(root.app.ui.text, 0.6)
        font.family: root.app.ui.font
        font.pixelSize: Math.max(10, Math.min(14, root.width / 9))
        font.weight: Font.DemiBold
        wrapMode: Text.Wrap
        maximumLineCount: 3
        elide: Text.ElideRight
      }
    }
  }

  Image {
    id: img
    anchors.fill: parent
    // The revision is passed only to be read: the binding runs again as a
    // picture arrives.
    source: root.source && root.app.images ? root.app.images.source(root.source, root.app.images.revision) : ""
    asynchronous: true
    cache: true
    smooth: true
    mipmap: false
    fillMode: Image.PreserveAspectCrop
    // A crop paints past the item's edges unless it is clipped.
    clip: root.radius === 0
    // Decoded at the size it is drawn, not the file's: a 300 px poster
    // shown at 120 px costs a sixth of the memory.
    sourceSize.width: Math.ceil(root.width * 1.5)
    opacity: root.fade ? 0 : 1
    states: State {
      when: img.status === Image.Ready
      PropertyChanges { img.opacity: 1 }
    }
    transitions: Transition {
      enabled: root.fade
      NumberAnimation { property: "opacity"; duration: 180; easing.type: Easing.OutCubic }
    }
    onStatusChanged: if (status === Image.Error && String(source).indexOf("file:") === 0 && root.app.images)
      root.app.images.invalidate(root.source)
  }

  // Corner cutter: a frame whose inner edge is the rounded outline.
  Rectangle {
    visible: root.radius > 0
    x: -root.radius
    y: -root.radius
    width: parent.width + root.radius * 2
    height: parent.height + root.radius * 2
    radius: root.radius * 2
    color: "transparent"
    border.width: root.radius
    border.color: root.ground
  }
}
