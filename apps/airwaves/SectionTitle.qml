import QtQuick
import "Glyphs.js" as G

// A heading over a part of a screen, with a quieter line under it and an
// optional link at the right.
Item {
  id: root
  property var app
  property string title: ""
  property string note: ""
  property string action: ""
  property int pad: 16
  signal triggered()

  implicitHeight: col.implicitHeight

  Column {
    id: col
    x: root.pad
    width: parent.width - root.pad * 2 - (link.visible ? link.width + 8 : 0)
    spacing: 2
    Text {
      width: parent.width
      text: root.title
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.lg + 1
      font.weight: Font.Bold
      elide: Text.ElideRight
    }
    Text {
      visible: text !== ""
      width: parent.width
      text: root.note
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs + 1
      elide: Text.ElideRight
    }
  }

  Rectangle {
    id: link
    visible: root.action !== ""
    anchors.right: parent.right
    anchors.rightMargin: root.pad - 8
    anchors.top: parent.top
    anchors.topMargin: -4
    width: linkRow.implicitWidth + 16
    height: 30
    radius: 15
    color: linkMouse.pressed ? root.app.ui.pressed : linkMouse.containsMouse ? root.app.ui.hover : "transparent"
    Row {
      id: linkRow
      anchors.centerIn: parent
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.action
        color: root.app.ui.accent
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.sm
        font.weight: Font.DemiBold
      }
      Icon {
        anchors.verticalCenter: parent.verticalCenter
        app: root.app
        text: G.chevronRight
        size: 16
        width: 18
        color: root.app.ui.accent
      }
    }
    MouseArea {
      id: linkMouse
      anchors.fill: parent
      hoverEnabled: !root.app.compact
      cursorShape: Qt.PointingHandCursor
      onClicked: root.triggered()
    }
  }
}
