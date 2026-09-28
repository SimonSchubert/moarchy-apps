import QtQuick

// A horizontal bar: a track and how much of it is used. `extra` is a second,
// fainter stretch after the first -- the page cache after used memory, which
// is taken but would be given back.
Rectangle {
  id: root
  property var app
  property real value: 0
  property real extra: 0
  property color fill: app.ui.accent
  property color extraColor: app.alpha(fill, 0.35)

  implicitHeight: 10
  radius: root.app.ui.round(height)
  color: app.ui.well
  clip: true

  Rectangle {
    x: 0
    height: parent.height
    width: Math.min(parent.width, parent.width * Math.max(0, Math.min(1, root.value + root.extra)))
    radius: root.app.ui.round(height)
    color: root.extraColor
    visible: root.extra > 0
  }
  Rectangle {
    height: parent.height
    width: root.value > 0 ? Math.max(parent.height, parent.width * Math.max(0, Math.min(1, root.value))) : 0
    radius: root.app.ui.round(height)
    color: root.fill
  }
}
