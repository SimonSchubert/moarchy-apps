import QtQuick
import "Api.mjs" as Api

// The journeys for the search in app.query, earliest first, with earlier and
// later ones a tap away. Every page is a URL in the cache, so paging back and
// forth costs nothing and a refresh updates them all.
Item {
  id: root
  property var app
  property alias flick: list

  readonly property var q: app.query
  // Cursors, one per page, in time order; "" is the first answer.
  property var cursors: [""]
  // One readable column, however wide the card.
  readonly property real colW: Math.min(list.width - 28, 760)
  readonly property real colX: (list.width - colW) / 2

  readonly property var urls: cursors.map(function (c) { return Api.planUrl(root.q, root.app.store.routing, c, root.app.lang) })
  readonly property var pages: { app.motis.revision; return urls.map(function (u) { return root.app.motis.peek(u) }) }
  readonly property var journeys: {
    var seen = {}, out = []
    for (var i = 0; i < pages.length; i++) {
      var p = pages[i]
      if (!p) continue
      for (var j = 0; j < p.itineraries.length; j++) {
        var it = p.itineraries[j]
        if (seen[it.key]) continue
        seen[it.key] = true
        out.push(it)
      }
    }
    out.sort(function (a, b) { return a.sStart - b.sStart || a.end - b.end })
    return out
  }
  readonly property var direct: pages.length && pages[0] ? pages[0].direct : []
  readonly property bool loadingFirst: { app.motis.revision; return !pages[0] && app.motis.busy(urls[0]) }
  readonly property string error: { app.motis.revision; return pages[0] ? "" : app.motis.error(urls[0]) }

  // A new search starts from its first page. Deferred: q is first read
  // while `urls` is being evaluated, and resetting cursors there is a loop.
  onQChanged: {
    list.pinned = true
    if (cursors.length > 1) Qt.callLater(function () { root.cursors = [""] })
  }
  Connections {
    target: root.app.store
    function onRoutingKeyChanged() { root.cursors = [""]; root.refresh(false) }
  }

  // Answers age: a minute for journeys, whose live times move.
  function refresh(force) {
    for (var i = 0; i < urls.length; i++) app.motis.want(urls[i], "plan", force ? 0 : 60000, i === 0)
  }

  function earlier() {
    var first = pages[0]
    if (!first || !first.prev) return
    cursors = [first.prev].concat(cursors)
    Qt.callLater(function () { root.app.motis.want(root.urls[0], "plan", 60000, true) })
  }
  function later() {
    var last = pages[pages.length - 1]
    if (!last || !last.next) return
    cursors = cursors.concat([last.next])
    Qt.callLater(function () { root.app.motis.want(root.urls[root.urls.length - 1], "plan", 60000, true) })
  }

  // What in Settings narrows this search, as the rest of a sentence that
  // starts "Your settings"; empty when nothing does.
  readonly property string limits: {
    var st = app.store, out = []
    var off = Api.GROUPS.filter(function (g) { return st.groups.indexOf(g.key) < 0 }).map(function (g) { return g.label.toLowerCase() })
    if (off.length) out.push("leave out " + off.join(" and "))
    if (st.maxTransfers === 0) out.push("allow only direct journeys")
    else if (st.maxTransfers > 0) out.push("allow at most " + st.maxTransfers + (st.maxTransfers === 1 ? " change" : " changes"))
    if (st.wheelchair) out.push("ask for step-free routes")
    return out.length > 1 ? out.slice(0, -1).join(", ") + " and " + out[out.length - 1] : out.join("")
  }
  function loosen() {
    app.store.set("groups", Api.GROUP_KEYS)
    app.store.set("maxTransfers", -1)
  }

  readonly property string whenText: {
    var t = q.time || app.clock
    var d = Api.dayLabel(t, app.clock)
    if (!q.time) return "Leaving now"
    return (q.arriveBy ? "Arrive by " : "Leave at ") + (d === "Today" ? "" : d + ", ") + app.time(t)
  }

  ListView {
    id: list
    anchors.fill: parent
    clip: true
    spacing: 10
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
    model: root.journeys
    header: Column {
      width: list.width
      onHeightChanged: list.keepTop()
      spacing: 10
      bottomPadding: 10

      // What was asked, in a strip you can tap to change.
      Card {
        x: root.colX
        width: root.colW
        app: root.app
        pad: 12
        Column {
          width: parent.width
          spacing: 6
          // From over to, each on its own line: station names run long.
          Repeater {
            model: [{ k: "from", end: false }, { k: "to", end: true }]
            delegate: Item {
              id: endRow
              required property var modelData
              width: parent.width - swapBtn.width
              height: 26
              Rectangle {
                x: 2
                anchors.verticalCenter: parent.verticalCenter
                width: 10
                height: 10
                radius: endRow.modelData.end ? 2 : 5
                color: endRow.modelData.end ? root.app.ui.accent : "transparent"
                border.width: endRow.modelData.end ? 0 : 2
                border.color: root.app.ui.accent
              }
              Text {
                x: 22
                width: parent.width - x
                anchors.verticalCenter: parent.verticalCenter
                text: root.q[endRow.modelData.k] ? root.q[endRow.modelData.k].name : ""
                color: root.app.ui.text
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.md
                font.weight: Font.DemiBold
                elide: Text.ElideRight
              }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.app.pick(endRow.modelData.k) }
            }
          }
          Row {
            spacing: 6
            Chip {
              app: root.app
              text: root.whenText
              hpad: 20
              onClicked: root.app.timeOpen = true
            }
          }
        }
        IconButton {
          id: swapBtn
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.rightMargin: -6
          app: root.app
          glyph: Api.GLYPH.swap
          label: "Swap start and destination"
          onClicked: root.app.swap()
        }
      }

      // Walking is sometimes the answer.
      Repeater {
        model: root.direct.filter(function (d) { return d.duration <= 1800 })
        delegate: Card {
          id: walkCard
          required property var modelData
          x: root.colX
          width: root.colW
          app: root.app
          pad: 12
          pressable: true
          onClicked: root.app.openJourney(modelData)
          Row {
            spacing: 10
            Icon { app: root.app; text: Api.GLYPH.walk; size: 20; color: root.app.ui.accent; anchors.verticalCenter: parent.verticalCenter }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Walk " + Api.duration(walkCard.modelData.duration) + (walkCard.modelData.legs[0] && isFinite(walkCard.modelData.legs[0].distance) ? " · " + Api.distance(walkCard.modelData.legs[0].distance) : "")
              color: root.app.ui.text
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.md
            }
          }
        }
      }

      Chip {
        visible: !!root.pages[0] && !!root.pages[0].prev
        anchors.horizontalCenter: parent.horizontalCenter
        app: root.app
        text: root.app.motis.busy(root.urls[0]) ? "Loading…" : "Earlier"
        onClicked: root.earlier()
      }
    }

    // The list places its delegates at x 0; the card is centred inside one.
    delegate: Item {
      id: slot
      required property var modelData
      width: list.width
      height: card.implicitHeight
      JourneyCard {
        id: card
        x: root.colX
        width: root.colW
        app: root.app
        journey: slot.modelData
        current: root.app.page && root.app.page.kind === "journey" && root.app.page.key === slot.modelData.key
        onClicked: root.app.openJourney(slot.modelData)
      }
    }

    footer: Column {
      width: list.width
      topPadding: 12
      bottomPadding: 20
      spacing: 14
      Chip {
        visible: root.journeys.length > 0 && !!root.pages[root.pages.length - 1] && !!root.pages[root.pages.length - 1].next
        anchors.horizontalCenter: parent.horizontalCenter
        app: root.app
        text: root.app.motis.busy(root.urls[root.urls.length - 1]) ? "Loading…" : "Later"
        onClicked: root.later()
      }
      Attribution { app: root.app; width: parent.width; visible: root.journeys.length > 0 }
    }
  }

  Column {
    anchors.centerIn: parent
    width: parent.width
    visible: root.journeys.length === 0
    spacing: 10
    Spinner {
      anchors.horizontalCenter: parent.horizontalCenter
      app: root.app
      running: root.loadingFirst
    }
    Placeholder {
      width: parent.width
      visible: !root.loadingFirst
      app: root.app
      glyph: root.error ? Api.GLYPH.alertCircle : Api.GLYPH.route
      title: root.error || (root.pages[0] ? "No connections found" : "Finding connections…")
      detail: root.error
        ? "Transitous covers most of Europe, North America, parts of Asia and Oceania. Check the places, or try again."
        : !root.pages[0] ? ""
        : root.limits ? "Your settings " + root.limits + ". Try without them, or at another time."
        : "Try another time."
      action: root.error ? "Try again" : !root.pages[0] ? "" : root.limits && root.app.store.groups.length < Api.GROUPS.length || root.app.store.maxTransfers >= 0 ? "Allow every route" : "Change time"
      onTriggered: {
        if (root.error) root.refresh(true)
        else if (action === "Allow every route") root.loosen()
        else root.app.timeOpen = true
      }
    }
  }
}
