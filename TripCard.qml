import QtQuick
import "Api.mjs" as Api

// A saved trip and when its next connection leaves: the line, the platform
// and a countdown, so the phone answers "when do I have to go?" at a glance.
Card {
  id: root
  property var trip: null
  property string url: ""
  signal openJourney(var journey)

  readonly property var plan: { app.motis.revision; return url ? app.motis.peek(url) : null }
  readonly property var next: {
    if (!plan) return null
    var now = app.clock
    for (var i = 0; i < plan.itineraries.length; i++) {
      var it = plan.itineraries[i]
      if (it.start >= now - 30000 && !it.cancelled) return it
    }
    return null
  }
  readonly property var ride: {
    if (!next) return null
    for (var i = 0; i < next.legs.length; i++) if (next.legs[i].transit) return next.legs[i]
    return null
  }
  readonly property int mins: next ? Math.round((next.start - app.clock) / 60000) : 0

  pressable: true
  pad: 14
  Accessible.role: Accessible.Button
  Accessible.name: trip ? trip.from.name + " to " + trip.to.name : ""

  Column {
    width: parent.width
    spacing: 10

    Item {
      width: parent.width
      height: names.implicitHeight
      Column {
        id: names
        width: parent.width - count.width - 10
        Text {
          width: parent.width
          text: root.trip ? root.trip.to.name : ""
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.md
          font.weight: Font.DemiBold
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          text: root.trip ? "from " + root.trip.from.name : ""
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xs
          elide: Text.ElideRight
        }
      }
      // The countdown, big: the one number that matters on the way out.
      Column {
        id: count
        anchors.right: parent.right
        visible: !!root.next
        Text {
          anchors.right: parent.right
          text: root.mins <= 0 ? "now" : root.mins < 60 ? root.mins + " min" : root.app.time(root.next ? root.next.start : 0)
          color: root.mins <= 5 ? root.app.ui.accent : root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xl
          font.weight: Font.Bold
          font.features: ({ "tnum": 1 })
        }
      }
    }

    Item {
      visible: !!root.next
      width: parent.width
      height: 24
      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        LineBadge {
          visible: !!root.ride
          anchors.verticalCenter: parent.verticalCenter
          app: root.app
          leg: root.ride
          size: 20
        }
        TimePair {
          anchors.verticalCenter: parent.verticalCenter
          app: root.app
          live: root.next ? root.next.start : 0
          planned: root.next ? root.next.sStart : 0
          realTime: root.next ? root.next.realTime : false
          size: root.app.ui.fs.sm
        }
        PlatformPill {
          anchors.verticalCenter: parent.verticalCenter
          app: root.app
          track: root.ride ? root.ride.from.track : ""
          planned: root.ride ? root.ride.from.sTrack : ""
        }
      }
      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.next ? Api.duration(root.next.duration) + (root.next.transfers ? " · " + root.next.transfers + (root.next.transfers === 1 ? " change" : " changes") : "") : ""
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
      }
      MouseArea {
        anchors.fill: parent
        onClicked: root.openJourney(root.next)
      }
    }

    Text {
      visible: !root.next && root.url !== ""
      text: { root.app.motis.revision; return root.app.motis.error(root.url) || (root.plan ? "No connection soon" : "Looking up the next connection…") }
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
    }
  }
}
