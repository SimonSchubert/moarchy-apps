import QtQuick
import "Api.mjs" as Api

// A kept stop or trip: tap to use it, move it up, or let it go.
Item {
  id: root
  property var app
  property string glyph: ""
  property color glyphColor: app.ui.muted
  property string title: ""
  property string subtitle: ""
  property bool divider: false
  property bool canMoveUp: false
  signal clicked()
  signal removed()
  signal movedUp()

  implicitHeight: 60

  Rectangle {
    visible: root.divider
    x: 60
    width: parent.width - 60
    height: 1
    color: root.app.ui.divider
  }
  Rectangle {
    anchors.fill: parent
    radius: root.app.ui.radius
    color: mouse.pressed ? root.app.ui.pressed : mouse.containsMouse ? root.app.ui.hover : "transparent"
  }
  Rectangle {
    x: 14
    anchors.verticalCenter: parent.verticalCenter
    width: 34
    height: 34
    radius: 10
    color: root.app.alpha(root.glyphColor, 0.14)
    Icon { anchors.centerIn: parent; app: root.app; text: root.glyph; size: 17; color: root.glyphColor }
  }
  Column {
    x: 60
    width: parent.width - 60 - actions.width - 8
    anchors.verticalCenter: parent.verticalCenter
    spacing: 1
    Text {
      width: parent.width
      text: root.title
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md
      font.weight: Font.DemiBold
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      visible: text !== ""
      text: root.subtitle
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
      elide: Text.ElideRight
    }
  }
  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: !root.app.compact
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
  Row {
    id: actions
    anchors.right: parent.right
    anchors.rightMargin: 4
    anchors.verticalCenter: parent.verticalCenter
    IconButton {
      visible: root.canMoveUp
      app: root.app
      glyph: Api.GLYPH.chevronUp
      size: 18
      color: root.app.ui.muted
      label: "Move up"
      onClicked: root.movedUp()
    }
    IconButton {
      app: root.app
      glyph: Api.GLYPH.trash
      size: 18
      color: root.app.ui.muted
      label: "Remove"
      onClicked: root.removed()
    }
  }
}
