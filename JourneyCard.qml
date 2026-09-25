import QtQuick
import "Api.mjs" as Api

// One way to get there, in the results list: when you leave and arrive, how
// long it takes and how often you change, the journey to scale, and where the
// first ride leaves from.
Card {
  id: root
  property var journey: null
  property bool current: false

  readonly property var j: journey
  readonly property var firstRide: {
    if (!j) return null
    for (var i = 0; i < j.legs.length; i++) if (j.legs[i].transit) return j.legs[i]
    return null
  }
  readonly property real leaveAt: j ? j.start : 0
  readonly property bool gone: j && j.start < app.clock - 60000
  readonly property var alerts: {
    if (!j) return []
    var out = []
    for (var i = 0; i < j.legs.length; i++) out = out.concat(j.legs[i].alerts)
    return out
  }

  pressable: true
  border.color: current ? app.ui.accent : app.ui.divider
  opacity: gone ? 0.55 : 1
  Accessible.role: Accessible.Button
  Accessible.name: j ? "Leave " + app.time(j.start) + ", arrive " + app.time(j.end) + ", " + Api.duration(j.duration) : ""

  Column {
    width: parent.width
    spacing: 10

    Item {
      width: parent.width
      height: Math.max(times.height, dur.height)

      Row {
        id: times
        spacing: 8
        TimePair {
          app: root.app
          live: root.j ? root.j.start : 0
          planned: root.j ? root.j.sStart : 0
          realTime: root.j ? root.j.realTime : false
          cancelled: root.j ? root.j.cancelled : false
          size: root.app.ui.fs.xl
        }
        Icon {
          app: root.app
          text: Api.GLYPH.arrowRight
          size: 16
          height: 26
          color: root.app.ui.muted
        }
        TimePair {
          app: root.app
          live: root.j ? root.j.end : 0
          planned: root.j ? root.j.sEnd : 0
          realTime: root.j ? root.j.realTime : false
          cancelled: root.j ? root.j.cancelled : false
          size: root.app.ui.fs.xl
        }
      }

      Column {
        id: dur
        anchors.right: parent.right
        Text {
          anchors.right: parent.right
          text: root.j ? Api.duration(root.j.duration) : ""
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.md
          font.weight: Font.DemiBold
        }
        Text {
          anchors.right: parent.right
          text: !root.j ? "" : root.j.transfers === 0 ? (root.firstRide ? "Direct" : "Walk") : root.j.transfers === 1 ? "1 change" : root.j.transfers + " changes"
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xs
        }
      }
    }

    LegBar {
      width: parent.width
      app: root.app
      journey: root.j
      dim: root.j ? root.j.cancelled : false
    }

    Item {
      width: parent.width
      height: 22

      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        width: parent.width - leave.width - 8
        clip: true

        LineBadge {
          visible: !!root.firstRide
          anchors.verticalCenter: parent.verticalCenter
          app: root.app
          leg: root.firstRide
          size: 20
        }
        PlatformPill {
          anchors.verticalCenter: parent.verticalCenter
          app: root.app
          track: root.firstRide ? root.firstRide.from.track : ""
          planned: root.firstRide ? root.firstRide.from.sTrack : ""
        }
        Icon {
          visible: root.alerts.length > 0
          anchors.verticalCenter: parent.verticalCenter
          app: root.app
          text: Api.GLYPH.alertCircle
          size: 15
          color: root.app.ui.warn
        }
        Text {
          visible: root.j && root.j.cancelled
          anchors.verticalCenter: parent.verticalCenter
          text: "Cancelled"
          color: root.app.ui.late
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
          font.weight: Font.DemiBold
        }
      }

      Row {
        id: leave
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 5
        LiveDot {
          visible: root.j ? root.j.realTime : false
          anchors.verticalCenter: parent.verticalCenter
          app: root.app
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          readonly property int mins: Math.round((root.leaveAt - root.app.clock) / 60000)
          text: root.gone ? "Departed" : mins <= 0 ? "Leave now" : Api.leavesIn(root.leaveAt, root.app.clock)
          color: mins <= 5 && !root.gone ? root.app.ui.accent : root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
          font.weight: mins <= 5 ? Font.DemiBold : Font.Normal
        }
      }
    }
  }
}
