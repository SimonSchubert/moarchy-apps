import QtQuick
import "Api.mjs" as Api

// One departure (or arrival) on the board: the line as the sign shows it,
// where it goes, the platform, and how long until it leaves, live.
Rectangle {
  id: root
  property var app
  property var row: null
  property bool arrivals: false
  signal clicked()

  readonly property real live: row ? (arrivals ? row.place.arr || row.place.dep : row.place.dep || row.place.arr) : 0
  readonly property real planned: row ? (arrivals ? row.place.sArr || row.place.sDep : row.place.sDep || row.place.sArr) : 0
  readonly property int mins: Math.round((live - app.clock) / 60000)
  readonly property bool cancelled: row ? row.cancelled : false

  implicitHeight: 64
  color: mouse.pressed ? app.ui.pressed : mouse.containsMouse ? app.ui.hover : "transparent"
  Accessible.role: Accessible.Button
  Accessible.name: row ? row.line + " to " + row.headsign + ", " + app.time(live) : ""

  Item {
    id: badgeSlot
    x: 16
    width: root.app.compact ? 76 : 88
    height: parent.height
    LineBadge {
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      leg: root.row
      size: 24
      muted: root.cancelled
      width: Math.min(implicitWidth, badgeSlot.width - 6)
    }
  }

  Column {
    anchors.left: badgeSlot.right
    anchors.right: timeCol.left
    anchors.rightMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    spacing: 4
    Text {
      width: parent.width
      text: root.row ? (root.arrivals ? (root.row.origin ? "from " + root.row.origin : root.row.headsign) : root.row.headsign || root.row.terminus) : ""
      color: root.cancelled ? root.app.ui.muted : root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md
      font.weight: Font.DemiBold
      font.strikeout: root.cancelled
      elide: Text.ElideRight
    }
    Row {
      spacing: 6
      PlatformPill {
        anchors.verticalCenter: parent.verticalCenter
        app: root.app
        track: root.row ? root.row.place.track : ""
        planned: root.row ? root.row.place.sTrack : ""
      }
      Text {
        visible: root.cancelled
        anchors.verticalCenter: parent.verticalCenter
        text: "Cancelled"
        color: root.app.ui.late
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
        font.weight: Font.DemiBold
      }
      Icon {
        visible: !!root.row && root.row.alerts.length > 0
        anchors.verticalCenter: parent.verticalCenter
        app: root.app
        text: Api.GLYPH.alertCircle
        size: 14
        color: root.app.ui.warn
      }
      Text {
        visible: !!root.row && !!root.row.number && !root.cancelled
        anchors.verticalCenter: parent.verticalCenter
        text: root.row ? root.row.number : ""
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
      }
    }
  }

  // Minutes while it is close, the clock after that; the time as planned
  // underneath when it runs late.
  Column {
    id: timeCol
    anchors.right: parent.right
    anchors.rightMargin: 16
    anchors.verticalCenter: parent.verticalCenter
    width: 72
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignRight
      text: root.cancelled ? root.app.time(root.planned) : root.mins <= 0 && root.mins > -2 ? "now" : root.mins > 0 && root.mins < 60 ? root.mins + " min" : root.app.time(root.live)
      color: root.cancelled ? root.app.ui.late
        : !root.row || !root.row.realTime ? root.app.ui.text
        : Api.delayMinutes(root.live, root.planned) >= 5 ? root.app.ui.late
        : Api.delayMinutes(root.live, root.planned) >= 2 ? root.app.ui.warn
        : root.mins <= 2 ? root.app.ui.accent : root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.lg
      font.weight: Font.Bold
      font.features: ({ "tnum": 1 })
      font.strikeout: root.cancelled
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignRight
      readonly property int delay: Api.delayMinutes(root.live, root.planned)
      text: !root.row ? "" : root.row.realTime && delay > 0 ? "+" + delay + " · " + root.app.time(root.planned)
        : root.row.realTime && delay < 0 ? delay + " · " + root.app.time(root.planned)
        : root.mins > 0 && root.mins < 60 ? root.app.time(root.live) : ""
      visible: text !== ""
      color: root.row && root.row.realTime && delay >= 5 ? root.app.ui.late : root.row && root.row.realTime && delay >= 2 ? root.app.ui.warn : root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
      font.features: ({ "tnum": 1 })
    }
  }

  Rectangle {
    anchors.bottom: parent.bottom
    x: badgeSlot.x
    width: parent.width - x * 2
    height: 1
    color: root.app.ui.divider
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: !root.app.compact
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
