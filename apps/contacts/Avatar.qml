import QtQuick
import "Contacts.js" as Contacts

// A person's initial in a disc, tinted with one of the theme's hues. The hue
// follows the name, so the same person is the same colour every time and a
// list of forty is not forty identical circles.
Rectangle {
  id: root
  property var app
  property var contact: null
  property int size: 40

  readonly property color hue: app.ui.personHue(contact ? Contacts.sortKey(contact) : "")

  width: size
  height: size
  // A square tile, as Omarchy draws an app's icon.
  radius: app.ui.radius
  color: app.alpha(hue, 0.18)

  Text {
    anchors.centerIn: parent
    text: root.contact ? Contacts.monogram(root.contact) : ""
    color: root.hue
    font.family: root.app.ui.font
    font.pixelSize: Math.round(root.size * 0.42)
    font.weight: Font.Bold
  }
}
