import QtQuick
import "kit"
import "Glyphs.js" as G
import "Countries.js" as C

// One country's flag, fitted into the box it is given and framed with the
// theme's line -- a white flag on a white page needs an edge to be a flag.
//
// From the copy on disk when there is one; from the CDN while the copy is
// being fetched; and, with neither, the country's two letters in the well,
// which is what a flag is for anyway.
Item {
  id: root
  property var app
  property string code: ""
  // Pixels the image is decoded at: the width it is drawn at, rounded up to
  // a step so a grid of flags shares a handful of sizes.
  property int decodeWidth: width > 160 ? 320 : 160

  readonly property bool local: code !== "" && !!app.flagHave[code]
  readonly property string url: code === "" ? ""
    : local ? "file://" + C.flagFile(app.flagDir, code)
    // Not until the folder has been read: a flag already on disk is not
    // worth a request.
    : app.offline || !app.flagsListed ? "" : C.flagUrl(code, 320)
  readonly property bool shown: image.status === Image.Ready

  Image {
    id: image
    anchors.centerIn: parent
    width: parent.width
    height: parent.height
    source: root.url
    fillMode: Image.PreserveAspectFit
    sourceSize.width: root.decodeWidth
    asynchronous: true
    smooth: true
    mipmap: true
    cache: true
  }

  // The frame, around what was painted rather than around the box.
  Rectangle {
    visible: root.shown
    anchors.centerIn: parent
    width: image.paintedWidth + 2
    height: image.paintedHeight + 2
    color: "transparent"
    border.width: 1
    border.color: root.app.ui.line
  }

  Rectangle {
    visible: !root.shown
    anchors.centerIn: parent
    width: Math.min(parent.width, parent.height * 1.5)
    height: width / 1.5
    color: root.app.ui.well
    border.width: 1
    border.color: root.app.ui.line
    Text {
      anchors.centerIn: parent
      text: image.status === Image.Loading ? "" : root.code
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: Math.max(10, Math.round(parent.height * 0.3))
      font.weight: Font.Bold
      font.letterSpacing: 2
    }
  }
}
