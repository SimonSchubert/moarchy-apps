import QtQuick
import "Api.mjs" as Api

// A departure board for any stop: what leaves next, from which platform, and
// how late. Tap a row for the vehicle's whole trip. Refreshes itself every
// half minute while it is on screen.
Item {
  id: root
  property var app
  property alias flick: list

  readonly property var stop: app.store.board
  property bool arrivals: false
  // "" is everything; otherwise one group's key.
  property string only: ""
  property var cursors: [""]
  readonly property real colW: Math.min(list.width, 800)
  readonly property real colX: (list.width - colW) / 2

  readonly property var groupsHere: {
    if (!stop || !stop.modes || !stop.modes.length) return Api.GROUPS
    return Api.GROUPS.filter(function (g) {
      return g.modes.some(function (m) { return root.stop.modes.indexOf(m) >= 0 })
    })
  }
  readonly property var urls: stop ? cursors.map(function (c) {
    return Api.stoptimesUrl(root.stop.id, 0, root.arrivals, root.only ? [root.only] : Api.GROUP_KEYS, c, root.app.lang)
  }) : []
  readonly property var pages: { app.motis.revision; return urls.map(function (u) { return root.app.motis.peek(u) }) }
  readonly property var rows: {
    var out = [], seen = {}
    for (var i = 0; i < pages.length; i++) {
      var p = pages[i]
      if (!p) continue
      for (var j = 0; j < p.rows.length; j++) {
        var r = p.rows[j]
        var k = r.tripId + "@" + (r.place.sDep || r.place.sArr)
        if (seen[k]) continue
        seen[k] = true
        // Gone more than a minute ago: off the board.
        var t = root.arrivals ? r.place.arr || r.place.dep : r.place.dep || r.place.arr
        if (t < root.app.clock - 60000) continue
        out.push(r)
      }
    }
    return out
  }
  readonly property bool loading: { app.motis.revision; return urls.length > 0 && !pages[0] && app.motis.busy(urls[0]) }
  readonly property string error: { app.motis.revision; return urls.length && !pages[0] ? app.motis.error(urls[0]) : "" }

  onStopChanged: { cursors = [""]; only = ""; list.pinned = true; if (visible) refresh(false) }
  onArrivalsChanged: { cursors = [""]; refresh(false) }
  onOnlyChanged: { cursors = [""]; refresh(false) }

  // Half a minute: a board is only worth looking at live. Only the first page
  // refreshes by itself; later pages are further out and change less.
  function refresh(force) {
    for (var i = 0; i < urls.length; i++) app.motis.want(urls[i], "stoptimes", force ? 0 : i === 0 ? 30000 : 120000, i === 0)
  }

  function later() {
    var last = pages[pages.length - 1]
    if (!last || !last.next) return
    cursors = cursors.concat([last.next])
    Qt.callLater(function () { root.refresh(false) })
  }

  ListView {
    id: list
    anchors.fill: parent
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    // No current item: the list would scroll its header away to show one.
    currentIndex: -1
    // A header that grows (Earlier appears, a walk option) grows upwards
    // and slides out of view. Until the list is scrolled by hand, it stays
    // at its top.
    property bool pinned: true
    onMovementStarted: pinned = false
    function keepTop() { if (pinned) Qt.callLater(positionViewAtBeginning) }
    onCountChanged: keepTop()
    model: root.rows
    visible: !!root.stop

    header: Column {
      width: list.width
      onHeightChanged: list.keepTop()
      spacing: 12
      bottomPadding: 6

      // The stop, and a way to another.
      Card {
        x: root.colX + 14
        width: root.colW - 28
        app: root.app
        pad: 14
        pressable: true
        onClicked: root.app.pick("board")
        Item {
          width: parent.width
          height: Math.max(44, stopCol.implicitHeight)
          Rectangle {
            id: stopTile
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            height: 44
            radius: 12
            color: root.app.ui.accentSoft
            Icon { anchors.centerIn: parent; app: root.app; text: Api.GLYPH.board; size: 22; color: root.app.ui.accent }
          }
          Column {
            id: stopCol
            anchors.left: stopTile.right
            anchors.leftMargin: 12
            anchors.right: starBtn.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
              width: parent.width
              text: root.stop ? root.stop.name : ""
              color: root.app.ui.text
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.lg
              font.weight: Font.Bold
              wrapMode: Text.Wrap
              maximumLineCount: 2
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              text: root.stop && root.stop.area ? root.stop.area + " · change stop" : "Change stop"
              color: root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.xs
              elide: Text.ElideRight
            }
          }
          IconButton {
            id: starBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: -6
            app: root.app
            readonly property bool on: root.stop ? root.app.store.isStop(root.stop) : false
            glyph: on ? Api.GLYPH.star : Api.GLYPH.starOutline
            color: on ? root.app.ui.star : root.app.ui.muted
            label: on ? "Remove from your stops" : "Add to your stops"
            onClicked: root.app.store.toggleStop(root.stop)
          }
        }
      }

      // Your stops, one tap apart.
      Flow {
        id: favs
        visible: root.app.store.stops.length > 1 || (root.app.store.stops.length === 1 && !root.app.store.isStop(root.stop))
        x: root.colX + 14
        width: root.colW - 28
        spacing: 6
        Repeater {
          model: root.app.store.stops
          delegate: Chip {
            required property var modelData
            app: root.app
            text: modelData.name
            selected: Api.samePlace(modelData, root.stop)
            onClicked: root.app.openBoard(modelData)
          }
        }
      }

      // Departures or arrivals, and which kind.
      Flow {
        id: filters
        x: root.colX + 14
        width: root.colW - 28
        spacing: 6
        Chip { app: root.app; text: "Departures"; selected: !root.arrivals; onClicked: root.arrivals = false }
        Chip { app: root.app; text: "Arrivals"; selected: root.arrivals; onClicked: root.arrivals = true }
        Chip {
          visible: root.groupsHere.length > 1
          app: root.app
          text: "All"
          selected: root.only === ""
          onClicked: root.only = ""
        }
        Repeater {
          model: root.groupsHere.length > 1 ? root.groupsHere : []
          delegate: Chip {
            required property var modelData
            app: root.app
            text: modelData.label
            selected: root.only === modelData.key
            onClicked: root.only = root.only === modelData.key ? "" : modelData.key
          }
        }
      }
    }

    // The list places its delegates at x 0; the row is centred inside one.
    delegate: Item {
      id: slot
      required property var modelData
      width: list.width
      height: depRow.implicitHeight
      DepartureRow {
        id: depRow
        x: root.colX
        width: root.colW
        app: root.app
        row: slot.modelData
        arrivals: root.arrivals
        onClicked: root.app.openTrip(slot.modelData, slot.modelData.place.stopId)
      }
    }

    footer: Column {
      width: list.width
      topPadding: 14
      bottomPadding: 20
      spacing: 14
      Chip {
        visible: root.rows.length > 0 && !!root.pages[root.pages.length - 1] && !!root.pages[root.pages.length - 1].next
        anchors.horizontalCenter: parent.horizontalCenter
        app: root.app
        text: root.app.motis.busy(root.urls[root.urls.length - 1]) ? "Loading…" : "Later"
        onClicked: root.later()
      }
      Column {
        visible: root.rows.length === 0
        width: parent.width
        spacing: 8
        Spinner { anchors.horizontalCenter: parent.horizontalCenter; app: root.app; running: root.loading }
        Placeholder {
          visible: !root.loading
          width: parent.width
          app: root.app
          glyph: root.error ? Api.GLYPH.alertCircle : Api.GLYPH.board
          title: root.error || (root.pages[0] ? "Nothing leaves here soon" : "Loading the board…")
          action: root.error ? "Try again" : ""
          onTriggered: root.refresh(true)
        }
      }
      Attribution { app: root.app; width: parent.width }
    }
  }

  // No stop yet.
  Column {
    visible: !root.stop
    anchors.centerIn: parent
    width: Math.min(parent.width, 480)
    spacing: 14
    Placeholder {
      width: parent.width
      app: root.app
      glyph: Api.GLYPH.board
      title: "Live departures"
      detail: "Pick a station or stop to see what leaves next, from which platform, and how late."
      action: "Choose a stop"
      onTriggered: root.app.pick("board")
    }
  }
}
