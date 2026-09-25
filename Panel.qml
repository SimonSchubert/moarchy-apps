import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "Api.mjs" as Api

// Transit: journeys and live departures for public transport anywhere
// Transitous has a timetable, as one panel.
//
//     omarchy-shell shell toggle io.github.simonschubert.transit
//
// One layer, sized from whatever it is drawn into. On a desktop that is the
// screen: a card in the middle with a rail of sections on its left, and a
// journey beside the list it was picked from when there is room. On a phone
// the panel is moved into an app window a few hundred pixels wide, and the
// same tree lays itself out as a phone app: full bleed, tabs at the bottom,
// pages that stack, and back stepping out one level at a time.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  readonly property string pluginId: manifest && manifest.id ? manifest.id : "io.github.simonschubert.transit"

  // ------------------------------------------------------------ tokens

  readonly property bool compact: stage.width < 720
  property real clock: Date.now()
  // The router names stops in the language asked for where the feed has it.
  readonly property string lang: {
    var l = Qt.locale().name.split("_")[0]
    return /^[a-z]{2,3}$/.test(l) ? l : "en"
  }

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function luminance(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
  function contrast(a, b) {
    var x = luminance(a) + 0.05, y = luminance(b) + 0.05
    return x > y ? x / y : y / x
  }
  readonly property color onAccent: luminance(ui.accent) > 0.6 ? "#111111" : "#ffffff"

  readonly property QtObject ui: QtObject {
    readonly property bool dark: root.luminance(Color.menu.background) < 0.5
    readonly property color bg: Color.menu.background
    readonly property color text: Color.menu.text
    readonly property color muted: Color.muted
    readonly property color accent: Color.accent
    readonly property color border: Color.menu.border
    readonly property color surface: Qt.tint(bg, root.alpha(text, dark ? 0.06 : 0.04))
    readonly property color surfaceHigh: Qt.tint(bg, root.alpha(text, dark ? 0.12 : 0.08))
    // No hover on a touch screen: a finger leaves the last row it lifted from
    // looking pointed at.
    readonly property color hover: root.compact ? "transparent" : root.alpha(text, 0.06)
    readonly property color pressed: root.alpha(text, 0.12)
    readonly property color accentSoft: root.alpha(accent, 0.16)
    readonly property color divider: root.alpha(text, 0.08)
    readonly property color ok: dark ? "#34d399" : "#15803d"
    readonly property color late: dark ? "#f87171" : "#dc2626"
    readonly property color warn: dark ? "#fbbf24" : "#b45309"
    readonly property color lateSoft: root.alpha(late, 0.14)
    readonly property color warnSoft: root.alpha(warn, 0.16)
    readonly property color okSoft: root.alpha(ok, 0.14)
    readonly property color star: "#f5b82e"
    readonly property string font: Style.font.family
    readonly property int radius: Math.max(6, Math.min(12, Style.cornerRadius))
    readonly property int target: root.compact ? 44 : 38
    readonly property int chip: root.compact ? 36 : 32
    readonly property QtObject fs: QtObject {
      readonly property int xs: 11
      readonly property int sm: 13
      readonly property int md: 14
      readonly property int lg: 17
      readonly property int xl: 20
      readonly property int xxl: root.compact ? 26 : 30
    }
  }

  // A line's own colour where the feed has one, else the mode's. On the
  // background (the timeline, the leg bar) a colour too close to it -- a
  // white line on a light theme, a black one on a dark -- gives way to text.
  function lineFill(leg) {
    if (!leg) return ui.muted
    return leg.color || Api.modeColor(leg.mode)
  }
  function lineStroke(leg) {
    var c = Qt.color(lineFill(leg))
    return contrast(c, ui.bg) < 1.35 ? ui.text : c
  }
  function lineOn(leg) {
    var fill = Qt.color(lineFill(leg))
    if (leg && leg.textColor) {
      var t = Qt.color(leg.textColor)
      if (contrast(t, fill) >= 2.2) return t
    }
    return luminance(fill) > 0.62 ? "#111111" : "#ffffff"
  }

  // START and END are what the router calls a place given as coordinates.
  function placeName(name, fallback) {
    if (!name || name === "START" || name === "END") return fallback || "Your location"
    return name
  }

  function time(t) { return Api.clock(t, store.clock24) }

  // ------------------------------------------------------------ state

  readonly property var tabs: [
    { key: "journey", label: "Journey", glyph: Api.GLYPH.route },
    { key: "departures", label: "Departures", glyph: Api.GLYPH.board },
    { key: "saved", label: "Saved", glyph: Api.GLYPH.star }
  ]
  readonly property var railExtras: [
    { key: "settings", label: "Settings", glyph: Api.GLYPH.settings }
  ]

  property string tab: "journey"
  // Pages over the current tab: { kind: "results" }, { kind: "journey", key,
  // seed } or { kind: "trip", tripId, seed, stopId }.
  property var stack: []
  // The search being made: places from the geocoder, and when.
  property var query: ({ from: null, to: null, time: 0, arriveBy: false })
  // Who the place picker is choosing for: "from", "to", "board", "home",
  // "work", or "" when it is shut.
  property string picking: ""
  property bool timeOpen: false

  readonly property var page: stack.length ? stack[stack.length - 1] : null
  readonly property bool detailOpen: !!page && (page.kind === "journey" || page.kind === "trip")
  readonly property bool resultsOpen: stack.some(function (p) { return p.kind === "results" })
  readonly property bool split: !compact && main.width >= 960 && detailOpen

  function setTab(key) {
    resetFocus()
    picking = ""
    timeOpen = false
    stack = []
    tab = key
    if (key !== "settings") store.set("lastTab", key)
    Qt.callLater(function () { root.refresh(false); keys.forceActiveFocus() })
  }

  // Take focus back from any text field left behind. On a phone a focused
  // field is a raised keyboard.
  function resetFocus() { keys.forceActiveFocus() }

  function push(p) {
    resetFocus()
    var s = stack.slice()
    // Journey to journey replaces rather than piles up: back from a journey
    // goes to the list it was picked from.
    if (s.length && (s[s.length - 1].kind === "journey" || s[s.length - 1].kind === "trip")
        && (p.kind === "journey" || p.kind === "trip")) s[s.length - 1] = p
    else s.push(p)
    stack = s
  }

  function setPlace(which, place) {
    var q = Object.assign({}, query)
    q[which] = Api.cleanPlace(place)
    query = q
  }

  function swap() {
    query = Object.assign({}, query, { from: query.to, to: query.from })
    if (resultsOpen) search()
  }

  // A search is a results page over the Journey tab.
  function search() {
    if (!query.from || !query.to) {
      picking = !query.from ? "from" : "to"
      return
    }
    store.remember(query.from, query.to)
    if (tab !== "journey") { tab = "journey"; store.set("lastTab", "journey") }
    stack = [{ kind: "results", q: query }]
    Qt.callLater(function () { root.refresh(false) })
  }

  function plan(from, to) {
    query = { from: Api.cleanPlace(from), to: Api.cleanPlace(to), time: 0, arriveBy: false }
    search()
  }

  function openJourney(it) {
    if (!it) return
    push({ kind: "journey", key: it.key, seed: it })
  }

  function openTrip(row, stopId) {
    if (!row || !row.tripId) return
    push({ kind: "trip", tripId: row.tripId, seed: row, stopId: stopId || "" })
  }

  function openBoard(place) {
    var p = Api.cleanPlace(place)
    if (!p) return
    store.set("board", p)
    if (tab !== "departures") setTab("departures")
    else { stack = []; Qt.callLater(function () { root.refresh(false) }) }
  }

  function pick(which) {
    resetFocus()
    timeOpen = false
    picking = which
  }

  // What the picker hands back.
  function picked(place) {
    var which = picking
    picking = ""
    resetFocus()
    var p = Api.cleanPlace(place)
    if (!p) return
    if (which === "from" || which === "to") {
      setPlace(which, p)
      if (query.from && query.to && !Api.samePlace(query.from, query.to)) search()
    } else if (which === "board") {
      openBoard(p)
    } else if (which === "home") {
      store.set("homePlace", p)
    } else if (which === "work") {
      store.set("workPlace", p)
    }
  }

  // The journey with this key, from the freshest plan that has it: a refresh
  // of the list brings its live times along.
  function findJourney(key, seed) {
    motis.revision
    var best = null, bestT = -1
    var c = motis.cache
    for (var url in c) {
      var e = c[url]
      if (e.kind !== "plan" || !e.data || e.t <= bestT) continue
      var its = e.data.itineraries
      for (var i = 0; i < its.length; i++) {
        if (its[i].key === key) { best = its[i]; bestT = e.t; break }
      }
    }
    return best || seed
  }

  // One step out: a sheet, the picker, the page, the tab, then nothing. True
  // when it stepped. On a phone the gesture bar calls this directly and hides
  // the panel itself when it answers false, so at the root it must not also
  // close; Escape from a keyboard closes there instead (see Keys below).
  function back() {
    resetFocus()
    if (timeOpen) { timeOpen = false; return true }
    if (picking) { picking = ""; return true }
    if (stack.length) { var s = stack.slice(); s.pop(); stack = s; return true }
    if (tab !== "journey") { setTab("journey"); return true }
    return false
  }

  // Refresh what is on screen. Everything else waits until it is looked at.
  function refresh(force) {
    if (!opened) return
    var v = currentView()
    if (v && v.refresh) v.refresh(force)
    if (detailLoader.item) detailLoader.item.refresh(force)
  }

  function currentView() {
    if (resultsOpen && resultsLoader.item) return resultsLoader.item
    switch (tab) {
    case "departures": return boardView
    case "saved": return savedView
    case "settings": return settingsView
    }
    return journeyView
  }

  function titleText() {
    if (resultsOpen) return "Journeys"
    if (tab === "settings") return "Settings"
    for (var i = 0; i < tabs.length; i++) if (tabs[i].key === tab) return tabs[i].label
    return "Transit"
  }

  // ------------------------------------------------------------ host API

  // A payload can start a search or open a board:
  //   { "from": place, "to": place } or { "board": place }
  function open(payloadJson) {
    opened = true
    var p = null
    try { p = typeof payloadJson === "string" && payloadJson ? JSON.parse(payloadJson) : payloadJson } catch (e) { p = null }
    if (p && p.from && p.to && Api.cleanPlace(p.from) && Api.cleanPlace(p.to)) plan(p.from, p.to)
    else if (p && p.board && Api.cleanPlace(p.board)) openBoard(p.board)
    root.clock = Date.now()
    Qt.callLater(function () { keys.forceActiveFocus(); root.refresh(false) })
  }

  function close() {
    timeOpen = false
    picking = ""
    opened = false
  }

  function toggle() { opened ? close() : open("") }

  // Closing from inside -- the close button, a click outside, Escape -- goes
  // through the host. Dropping `opened` alone leaves the host counting the
  // panel open, and the next `shell toggle` (the keybinding) would "hide" it
  // and show nothing. The host's hide() calls close() in turn.
  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  // ------------------------------------------------------------ plumbing

  Store {
    id: storeObj
    onReadyChanged: {
      if (!ready) return
      var t = prefs.lastTab
      if (["journey", "departures", "saved"].indexOf(t) >= 0) root.tab = t
      // Start from where the last search started: most trips begin at the
      // same few places.
      if (storeObj.recents.length) root.query = { from: storeObj.recents[0].from, to: null, time: 0, arriveBy: false }
      root.refresh(false)
    }
    onSnapshotLoaded: function (text) { motisObj.restoreText(text) }
  }

  Motis { id: motisObj }

  LauncherEntry {
    id: launcherObj
    app: root
    pluginId: root.pluginId
  }

  // Aliases for the views, which reach everything through `app`.
  readonly property alias store: storeObj
  readonly property alias motis: motisObj
  readonly property alias launcher: launcherObj

  // Countdowns tick, and what is on screen stays live: a board or journey
  // refreshes itself as its answer ages past 30 seconds.
  Timer {
    interval: 15000
    repeat: true
    running: root.opened
    onTriggered: { root.clock = Date.now(); root.refresh(false) }
  }

  // Written when the app closes, not while it is in use.
  onOpenedChanged: if (!opened) store.saveSnapshot(motis.snapshot(["plan", "stoptimes"], 10))

  // ------------------------------------------------------------ window

  PanelWindow {
    id: window
    visible: root.opened
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-transit"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }

    Item {
      id: stage
      anchors.fill: parent

      // Outside the card, on a desktop: dim, and a click closes. Never on a
      // phone, where the card is the whole window and a full-surface
      // MouseArea would eat the home gesture.
      Rectangle {
        anchors.fill: parent
        visible: !root.compact
        color: Color.menu.scrim
        MouseArea {
          anchors.fill: parent
          enabled: !root.compact
          onClicked: root.dismiss()
        }
      }

      Rectangle {
        id: card
        anchors.centerIn: parent
        width: root.compact ? parent.width : Math.min(parent.width - 80, 1320)
        height: root.compact ? parent.height : Math.min(parent.height - 80, 880)
        radius: root.compact ? 0 : root.ui.radius + 4
        color: root.ui.bg
        border.width: root.compact ? 0 : 1
        border.color: root.ui.border
        clip: true

        MouseArea { anchors.fill: parent; enabled: !root.compact }

        // A plain Item and not a FocusScope: forceActiveFocus() on a scope
        // hands focus back to whatever inside it had it last -- the search
        // field -- and the phone's keyboard comes straight back up. Keys
        // from every child still bubble up to here.
        Item {
          id: keys
          anchors.fill: parent
          anchors.margins: card.border.width
          focus: true

          Keys.onPressed: function (event) {
            var k = event.key
            if (k === Qt.Key_Escape || k === Qt.Key_Back) { if (!root.back()) root.dismiss(); event.accepted = true; return }
            if (root.picking || root.timeOpen) return
            if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
            var v = root.currentView()
            var f = root.detailOpen && detailLoader.item ? detailLoader.item.flick : v && v.flick ? v.flick : null
            if ((k === Qt.Key_Down || k === Qt.Key_Up) && f) {
              f.contentY = Math.max(0, Math.min(f.contentHeight - f.height, f.contentY + (k === Qt.Key_Down ? 80 : -80)))
              event.accepted = true
              return
            }
            if (event.text === "/") { root.pick(root.tab === "departures" ? "board" : "to"); event.accepted = true; return }
            if (event.text === "r") { root.refresh(true); event.accepted = true; return }
            if (event.text === "s" && root.tab === "journey") { root.swap(); event.accepted = true; return }
            var n = "123".indexOf(event.text)
            if (n >= 0 && event.text !== "") { root.setTab(root.tabs[n].key); event.accepted = true }
          }

          // Rail: desktop only.
          Rectangle {
            id: rail
            visible: !root.compact
            width: root.compact ? 0 : 200
            height: parent.height
            color: root.ui.surface
            radius: card.radius

            Rectangle {
              anchors.right: parent.right
              width: card.radius
              height: parent.height
              color: parent.color
            }

            Column {
              anchors.fill: parent
              anchors.topMargin: 16
              anchors.leftMargin: 10
              anchors.rightMargin: 10
              spacing: 2

              Row {
                x: 6
                height: 44
                spacing: 10
                Mark { app: root; size: 28; anchors.verticalCenter: parent.verticalCenter }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Transit"
                  color: root.ui.text
                  font.family: root.ui.font
                  font.pixelSize: root.ui.fs.lg
                  font.weight: Font.Bold
                }
              }
              Item { width: 1; height: 10 }

              Repeater {
                model: root.tabs.concat(root.railExtras)
                delegate: Rectangle {
                  id: railItem
                  required property var modelData
                  required property int index
                  readonly property bool current: root.tab === modelData.key
                  width: parent.width
                  height: 40
                  radius: root.ui.radius
                  color: current ? root.ui.accentSoft : railMouse.containsMouse ? root.ui.hover : "transparent"
                  Row {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 8
                    spacing: 8
                    Icon { app: root; text: railItem.modelData.glyph; size: 18; color: railItem.current ? root.ui.accent : root.ui.text }
                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: railItem.modelData.label
                      color: railItem.current ? root.ui.accent : root.ui.text
                      font.family: root.ui.font
                      font.pixelSize: root.ui.fs.md
                      font.weight: railItem.current ? Font.DemiBold : Font.Normal
                    }
                  }
                  Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    visible: railItem.index < 3
                    text: railItem.index + 1
                    color: root.ui.muted
                    font.family: root.ui.font
                    font.pixelSize: root.ui.fs.xs
                  }
                  MouseArea {
                    id: railMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setTab(railItem.modelData.key)
                  }
                }
              }
            }

            Text {
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 14
              x: 18
              width: parent.width - 36
              visible: rail.height > 16 + 64 + (root.tabs.length + root.railExtras.length) * 42 + implicitHeight + 40
              wrapMode: Text.Wrap
              text: "Routing by Transitous\n/ search · s swap · r refresh · Esc back"
              color: root.ui.muted
              font.family: root.ui.font
              font.pixelSize: root.ui.fs.xs
              lineHeight: 1.3
            }
          }

          // Everything right of the rail (all of it, on a phone).
          Item {
            id: main
            anchors.left: rail.visible ? rail.right : parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: nav.visible ? nav.top : parent.bottom

            Item {
              id: listSide
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: root.split ? Math.max(440, parent.width * 0.44) : parent.width

              Item {
                id: header
                width: parent.width
                height: 56

                IconButton {
                  id: headerBack
                  x: 4
                  anchors.verticalCenter: parent.verticalCenter
                  visible: root.resultsOpen || (root.compact && root.tab === "settings")
                  width: visible ? implicitWidth : 0
                  app: root
                  glyph: Api.GLYPH.back
                  label: "Back"
                  onClicked: {
                    // Beside a journey, back from the list closes both.
                    if (root.split) root.stack = []
                    else if (!root.back()) root.dismiss()
                  }
                }
                Text {
                  anchors.left: headerBack.visible ? headerBack.right : parent.left
                  anchors.leftMargin: headerBack.visible ? 4 : 16
                  anchors.right: headerActions.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.titleText()
                  color: root.ui.text
                  font.family: root.ui.font
                  font.pixelSize: root.compact ? 20 : 22
                  font.weight: Font.Bold
                  elide: Text.ElideRight
                }
                Row {
                  id: headerActions
                  anchors.right: parent.right
                  anchors.rightMargin: root.compact || root.split ? 4 : 52
                  anchors.verticalCenter: parent.verticalCenter
                  Spinner {
                    app: root
                    size: 18
                    anchors.verticalCenter: parent.verticalCenter
                    running: root.motis.inflight !== "" || root.motis.queue.length > 0
                  }
                  Item { width: 8; height: 1 }
                  IconButton {
                    visible: root.resultsOpen && !!root.query.from && !!root.query.to
                    app: root
                    glyph: root.store.isTrip(root.query.from, root.query.to) ? Api.GLYPH.star : Api.GLYPH.starOutline
                    color: root.store.isTrip(root.query.from, root.query.to) ? root.ui.star : root.ui.text
                    label: "Save this trip"
                    onClicked: root.store.toggleTrip(root.query.from, root.query.to)
                  }
                  IconButton {
                    visible: root.compact && root.tab !== "settings" && !root.resultsOpen
                    app: root
                    glyph: Api.GLYPH.settings
                    label: "Settings"
                    onClicked: root.setTab("settings")
                  }
                }
              }

              Rectangle {
                id: banner
                anchors.top: header.bottom
                width: parent.width
                // A file problem outranks a network one: it loses data.
                readonly property string message: store.warning || motis.banner
                height: visible ? (store.warning ? 44 : 30) : 0
                visible: message !== ""
                color: store.warning ? root.ui.lateSoft : motis.waitSeconds > 0 ? root.ui.warnSoft : root.ui.surfaceHigh
                Text {
                  anchors.centerIn: parent
                  width: parent.width - 24
                  horizontalAlignment: Text.AlignHCenter
                  text: banner.message
                  color: root.ui.text
                  font.family: root.ui.font
                  font.pixelSize: root.ui.fs.xs
                  wrapMode: Text.Wrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                }
              }

              Item {
                id: views
                anchors.top: banner.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                clip: true

                JourneyTab { id: journeyView; anchors.fill: parent; app: root; visible: root.tab === "journey" && !root.resultsOpen }
                BoardView { id: boardView; anchors.fill: parent; app: root; visible: root.tab === "departures" && !root.resultsOpen }
                SavedView { id: savedView; anchors.fill: parent; app: root; visible: root.tab === "saved" && !root.resultsOpen }
                SettingsView { id: settingsView; anchors.fill: parent; app: root; visible: root.tab === "settings" && !root.resultsOpen }

                Loader {
                  id: resultsLoader
                  anchors.fill: parent
                  active: root.resultsOpen
                  sourceComponent: Component {
                    ResultsView {
                      app: root
                      Component.onCompleted: refresh(false)
                    }
                  }
                }
              }
            }

            Rectangle {
              visible: root.split
              anchors.left: listSide.right
              width: 1
              height: parent.height
              color: root.ui.divider
            }

            // A journey or a trip: over everything on a phone or a narrow
            // card, beside the list when the card is wide enough.
            Loader {
              id: detailLoader
              active: root.detailOpen
              z: 3
              x: root.split ? listSide.width + 1 : 0
              y: 0
              width: root.split ? parent.width - listSide.width - 1 : parent.width
              height: root.compact ? keys.height : parent.height
              sourceComponent: Component {
                DetailView {
                  app: root
                  pane: root.split
                  pageData: root.page
                  Component.onCompleted: refresh(false)
                }
              }
            }
          }

          // Tabs: phone only, and not under a journey.
          Rectangle {
            id: nav
            visible: root.compact && !root.detailOpen
            anchors.bottom: parent.bottom
            width: parent.width
            height: visible ? 62 : 0
            color: root.ui.surface

            Rectangle { width: parent.width; height: 1; color: root.ui.divider }

            Row {
              anchors.fill: parent
              Repeater {
                model: root.tabs
                delegate: Item {
                  id: navItem
                  required property var modelData
                  readonly property bool current: root.tab === modelData.key
                  width: nav.width / root.tabs.length
                  height: nav.height
                  Accessible.role: Accessible.PageTab
                  Accessible.name: modelData.label

                  Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 7
                    width: 56
                    height: 28
                    radius: 14
                    color: navItem.current ? root.ui.accentSoft : navMouse.pressed ? root.ui.pressed : "transparent"
                  }
                  Icon {
                    app: root
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 7
                    height: 28
                    text: navItem.modelData.glyph
                    size: 19
                    color: navItem.current ? root.ui.accent : root.ui.muted
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 38
                    text: navItem.modelData.label
                    color: navItem.current ? root.ui.text : root.ui.muted
                    font.family: root.ui.font
                    font.pixelSize: root.ui.fs.xs
                    font.weight: navItem.current ? Font.DemiBold : Font.Normal
                  }
                  MouseArea {
                    id: navMouse
                    anchors.fill: parent
                    onClicked: root.setTab(navItem.modelData.key)
                  }
                }
              }
            }
          }

          PlacePicker {
            id: picker
            anchors.fill: parent
            z: 10
            app: root
            visible: root.picking !== ""
            which: root.picking
          }

          TimeSheet {
            anchors.fill: parent
            z: 11
            app: root
            visible: root.timeOpen
          }
        }

        // Desktop: close the whole panel from the card's corner.
        IconButton {
          visible: !root.compact
          z: 20
          anchors.top: parent.top
          anchors.right: parent.right
          anchors.margins: 8
          app: root
          glyph: Api.GLYPH.close
          label: "Close"
          onClicked: root.dismiss()
        }

        // The card's outline, drawn over its content so nothing inside paints
        // across it.
        Rectangle {
          visible: !root.compact
          anchors.fill: parent
          z: 30
          color: "transparent"
          radius: card.radius
          border.width: 1
          border.color: root.ui.border
        }
      }
    }
  }
}
