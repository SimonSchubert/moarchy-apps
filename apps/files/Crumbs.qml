import QtQuick

// Where we are, as one tap per level. The interesting end is the right one, so
// the strip sits there whenever the path changes length.
Rectangle {
  id: root
  property var app
  property var crumbs: []
  signal go(string path)

  implicitHeight: app.compact ? 38 : 34
  radius: height / 2
  color: app.ui.surface
  border.width: 1
  border.color: app.ui.divider

  Flickable {
    id: flick
    anchors.fill: parent
    anchors.leftMargin: 6
    anchors.rightMargin: 6
    clip: true
    contentWidth: row.width
    contentHeight: height
    flickableDirection: Flickable.HorizontalFlick
    boundsBehavior: Flickable.StopAtBounds
    onContentWidthChanged: contentX = Math.max(0, contentWidth - width)

    Row {
      id: row
      height: flick.height
      Repeater {
        model: root.crumbs
        delegate: Row {
          id: crumb
          required property var modelData
          required property int index
          readonly property bool last: index === root.crumbs.length - 1
          height: row.height
          Text {
            visible: crumb.index > 0
            anchors.verticalCenter: parent.verticalCenter
            text: "›"
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
          }
          Rectangle {
            height: row.height - 8
            anchors.verticalCenter: parent.verticalCenter
            width: label.implicitWidth + 16
            radius: height / 2
            color: crumbMouse.pressed ? root.app.ui.pressed : crumbMouse.containsMouse && !crumb.last ? root.app.ui.hover : "transparent"
            Text {
              id: label
              anchors.centerIn: parent
              text: crumb.modelData.label
              // The last crumb is where we are, so it is the one that is not
              // a link anywhere.
              color: crumb.last ? root.app.ui.text : root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.sm
              font.weight: crumb.last ? Font.DemiBold : Font.Normal
            }
            MouseArea {
              id: crumbMouse
              anchors.fill: parent
              hoverEnabled: !root.app.compact
              cursorShape: Qt.PointingHandCursor
              onClicked: root.go(crumb.modelData.path)
            }
          }
        }
      }
    }
  }
}
