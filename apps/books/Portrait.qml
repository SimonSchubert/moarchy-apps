import QtQuick
import "kit"
import "OpenLibrary.js" as OL

// An author's photo, in a box drawn with the theme's line, as Video Library
// draws a channel's face. Until it arrives, or when Open Library has none,
// their initials.
Rectangle {
  id: root
  property var app
  property string name: ""
  property string source: ""
  readonly property bool ready: img.status === Image.Ready

  radius: app.ui.radius
  color: app.ui.surfaceHigh
  border.width: 1
  border.color: app.ui.line
  clip: true

  Text {
    anchors.centerIn: parent
    visible: !root.ready
    text: OL.initials(root.name)
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: Math.round(root.width * 0.34)
    font.weight: Font.Bold
  }

  Image {
    id: img
    anchors.fill: parent
    anchors.margins: 1
    source: root.source
    fillMode: Image.PreserveAspectCrop
    // A portrait's face is in its top half.
    verticalAlignment: Image.AlignTop
    asynchronous: true
    cache: true
    sourceSize.width: Math.max(96, root.width * 2)
    opacity: root.ready ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 200 } }
  }
}
