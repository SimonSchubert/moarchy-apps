import QtQuick

// A heading over a group, as Omarchy writes one: "# Title" in bold, and what
// is in it in muted type after -- "# Catalog (32 items)".
Row {
  id: root
  property var app
  property string text: ""
  property string note: ""
  spacing: 8
  height: 28

  Text {
    anchors.verticalCenter: parent.verticalCenter
    text: "# " + root.text
    color: root.app.ui.text
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.md
    font.weight: Font.Bold
  }
  Text {
    anchors.verticalCenter: parent.verticalCenter
    visible: root.note !== ""
    text: "(" + root.note + ")"
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.sm
  }
}
