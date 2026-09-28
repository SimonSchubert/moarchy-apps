import QtQuick
import "Launches.js" as L

// The status as a tag, drawn as the kit's Badge is -- a square box with its
// word in small capitals -- but with a wash of the status colour under the
// theme's own text rather than coloured text: a yellow Hold in coloured type
// is unreadable in a light theme. Colour is never the only signal either,
// because roughly one man in twelve cannot tell this green from this red.
Rectangle {
  id: root
  property var app
  property var item: null
  // The tag's width; its height follows. 36 in a row, 48 on the detail page.
  property int size: 36

  readonly property color hue: app.ui.role(L.hue(item))

  width: Math.max(size + 4, label.implicitWidth + 12)
  height: Math.round(size * 0.62)
  radius: app.ui.radius > 0 ? 3 : 0
  color: Qt.tint(app.ui.bg, Qt.rgba(hue.r, hue.g, hue.b, app.ui.dark ? 0.32 : 0.26))
  border.width: 1
  border.color: Qt.rgba(hue.r, hue.g, hue.b, 0.6)
  Accessible.name: item ? item.status : ""

  Text {
    id: label
    anchors.centerIn: parent
    text: L.disc(root.item)
    color: root.app.ui.text
    font.family: root.app.ui.font
    font.pixelSize: Math.max(10, Math.round(root.size * 0.28))
    font.weight: Font.Bold
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 0.8
    font.features: ({ "tnum": 1 })
  }
}
