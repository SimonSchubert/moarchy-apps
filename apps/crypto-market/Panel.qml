import QtQuick
import Quickshell
import "Api.mjs" as Api
import "Theme.js" as Theme

// Crypto Market: CoinGecko's markets, coin pages, watchlist and a portfolio,
// as an app.
//
//     omarchy-shell shell toggle io.github.simonschubert.crypto-market
//
// An ordinary window, tiled, focused and closed like any other app, and laid
// out from its own size: a rail of sections on the left, with the coin page
// beside the list when there is room, and a phone app -- tabs at the bottom,
// pages that stack -- when it is narrow, as on Omarchy Mobile, where the
// window is the whole screen. Escape (the phone's back) steps out one level
// at a time.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  // True when shell.qml runs it as its own process, with no Omarchy shell.
  property bool standalone: false

  // ------------------------------------------------------------ tokens

  readonly property bool compact: stage.width < 720
  readonly property string currency: store.currency

  // For the screenshots (scripts/app-shot.sh, dev/shots), all inert unset.
  // MOARCHY_CRYPTO_MARKET_OFFLINE: never open a socket -- answers come from
  // the fixture.json dev/demo.py left in MOARCHY_CRYPTO_MARKET_DIR (Gecko).
  // MOARCHY_CRYPTO_MARKET_NOW: a frozen clock, in seconds, so what was
  // recorded then is fresh now. MOARCHY_CRYPTO_MARKET_LOGOS: a folder of
  // logos by URL, in place of the logo cache (LogoCache).
  // MOARCHY_CRYPTO_MARKET_PAGE: the tab to open on, over the one saved; a
  // coin page is CRYPTO_MARKET_PAYLOAD='{"coin":"bitcoin"}', as bin/ passes it.
  readonly property bool offline: (Quickshell.env("MOARCHY_CRYPTO_MARKET_OFFLINE") || "") !== ""
  readonly property real pinnedNow: (parseFloat(Quickshell.env("MOARCHY_CRYPTO_MARKET_NOW") || "0") || 0) * 1000
  readonly property string harnessDir: Quickshell.env("MOARCHY_CRYPTO_MARKET_DIR") || ""
  readonly property string harnessPage: Quickshell.env("MOARCHY_CRYPTO_MARKET_PAGE") || ""
  // MOARCHY_CRYPTO_MARKET_RANGE: the chart's range on a coin page (1, 7, 30,
  // 90, 365, max) in place of 7 days.
  readonly property string harnessRange: Quickshell.env("MOARCHY_CRYPTO_MARKET_RANGE") || ""
  function now() { return pinnedNow > 0 ? pinnedNow : Date.now() }
  property real clock: now()

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function luminance(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }

  // Omarchy's theme: the shell's inside it, its theme files outside it, a
  // plain palette where there is neither.
  HostTheme { id: theme }
  Component.onCompleted: theme.probe(root)

  // Every hex colour the app draws with is here, as the theme's fallback.
  readonly property var ui: QtObject {
    readonly property bool dark: root.luminance(theme.background) < 0.5
    readonly property color bg: theme.background
    readonly property color text: theme.text
    // A theme's muted is sometimes its border colour, too faint for a
    // caption: then the text, faded.
    readonly property color muted: Theme.mutedReads(theme.muted, theme.background)
      ? theme.muted : Qt.tint(bg, root.alpha(text, 0.62))
    readonly property color accent: theme.accent
    readonly property color border: theme.border
    readonly property color surface: Qt.tint(bg, root.alpha(text, dark ? 0.06 : 0.04))
    readonly property color surfaceHigh: Qt.tint(bg, root.alpha(text, dark ? 0.12 : 0.08))
    // No hover on a touch screen: a finger leaves the last row it lifted from
    // looking pointed at.
    readonly property color hover: root.compact ? "transparent" : root.alpha(text, 0.06)
    readonly property color pressed: root.alpha(text, 0.12)
    readonly property color selected: root.alpha(accent, 0.14)
    readonly property color accentSoft: root.alpha(accent, 0.16)
    readonly property color divider: root.alpha(text, 0.08)
    // A price's direction in the theme's own green and red where it has
    // them and they read as green and red; the plain pair where it does not
    // (Lumon's "red" is a blue, White's a grey).
    readonly property color up: Theme.tone(theme.hue("green"), "green", bg, dark ? "#34d399" : "#15803d")
    readonly property color down: Theme.tone(theme.hue("red"), "red", bg, dark ? "#f87171" : "#dc2626")
    readonly property color upSoft: root.alpha(up, 0.15)
    readonly property color downSoft: root.alpha(down, 0.15)
    readonly property color star: Theme.tone(theme.hue("yellow"), "yellow", bg, dark ? "#f5b82e" : "#c98a06")
    readonly property color scrim: "#000000"
    // The allocation bar: the accent, then the colours of the coins most
    // portfolios start with, then a grey for the rest.
    readonly property var series: [accent, "#f7931a", "#627eea", "#14f195", "#e84142", "#8c8c8c"]
    readonly property string font: theme.fontFamily
    readonly property int radius: Math.max(6, Math.min(12, theme.cornerRadius))
    readonly property int target: root.compact ? 44 : 38
    readonly property int chip: root.compact ? 36 : 32
    readonly property QtObject fs: QtObject {
      readonly property int xs: 11
      readonly property int sm: 13
      readonly property int md: 14
      readonly property int lg: 17
      readonly property int xxl: root.compact ? 28 : 32
    }
  }

  // ------------------------------------------------------------ state

  readonly property var tabs: [
    { key: "markets", label: "Markets", glyph: "󰄪" },
    { key: "watchlist", label: "Watchlist", glyph: "󰓒" },
    { key: "discover", label: "Discover", glyph: "󰈸" },
    { key: "portfolio", label: "Portfolio", glyph: "󰯝" }
  ]
  readonly property var railExtras: [
    { key: "search", label: "Search", glyph: "󰍉" },
    { key: "settings", label: "Settings", glyph: "󰢻" }
  ]

  property string tab: "markets"
  // Pages over the current tab: { kind: "coin", id, seed } or
  // { kind: "category", id, name }.
  property var stack: []
  property bool picking: false
  property bool txOpen: false

  readonly property var page: stack.length ? stack[stack.length - 1] : null
  readonly property var category: {
    for (var i = stack.length - 1; i >= 0; i--) if (stack[i].kind === "category") return stack[i]
    return null
  }
  readonly property string openCoinId: page && page.kind === "coin" ? page.id : ""
  readonly property bool split: !compact && main.width >= 960 && openCoinId !== ""

  function setTab(key) {
    resetFocus()
    if (key !== "search") picking = false
    stack = []
    tab = key
    if (key !== "search" && key !== "settings") store.set("lastTab", key)
    Qt.callLater(function () { root.refresh(false); keys.forceActiveFocus() })
  }

  // Take focus back from any text field left behind. On a phone a focused
  // field is a raised keyboard, and a keyboard over a coin page nobody is
  // typing on is in the way.
  function resetFocus() { keys.forceActiveFocus() }

  function openCoin(coin) {
    if (!coin || !Api.safeId(coin.id)) return
    resetFocus()
    var page = { kind: "coin", id: coin.id, seed: coin }
    var s = stack.slice()
    // Coin to coin replaces rather than piles up: back from a coin goes to
    // the list it was picked from, not through every coin looked at.
    if (s.length && s[s.length - 1].kind === "coin") s[s.length - 1] = page
    else s.push(page)
    stack = s
  }

  function openCategory(id, name) {
    resetFocus()
    stack = [{ kind: "category", id: id, name: name }]
  }

  function startPick() {
    resetFocus()
    picking = true
    stack = []
    tab = "search"
  }

  function startTx(coin) {
    if (!coin) return
    sheet.reset(coin)
    txOpen = true
    sheet.focusAmount()
  }

  // One step out: the sheet, the page, the tab, then nothing. True when it
  // stepped. On a phone the gesture bar calls this directly and hides the
  // panel itself when it answers false, so at the root it must not also
  // close; Escape from a keyboard closes there instead (see Keys below).
  function back() {
    resetFocus()
    if (txOpen) { txOpen = false; return true }
    if (stack.length) { var s = stack.slice(); s.pop(); stack = s; return true }
    if (picking) { picking = false; tab = "portfolio"; return true }
    if (tab !== "markets") { setTab("markets"); return true }
    return false
  }

  // Refresh what is on screen. Everything else waits until it is looked at.
  function refresh(force) {
    if (!opened) return
    var v = currentView()
    if (v && v.refresh) v.refresh(force)
    var detail = detailLoader.item as DetailView
    if (detail) detail.refresh(force)
  }

  function currentView() {
    if (category && categoryLoader.item) return categoryLoader.item
    switch (tab) {
    case "watchlist": return watchlistView
    case "discover": return discoverView
    case "portfolio": return portfolioView
    case "search": return searchView
    case "settings": return settingsView
    }
    return marketsView
  }

  function agoText(ms) {
    if (!isFinite(ms)) return ""
    var s = Math.round(ms / 1000)
    if (s < 10) return "just now"
    if (s < 60) return s + " s ago"
    if (s < 3600) return Math.round(s / 60) + " min ago"
    return Math.round(s / 3600) + " h ago"
  }

  function titleText() {
    if (category) return category.name
    if (tab === "search") return picking ? "Add to portfolio" : "Search"
    if (tab === "settings") return "Settings"
    for (var i = 0; i < tabs.length; i++) if (tabs[i].key === tab) return tabs[i].label
    return "Crypto Market"
  }

  // ------------------------------------------------------------ host API

  function open(payloadJson) {
    theme.reload()
    opened = true
    window.visible = true
    var p = null
    try { p = typeof payloadJson === "string" && payloadJson ? JSON.parse(payloadJson) : payloadJson } catch (e) { p = null }
    if (p && Api.safeId(p.coin)) openCoin({ id: p.coin })
    Qt.callLater(function () { keys.forceActiveFocus(); root.refresh(false) })
  }

  // From the host (`shell hide`, the keybinding). The window goes without
  // telling the host back: it already knows.
  property bool closingFromHost: false
  function close() {
    txOpen = false
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
    var id = manifest && manifest.id ? manifest.id : "io.github.simonschubert.crypto-market"
    if (shell && typeof shell.hide === "function") shell.hide(id)
    else close()
  }

  // ------------------------------------------------------------ plumbing

  Store {
    id: storeObj
    onReadyChanged: {
      if (!ready) return
      var t = root.harnessPage || prefs.lastTab
      if (["markets", "watchlist", "discover", "portfolio"].indexOf(t) >= 0) root.tab = t
      else if (t === "search" || t === "settings") root.setTab(t)
      root.refresh(false)
    }
    onSnapshotLoaded: function (text) { geckoObj.restoreText(text) }
  }

  Gecko {
    id: geckoObj
    apiKey: storeObj.apiKey
    currency: storeObj.currency
    sealed: root.offline
    fixturePath: root.offline && root.harnessDir ? root.harnessDir + "/fixture.json" : ""
    pinnedNow: root.pinnedNow
  }

  LogoCache {
    id: logosObj
    app: root
    dir: storeObj.cacheDir + "/logos"
    fixed: Quickshell.env("MOARCHY_CRYPTO_MARKET_LOGOS") || ""
  }

  LauncherEntry {
    id: launcherObj
    app: root
    pluginId: root.manifest && root.manifest.id ? root.manifest.id : "io.github.simonschubert.crypto-market"
  }

  // Aliases for the views, which reach everything through `app`.
  readonly property alias store: storeObj
  readonly property alias gecko: geckoObj
  readonly property alias logos: logosObj
  readonly property alias launcher: launcherObj

  Timer {
    interval: 15000
    repeat: true
    running: root.opened
    onTriggered: { root.clock = root.now(); root.refresh(false) }
  }

  onCurrencyChanged: Qt.callLater(function () { root.refresh(false) })
  // Written when the app closes, not while it is in use: the stringify of a
  // few hundred kilobytes is a hitch nobody should feel mid-scroll.
  onOpenedChanged: if (!opened) store.saveSnapshot(gecko.snapshot(["markets", "global", "trending", "categories"], 8))

  // ------------------------------------------------------------ window

  // Shown and hidden by open() and close(), not bound to `opened`: the window
  // manager closes it too, and a binding would fight that.
  FloatingWindow {
    id: window
    visible: false
    title: "Crypto Market"
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
            var v = root.currentView()
            var list = v && v.list ? v.list : null
            var detail = detailLoader.item as DetailView
            var k = event.key
            // One step back; at the top there is nothing to leave -- an app
            // window is closed by the window manager, not by Escape.
            if (k === Qt.Key_Escape || k === Qt.Key_Back) { root.back(); event.accepted = true; return }
            if (root.txOpen) return
            if (k === Qt.Key_Down && list) { event.accepted = list.moveCursor(1); return }
            if (k === Qt.Key_Up && list) { event.accepted = list.moveCursor(-1); return }
            if ((k === Qt.Key_Return || k === Qt.Key_Enter) && list) { event.accepted = list.activateCurrent(); return }
            if ((k === Qt.Key_Left || k === Qt.Key_Right) && detail) { detail.stepRange(k === Qt.Key_Left ? -1 : 1); event.accepted = true; return }
            if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
            if (event.text === "/") { root.setTab("search"); Qt.callLater(searchView.focusField); event.accepted = true; return }
            if (event.text === "r") { root.refresh(true); event.accepted = true; return }
            if (event.text === "f") {
              var c = detail && !root.split ? { id: detail.coinId } : list && list.currentCoin ? list.currentCoin() : null
              if (!c && detail) c = { id: detail.coinId }
              if (c) root.store.toggleStar(c.id)
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
            width: root.compact ? 0 : 200
            height: parent.height
            color: root.ui.surface
            // Rounded where it meets the card's corners, square where it
            // meets the list.
            radius: card.radius

            Rectangle {
              anchors.right: parent.right
              width: card.radius
              height: parent.height
              color: parent.color
            }

            Column {
              id: railColumn
              anchors.fill: parent
              anchors.topMargin: 16
              anchors.leftMargin: 10
              anchors.rightMargin: 10
              spacing: 2

              Row {
                x: 8
                height: 44
                spacing: 8
                Icon { app: root; anchors.verticalCenter: parent.verticalCenter; text: "󰠟"; size: 22; color: root.ui.accent }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Crypto Market"
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
                  readonly property bool current: root.tab === modelData.key && !root.category
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
              id: railFooter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 14
              x: 18
              width: parent.width - 36
              // Only where it fits under the sections, not over them.
              visible: rail.height > 16 + 64 + (root.tabs.length + root.railExtras.length) * 42 + implicitHeight + 40
              wrapMode: Text.Wrap
              text: "Data by CoinGecko\n/ search · f star · r refresh · Esc back"
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

            // List side: header, banner, the tab's view.
            Item {
              id: listSide
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: root.split ? Math.max(460, parent.width * 0.46) : parent.width

              Item {
                id: header
                width: parent.width
                height: 56

                IconButton {
                  id: headerBack
                  x: 4
                  anchors.verticalCenter: parent.verticalCenter
                  visible: !!root.category || root.picking || (root.compact && (root.tab === "search" || root.tab === "settings"))
                  width: visible ? implicitWidth : 0
                  app: root
                  glyph: "󰁍"
                  label: "Back"
                  onClicked: if (!root.back()) root.dismiss()
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
                  // Category names run long ("Smart Contract Platform"):
                  // smaller before shorter.
                  fontSizeMode: Text.HorizontalFit
                  minimumPixelSize: 14
                  elide: Text.ElideRight
                }
                Row {
                  id: headerActions
                  anchors.right: parent.right
                  anchors.rightMargin: 4
                  anchors.verticalCenter: parent.verticalCenter
                  IconButton {
                    visible: root.compact && root.tab !== "search"
                    app: root
                    glyph: "󰍉"
                    label: "Search"
                    onClicked: root.setTab("search")
                  }
                  IconButton {
                    visible: root.compact && root.tab !== "settings"
                    app: root
                    glyph: "󰢻"
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
                readonly property string message: store.warning || gecko.banner
                height: visible ? (store.warning ? 44 : 30) : 0
                visible: message !== ""
                color: store.warning ? root.alpha(root.ui.down, 0.2)
                  : gecko.waitSeconds > 0 ? root.alpha(root.ui.star, 0.18) : root.ui.surfaceHigh
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

                MarketsView { id: marketsView; anchors.fill: parent; app: root; visible: root.tab === "markets" && !root.category }
                WatchlistView { id: watchlistView; anchors.fill: parent; app: root; visible: root.tab === "watchlist" && !root.category }
                DiscoverView { id: discoverView; anchors.fill: parent; app: root; visible: root.tab === "discover" && !root.category }
                PortfolioView { id: portfolioView; anchors.fill: parent; app: root; visible: root.tab === "portfolio" && !root.category }
                SearchView { id: searchView; anchors.fill: parent; app: root; picking: root.picking; visible: root.tab === "search" && !root.category }
                SettingsView { id: settingsView; anchors.fill: parent; app: root; visible: root.tab === "settings" && !root.category }

                Loader {
                  id: categoryLoader
                  anchors.fill: parent
                  active: !!root.category
                  sourceComponent: Component {
                    MarketsView {
                      app: root
                      category: root.category ? root.category.id : ""
                      categoryName: root.category ? root.category.name : ""
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

            // The coin page: over everything on a phone or a narrow card,
            // beside the list when the card is wide enough.
            Loader {
              id: detailLoader
              active: root.openCoinId !== ""
              z: 3
              x: root.split ? listSide.width + 1 : 0
              y: 0
              width: root.split ? parent.width - listSide.width - 1 : parent.width
              height: root.compact ? keys.height : parent.height
              sourceComponent: Component {
                DetailView {
                  app: root
                  pane: root.split
                  coinId: root.openCoinId
                  seed: root.page && root.page.kind === "coin" ? root.page.seed : null
                }
              }
            }
          }

          // Tabs: phone only, and not under a coin page.
          Rectangle {
            id: nav
            visible: root.compact && root.openCoinId === ""
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
                  readonly property bool current: root.tab === modelData.key && !root.category
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

          TxSheet {
            id: sheet
            anchors.fill: parent
            z: 10
            visible: root.txOpen
            app: root
            onDone: { root.resetFocus(); root.txOpen = false; if (root.picking) { root.picking = false; root.setTab("portfolio") } }
          }
        }

      }
    }
  }
}
