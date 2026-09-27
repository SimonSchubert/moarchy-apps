import QtQuick
import Quickshell
import Quickshell.Io
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G
import "Facts.js" as F
import "Store.js" as S

// Food: point the camera at a barcode, and Open Food Facts answers with the
// name, the Nutri-Score, the table and the allergens.
//
//     omarchy-shell shell toggle org.moarchy.food
//
// Two pages: Scan, the camera, which is the job; History, the jobs already
// done. There is no typed barcode -- a code enters this app through the
// camera or not at all, and a missing camera is an empty state that says so.
//
// The camera is a helper process (Scanner.qml, libexec/moarchy-food-scan),
// running only while the scan page is on screen. A lookup is one curl of
// /api/v2/product/{code}; the history and the last answer for each code are
// 0.1.0's two files, so an upgrade keeps what was scanned, and a row opens on
// facts in a shop with no signal.
//
// A phone gets the two pages as tabs and a product as a page over them; a
// desktop gets the tabs in the rail and the product in a pane beside the
// camera or the history.
App {
  id: root

  appId: "org.moarchy.food"
  title: "Food"
  subtitle: fetching ? "Looking up…" : offline ? "Offline · Open Food Facts" : "Open Food Facts"
  caption: "Open Food Facts"
  windowWidth: 1180
  windowHeight: 800

  store: Store { name: "moarchy-food" }

  launcher.desktopId: "org.moarchy.Food"
  launcher.genericName: "Food facts"
  launcher.comment: "Point the camera at a barcode for nutrition facts"
  launcher.categories: "Utility;"
  launcher.keywords: "food;nutrition;barcode;scan;camera;nutriscore;nova;allergens;ingredients;openfoodfacts;"

  mark: Component { Image { source: root.appDir + "/icon.svg"; sourceSize: Qt.size(60, 60) } }

  ui: Tokens {
    theme: root.hostTheme
    compact: root.compact
    // Nutri-Score A is the theme's green, E its red, and the three between
    // walk the hues a theme already names -- 0.1.0's choice, over the
    // official traffic lights: the theme's yellow is the one that is still
    // yellow after `omarchy-theme-set`, and the letter is on the badge for
    // everybody who cannot tell green from red anyway.
    readonly property color gradeA: hue("green", "#4ade80", "#16a34a")
    readonly property color gradeB: hue("cyan", "#22d3ee", "#0891b2")
    readonly property color gradeC: hue("yellow", "#facc15", "#ca8a04")
    readonly property color gradeD: hue("orange", "#fb923c", "#ea580c")
    readonly property color gradeE: hue("red", "#f87171", "#dc2626")
    function gradeHue(letter) {
      switch (letter) {
      case "a": return gradeA
      case "b": return gradeB
      case "c": return gradeC
      case "d": return gradeD
      default: return gradeE
      }
    }
    // A wash of the hue under the theme's own text colour, so the letter
    // reads in every theme rather than white on yellow vanishing on a light
    // one.
    function gradeFill(letter) { return Qt.tint(bg, alpha(gradeHue(letter), 0.38)) }
  }

  tabs: [
    { key: "scan", label: "Scan", glyph: G.scan },
    { key: "history", label: "History", glyph: G.history }
  ]

  settings: Component {
    SettingsPage {
      app: root
      blurb: "Point the camera at a barcode: nutrition facts from Open Food Facts."
      AppearanceSection { app: root }
      LauncherSection { app: root }
      KeysSection {
        app: root
        keys: [
          ["1  2", "Scan, History"],
          ["s", "Scan"],
          ["/", "Search the history"],
          ["↑ ↓  Enter", "Move through the history, open a product"],
          ["Delete", "Remove the product from the history"],
          [",", "Settings"],
          ["Esc", "Back one step"]
        ]
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "What leaves this computer"
        note: "One HTTPS request to world.openfoodfacts.org per scan, with nothing in it but the barcode and a User-Agent naming this app, and a second for the front-of-pack picture of the product on screen. No account and no key. The camera runs only while the Scan page is showing."
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Where it keeps things"
        note: "~/.local/share/moarchy-food: history.json, the barcodes you scanned, and products.json, the last answer for each -- public data, nothing about what you ate. Pictures are cached in ~/.cache/moarchy-food."
      }
    }
  }

  // A product, or a barcode the catalogue does not have, as a page over the
  // tab on a phone: { kind: "product" | "missing", code }.
  page: Component {
    Item {
      Loader {
        anchors.fill: parent
        active: root.topPage !== null && root.topPage.kind === "product"
        sourceComponent: ProductView {
          app: root
          paged: true
          product: root.topPage ? root.book.products[root.topPage.code] || null : null
          image: root.topPage ? root.imagePath(root.topPage.code) : ""
          onRemoved: root.forget(root.topPage.code)
        }
      }
      Loader {
        anchors.fill: parent
        active: root.topPage !== null && root.topPage.kind === "missing"
        sourceComponent: Item {
          PageHeader { id: missingHead; app: root; width: parent.width; title: "Not found"; subtitle: root.topPage ? root.topPage.code : "" }
          MissingState { app: root; anchors.top: missingHead.bottom; anchors.bottom: parent.bottom; width: parent.width; code: root.topPage ? root.topPage.code : "" }
        }
      }
    }
  }

  // ------------------------------------------------------------ state

  property var book: S.fresh()
  readonly property var recent: S.recent(book)
  readonly property var shown: S.filter(recent, historyList.query)

  property bool fetching: false
  property string fetchingCode: ""
  property real retryAt: 0

  // The product in the pane on a desktop: { kind, code }, or null.
  property var selection: null
  readonly property bool split: contentArea.width >= 820
  property int current: -1

  // MOARCHY_FOOD_OFFLINE: never open a socket -- the cache, and nothing
  // else. MOARCHY_FOOD_SCAN_ONLY: say the code, look nothing up.
  readonly property bool offline: (Quickshell.env("MOARCHY_FOOD_OFFLINE") || "") !== ""
  readonly property bool scanOnly: (Quickshell.env("MOARCHY_FOOD_SCAN_ONLY") || "") !== ""

  readonly property bool scanning: opened && tab === "scan" && topPage === null && !inSettings && !fetching

  // Beside the camera or the list when there is room, over it when not.
  function show(entry) {
    resetFocus()
    if (split) selection = entry
    else push(entry)
    if (entry.kind === "product") fetchImage(entry.code)
  }

  onSplitChanged: {
    if (!split && selection) {
      var entry = selection
      selection = null
      push(entry)
    } else if (split && topPage) {
      selection = topPage
      stack = []
    }
  }

  // ------------------------------------------------------------ a scan

  function scanned(code) {
    if (scanOnly) { toast(code); return }
    if (fetching) return
    var cached = book.products[code]
    if (offline) {
      if (!cached) { toast("No network, and this barcode is not in the cache"); return }
      remember(cached)
      show({ kind: "product", code: code })
      return
    }
    if (retryAt && Date.now() / 1000 < retryAt) {
      if (cached) { show({ kind: "product", code: code }); return }
      toast("Open Food Facts asked this app to wait a minute")
      return
    }
    fetching = true
    fetchingCode = code
    fetcher.command = F.command(code)
    fetcher.running = true
  }

  function arrived(exitCode) {
    var code = fetchingCode
    fetching = false
    var got = F.answer(exitCode, fetchOut.text, fetchErr.text, code)
    if (got.product) {
      remember(got.product)
      show({ kind: "product", code: got.product.code })
      return
    }
    if (got.error.missing) { show({ kind: "missing", code: code }); return }
    if (got.error.retry) retryAt = Date.now() / 1000 + got.error.retry
    // A product from this morning is worth something: open it and say why.
    if (book.products[code]) {
      show({ kind: "product", code: code })
      toast(got.error.message + " This is the last answer.")
    } else {
      toast(got.error.message)
    }
  }

  Process {
    id: fetcher
    running: false
    stdout: StdioCollector { id: fetchOut; waitForEnd: true }
    stderr: StdioCollector { id: fetchErr; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { root.arrived(code) }
    // qmllint enable signal-handler-parameters
  }

  // Written the moment a lookup succeeds, before the page is pushed: the next
  // thing that happens to a phone app is usually being killed.
  function remember(product) {
    book = S.remember(book, product)
    save()
  }

  function forget(code) {
    book = S.forget(book, code)
    save()
    if (selection && selection.code === code) selection = null
    stack = stack.filter(function (e) { return e.code !== code })
    toast("Removed from the history")
  }

  function save() {
    historyFile.save(S.serializeHistory(book))
    productsFile.save(S.serializeProducts(book))
  }

  // ------------------------------------------------------------ pictures

  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/moarchy-food"
  // The pictures on disk, by code: listed once, added to as they land. A
  // page names a file only when it is there.
  property var pictures: ({})
  property bool picturesListed: false
  function imagePath(code) { return pictures[code] ? cacheDir + "/" + code + ".jpg?" + pictures[code] : "" }

  // The front-of-pack thumbnail, once a session per product, to a file the
  // page reads. Offline, the file from last time is shown if there is one.
  property var imagesAsked: ({})
  function fetchImage(code) {
    var p = book.products[code]
    if (offline || !p || !F.httpImage(p.image_url) || !/^[0-9]+$/.test(code)) return
    if (imagesAsked[code] || imager.running) return
    var asked = Object.assign({}, imagesAsked)
    asked[code] = true
    imagesAsked = asked
    imager.code = code
    imager.command = ["sh", "-c", "mkdir -p -- \"$1\" && shift && exec \"$@\"", "sh", cacheDir]
      .concat(F.imageCommand(p.image_url, cacheDir + "/" + code + ".jpg"))
    imager.running = true
  }

  Process {
    id: imager
    property string code: ""
    running: false
    // qmllint disable signal-handler-parameters
    onExited: function (exitCode, status) {
      if (exitCode !== 0) return
      var have = Object.assign({}, root.pictures)
      have[imager.code] = (have[imager.code] || 0) + 1
      root.pictures = have
    }
    // qmllint enable signal-handler-parameters
  }

  Process {
    id: lister
    running: false
    command: ["sh", "-c", "ls -1 -- \"$1\" 2>/dev/null; true", "sh", root.cacheDir]
    stdout: StdioCollector { id: listOut; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (exitCode, status) {
      var have = Object.assign({}, root.pictures)
      var names = listOut.text.split("\n")
      for (var i = 0; i < names.length; i++) {
        var m = names[i].match(/^([0-9]+)\.jpg$/)
        if (m && !have[m[1]]) have[m[1]] = 1
      }
      root.pictures = have
    }
    // qmllint enable signal-handler-parameters
  }
  onOpenedChanged: if (opened && !picturesListed) { picturesListed = true; lister.running = true }

  // ------------------------------------------------------------ the files

  property bool historyRead: false
  property bool productsRead: false
  property var pendingHistory: []

  DataFile {
    id: historyFile
    app: "food"
    name: "history.json"
    onParsed: function (d) {
      root.pendingHistory = S.parseHistory(d)
      root.historyRead = true
      root.merge()
    }
    onQuarantined: function (to) { root.toast("The history was unreadable and was kept aside") }
  }

  DataFile {
    id: productsFile
    app: "food"
    name: "products.json"
    property var parsedData: ({ products: ({}), fetched: ({}) })
    onParsed: function (d) {
      parsedData = S.parseProducts(d)
      root.productsRead = true
      root.merge()
    }
  }

  function merge() {
    if (!historyRead || !productsRead) return
    var next = { history: pendingHistory, products: productsFile.parsedData.products, fetched: productsFile.parsedData.fetched }
    if (S.serializeHistory(next) === S.serializeHistory(book) && S.serializeProducts(next) === S.serializeProducts(book)) return
    book = next
    harness()
  }

  // ------------------------------------------------------------ keys

  stepBack: function () {
    if (historyList.query !== "") { historyList.query = ""; return true }
    if (selection && split) { selection = null; return true }
    return false
  }

  keyHandler: function (event) {
    if (topPage || inSettings) return
    var k = event.key
    if (k === Qt.Key_Delete && selection && selection.kind === "product") { forget(selection.code); event.accepted = true; return }
    if (tab === "history") {
      var n = shown.length
      if (k === Qt.Key_Down || k === Qt.Key_Up) {
        if (!n) return
        current = Math.max(0, Math.min(n - 1, current + (k === Qt.Key_Down ? 1 : -1)))
        historyList.show(current)
        if (split) show({ kind: "product", code: shown[current].code })
        event.accepted = true
        return
      }
      if ((k === Qt.Key_Return || k === Qt.Key_Enter) && current >= 0 && current < n) {
        show({ kind: "product", code: shown[current].code })
        event.accepted = true
        return
      }
      if (k === Qt.Key_Delete && current >= 0 && current < n) { forget(shown[current].code); event.accepted = true; return }
    }
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    if (event.text === "s") { setTab("scan"); event.accepted = true; return }
    if (event.text === "/") {
      setTab("history")
      Qt.callLater(historyList.focusField)
      event.accepted = true
    }
  }

  onTabSelected: current = -1

  // ------------------------------------------------------------ harness

  // MOARCHY_FOOD_PAGE (scan, history, product, missing) and MOARCHY_FOOD_CODE:
  // straight onto the screen a screenshot is of.
  property bool harnessed: false
  function harness() {
    if (harnessed) return
    harnessed = true
    var page = Quickshell.env("MOARCHY_FOOD_PAGE") || ""
    var code = Quickshell.env("MOARCHY_FOOD_CODE") || ""
    if (page === "history") setTab("history")
    if (page === "missing") {
      Qt.callLater(function () { root.show({ kind: "missing", code: code || "0000000000000" }) })
    } else if (page === "product" || (page === "history" && code)) {
      var target = code && book.products[code] ? code : (recent.length ? recent[0].code : "")
      if (target) Qt.callLater(function () { root.show({ kind: "product", code: target }) })
    }
  }

  IpcHandler {
    target: "food"
    // As if the camera had read it.
    function scan(code: string): string { root.scanned(F.normalize(code) || code); return "ok" }
    function history(): string { return root.book.history.join(",") }
    function remove(code: string): string { root.forget(code); return "ok" }
    function scanning(): bool { return root.scanning }
    function settled(): bool { return !root.fetching }
    function close(): string { root.dismiss(); return "ok" }
  }

  // ------------------------------------------------------------ views

  Item {
    anchors.fill: parent

    Item {
      id: left
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: root.split ? Math.min(560, Math.max(400, parent.width * 0.5)) : parent.width

      Scanner {
        anchors.fill: parent
        anchors.margins: root.compact ? 0 : root.ui.gutter
        anchors.topMargin: root.compact ? 0 : 4
        visible: root.tab === "scan"
        app: root
        active: root.scanning
        busyTitle: root.fetching ? "Looking up" : ""
        busyText: "Open Food Facts is answering for " + root.fetchingCode + "."
        onScanned: function (code) { root.scanned(code) }
      }

      HistoryList {
        id: historyList
        anchors.fill: parent
        visible: root.tab === "history"
        app: root
        items: root.shown
        selected: root.split && root.selection ? root.selection.code : ""
        current: root.tab === "history" ? root.current : -1
        onQueryChanged: root.current = -1
        onOpened: function (code) { root.show({ kind: "product", code: code }) }
      }
    }

    // The pane: a product, a barcode the catalogue lacks, or what to do.
    Rectangle {
      visible: root.split
      anchors.left: left.right
      anchors.leftMargin: 8
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.rightMargin: root.ui.gutter
      anchors.bottomMargin: root.ui.gutter
      anchors.topMargin: 4
      radius: root.ui.radius + 4
      color: root.ui.surface
      border.width: 1
      border.color: root.ui.divider

      readonly property var product: root.selection && root.selection.kind === "product" ? root.book.products[root.selection.code] || null : null

      ProductView {
        anchors.fill: parent
        visible: parent.product !== null
        app: root
        product: parent.product
        image: root.selection ? root.imagePath(root.selection.code) : ""
        onRemoved: root.forget(root.selection.code)
        onClosed: root.selection = null
      }
      MissingState {
        app: root
        anchors.fill: parent
        visible: root.selection !== null && root.selection.kind === "missing"
        code: root.selection ? root.selection.code : ""
      }
      EmptyState {
        anchors.centerIn: parent
        visible: root.selection === null
        app: root
        glyph: G.food
        title: root.tab === "scan" ? "Point at a barcode" : "Pick a product"
        text: root.tab === "scan"
          ? "The name, the Nutri-Score, the table per 100 g and the allergens appear here."
          : "Its grades, its table per 100 g, its allergens and what is in it."
      }
    }
  }
}
