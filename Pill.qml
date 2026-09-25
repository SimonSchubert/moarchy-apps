import QtQuick

// A small fact about a journey: its day, length, changes, or that it is live.
Rectangle {
  id: root
  property var app
  property string text: ""
  property bool live: false

  visible: text !== ""
  implicitHeight: 26
  implicitWidth: row.implicitWidth + 18
  radius: 13
  color: live ? app.ui.okSoft : app.ui.surfaceHigh

  Row {
    id: row
    anchors.centerIn: parent
    spacing: 4
    LiveDot {
      visible: root.live
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      size: 7
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.text
      color: root.live ? root.app.ui.ok : root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
      font.weight: Font.DemiBold
    }
  }
}
