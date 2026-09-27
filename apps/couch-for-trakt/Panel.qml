import QtQuick
import Quickshell
import "Api.mjs" as Api
import "Glyphs.js" as G

// Couch: what is on, what is next, and what you are watching -- Trakt as one
// panel.
//
//     omarchy-shell shell toggle io.github.simonschubert.couch
//
// An ordinary window, tiled, focused and closed like any other app, and laid
// out from its own size: a rail of sections on the left when it is wide, and
// a phone app -- tabs at the bottom, pages that stack -- when it is narrow, as
// on Omarchy Mobile, where the window is the whole screen. Escape (the phone's
// back) steps out one level at a time.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  // True when shell.qml runs it as its own process, with no Omarchy shell.
  property bool standalone: false

  // ------------------------------------------------------------ tokens

  readonly property bool compact: stage.width < 720
  property real clock: Date.now()

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function luminance(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
  // Text on a filled accent button: dark on a light accent, white otherwise.
  readonly property color onAccent: luminance(ui.accent) > 0.6 ? "#111111" : "#ffffff"

  // Omarchy's theme inside its shell, a plain one under any other Quickshell.
  HostTheme { id: theme }
  Component.onCompleted: theme.probe(root)

  readonly property QtObject ui: QtObject {
    readonly property bool dark: root.luminance(theme.background) < 0.5
    readonly property color bg: theme.background
    readonly property color text: theme.text
    readonly property color muted: theme.muted
    readonly property color accent: theme.accent
    readonly property color border: theme.border
    readonly property color surface: Qt.tint(bg, root.alpha(text, dark ? 0.06 : 0.04))
    readonly property color surfaceHigh: Qt.tint(bg, root.alpha(text, dark ? 0.12 : 0.08))
    // No hover on a touch screen: a finger leaves the last card it lifted
    // from looking pointed at.
    readonly property color hover: root.compact ? "transparent" : root.alpha(text, 0.06)
    readonly property color pressed: root.alpha(text, 0.12)
    readonly property color selected: root.alpha(accent, 0.14)
    readonly property color accentSoft: root.alpha(accent, 0.16)
    readonly property color divider: root.alpha(text, 0.08)
    readonly property color good: dark ? "#22c55e" : "#15803d"
    readonly property color heart: "#ed2224"
    readonly property color star: "#f5b82e"
    readonly property color warn: "#f59e0b"
    readonly property string font: theme.fontFamily
    readonly property int radius: Math.max(6, Math.min(10, theme.cornerRadius))
    readonly property int target: root.compact ? 44 : 38
    readonly property int chip: root.compact ? 34 : 32
    readonly property QtObject fs: QtObject {
      readonly property int xs: 11
      readonly property int sm: 13
      readonly property int md: 14
      readonly property int lg: 17
      readonly property int xl: root.compact ? 22 : 26
      readonly property int xxl: root.compact ? 26 : 34
    }
  }

  // ------------------------------------------------------------ state

  readonly property var tabs: [
    { key: "discover", label: "Discover", glyph: G.discover },
    { key: "upnext", label: "Up Next", glyph: G.upNext },
    { key: "calendar", label: "Calendar", glyph: G.calendar },
    { key: "watchlist", label: "Watchlist", glyph: G.watchlist }
  ]
  readonly property var railExtras: [
    { key: "search", label: "Search", glyph: G.search },
    { key: "history", label: "History", glyph: G.history },
    { key: "settings", label: "Settings", glyph: G.settings }
  ]

  property string tab: "discover"
  // Pages over the current tab: { item } -- a movie or show, seeded with
  // what the card that opened it knew.
  property var stack: []
  readonly property var page: stack.length ? stack[stack.length - 1] : null

  function setTab(key) {
    resetFocus()
    stack = []
    tab = key
    if (tabs.some(function (t) { return t.key === key })) store.set("lastTab", key)
    Qt.callLater(function () { root.refresh(false); keys.forceActiveFocus() })
  }

  function openSettings() { setTab("settings") }

  function startSignIn() {
    setTab("settings")
    if (trakt.authState !== "code" && trakt.authState !== "asking") trakt.beginSignIn()
  }

  // Take focus back from any text field left behind. On a phone a focused
  // field is a raised keyboard, and a keyboard over a page nobody is typing
  // on is in the way.
  function resetFocus() { keys.forceActiveFocus() }

  function openMedia(item) {
    if (!item || !Api.tid(item.id)) return
    resetFocus()
    var s = stack.slice()
    var top = s.length ? s[s.length - 1] : null
    if (top && top.item.type === item.type && top.item.id === item.id) return
    s.push({ item: item })
    // Related to related to related: the way back stays a few steps long.
    if (s.length > 8) s.splice(0, s.length - 8)
    stack = s
  }

  // One step out: the page, the tab, then nothing. True when it stepped. On a
  // phone the gesture bar calls this directly and hides the panel itself
  // when it answers false, so at the root it must not also close; Escape
  // from a keyboard closes there instead (see Keys below).
  function back() {
    resetFocus()
    if (stack.length) { var s = stack.slice(); s.pop(); stack = s; return true }
    if (tab !== "discover") { setTab("discover"); return true }
    return false
  }

  // Refresh what is on screen. Everything else waits until it is looked at.
  function refresh(force) {
    if (!opened) return
    var v = currentView()
    if (v && v.refresh) v.refresh(force)
    if (detailLoader.item) detailLoader.item.refresh(force)
    library.ensure(force)
  }

  function currentView() {
    switch (tab) {
    case "upnext": return upNextView
    case "calendar": return calendarView
    case "watchlist": return watchlistView
    case "search": return searchView
    case "history": return historyView
    case "settings": return settingsView
    }
    return discoverView
  }

  function titleText() {
    var all = tabs.concat(railExtras)
    for (var i = 0; i < all.length; i++) if (all[i].key === tab) return all[i].label
    return "Couch"
  }

  function dayLabel(day) { return Api.dayLabel(day, clock) }
  // The date beside a day's name, unless the name is already a date.
  function dateLabel(day) {
    var name = Api.dayLabel(day, clock)
    if (/\d/.test(name)) return ""
    var p = String(day).split("-")
    return Api.MONTHS[Number(p[1]) - 1] + " " + Number(p[2])
  }

  property string toastText: ""
  function toast(text) {
    toastText = text
    toastTimer.restart()
  }

  // ------------------------------------------------------------ host API

  function open(payloadJson) {
    opened = true
    window.visible = true
    var p = null
    try { p = typeof payloadJson === "string" && payloadJson ? JSON.parse(payloadJson) : payloadJson } catch (e) { p = null }
    if (p && Api.tid(p.movie)) openMedia({ type: "movie", id: Api.tid(p.movie) })
    else if (p && Api.tid(p.show)) openMedia({ type: "show", id: Api.tid(p.show) })
    Qt.callLater(function () { keys.forceActiveFocus(); root.refresh(false) })
  }

  // From the host (`shell hide`, the keybinding). The window goes without
  // telling the host back: it already knows.
  property bool closingFromHost: false
  function close() {
    closingFromHost = true
    window.visible = false
    closingFromHost = false
    opened = false
  }

  function toggle() { opened ? close() : open("") }

  // Closing from inside -- the close button, a click outside, Escape -- goes
  // through the host. Dropping `opened` alone leaves the host counting the
  // panel open, and the next `shell toggle` (the keybinding) would "hide" it
  // and show nothing. The host's hide() calls close() in turn.
  function dismiss() {
    var id = manifest && manifest.id ? manifest.id : "io.github.simonschubert.couch"
    if (shell && typeof shell.hide === "function") shell.hide(id)
    else close()
  }

  // ------------------------------------------------------------ plumbing

  Store {
    id: storeObj
    onReadyChanged: {
      if (!ready) return
      var t = prefs.lastTab
      if (root.tabs.some(function (x) { return x.key === t })) root.tab = t
      root.refresh(false)
    }
    onSnapshotLoaded: function (text) { traktObj.restoreText(text) }
  }

  Trakt {
    id: traktObj
    store: storeObj
  }

  Library {
    id: libraryObj
    app: root
  }

  Images {
    id: imagesObj
    app: root
    dir: storeObj.cacheDir + "/images"
  }

  LauncherEntry {
    id: launcherObj
    app: root
    pluginId: root.manifest && root.manifest.id ? root.manifest.id : "io.github.simonschubert.couch"
  }

  // Aliases for the views, which reach everything through `app`.
  readonly property alias store: storeObj
  readonly property alias trakt: traktObj
  readonly property alias library: libraryObj
  readonly property alias images: imagesObj
  readonly property alias launcher: launcherObj

  Timer {
    interval: 60000
    repeat: true
    running: root.opened
    onTriggered: { root.clock = Date.now(); root.refresh(false) }
  }

  Timer {
    id: toastTimer
    interval: 2600
    onTriggered: root.toastText = ""
  }

  // Written when the app closes, not while it is in use: the stringify of a
  // few hundred kilobytes is a hitch nobody should feel mid-scroll.
  onOpenedChanged: {
    if (opened) clock = Date.now()
    else store.saveSnapshot(trakt.snapshot(["list", "upnext", "watchlist", "calendar"], 14))
  }

  // ------------------------------------------------------------ window

  // Shown and hidden by open() and close(), not bound to `opened`: the window
  // manager closes it too, and a binding would fight that.
  FloatingWindow {
    id: window
    visible: false
    title: "Couch for Trakt"
    color: root.ui.bg
    implicitWidth: 1280
    implicitHeight: 820
    minimumSize: Qt.size(360, 480)

    // Closed from outside -- the close key, the window manager: tell the
    // host, so its idea of what is open stays true and the next `shell
    // toggle` opens it again rather than "closing" it.
    onVisibleChanged: if (!visible && !root.closingFromHost && root.opened) root.dismiss()

    Item {
      id: stage
      anchors.fill: parent

      Rectangle {
        id: card
        anchors.fill: parent
        radius: 0
        color: root.ui.bg
        clip: true

        // A plain Item and not a FocusScope: forceActiveFocus() on a scope
        // hands focus back to whatever inside it had it last -- the search
        // field -- and the phone's keyboard comes straight back up. Keys
        // from every child still bubble up to here.
        Item {
          id: keys
          anchors.fill: parent
          focus: true

          Keys.onPressed: function (event) {
            var detail = detailLoader.item
            var v = detail ? null : root.currentView()
            var grid = v && v.list ? v.list : null
            var k = event.key
            // One step back; at the top there is nothing to leave -- an app
            // window is closed by the window manager, not by Escape.
            if (k === Qt.Key_Escape || k === Qt.Key_Back) { root.back(); event.accepted = true; return }
            if (grid) {
              if (k === Qt.Key_Down) { event.accepted = grid.move(0, 1); return }
              if (k === Qt.Key_Up) { event.accepted = grid.move(0, -1); return }
              if (k === Qt.Key_Right) { event.accepted = grid.move(1, 0); return }
              if (k === Qt.Key_Left) { event.accepted = grid.move(-1, 0); return }
              if (k === Qt.Key_Return || k === Qt.Key_Enter) { event.accepted = grid.activateCurrent(); return }
            } else if (detail) {
              if (k === Qt.Key_Down || k === Qt.Key_PageDown) { detail.scroll(k === Qt.Key_Down ? 80 : 400); event.accepted = true; return }
              if (k === Qt.Key_Up || k === Qt.Key_PageUp) { detail.scroll(k === Qt.Key_Up ? -80 : -400); event.accepted = true; return }
            }
            if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
            if (event.text === "/") { root.setTab("search"); Qt.callLater(searchView.focusField); event.accepted = true; return }
            if (event.text === "r") { root.refresh(true); event.accepted = true; return }
            if (event.text === "w") {
              var m = detail ? detail.item : grid && grid.currentItem ? grid.currentItem() : null
              if (m && m.type) root.library.toggleWatchlist(m)
              event.accepted = true
              return
            }
            var n = "1234".indexOf(event.text)
            if (n >= 0 && event.text !== "") { root.setTab(root.tabs[n].key); event.accepted = true }
          }

          // Rail: desktop only.
          Rectangle {
            id: rail
            visible: !root.compact
            width: root.compact ? 0 : 212
            height: parent.height
            color: root.ui.surface
            radius: card.radius

            // Square where it meets the content.
            Rectangle {
              anchors.right: parent.right
              width: card.radius
              height: parent.height
              color: parent.color
            }

            Column {
              id: railColumn
              anchors.fill: parent
              anchors.topMargin: 18
              anchors.leftMargin: 12
              anchors.rightMargin: 12
              spacing: 2

              Row {
                x: 6
                height: 44
                spacing: 10
                Mark { anchors.verticalCenter: parent.verticalCenter; size: 28 }
                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  Text {
                    text: "Couch"
                    color: root.ui.text
                    font.family: root.ui.font
                    font.pixelSize: 19
                    font.weight: Font.Bold
                  }
                  Text {
                    text: "for Trakt"
                    color: root.ui.muted
                    font.family: root.ui.font
                    font.pixelSize: root.ui.fs.xs
                  }
                }
              }
              Item { width: 1; height: 12 }

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
                    visible: railItem.index < 4
                    text: railItem.index + 1
                    color: root.ui.muted
                    font.family: root.ui.font
                    font.pixelSize: root.ui.fs.xs
                  }
                  // A gap between the tabs and the extras.
                  Rectangle {
                    visible: railItem.index === root.tabs.length
                    y: -6
                    x: 8
                    width: parent.width - 16
                    height: 1
                    color: root.ui.divider
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

            // Who is signed in, at the foot of the rail -- when the window is
            // tall enough for it below the sections, not over them.
            Rectangle {
              id: who
              visible: rail.height >= 18 + railColumn.childrenRect.height + height + 24
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 12
              x: 12
              width: parent.width - 24
              height: 52
              radius: root.ui.radius
              color: whoMouse.containsMouse ? root.ui.hover : "transparent"
              Avatar {
                id: whoAvatar
                x: 8
                anchors.verticalCenter: parent.verticalCenter
                app: root
                size: 32
                source: root.store.user ? root.store.user.avatar || "" : ""
                name: root.store.user ? root.store.user.username || "" : ""
              }
              Column {
                anchors.left: whoAvatar.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                  width: parent.width
                  text: root.store.signedIn ? (root.store.user ? root.store.user.name || root.store.user.username : "Signed in") : "Sign in"
                  color: root.ui.text
                  font.family: root.ui.font
                  font.pixelSize: root.ui.fs.sm
                  font.weight: Font.DemiBold
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  text: root.store.signedIn ? (root.store.user ? "@" + root.store.user.username : "") : "Sync your watchlist"
                  color: root.ui.muted
                  font.family: root.ui.font
                  font.pixelSize: root.ui.fs.xs
                  elide: Text.ElideRight
                }
              }
              MouseArea {
                id: whoMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openSettings()
              }
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
              id: header
              width: parent.width
              height: root.compact ? 56 : 64

              IconButton {
                id: headerBack
                x: 4
                anchors.verticalCenter: parent.verticalCenter
                visible: root.compact && root.railExtras.some(function (e) { return e.key === root.tab })
                width: visible ? implicitWidth : 0
                app: root
                glyph: G.back
                label: "Back"
                onClicked: if (!root.back()) root.dismiss()
              }
              Text {
                anchors.left: headerBack.visible ? headerBack.right : parent.left
                anchors.leftMargin: headerBack.visible ? 4 : (root.compact ? 16 : 24)
                anchors.right: headerActions.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.titleText()
                color: root.ui.text
                font.family: root.ui.font
                font.pixelSize: root.compact ? 22 : 24
                font.weight: Font.Bold
                elide: Text.ElideRight
              }
              Row {
                id: headerActions
                anchors.right: parent.right
                anchors.rightMargin: root.compact ? 4 : 12
                anchors.verticalCenter: parent.verticalCenter
                IconButton {
                  visible: root.compact && root.tab !== "search"
                  app: root
                  glyph: G.search
                  label: "Search"
                  onClicked: root.setTab("search")
                }
                IconButton {
                  visible: root.compact && root.tab !== "history" && root.store.signedIn
                  app: root
                  glyph: G.history
                  label: "History"
                  onClicked: root.setTab("history")
                }
                Item {
                  visible: root.compact && root.tab !== "settings"
                  width: root.ui.target
                  height: root.ui.target
                  Avatar {
                    anchors.centerIn: parent
                    visible: root.store.signedIn
                    app: root
                    size: 28
                    ground: root.ui.bg
                    source: root.store.user ? root.store.user.avatar || "" : ""
                    name: root.store.user ? root.store.user.username || "" : ""
                  }
                  Icon {
                    anchors.centerIn: parent
                    visible: !root.store.signedIn
                    app: root
                    text: G.settings
                    size: 20
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openSettings()
                  }
                }
              }
            }

            Rectangle {
              id: banner
              anchors.top: header.bottom
              width: parent.width
              // A file problem outranks a network one: it loses data.
              readonly property string message: store.warning || trakt.banner || trakt.signedOutMessage
                || (!trakt.configured ? "No Trakt app is set up yet · add one in Settings" : "")
              height: visible ? (store.warning ? 44 : 30) : 0
              visible: message !== ""
              color: store.warning ? root.alpha(root.ui.heart, 0.2)
                : trakt.waitSeconds > 0 || !trakt.configured ? root.alpha(root.ui.warn, 0.18) : root.ui.surfaceHigh
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
              MouseArea {
                anchors.fill: parent
                enabled: trakt.signedOutMessage !== "" || !trakt.configured
                onClicked: { trakt.signedOutMessage = ""; root.openSettings() }
              }
            }

            Item {
              id: views
              anchors.top: banner.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom

              DiscoverView { id: discoverView; anchors.fill: parent; app: root; visible: root.tab === "discover" }
              UpNextView { id: upNextView; anchors.fill: parent; app: root; visible: root.tab === "upnext" }
              CalendarView { id: calendarView; anchors.fill: parent; app: root; visible: root.tab === "calendar" }
              WatchlistView { id: watchlistView; anchors.fill: parent; app: root; visible: root.tab === "watchlist" }
              SearchView { id: searchView; anchors.fill: parent; app: root; visible: root.tab === "search" }
              HistoryView { id: historyView; anchors.fill: parent; app: root; visible: root.tab === "history" }
              SettingsView { id: settingsView; anchors.fill: parent; app: root; visible: root.tab === "settings" }
            }

            // A movie or show: over the whole of this side, header included.
            Loader {
              id: detailLoader
              active: root.page !== null
              z: 3
              width: parent.width
              height: root.compact ? keys.height : parent.height
              sourceComponent: Component {
                DetailView {
                  app: root
                  seed: root.page ? root.page.item : null
                }
              }
            }
          }

          // Tabs: phone only, and not under a page.
          Rectangle {
            id: nav
            visible: root.compact && root.page === null
            anchors.bottom: parent.bottom
            width: parent.width
            height: visible ? 64 : 0
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
                    y: 8
                    width: 60
                    height: 30
                    radius: 15
                    color: navItem.current ? root.ui.accentSoft : navMouse.pressed ? root.ui.pressed : "transparent"
                  }
                  Icon {
                    app: root
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 8
                    height: 30
                    text: navItem.modelData.glyph
                    size: 20
                    color: navItem.current ? root.ui.accent : root.ui.muted
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 41
                    text: navItem.modelData.label
                    color: navItem.current ? root.ui.text : root.ui.muted
                    font.family: root.ui.font
                    font.pixelSize: root.ui.fs.xs
                    font.weight: navItem.current ? Font.DemiBold : Font.Normal
                  }
                  MouseArea {
                    id: navMouse
                    anchors.fill: parent
                    onClicked: {
                      // Tapping the tab you are on scrolls it back to the top.
                      if (navItem.current) { var v = root.currentView(); if (v && v.list) v.list.toTop() }
                      root.setTab(navItem.modelData.key)
                    }
                  }
                }
              }
            }
          }

          // A short word about what just happened.
          Rectangle {
            id: toastBox
            z: 20
            anchors.horizontalCenter: main.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: (nav.visible ? nav.height : 0) + 16
            width: Math.min(toastLabel.implicitWidth + 36, main.width - 32)
            height: 40
            radius: 20
            color: root.ui.dark ? "#f2f2f2" : "#1f1f1f"
            opacity: root.toastText !== "" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Text {
              id: toastLabel
              anchors.centerIn: parent
              width: Math.min(implicitWidth, parent.width - 24)
              text: root.toastText
              color: root.ui.dark ? "#111111" : "#f5f5f5"
              font.family: root.ui.font
              font.pixelSize: root.ui.fs.sm
              font.weight: Font.DemiBold
              elide: Text.ElideRight
            }
          }
        }
      }
    }
  }
}
