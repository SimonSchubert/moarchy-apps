import QtQuick
import "Api.mjs" as Api

// Where every trip starts: from, to and when in one card, the kinds of
// transport to use, and below it the trips you make often, each with its
// next connection already looked up.
Item {
  id: root
  property var app
  property alias flick: flick

  readonly property var q: app.query
  readonly property var saved: app.store.trips
  readonly property var recents: app.store.recents.filter(function (r) { return !root.app.store.isTrip(r.from, r.to) }).slice(0, 6)

  // The next connections for the first few saved trips: one request each,
  // two minutes apart at most, and only while this tab is on screen.
  function tripUrl(t) { return Api.planUrl({ from: t.from, to: t.to, time: 0, arriveBy: false }, app.store.routing, "", app.lang) }
  function refresh(force) {
    for (var i = 0; i < saved.length && i < 3; i++) app.motis.want(tripUrl(saved[i]), "plan", force ? 0 : 120000, false)
  }
  onSavedChanged: if (visible) refresh(false)

  readonly property string whenText: {
    if (!q.time) return "Now"
    var d = Api.dayLabel(q.time, app.clock)
    return (q.arriveBy ? "Arrive " : "Leave ") + (d === "Today" ? "" : d + " ") + app.time(q.time)
  }

  Flickable {
    id: flick
    anchors.fill: parent
    contentWidth: width
    contentHeight: body.implicitHeight + 40
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick

    Column {
      id: body
      x: (flick.width - width) / 2
      y: 4
      width: Math.min(flick.width - 28, 720)
      spacing: 14

      // -------------------------------------------------------- search
      Card {
        width: parent.width
        app: root.app
        pad: 6

        Column {
          width: parent.width
          spacing: 0

          PlaceField {
            width: parent.width - 48
            app: root.app
            label: "From"
            place: root.q.from
            dot: "start"
            onClicked: root.app.pick("from")
          }
          Item {
            width: parent.width
            height: 1
            Rectangle { x: 52; width: parent.width - 52 - 48; height: 1; color: root.app.ui.divider }
            Rectangle {
              // The line joining the two dots.
              x: 25
              y: -18
              width: 2
              height: 36
              color: root.app.ui.divider
            }
          }
          PlaceField {
            width: parent.width - 48
            app: root.app
            label: "To"
            place: root.q.to
            dot: "end"
            onClicked: root.app.pick("to")
          }
        }

        IconButton {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: -1
          app: root.app
          glyph: Api.GLYPH.swap
          label: "Swap start and destination"
          onClicked: root.app.swap()
        }
      }

      // When, and how.
      Flow {
        id: opts
        width: parent.width
        spacing: 6
        Chip {
          app: root.app
          text: root.whenText
          hpad: 22
          selected: !!root.q.time
          onClicked: root.app.timeOpen = true
        }
        Repeater {
          model: Api.GROUPS
          delegate: Chip {
            required property var modelData
            app: root.app
            text: modelData.label
            selected: root.app.store.groups.indexOf(modelData.key) >= 0
            onClicked: root.app.store.toggleGroup(modelData.key)
          }
        }
      }

      Button {
        width: parent.width
        height: 48
        app: root.app
        primary: true
        glyph: Api.GLYPH.search
        text: "Find connections"
        onClicked: root.app.search()
      }

      // Home and work, one tap from wherever the search starts.
      Row {
        visible: !!root.app.store.homePlace || !!root.app.store.workPlace
        width: parent.width
        spacing: 8
        Button {
          visible: !!root.app.store.homePlace
          app: root.app
          glyph: Api.GLYPH.home
          text: "Go home"
          onClicked: { root.app.setPlace("to", root.app.store.homePlace); root.app.search() }
        }
        Button {
          visible: !!root.app.store.workPlace
          app: root.app
          glyph: Api.GLYPH.work
          text: "To work"
          onClicked: { root.app.setPlace("to", root.app.store.workPlace); root.app.search() }
        }
      }

      // -------------------------------------------------------- saved
      SectionTitle {
        visible: root.saved.length > 0
        width: parent.width
        app: root.app
        text: "Your trips"
      }
      Repeater {
        model: root.saved
        delegate: TripCard {
          required property var modelData
          required property int index
          width: body.width
          app: root.app
          trip: modelData
          url: index < 3 ? root.tripUrl(modelData) : ""
          onClicked: root.app.plan(modelData.from, modelData.to)
          onOpenJourney: function (j) { root.app.query = { from: modelData.from, to: modelData.to, time: 0, arriveBy: false }; root.app.openJourney(j) }
        }
      }

      // -------------------------------------------------------- recent
      SectionTitle {
        visible: root.recents.length > 0
        width: parent.width
        app: root.app
        text: "Recent"
      }
      Card {
        visible: root.recents.length > 0
        width: parent.width
        app: root.app
        pad: 0
        Column {
          width: parent.width
          Repeater {
            model: root.recents
            delegate: Item {
              id: rec
              required property var modelData
              required property int index
              width: parent.width
              height: 56
              Rectangle {
                visible: rec.index > 0
                x: 52
                width: parent.width - 52
                height: 1
                color: root.app.ui.divider
              }
              Rectangle {
                anchors.fill: parent
                radius: root.app.ui.radius
                color: recMouse.pressed ? root.app.ui.pressed : recMouse.containsMouse ? root.app.ui.hover : "transparent"
              }
              Icon {
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                app: root.app
                text: Api.GLYPH.history
                size: 18
                color: root.app.ui.muted
              }
              Column {
                x: 52
                width: parent.width - 52 - 96
                anchors.verticalCenter: parent.verticalCenter
                Text {
                  width: parent.width
                  text: rec.modelData.to.name
                  color: root.app.ui.text
                  font.family: root.app.ui.font
                  font.pixelSize: root.app.ui.fs.md
                  font.weight: Font.DemiBold
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  text: "from " + rec.modelData.from.name
                  color: root.app.ui.muted
                  font.family: root.app.ui.font
                  font.pixelSize: root.app.ui.fs.xs
                  elide: Text.ElideRight
                }
              }
              MouseArea {
                id: recMouse
                anchors.fill: parent
                hoverEnabled: !root.app.compact
                cursorShape: Qt.PointingHandCursor
                onClicked: root.app.plan(rec.modelData.from, rec.modelData.to)
              }
              Row {
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                IconButton {
                  app: root.app
                  glyph: Api.GLYPH.starOutline
                  size: 18
                  color: root.app.ui.muted
                  label: "Save this trip"
                  onClicked: root.app.store.toggleTrip(rec.modelData.from, rec.modelData.to)
                }
                IconButton {
                  app: root.app
                  glyph: Api.GLYPH.close
                  size: 16
                  color: root.app.ui.muted
                  label: "Remove from recent"
                  onClicked: {
                    var all = root.app.store.recents
                    for (var i = 0; i < all.length; i++) if (root.app.store.sameTrip(all[i], rec.modelData)) { root.app.store.forget(i); break }
                  }
                }
              }
            }
          }
        }
      }

      // -------------------------------------------------------- first run
      Card {
        visible: root.saved.length === 0 && root.recents.length === 0
        width: parent.width
        app: root.app
        pad: 18
        Column {
          width: parent.width
          spacing: 8
          Row {
            spacing: 10
            Mark { app: root.app; size: 30; anchors.verticalCenter: parent.verticalCenter }
            Text {
              width: body.width - 36 - 40 - 10
              wrapMode: Text.Wrap
              anchors.verticalCenter: parent.verticalCenter
              text: "Buses, trains and trams, worldwide"
              color: root.app.ui.text
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.md
              font.weight: Font.DemiBold
            }
          }
          Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: "Search any two places for live connections. Star a trip to keep its next departure here, and set home and work under Saved."
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
            lineHeight: 1.2
          }
        }
      }
    }
  }
}
