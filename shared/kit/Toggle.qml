import QtQuick

// A switch with its label, the whole row pressable.
Item {
  id: root
  property var app
  property string text: ""
  property string note: ""
  property bool checked: false
  signal toggled(bool checked)

  implicitWidth: 320
  implicitHeight: Math.max(app.ui.target, labels.implicitHeight + 8)
  Accessible.role: Accessible.CheckBox
  Accessible.name: text
  Accessible.checked: checked

  Column {
    id: labels
    anchors.left: parent.left
    anchors.right: track.left
    anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2
    Text {
      width: parent.width
      text: root.text
      wrapMode: Text.Wrap
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md
    }
    Text {
      visible: root.note !== ""
      width: parent.width
      text: root.note
      wrapMode: Text.Wrap
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
    }
  }

  Rectangle {
    id: track
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: 44
    height: 24
    radius: 12
    color: root.checked ? root.app.ui.accent : root.app.ui.well
    border.width: root.checked ? 0 : 1
    border.color: root.app.ui.border
    Rectangle {
      width: 18
      height: 18
      radius: 9
      y: 3
      x: root.checked ? parent.width - width - 3 : 3
      color: root.checked ? root.app.ui.inkOnAccent : root.app.ui.muted
      Behavior on x { NumberAnimation { duration: 120 } }
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.toggled(!root.checked)
  }
}
