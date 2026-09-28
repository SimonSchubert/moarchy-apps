import QtQuick
import "Launches.js" as L

// The status as a disc: a wash of its colour under the theme's own text, and
// a short mark in it. Not a solid hue with light text on it, which is
// unreadable on a yellow Hold in a light theme -- and colour is never the
// only signal, because roughly one man in twelve cannot tell this green from
// this red.
Rectangle {
  id: root
  property var app
  property var item: null
  property int size: 36

  readonly property color hue: app.ui.role(L.hue(item))

  width: size
  height: size
  radius: size / 2
  color: Qt.tint(app.ui.bg, Qt.rgba(hue.r, hue.g, hue.b, app.ui.dark ? 0.32 : 0.26))
  border.width: 1
  border.color: Qt.rgba(hue.r, hue.g, hue.b, 0.5)
  Accessible.name: item ? item.status : ""

  Text {
    anchors.centerIn: parent
    text: L.disc(root.item)
    color: root.app.ui.text
    font.family: root.app.ui.font
    font.pixelSize: Math.round(root.size * 0.3)
    font.weight: Font.Bold
    font.features: ({ "tnum": 1 })
  }
}
