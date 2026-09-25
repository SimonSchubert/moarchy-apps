import QtQuick
import "Api.mjs" as Api

// A notice from the operator: its headline, and the whole text on a tap.
Rectangle {
  id: root
  property var app
  property var alert: null
  property bool open: false

  implicitHeight: col.implicitHeight + 16
  radius: 8
  color: alert && alert.severe ? app.ui.lateSoft : app.ui.warnSoft

  Icon {
    x: 8
    y: 8
    app: root.app
    text: Api.GLYPH.alertCircle
    size: 15
    color: root.alert && root.alert.severe ? root.app.ui.late : root.app.ui.warn
  }
  Column {
    id: col
    x: 34
    y: 8
    width: parent.width - 42
    spacing: 4
    Text {
      width: parent.width
      text: root.alert ? (root.alert.header || root.alert.text) : ""
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      font.weight: Font.DemiBold
      wrapMode: Text.Wrap
      maximumLineCount: root.open ? 6 : 2
      elide: Text.ElideRight
    }
    Text {
      visible: root.open && !!root.alert && !!root.alert.header && !!root.alert.text
      width: parent.width
      text: root.alert ? root.alert.text : ""
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
      wrapMode: Text.Wrap
      textFormat: Text.PlainText
    }
  }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.open = !root.open
  }
}
