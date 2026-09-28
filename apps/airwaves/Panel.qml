import QtQuick
import Quickshell
import Quickshell.Io
import "Api.mjs" as Api
import "Glyphs.js" as G

// Airwaves: radio stations from all over the world, from the community
// directory at radio-browser.info, as one panel.
//
//     omarchy-shell shell toggle io.github.simonschubert.airwaves
//
// An ordinary window, tiled, focused and closed like any other app, and laid
// out from its own size: a rail of sections on the left and a player along
// the foot when it is wide, and a phone app -- tabs at the bottom, a mini
// player above them, pages that stack -- when it is narrow, as on Omarchy
// Mobile, where the window is the whole screen. Escape (the phone's back)
// steps out one level at a time.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  // True when shell.qml runs it as its own process, with no Omarchy shell.
  property bool standalone: false

  // ------------------------------------------------------------ tokens

  readonly property bool compact: stage.width < 720
  property real clock: pinnedNow || Date.now()

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function luminance(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
  // Text on a filled accent button: dark on a light accent, white otherwise.
  readonly property color onAccent: luminance(tokens.accent) > 0.6 ? "#111111" : "#ffffff"

  // Omarchy's theme: its shell's, or its theme files when Airwaves runs on
  // its own; a plain palette where there is neither.
  HostTheme {
    id: theme
    appearance: storeObj.prefs.appearance || "theme"
  }
  readonly property alias hostTheme: theme
  readonly property bool inShell: theme.inShell
  Component.onCompleted: theme.probe(root)

  readonly property QtObject ui: QtObject {
    id: tokens
    readonly property bool dark: root.luminance(theme.background) < 0.5
    readonly property color bg: theme.background
    readonly property color text: theme.text
    readonly property color muted: theme.muted
    readonly property color accent: theme.accent
    readonly property color border: theme.border
    readonly property color surface: Qt.tint(bg, root.alpha(text, dark ? 0.06 : 0.04))
    readonly property color surfaceHigh: Qt.tint(bg, root.alpha(text, dark ? 0.12 : 0.08))
    // No hover on a touch screen: a finger leaves the last row it lifted
    // from looking pointed at.
    readonly property color hover: root.compact ? "transparent" : root.alpha(text, 0.06)
    readonly property color pressed: root.alpha(text, 0.12)
    readonly property color selected: root.alpha(accent, 0.14)
    readonly property color accentSoft: root.alpha(accent, 0.16)
    readonly property color divider: root.alpha(text, 0.08)
    readonly property color live: dark ? "#f87171" : "#dc2626"
    readonly property color down: dark ? "#f87171" : "#dc2626"
    readonly property color star: "#f5b82e"
    readonly property color warn: "#f59e0b"
    // The card a logo sits on, whatever the theme: logos are drawn for white.
    readonly property color logoCard: "#f7f7f9"
    readonly property color knob: "#ffffff"
    readonly property string font: theme.fontFamily
    readonly property int radius: Math.max(6, Math.min(10, theme.cornerRadius))
    readonly property int target: root.compact ? 44 : 38
    readonly property int chip: root.compact ? 34 : 32
    readonly property QtObject fs: QtObject {
      id: sizes
      readonly property int xs: 11
      readonly property int sm: 13
      readonly property int md: 14
      readonly property int lg: 17
      readonly property int xl: root.compact ? 22 : 28
      readonly property int xxl: root.compact ? 26 : 32
    }
  }

  // ------------------------------------------------------------ state

  readonly property var tabs: [
    { key: "discover", label: "Discover", glyph: G.discover },
    { key: "browse", label: "Browse", glyph: G.browse },
    { key: "favorites", label: "Favourites", glyph: G.favorites },
    { key: "recent", label: "Recent", glyph: G.recent }
  ]
  readonly property var railExtras: [
    { key: "search", label: "Search", glyph: G.search },
    { key: "settings", label: "Settings", glyph: G.settings }
  ]

  property string tab: "discover"
  // Pages over the current tab: { kind: "list", spec } -- a genre, a
  // country, a language -- or { kind: "player" }.
  property var stack: []
  readonly property var page: stack.length ? stack[stack.length - 1] : null

  // The country Discover shows: chosen in Settings, or this computer's.
  readonly property string country: storeObj.prefs.country || Api.localeCountry(Qt.locale().name)
  readonly property string countryName: {
    api.revision
    var list = api.peek(Api.countriesPath()) || []
    for (var i = 0; i < list.length; i++) if (list[i].code === country) return list[i].name
    return country
  }

  readonly property string version: manifest && manifest.version ? manifest.version : ownVersion

  // Stations voted for this session: the directory allows one vote per
  // station and address every ten minutes.
  property var voted: ({})
  property int sleepChoice: 0

  function setTab(key) {
    resetFocus()
    stack = []
    tab = key
    if (tabs.some(function (t) { return t.key === key })) store.set("lastTab", key)
    Qt.callLater(function () { root.refresh(false); keys.forceActiveFocus() })
  }

  function openSettings() { setTab("settings") }

  // Take focus back from any text field left behind. On a phone a focused
  // field is a raised keyboard, and a keyboard over a page nobody is typing
  // on is in the way.
  function resetFocus() { keys.forceActiveFocus() }

  function push(entry) {
    resetFocus()
    var s = stack.slice()
    // Genre to country to language: the way back stays a few steps long.
    if (s.length > 6) s.splice(0, s.length - 6)
    s.push(entry)
    stack = s
  }

  function openList(spec) {
    if (!spec) return
    var top = page
    if (top && top.kind === "list" && top.spec.facet === spec.facet && top.spec.value === spec.value) return
    // From Now Playing, a tag replaces the page rather than stacking over it.
    if (top && top.kind === "player") { var s = stack.slice(); s.pop(); stack = s }
    push({ kind: "list", spec: spec })
  }

  function openPlayer() {
    if (!player.station) return
    if (page && page.kind === "player") return
    push({ kind: "player" })
  }

  // One step out: the page, the tab, then nothing. True when it stepped. On a
  // phone the gesture bar calls this directly and hides the panel itself
  // when it answers false, so at the root it must not also close.
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
    api.want(Api.countriesPath(), "countries", force ? 0 : 86400000, false)
  }

  function currentView() {
    if (pageLoader.item) return pageLoader.item
    switch (tab) {
    case "browse": return browseView
    case "favorites": return favoritesView
    case "recent": return recentView
    case "search": return searchView
    case "settings": return settingsView
    }
    return discoverView
  }

  function titleText() {
    var all = tabs.concat(railExtras)
    for (var i = 0; i < all.length; i++) if (all[i].key === tab) return all[i].label
    return "Airwaves"
  }

  // ------------------------------------------------------------ actions

  function play(s) { player.play(s) }

  // A tap on a station: play it, or -- when it is the one already on air --
  // open Now Playing.
  function activate(s) {
    if (!s) return
    if (player.station && player.station.id === s.id && player.active) openPlayer()
    else play(s)
  }

  function toggleFavorite(s) {
    if (!s || !s.id) return
    toast(store.toggleFavorite(s) ? "Added to favourites" : "Removed from favourites")
  }

  function vote(s) {
    if (!s || !s.id) return
    if (voted[s.id]) { toast("You voted for this station"); return }
    api.vote(s.id, function (ok, message) {
      if (ok) {
        var v = Object.assign({}, root.voted)
        v[s.id] = true
        root.voted = v
        root.toast("Thanks for voting")
      } else {
        root.toast(message || "The vote didn't count")
      }
    })
  }

  function sleep(minutes) {
    sleepChoice = minutes
    player.sleepIn(minutes)
    toast(minutes ? "Stops in " + minutes + " minutes" : "Sleep timer off")
  }

  // Only web pages leave the app, in your browser.
  function openLink(url) {
    var u = Api.webUrl(url)
    if (u) Qt.openUrlExternally(u)
  }

  property string toastText: ""
  function toast(text) {
    toastText = text
    toastTimer.restart()
  }

  // ------------------------------------------------------------ host API

  function open(payloadJson) {
    // A theme switch while the window was away may have replaced the file.
    theme.reload()
    opened = true
    window.visible = true
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

  // Closing from inside -- the close button, the window manager -- goes
  // through the host. Dropping `opened` alone leaves the host counting the
  // panel open, and the next `shell toggle` (the keybinding) would "hide" it
  // and show nothing. The host's hide() calls close() in turn.
  function dismiss() {
    var id = manifest && manifest.id ? manifest.id : "io.github.simonschubert.airwaves"
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
      playerObj.volume = prefs.volume
      playerObj.muted = prefs.muted
      // The last station, ready to play again, but not playing: sound
      // nobody asked for is the worst thing an app can do on opening.
      if (!playerObj.station && prefs.lastStation) playerObj.station = prefs.lastStation
      root.harness()
      root.refresh(false)
    }
    onSnapshotLoaded: function (text) { apiObj.restoreText(text) }
  }

  RadioBrowser {
    id: apiObj
    version: root.version
    recorded: root.offline
    fixtureFile: root.harnessDir ? root.harnessDir + "/fixture.json" : ""
  }

  Player {
    id: playerObj
    app: root
    pretend: root.offline
  }

  Images {
    id: imagesObj
    app: root
    dir: storeObj.cacheDir + "/logos"
    offline: root.offline
    recordedDir: root.imagesDir
  }

  LauncherEntry {
    id: launcherObj
    app: root
    pluginId: root.manifest && root.manifest.id ? root.manifest.id : "io.github.simonschubert.airwaves"
  }

  // The version, for the standalone app: the shell hands the manifest over,
  // shell.qml does not.
  property string ownVersion: ""
  FileView {
    path: String(Qt.resolvedUrl("manifest.json")).replace(/^file:\/\//, "")
    preload: root.manifest === null
    printErrors: false
    onLoaded: {
      try { root.ownVersion = String(JSON.parse(text()).version || "").slice(0, 20) } catch (e) {}
    }
  }

  // Aliases for the views, which reach everything through `app`.
  readonly property alias store: storeObj
  readonly property alias api: apiObj
  readonly property alias player: playerObj
  readonly property alias images: imagesObj
  readonly property alias launcher: launcherObj

  // The greeting and "5 min ago" follow the minute, while somebody looks.
  Timer {
    interval: 60000
    repeat: true
    running: root.opened
    onTriggered: root.clock = root.pinnedNow || Date.now()
  }

  // The sleep timer's countdown, while it is on screen.
  Timer {
    interval: 1000
    repeat: true
    running: root.opened && playerObj.sleepAt > 0 && root.page !== null && root.page.kind === "player"
    onTriggered: root.clock = root.pinnedNow || Date.now()
  }

  Timer {
    id: toastTimer
    interval: 2600
    onTriggered: root.toastText = ""
  }

  // The first mirror is picked on the first open, not at shell start.
  // Written when the app closes, not while it is in use: the stringify of a
  // few hundred kilobytes is a hitch nobody should feel mid-scroll.
  onOpenedChanged: {
    if (opened) { clock = pinnedNow || Date.now(); api.pickServer() }
    else store.saveSnapshot(api.snapshot(["stations", "tags", "countries", "languages", "stats"], 16))
  }

  // A station that could not be played says so once, where you are.
  Connections {
    target: playerObj
    function onFailureChanged() { if (playerObj.failure && root.opened) root.toast(playerObj.failure) }
  }

  // ------------------------------------------------------------ harness

  // For scripts/app-shot.sh, and inert when unset.
  //
  // MOARCHY_AIRWAVES_OFFLINE: no request, no logo download, no sound, and no
  // word about being offline -- lists come from the fixture dev/demo.py put
  // in MOARCHY_AIRWAVES_DIR, a play is shown and never heard, and animations
  // stand still. MOARCHY_AIRWAVES_NOW: a frozen clock (ms), so the greeting
  // and "5 min ago" say the same in two screenshots. MOARCHY_AIRWAVES_IMAGES:
  // the logos dev/capture.py saved, in place of the stations' sites.
  readonly property bool offline: (Quickshell.env("MOARCHY_AIRWAVES_OFFLINE") || "") !== ""
  readonly property real pinnedNow: parseFloat(Quickshell.env("MOARCHY_AIRWAVES_NOW") || "0") || 0
  readonly property string imagesDir: Quickshell.env("MOARCHY_AIRWAVES_IMAGES") || ""
  readonly property string harnessDir: Quickshell.env("MOARCHY_AIRWAVES_DIR") || ""

  // MOARCHY_AIRWAVES_PAGE: a tab (discover, browse, favorites, recent,
  // search, settings), `list` for the stations of MOARCHY_AIRWAVES_TAG, or
  // `player` for Now Playing. MOARCHY_AIRWAVES_SEARCH: what Search asks.
  // MOARCHY_AIRWAVES_PLAYING: the last station, on air -- offline, only
  // shown -- with MOARCHY_AIRWAVES_SONG as the song it says is on.
  function harness() {
    if (Quickshell.env("MOARCHY_AIRWAVES_PLAYING") && playerObj.station) {
      playerObj.play(playerObj.station)
      playerObj.song = Api.clean(Quickshell.env("MOARCHY_AIRWAVES_SONG") || "", 200)
    }
    var page = Quickshell.env("MOARCHY_AIRWAVES_PAGE") || ""
    if (!page) return
    if (tabs.concat(railExtras).some(function (x) { return x.key === page })) {
      tab = page
    } else if (page === "list") {
      var tag = Api.clean(Quickshell.env("MOARCHY_AIRWAVES_TAG") || "jazz", 32).toLowerCase()
      var label = tag
      for (var i = 0; i < Api.GENRES.length; i++) if (Api.GENRES[i].tag === tag) label = Api.GENRES[i].label
      openList({ facet: "tag", value: tag, label: label })
    } else if (page === "player") {
      openPlayer()
    }
    var q = Quickshell.env("MOARCHY_AIRWAVES_SEARCH") || ""
    if (q) { searchView.query = q; searchView.asked = q.trim() }
  }

  // ------------------------------------------------------------ window

  // Shown and hidden by open() and close(), not bound to `opened`: the window
  // manager closes it too, and a binding would fight that.
  FloatingWindow {
    id: window
    visible: false
    title: "Airwaves"
    color: tokens.bg
    implicitWidth: 1240
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
        color: tokens.bg
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
            var v = root.currentView()
            var grid = v && v.list ? v.list : null
            var k = event.key
            if (k === Qt.Key_Escape || k === Qt.Key_Back) { root.back(); event.accepted = true; return }
            if (root.page && root.page.kind === "player" && pageLoader.item) {
              var np = pageLoader.item
              // qmllint disable missing-property
              if (k === Qt.Key_Down || k === Qt.Key_PageDown) { np.scroll(k === Qt.Key_Down ? 80 : 400); event.accepted = true; return }
              if (k === Qt.Key_Up || k === Qt.Key_PageUp) { np.scroll(k === Qt.Key_Up ? -80 : -400); event.accepted = true; return }
              // qmllint enable missing-property
            } else if (grid) {
              if (k === Qt.Key_Down) { event.accepted = grid.move(0, 1); return }
              if (k === Qt.Key_Up) { event.accepted = grid.move(0, -1); return }
              if (k === Qt.Key_Right) { event.accepted = grid.move(1, 0); return }
              if (k === Qt.Key_Left) { event.accepted = grid.move(-1, 0); return }
              if (k === Qt.Key_Return || k === Qt.Key_Enter) { event.accepted = grid.activateCurrent(); return }
            }
            if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
            if (k === Qt.Key_Space) { playerObj.toggle(); event.accepted = true; return }
            if (event.text === "/") { root.setTab("search"); Qt.callLater(searchView.focusField); event.accepted = true; return }
            if (event.text === "r") { root.refresh(true); event.accepted = true; return }
            if (event.text === "n") { root.openPlayer(); event.accepted = true; return }
            if (event.text === "m") { playerObj.setMuted(!playerObj.muted); event.accepted = true; return }
            if (event.text === "+" || event.text === "=") { playerObj.setVolume(playerObj.volume + 5); event.accepted = true; return }
            if (event.text === "-") { playerObj.setVolume(playerObj.volume - 5); event.accepted = true; return }
            if (event.text === "f") {
              var s = grid && grid.currentItem && !(root.page && root.page.kind === "player") ? grid.currentItem() : null
              root.toggleFavorite(s || playerObj.station)
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
            width: root.compact ? 0 : 216
            anchors.top: parent.top
            anchors.bottom: bar.visible ? bar.top : parent.bottom
            color: tokens.surface

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
                Mark { anchors.verticalCenter: parent.verticalCenter; size: 30 }
                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  Text {
                    text: "Airwaves"
                    color: tokens.text
                    font.family: tokens.font
                    font.pixelSize: 19
                    font.weight: Font.Bold
                  }
                  Text {
                    text: "Radio, worldwide"
                    color: tokens.muted
                    font.family: tokens.font
                    font.pixelSize: sizes.xs
                  }
                }
              }
              Item { width: 1; height: 14 }

              Repeater {
                model: root.tabs.concat(root.railExtras)
                delegate: Rectangle {
                  id: railItem
                  required property var modelData
                  required property int index
                  readonly property bool current: root.tab === modelData.key
                  width: parent.width
                  height: 40
                  radius: tokens.radius
                  color: current ? tokens.accentSoft : railMouse.containsMouse ? tokens.hover : "transparent"
                  Row {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 8
                    spacing: 8
                    Icon { app: root; text: railItem.modelData.glyph; size: 18; color: railItem.current ? tokens.accent : tokens.text }
                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: railItem.modelData.label
                      color: railItem.current ? tokens.accent : tokens.text
                      font.family: tokens.font
                      font.pixelSize: sizes.md
                      font.weight: railItem.current ? Font.DemiBold : Font.Normal
                    }
                  }
                  Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    visible: railItem.index < 4
                    text: railItem.index + 1
                    color: tokens.muted
                    font.family: tokens.font
                    font.pixelSize: sizes.xs
                  }
                  // A gap between the tabs and the extras.
                  Rectangle {
                    visible: railItem.index === root.tabs.length
                    y: -6
                    x: 8
                    width: parent.width - 16
                    height: 1
                    color: tokens.divider
                  }
                  MouseArea {
                    id: railMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.setTab(railItem.modelData.key)
                      if (railItem.modelData.key === "search") Qt.callLater(searchView.focusField)
                    }
                  }
                }
              }
            }

            // Where it all comes from, at the foot of the rail -- when there
            // is room below the sections.
            Text {
              visible: rail.height >= 18 + railColumn.childrenRect.height + 60
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 16
              x: 20
              width: parent.width - 40
              wrapMode: Text.Wrap
              text: "Stations from the community directory at radio-browser.info"
              color: root.alpha(tokens.muted, 0.8)
              font.family: tokens.font
              font.pixelSize: sizes.xs
              lineHeight: 1.2
            }
          }

          // Everything right of the rail (all of it, on a phone).
          Item {
            id: main
            anchors.left: rail.visible ? rail.right : parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: mini.visible ? mini.top : nav.visible ? nav.top : bar.visible ? bar.top : parent.bottom

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
              Row {
                anchors.left: headerBack.visible ? headerBack.right : parent.left
                anchors.leftMargin: headerBack.visible ? 4 : (root.compact ? 16 : 26)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Mark {
                  visible: root.compact && root.tab === "discover"
                  anchors.verticalCenter: parent.verticalCenter
                  size: 28
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.compact && root.tab === "discover" ? "Airwaves" : root.titleText()
                  color: tokens.text
                  font.family: tokens.font
                  font.pixelSize: root.compact ? 22 : 24
                  font.weight: Font.Bold
                }
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
                  onClicked: { root.setTab("search"); Qt.callLater(searchView.focusField) }
                }
                IconButton {
                  visible: root.compact && root.tab !== "settings"
                  app: root
                  glyph: G.settings
                  label: "Settings"
                  onClicked: root.openSettings()
                }
              }
            }

            Rectangle {
              id: banner
              anchors.top: header.bottom
              width: parent.width
              // A file problem outranks a network one: it loses data.
              readonly property string message: root.store.warning || root.api.banner
                || (root.player.missing ? "Airwaves plays through mpv, which isn't installed · sudo pacman -S mpv" : "")
              height: visible ? (root.store.warning ? 44 : 30) : 0
              visible: message !== ""
              color: root.store.warning || root.player.missing ? root.alpha(tokens.down, 0.2) : tokens.surfaceHigh
              Text {
                anchors.centerIn: parent
                width: parent.width - 24
                horizontalAlignment: Text.AlignHCenter
                text: banner.message
                color: tokens.text
                font.family: tokens.font
                font.pixelSize: sizes.xs
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

              DiscoverView { id: discoverView; anchors.fill: parent; app: root; visible: root.tab === "discover" }
              BrowseView { id: browseView; anchors.fill: parent; app: root; visible: root.tab === "browse" }
              FavoritesView { id: favoritesView; anchors.fill: parent; app: root; visible: root.tab === "favorites" }
              RecentView { id: recentView; anchors.fill: parent; app: root; visible: root.tab === "recent" }
              SearchView { id: searchView; anchors.fill: parent; app: root; visible: root.tab === "search" }
              SettingsView { id: settingsView; anchors.fill: parent; app: root; visible: root.tab === "settings" }
            }
          }

          // A page -- a list, or Now Playing -- over the whole of the main
          // side, header included; on a phone Now Playing takes the screen.
          Loader {
            id: pageLoader
            z: 3
            active: root.page !== null
            anchors.left: main.left
            anchors.right: main.right
            anchors.top: parent.top
            anchors.bottom: root.page && root.page.kind === "player" && root.compact ? parent.bottom : main.bottom
            sourceComponent: root.page && root.page.kind === "player" ? nowPlaying : listPage
          }
          Component {
            id: listPage
            ListPage { app: root; spec: root.page && root.page.spec ? root.page.spec : ({}) }
          }
          Component {
            id: nowPlaying
            NowPlaying { app: root }
          }

          // Phone: the station on air, above the tabs.
          MiniPlayer {
            id: mini
            z: 4
            visible: root.compact && root.player.station !== null && !(root.page && root.page.kind === "player")
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: nav.visible ? nav.top : parent.bottom
            height: visible ? implicitHeight : 0
            app: root
          }

          // Tabs: phone only, and not under a page.
          Rectangle {
            id: nav
            z: 4
            visible: root.compact && root.page === null
            anchors.bottom: parent.bottom
            width: parent.width
            height: visible ? 64 : 0
            color: tokens.surface

            Rectangle { width: parent.width; height: 1; color: tokens.divider }

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
                    color: navItem.current ? tokens.accentSoft : navMouse.pressed ? tokens.pressed : "transparent"
                  }
                  Icon {
                    app: root
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 8
                    height: 30
                    text: navItem.current && navItem.modelData.key === "favorites" ? G.star : navItem.modelData.glyph
                    size: 20
                    color: navItem.current ? tokens.accent : tokens.muted
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 41
                    text: navItem.modelData.label
                    color: navItem.current ? tokens.text : tokens.muted
                    font.family: tokens.font
                    font.pixelSize: sizes.xs
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

          // Desktop: the player along the foot of the window.
          PlayerBar {
            id: bar
            z: 4
            visible: !root.compact && root.player.station !== null
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: visible ? implicitHeight : 0
            app: root
          }

          // A short word about what just happened.
          Rectangle {
            id: toastBox
            z: 20
            anchors.horizontalCenter: main.horizontalCenter
            anchors.bottom: main.bottom
            anchors.bottomMargin: 16
            width: Math.min(toastLabel.implicitWidth + 36, main.width - 32)
            height: 40
            radius: 20
            color: tokens.dark ? "#f2f2f2" : "#1f1f1f"
            opacity: root.toastText !== "" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Text {
              id: toastLabel
              anchors.centerIn: parent
              width: Math.min(implicitWidth, parent.width - 24)
              text: root.toastText
              color: tokens.dark ? "#111111" : "#f5f5f5"
              font.family: tokens.font
              font.pixelSize: sizes.sm
              font.weight: Font.DemiBold
              elide: Text.ElideRight
            }
          }
        }
      }
    }
  }
}
