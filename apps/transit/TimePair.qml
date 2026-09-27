import QtQuick
import "Api.mjs" as Api

// A time as it will be, and as it was planned when the two differ.
//
// Green is live and on time, amber a few minutes late, red later than that or
// cancelled. A feed with no live data draws in plain text: "on time" is a
// promise only a live feed can make.
Column {
  id: root
  property var app
  property real live: 0
  property real planned: 0
  property bool realTime: false
  property bool cancelled: false
  property int size: app.ui.fs.md
  property bool bold: true
  property int align: Text.AlignLeft
  // A fixed width to align in (a timeline's time column); 0 is as wide as
  // the time.
  property real boxWidth: 0

  readonly property int delay: Api.delayMinutes(live, planned)
  readonly property color tone: cancelled ? app.ui.late
    : !realTime ? app.ui.text
    : delay >= 5 ? app.ui.late
    : delay >= 2 ? app.ui.warn
    : app.ui.ok

  spacing: 0

  Text {
    width: root.boxWidth > 0 ? root.boxWidth : implicitWidth
    horizontalAlignment: root.align
    text: root.app.time(root.cancelled ? root.planned || root.live : root.live || root.planned)
    color: root.tone
    font.family: root.app.ui.font
    font.pixelSize: root.size
    font.weight: root.bold ? Font.Bold : Font.Normal
    font.features: ({ "tnum": 1 })
    font.strikeout: root.cancelled
  }
  Text {
    visible: !root.cancelled && root.realTime && root.delay !== 0 && root.planned > 0
    width: root.boxWidth > 0 ? root.boxWidth : implicitWidth
    horizontalAlignment: root.align
    text: root.app.time(root.planned)
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: Math.max(10, root.size - 3)
    font.features: ({ "tnum": 1 })
    font.strikeout: true
  }
}
