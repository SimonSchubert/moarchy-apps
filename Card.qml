import QtQuick

// A soft surface to group things on, pressable when it leads somewhere.
Rectangle {
  id: root
  property var app
  property bool pressable: false
  property alias pressed: mouse.pressed
  default property alias content: inner.data
  property int pad: 14
  signal clicked()

  radius: app.ui.radius + 4
  color: pressable && mouse.pressed ? app.ui.surfaceHigh : pressable && mouse.containsMouse ? Qt.tint(app.ui.surface, app.ui.hover) : app.ui.surface
  border.width: 1
  border.color: app.ui.divider
  // From the first child, the content's own column: childrenRect would count
  // a child centred on the card, which depends on this height in turn.
  implicitHeight: (inner.children.length ? inner.children[0].height : 0) + pad * 2

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.pressable
    hoverEnabled: root.pressable && !root.app.compact
    cursorShape: root.pressable ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.clicked()
  }

  Item {
    id: inner
    x: root.pad
    y: root.pad
    width: root.width - root.pad * 2
    height: root.height - root.pad * 2
  }
}
