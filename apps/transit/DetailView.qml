import QtQuick
import "Api.mjs" as Api

// One journey, or one vehicle's whole trip, as a timeline: over the list on a
// phone, beside it on a wide screen. Its live times come from whatever it was
// opened from -- the results list refreshing, or its own trip request.
Rectangle {
  id: root
  property var app
  property bool pane: false
  property var pageData: null
  property alias flick: flick
  property bool scrolled: false

  readonly property bool isTrip: pageData && pageData.kind === "trip"
  readonly property string tripUrl: isTrip ? Api.tripUrl(pageData.tripId, app.lang) : ""
  readonly property var journey: {
    app.motis.revision
    if (!pageData) return null
    if (isTrip) return app.motis.peek(tripUrl)
    return app.findJourney(pageData.key, pageData.seed)
  }
  // A trip not loaded yet: the board's row is enough for the header.
  readonly property var seedRow: isTrip ? pageData.seed : null
  readonly property var rides: {
    if (!journey) return []
    return journey.legs.filter(function (l) { return l.transit })
  }
  readonly property var firstRide: rides.length ? rides[0] : null
  readonly property var tripLeg: isTrip && journey ? journey.legs[0] : null
  readonly property string tripError: { app.motis.revision; return isTrip && !journey ? app.motis.error(tripUrl) : "" }

  color: app.ui.bg

  function refresh(force) {
    if (isTrip) app.motis.want(tripUrl, "trip", force ? 0 : 30000, true)
  }
  onTripUrlChanged: refresh(false)

  // ------------------------------------------------------------ header

  Item {
    id: header
    width: parent.width
    height: 56

    IconButton {
      id: backBtn
      x: 4
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      glyph: root.pane ? Api.GLYPH.close : Api.GLYPH.back
      label: root.pane ? "Close" : "Back"
      onClicked: root.app.back()
    }
    Text {
      anchors.left: backBtn.right
      anchors.leftMargin: 4
      anchors.right: actions.left
      anchors.verticalCenter: parent.verticalCenter
      text: root.isTrip ? "Trip" : "Journey"
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.compact ? 20 : 22
      font.weight: Font.Bold
      elide: Text.ElideRight
    }
    Row {
      id: actions
      anchors.right: parent.right
      anchors.rightMargin: root.pane ? 12 : 4
      anchors.verticalCenter: parent.verticalCenter
      IconButton {
        app: root.app
        glyph: Api.GLYPH.refresh
        label: "Refresh"
        onClicked: { root.refresh(true); root.app.refresh(true) }
      }
      // From a trip: plan a journey to where this vehicle is going.
      IconButton {
        visible: root.isTrip && !!root.tripLeg
        app: root.app
        glyph: Api.GLYPH.route
        label: "Plan a journey on this line"
        onClicked: {
          var l = root.tripLeg
          if (!l) return
          var at = null
          for (var i = 0; i < l.stops.length; i++) if (l.stops[i].stopId === root.pageData.stopId) at = l.stops[i]
          var from = at || l.from
          root.app.plan({ id: from.stopId, name: from.name, type: "STOP", lat: from.lat, lon: from.lon },
                        { id: l.to.stopId, name: l.to.name, type: "STOP", lat: l.to.lat, lon: l.to.lon })
        }
      }
    }
  }

  Rectangle { anchors.top: header.bottom; width: parent.width; height: 1; color: root.app.ui.divider; visible: flick.contentY > 4 }

  Flickable {
    id: flick
    anchors.top: header.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentWidth: width
    contentHeight: body.implicitHeight + 40
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick

    Column {
      id: body
      x: 16
      width: flick.width - 32
      spacing: 16

      // -------------------------------------------------------- summary
      Column {
        width: parent.width
        spacing: 10
        visible: !!root.journey || !!root.seedRow

        Row {
          spacing: 10
          visible: root.isTrip
          LineBadge {
            anchors.verticalCenter: parent.verticalCenter
            app: root.app
            leg: root.tripLeg || root.seedRow
            size: 30
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            Text {
              text: {
                var l = root.tripLeg || root.seedRow
                return l ? "to " + (l.headsign || (l.to ? l.to.name : "")) : ""
              }
              color: root.app.ui.text
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.lg
              font.weight: Font.DemiBold
              width: body.width - 90
              elide: Text.ElideRight
            }
            Text {
              text: {
                var l = root.tripLeg || root.seedRow
                return l ? [l.number, l.agency].filter(function (s) { return s }).join(" · ") : ""
              }
              visible: text !== ""
              color: root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.sm
            }
          }
        }

        // From → to, when, how long.
        Column {
          visible: !root.isTrip && !!root.journey
          width: parent.width
          spacing: 6
          Text {
            width: parent.width
            text: root.journey ? root.app.placeName(root.journey.legs[0].from.name, root.app.query.from ? root.app.query.from.name : "") + "  →  " + root.app.placeName(root.journey.legs[root.journey.legs.length - 1].to.name, root.app.query.to ? root.app.query.to.name : "") : ""
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.lg
            font.weight: Font.DemiBold
            wrapMode: Text.Wrap
          }
          Row {
            spacing: 10
            TimePair {
              app: root.app
              live: root.journey ? root.journey.start : 0
              planned: root.journey ? root.journey.sStart : 0
              realTime: root.journey ? root.journey.realTime : false
              cancelled: root.journey ? root.journey.cancelled : false
              size: root.app.ui.fs.xxl
            }
            Icon { app: root.app; text: Api.GLYPH.arrowRight; size: 20; height: 36; color: root.app.ui.muted }
            TimePair {
              app: root.app
              live: root.journey ? root.journey.end : 0
              planned: root.journey ? root.journey.sEnd : 0
              realTime: root.journey ? root.journey.realTime : false
              cancelled: root.journey ? root.journey.cancelled : false
              size: root.app.ui.fs.xxl
            }
          }
          Flow {
            width: parent.width
            spacing: 8
            Pill {
              app: root.app
              text: root.journey ? Api.dayLabel(root.journey.start, root.app.clock) : ""
            }
            Pill {
              app: root.app
              text: root.journey ? Api.duration(root.journey.duration) : ""
            }
            Pill {
              app: root.app
              text: !root.journey ? "" : root.journey.transfers === 0 ? (root.firstRide ? "Direct" : "On foot") : root.journey.transfers === 1 ? "1 change" : root.journey.transfers + " changes"
            }
            Pill {
              app: root.app
              live: root.journey ? root.journey.realTime : false
              text: root.journey && root.journey.realTime ? "Live" : "Timetable only"
            }
          }
          LegBar {
            width: parent.width
            app: root.app
            journey: root.journey
          }
        }

        Rectangle {
          visible: root.isTrip && !!root.tripLeg
          width: parent.width
          height: 1
          color: root.app.ui.divider
        }
        Row {
          visible: root.isTrip && !!root.tripLeg
          spacing: 8
          Pill {
            app: root.app
            live: root.tripLeg ? root.tripLeg.realTime : false
            text: root.tripLeg && root.tripLeg.realTime ? "Live" : "Timetable only"
          }
          Pill {
            app: root.app
            text: root.tripLeg ? Api.modeLabel(root.tripLeg.mode) : ""
          }
        }
      }

      // Where the journey starts, counted down.
      Rectangle {
        id: countdown
        readonly property real at: root.firstRide ? root.firstRide.start : 0
        readonly property int mins: Math.round((at - root.app.clock) / 60000)
        visible: !root.isTrip && !!root.firstRide && mins >= -1 && mins <= 120 && !root.journey.cancelled
        width: parent.width
        height: 52
        radius: root.app.ui.radius + 4
        color: root.app.ui.accentSoft
        Row {
          anchors.verticalCenter: parent.verticalCenter
          x: 14
          spacing: 10
          Icon { anchors.verticalCenter: parent.verticalCenter; app: root.app; text: Api.GLYPH.clock; size: 20; color: root.app.ui.accent }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: body.width - 14 - 30 - 10 - 14
            elide: Text.ElideRight
            readonly property int m: countdown.mins
            text: root.firstRide ? (m <= 0 ? root.firstRide.line + " leaves now" : root.firstRide.line + " leaves in " + m + " min")
              + (root.firstRide.from.track ? " from " + Api.platform(root.firstRide.from.track) : "") : ""
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.md
            font.weight: Font.DemiBold
          }
        }
      }

      // -------------------------------------------------------- timeline
      Timeline {
        visible: !!root.journey
        width: parent.width
        app: root.app
        journey: root.journey
        originName: root.app.query.from ? root.app.query.from.name : ""
        destName: root.app.query.to ? root.app.query.to.name : ""
        focusStop: root.isTrip ? root.pageData.stopId : ""
        expandAll: root.isTrip
        // A long trip opened mid-route: start with its stop in view, a third
        // of the way down, once.
        onFocusShown: function (item) {
          if (root.scrolled) return
          root.scrolled = true
          focusItem = item
          // After the columns have laid out; before, every row is at 0.
          scrollTimer.start()
        }
        property Item focusItem: null
        Timer {
          id: scrollTimer
          interval: 80
          onTriggered: {
            var item = parent.focusItem
            if (!item) return
            var y = item.mapToItem(body, 0, 0).y
            flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, y - flick.height / 3))
          }
        }
      }

      Column {
        visible: !root.journey
        width: parent.width
        spacing: 10
        topPadding: 30
        Spinner {
          anchors.horizontalCenter: parent.horizontalCenter
          app: root.app
          running: !root.journey && !root.tripError
        }
        Placeholder {
          visible: root.tripError !== ""
          width: parent.width
          app: root.app
          glyph: Api.GLYPH.alertCircle
          title: root.tripError
          action: "Try again"
          onTriggered: root.refresh(true)
        }
      }

      Attribution { app: root.app; width: parent.width }
    }
  }
}
