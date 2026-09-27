import QtQuick
import "Api.mjs" as Api

// A journey from top to bottom, the way you live it: each ride a line in its
// own colour with the stops on it, walks as dots, and every change marked
// with the minutes it leaves you. Live times, platforms and notices sit on
// the stop or ride they belong to.
Column {
  id: root
  property var app
  property var journey: null
  property string originName: ""
  property string destName: ""
  // A trip opened from a departure board: the stop it was picked at. Stops
  // before it are drawn faint, and the ride starts open.
  property string focusStop: ""
  property bool expandAll: false
  // The row of focusStop, once drawn, so the page can scroll to it.
  signal focusShown(Item item)

  readonly property int timeW: app.compact ? 56 : 64
  readonly property int railW: 28
  readonly property real railX: timeW + railW / 2

  readonly property var rows: {
    var out = []
    var j = journey
    if (!j) return out
    var legs = j.legs
    var changes = Api.transfers(j)
    function changeBefore(i) {
      for (var k = 0; k < changes.length; k++) if (changes[k].before === i) return changes[k]
      return null
    }
    for (var i = 0; i < legs.length; i++) {
      var l = legs[i]
      var first = i === 0, last = i === legs.length - 1
      if (!l.transit) {
        if (first) out.push({ type: "stop", role: "origin", name: root.app.placeName(l.from.name, root.originName), live: l.start, planned: l.sStart, realTime: false, place: l.from, below: "dots" })
        // The change this walk makes, if it sits between two rides.
        var ch = null
        for (var k = 0; k < changes.length; k++) if (changes[k].after < i && changes[k].before > i) ch = changes[k]
        // A walk inside one station is only a change; skip the walk row when
        // it is under a minute and says nothing new.
        out.push({ type: "walk", leg: l, change: ch })
        if (last) out.push({ type: "stop", role: "dest", name: root.app.placeName(l.to.name, root.destName), live: l.end, planned: l.sEnd, realTime: false, place: l.to, above: "dots" })
        continue
      }
      var cb = changeBefore(i)
      if (cb && (i === 0 || legs[i - 1].transit)) out.push({ type: "change", change: cb })
      out.push({ type: "stop", role: "dep", edge: first, name: l.from.name, live: l.from.dep || l.start, planned: l.from.sDep || l.sStart, realTime: l.realTime, place: l.from, leg: l, below: "line" })
      out.push({ type: "ride", leg: l, index: i })
      out.push({ type: "stop", role: "arr", edge: last, name: l.to.name, live: l.to.arr || l.end, planned: l.to.sArr || l.sEnd, realTime: l.realTime, place: l.to, leg: l, above: "line" })
    }
    return out
  }

  Repeater {
    model: root.rows
    delegate: Item {
      id: cell
      required property var modelData
      readonly property var row: modelData
      width: root.width
      height: loader.item ? loader.item.implicitHeight : 0

      Loader {
        id: loader
        width: parent.width
        sourceComponent: cell.row.type === "stop" ? stopC : cell.row.type === "ride" ? rideC : cell.row.type === "walk" ? walkC : changeC
      }

      // ---------------------------------------------------------- a stop
      Component {
        id: stopC
        Item {
          readonly property var r: cell.row
          readonly property bool ends: r.role === "origin" || r.role === "dest" || r.edge === true
          readonly property bool cancelled: r.place && r.place.cancelled
          implicitHeight: Math.max(44, nameCol.implicitHeight + 16)

          // Half a rail above and below the node, in the ride's colour or as
          // a walk's dots.
          Rectangle {
            visible: r.above === "line"
            x: root.railX - 2
            width: 4
            height: parent.height / 2
            color: root.app.lineStroke(r.leg)
          }
          Rectangle {
            visible: r.below === "line"
            x: root.railX - 2
            y: parent.height / 2
            width: 4
            height: parent.height / 2
            color: root.app.lineStroke(r.leg)
          }
          Rectangle {
            x: root.railX - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: ends ? 16 : 14
            height: width
            radius: width / 2
            color: ends ? root.app.ui.text : root.app.ui.bg
            border.width: ends ? 0 : 3
            border.color: r.leg ? root.app.lineStroke(r.leg) : root.app.ui.text
            Rectangle {
              visible: ends
              anchors.centerIn: parent
              width: 6
              height: 6
              radius: 3
              color: root.app.ui.bg
            }
          }

          TimePair {
            x: 0
            boxWidth: root.timeW - 8
            anchors.verticalCenter: parent.verticalCenter
            app: root.app
            live: r.live
            planned: r.planned
            realTime: r.realTime
            cancelled: cancelled
            align: Text.AlignRight
            size: root.app.ui.fs.md
          }

          Column {
            id: nameCol
            x: root.timeW + root.railW + 4
            width: parent.width - x - pill.width - 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
              width: parent.width
              text: r.name
              color: root.app.ui.text
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.md
              font.weight: Font.DemiBold
              font.strikeout: cancelled
              wrapMode: Text.Wrap
              maximumLineCount: 2
              elide: Text.ElideRight
            }
            Text {
              visible: cancelled
              text: "Stop cancelled"
              color: root.app.ui.late
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.xs
              font.weight: Font.DemiBold
            }
          }

          PlatformPill {
            id: pill
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            app: root.app
            track: r.place ? r.place.track : ""
            planned: r.place ? r.place.sTrack : ""
          }
        }
      }

      // ---------------------------------------------------------- a ride
      Component {
        id: rideC
        Item {
          id: ride
          readonly property var leg: cell.row.leg
          readonly property int focusIndex: {
            if (!root.focusStop) return -1
            for (var i = 0; i < leg.stops.length; i++) if (leg.stops[i].stopId === root.focusStop) return i
            return -1
          }
          property bool expanded: root.expandAll
          implicitHeight: body.implicitHeight + 16

          Rectangle {
            x: root.railX - 2
            width: 4
            height: parent.height
            color: root.app.lineStroke(ride.leg)
            opacity: ride.leg.cancelled ? 0.35 : 1
          }

          Column {
            id: body
            x: root.timeW + root.railW + 4
            y: 8
            width: parent.width - x
            spacing: 8

            Row {
              width: parent.width
              spacing: 8
              LineBadge {
                id: badge
                anchors.verticalCenter: parent.verticalCenter
                app: root.app
                leg: ride.leg
                size: 24
                muted: ride.leg.cancelled
              }
              Text {
                width: parent.width - badge.width - 8
                anchors.verticalCenter: parent.verticalCenter
                text: ride.leg.headsign ? "to " + ride.leg.headsign : Api.modeLabel(ride.leg.mode)
                color: root.app.ui.text
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.sm
                elide: Text.ElideRight
              }
            }

            Text {
              width: parent.width
              visible: text !== ""
              text: [ride.leg.number && ride.leg.number !== ride.leg.line ? ride.leg.number : "", ride.leg.agency].filter(function (s) { return s }).join(" · ")
              color: root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.xs
              elide: Text.ElideRight
            }

            Rectangle {
              visible: ride.leg.cancelled
              width: cancelText.implicitWidth + 16
              height: 26
              radius: 6
              color: root.app.ui.lateSoft
              Text {
                id: cancelText
                anchors.centerIn: parent
                text: "This ride is cancelled"
                color: root.app.ui.late
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.sm
                font.weight: Font.DemiBold
              }
            }

            Repeater {
              model: ride.leg.alerts
              delegate: AlertCard {
                required property var modelData
                width: body.width - 4
                app: root.app
                alert: modelData
              }
            }

            // "12 stops · 4 h 7 min", and the stops themselves on a tap.
            Item {
              width: parent.width
              height: 26
              Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: (ride.leg.stops.length ? ride.leg.stops.length + (ride.leg.stops.length === 1 ? " stop · " : " stops · ") : "Non-stop · ") + Api.duration(ride.leg.duration)
                  color: root.app.ui.muted
                  font.family: root.app.ui.font
                  font.pixelSize: root.app.ui.fs.sm
                }
                Icon {
                  visible: ride.leg.stops.length > 0
                  anchors.verticalCenter: parent.verticalCenter
                  app: root.app
                  text: ride.expanded ? Api.GLYPH.chevronUp : Api.GLYPH.chevronDown
                  size: 16
                  color: root.app.ui.muted
                }
                Icon {
                  visible: ride.leg.wheelchair
                  anchors.verticalCenter: parent.verticalCenter
                  app: root.app
                  text: Api.GLYPH.wheelchair
                  size: 14
                  color: root.app.ui.muted
                }
                Icon {
                  visible: ride.leg.bikes
                  anchors.verticalCenter: parent.verticalCenter
                  app: root.app
                  text: Api.GLYPH.bike
                  size: 14
                  color: root.app.ui.muted
                }
              }
              MouseArea {
                anchors.fill: parent
                enabled: ride.leg.stops.length > 0
                cursorShape: Qt.PointingHandCursor
                onClicked: ride.expanded = !ride.expanded
              }
            }

            Column {
              visible: ride.expanded
              width: parent.width
              Repeater {
                model: ride.expanded ? ride.leg.stops : []
                delegate: Item {
                  id: mid
                  required property var modelData
                  required property int index
                  readonly property bool before: ride.focusIndex >= 0 && index < ride.focusIndex
                  readonly property bool here: index === ride.focusIndex
                  width: body.width
                  height: 30
                  opacity: before ? 0.45 : 1
                  Component.onCompleted: if (here) root.focusShown(mid)

                  Rectangle {
                    x: root.railX - body.x - 4
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8
                    height: 8
                    radius: 4
                    color: mid.here ? root.app.lineStroke(ride.leg) : root.app.ui.bg
                    border.width: 2
                    border.color: root.app.lineStroke(ride.leg)
                  }
                  TimePair {
                    x: -body.x
                    boxWidth: root.timeW - 8
                    anchors.verticalCenter: parent.verticalCenter
                    app: root.app
                    live: mid.modelData.dep || mid.modelData.arr
                    planned: mid.modelData.sDep || mid.modelData.sArr
                    realTime: ride.leg.realTime
                    cancelled: mid.modelData.cancelled
                    align: Text.AlignRight
                    size: root.app.ui.fs.sm
                    bold: mid.here
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - midPill.width - 8
                    text: mid.modelData.name
                    color: mid.here ? root.app.ui.text : root.app.ui.muted
                    font.family: root.app.ui.font
                    font.pixelSize: root.app.ui.fs.sm
                    font.weight: mid.here ? Font.DemiBold : Font.Normal
                    font.strikeout: mid.modelData.cancelled
                    elide: Text.ElideRight
                  }
                  PlatformPill {
                    id: midPill
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    app: root.app
                    track: mid.modelData.track
                    planned: mid.modelData.sTrack
                  }
                }
              }
            }
          }
        }
      }

      // ---------------------------------------------------------- a walk
      Component {
        id: walkC
        Item {
          readonly property var leg: cell.row.leg
          readonly property var ch: cell.row.change
          readonly property bool tight: ch && (ch.minutes - ch.walk) < 2
          implicitHeight: Math.max(44, walkFlow.implicitHeight + 16)

          Column {
            x: root.railX - 2
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Repeater {
              model: Math.max(3, Math.round((parent.parent.height - 8) / 8))
              delegate: Rectangle { width: 4; height: 4; radius: 2; color: root.app.ui.muted }
            }
          }
          // The walk, and the change it makes; the tag drops under the walk
          // when both do not fit on one line.
          Flow {
            id: walkFlow
            x: root.timeW + root.railW + 4
            width: parent.width - x
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Row {
              spacing: 6
              height: 22
              Icon { anchors.verticalCenter: parent.verticalCenter; app: root.app; text: Api.GLYPH.walk; size: 16; color: root.app.ui.muted }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Walk " + Api.duration(leg.duration) + (isFinite(leg.distance) ? " · " + Api.distance(leg.distance) : "")
                color: root.app.ui.muted
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.sm
              }
            }
            ChangeTag { visible: !!ch; app: root.app; change: ch }
          }
        }
      }

      // ---------------------------------------------------------- a change
      Component {
        id: changeC
        Item {
          implicitHeight: 36
          Row {
            x: root.timeW + root.railW + 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Icon { anchors.verticalCenter: parent.verticalCenter; app: root.app; text: Api.GLYPH.transfer; size: 16; color: root.app.ui.muted }
            ChangeTag { app: root.app; change: cell.row.change; anchors.verticalCenter: parent.verticalCenter }
          }
        }
      }
    }
  }
}
