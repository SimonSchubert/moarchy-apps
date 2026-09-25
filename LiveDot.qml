import QtQuick

// This is live data: a small green dot in a soft ring. Shown only where the
// feed really sends realtime updates. Still, not pulsing: an animation on
// every card would keep the phone redrawing the whole list.
Item {
  id: root
  property var app
  property int size: 8
  width: size + 6
  height: size + 6
  Accessible.role: Accessible.StaticText
  Accessible.name: "Live"

  Rectangle {
    anchors.centerIn: parent
    width: root.size + 6
    height: width
    radius: width / 2
    color: root.app.ui.okSoft
  }
  Rectangle {
    anchors.centerIn: parent
    width: root.size
    height: root.size
    radius: width / 2
    color: root.app.ui.ok
  }
}
