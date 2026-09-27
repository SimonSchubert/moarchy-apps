import QtQuick
import "Glyphs.js" as KG

// One row of a list: a leading glyph, a title with a line under it, and a
// trailing word or chevron. Selected is the desktop's "shown in the pane
// beside"; a phone has no such thing and never sets it.
Rectangle {
  id: root
  property var app
  property string glyph: ""
  property color glyphColor: app.ui.muted
  property string title: ""
  property string text: ""
  property string trailing: ""
  property color trailingColor: app.ui.muted
  property bool chevron: false
  property bool selected: false
  // Anything placed inside goes at the right, before the trailing word.
  default property alias extra: slot.data
  signal clicked()
  signal pressAndHold()

  implicitWidth: 320
  implicitHeight: Math.max(app.compact ? 56 : 48, labels.implicitHeight + 16)
  radius: app.ui.radius
  color: selected ? app.ui.selected : mouse.pressed ? app.ui.pressed : mouse.containsMouse ? app.ui.hover : "transparent"
  Accessible.role: Accessible.ListItem
  Accessible.name: title

  Icon {
    id: lead
    visible: root.glyph !== ""
    x: 8
    anchors.verticalCenter: parent.verticalCenter
    app: root.app
    text: root.glyph
    size: 20
    color: root.glyphColor
  }
  Column {
    id: labels
    anchors.left: lead.visible ? lead.right : parent.left
    anchors.leftMargin: lead.visible ? 8 : 12
    anchors.right: tail.left
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2
    Text {
      width: parent.width
      text: root.title
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md
      font.weight: root.selected ? Font.DemiBold : Font.Normal
      elide: Text.ElideRight
    }
    Text {
      visible: root.text !== ""
      width: parent.width
      text: root.text
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      elide: Text.ElideRight
    }
  }
  Row {
    id: tail
    anchors.right: parent.right
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    spacing: 6
    Row { id: slot; anchors.verticalCenter: parent.verticalCenter; spacing: 4 }
    Text {
      visible: root.trailing !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: root.trailing
      color: root.trailingColor
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      font.features: ({ "tnum": 1 })
    }
    Icon {
      visible: root.chevron
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      text: KG.chevronRight
      size: 18
      color: root.app.ui.muted
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: !root.app.compact
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
    onPressAndHold: root.pressAndHold()
  }
}
