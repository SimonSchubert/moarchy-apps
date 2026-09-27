import QtQuick

// The flag mode, latched. Lit, a tap flags and a hold opens; unlit, the other
// way round. Latching is what makes the common run of twenty flags twenty
// taps with no aiming at all.
Rectangle {
  id: root
  property var app

  readonly property bool on: app.marking
  implicitWidth: row.implicitWidth + 32
  implicitHeight: app.ui.target + 4
  radius: height / 2
  opacity: app.over ? 0.45 : 1
  color: on ? app.ui.flag : mouse.pressed ? app.ui.pressed : mouse.containsMouse ? app.ui.hover : app.ui.surface
  border.width: on ? 0 : 1
  border.color: app.ui.border
  Accessible.role: Accessible.CheckBox
  Accessible.name: "Flag"
  Accessible.checked: on

  Row {
    id: row
    anchors.centerIn: parent
    spacing: 8
    // A small flag, drawn as the board draws one.
    Item {
      width: 16
      height: 18
      anchors.verticalCenter: parent.verticalCenter
      Rectangle { x: 4; y: 1; width: 2; height: 15; color: root.on ? root.app.ui.inkOnFlag : root.app.ui.text }
      Rectangle { x: 0; y: 15; width: 11; height: 2; color: root.on ? root.app.ui.inkOnFlag : root.app.ui.text }
      Canvas {
        x: 6
        y: 1
        width: 9
        height: 8
        property color ink: root.on ? root.app.ui.inkOnFlag : root.app.ui.flag
        onInkChanged: requestPaint()
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          ctx.fillStyle = ink
          ctx.beginPath()
          ctx.moveTo(0, 0)
          ctx.lineTo(width, height / 2)
          ctx.lineTo(0, height)
          ctx.closePath()
          ctx.fill()
        }
      }
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.on ? "Flagging" : "Flag"
      color: root.on ? root.app.ui.inkOnFlag : root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      font.weight: Font.DemiBold
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: !root.app.over
    hoverEnabled: !root.app.compact
    cursorShape: Qt.PointingHandCursor
    onClicked: root.app.marking = !root.app.marking
  }
}
