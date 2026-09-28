import QtQuick
import "kit"
import "Glyphs.js" as G

// One answer. Before the pick it is a box with its letter; after it, the
// right answer is marked with a tick and the wrong pick with a cross, as well
// as in green and red -- the colour is not the only thing saying which.
Rectangle {
  id: root
  property var app
  property string letter: "A"
  property string text: ""
  // "open" before the pick; then "right", "wrong" (the one picked), or "other".
  property string mark: "open"
  readonly property bool open: mark === "open"
  readonly property color tint: mark === "right" ? app.ui.good : mark === "wrong" ? app.ui.bad : app.ui.accent
  signal clicked()

  implicitHeight: Math.max(app.compact ? 54 : 56, label.implicitHeight + 28)
  radius: app.ui.radius
  color: mark === "right" || mark === "wrong" ? app.ui.alpha(tint, 0.14)
    : open && mouse.pressed ? Qt.tint(app.ui.surface, app.ui.pressed)
    : open && mouse.containsMouse ? Qt.tint(app.ui.surface, app.ui.hover) : app.ui.surface
  border.width: 1
  border.color: mark === "right" || mark === "wrong" ? tint : open && mouse.containsMouse ? app.ui.alpha(app.ui.accent, 0.6) : app.ui.line
  opacity: mark === "other" ? 0.5 : 1
  Behavior on color { ColorAnimation { duration: 140 } }
  Behavior on opacity { NumberAnimation { duration: 140 } }
  Accessible.role: Accessible.Button
  Accessible.name: text

  Rectangle {
    id: key
    x: 12
    anchors.verticalCenter: parent.verticalCenter
    width: 30
    height: 30
    radius: root.app.ui.radius
    color: root.open || root.mark === "other" ? root.app.ui.well : root.tint
    Text {
      anchors.centerIn: parent
      visible: root.open || root.mark === "other"
      text: root.letter
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      font.weight: Font.Bold
    }
    Icon {
      anchors.centerIn: parent
      visible: !root.open && root.mark !== "other"
      app: root.app
      text: root.mark === "right" ? G.right : G.wrong
      size: 18
      color: root.app.ui.bg
    }
  }

  Text {
    id: label
    anchors.left: key.right
    anchors.leftMargin: 14
    anchors.right: parent.right
    anchors.rightMargin: 14
    anchors.verticalCenter: parent.verticalCenter
    wrapMode: Text.Wrap
    text: root.text
    color: root.app.ui.text
    font.family: root.app.ui.font
    font.pixelSize: root.app.compact ? root.app.ui.fs.lg : root.app.ui.fs.lg + 1
    font.weight: root.mark === "right" ? Font.Bold : Font.Normal
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.open
    hoverEnabled: !root.app.compact
    cursorShape: root.open ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.clicked()
  }
}
