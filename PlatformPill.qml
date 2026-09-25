import QtQuick
import "Api.mjs" as Api

// Where to stand. When the platform has changed, the new one in amber with
// the old one struck through beside it: the first thing to look for on a
// busy station.
Rectangle {
  id: root
  property var app
  property string track: ""
  property string planned: ""

  readonly property bool changed: planned !== "" && track !== "" && track !== planned
  visible: track !== "" || planned !== ""
  implicitHeight: 22
  implicitWidth: row.implicitWidth + 14
  radius: 6
  color: changed ? app.ui.warnSoft : app.ui.surfaceHigh
  border.width: changed ? 1 : 0
  border.color: app.ui.warn
  Accessible.role: Accessible.StaticText
  Accessible.name: changed ? "Platform changed to " + track + ", was " + planned : "Platform " + (track || planned)

  Row {
    id: row
    anchors.centerIn: parent
    spacing: 5
    Text {
      text: Api.platform(root.track || root.planned)
      color: root.changed ? root.app.ui.warn : root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
      font.weight: Font.DemiBold
      font.features: ({ "tnum": 1 })
    }
    Text {
      visible: root.changed
      text: root.planned
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
      font.strikeout: true
    }
  }
}
