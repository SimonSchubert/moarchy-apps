import QtQuick

// One column title over a wide coin list.
Item {
  id: head
  property var app
  property string key: ""
  property string title: ""
  property bool alignRight: true
  property string sortKey: ""
  property bool descending: false
  property bool sortable: true
  signal picked(string key)

  height: parent ? parent.height : 34

  Text {
    anchors.verticalCenter: parent.verticalCenter
    anchors.right: head.alignRight ? parent.right : undefined
    anchors.left: head.alignRight ? undefined : parent.left
    text: head.title + (head.sortKey === head.key && head.key !== "" ? (head.descending ? " ↓" : " ↑") : "")
    color: head.sortKey === head.key ? head.app.ui.text : head.app.ui.muted
    font.family: head.app.ui.font
    font.pixelSize: head.app.ui.fs.xs
    font.weight: Font.DemiBold
  }
  MouseArea {
    anchors.fill: parent
    enabled: head.sortable && head.key !== ""
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: head.picked(head.key)
  }
}
