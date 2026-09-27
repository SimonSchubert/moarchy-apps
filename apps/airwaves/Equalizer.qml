import QtQuick

// Three bars that bounce while a station plays, and lie still while it
// connects or is stopped. They move only while somebody can see them: the
// animation is bound to the window being up.
Row {
  id: root
  property var app
  property bool running: false
  property color color: app.ui.accent
  property int size: 16

  width: size
  height: size
  spacing: Math.max(1, Math.round(size / 8))

  Repeater {
    model: [{ d: 420, lo: 0.3, hi: 1.0 }, { d: 560, lo: 0.2, hi: 0.8 }, { d: 360, lo: 0.4, hi: 0.95 }]
    delegate: Rectangle {
      id: bar
      required property var modelData
      property real level: modelData.lo + 0.2
      anchors.bottom: parent.bottom
      width: (root.size - root.spacing * 2) / 3
      height: Math.max(2, root.size * level)
      radius: width / 2
      color: root.color

      SequentialAnimation on level {
        running: root.running && root.visible && root.app.opened
        loops: Animation.Infinite
        NumberAnimation { to: bar.modelData.hi; duration: bar.modelData.d; easing.type: Easing.InOutSine }
        NumberAnimation { to: bar.modelData.lo; duration: bar.modelData.d; easing.type: Easing.InOutSine }
      }
    }
  }
}
