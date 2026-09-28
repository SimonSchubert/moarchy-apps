import QtQuick
import Quickshell
import Quickshell.Io
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G
import "Launches.js" as L
import "Store.js" as S

// Launches: the next twenty rocket launches with countdowns, and the ones you
// star. One GET of Launch Library 2 for the whole list, through curl, and only
// while the window is open.
//
//     omarchy-shell shell toggle org.moarchy.launches
//
// The stars and the last answer are the two files the GTK version wrote
// (Store.js), so a launch starred in 0.1.0 is starred here, and an app opened
// with no signal opens on the last countdowns rather than an apology.
//
// The clock ticks once a second only while the window is up, and the pad is
// asked again at most four times an hour -- every five minutes inside an hour
// of a launch, every two inside ten. A refresh that fails keeps the launches
// on screen, says so in the header, and backs off.
//
// A phone gets two tabs at the bottom and a launch as a page over them; a
// desktop gets the tabs in the rail and a launch in a pane beside the list.
App {
  id: root

  appId: "org.moarchy.launches"
  title: "Launches"
  subtitle: freshnessText()
  caption: "From Launch Library 2"
  windowWidth: 1180
  windowHeight: 800

  store: Store { name: "moarchy-launches" }

  launcher.desktopId: "org.moarchy.Launches"
  launcher.genericName: "Launch tracker"
  launcher.comment: "Upcoming rocket launches, and the ones you star"
  launcher.categories: "Science;"
  launcher.keywords: "launch;rocket;spacex;nasa;countdown;space;orbit;pad;ariane;electron;soyuz;"

  mark: Component { Image { source: root.appDir + "/icon.svg"; sourceSize: Qt.size(60, 60) } }

  ui: Tokens {
    theme: root.hostTheme
    compact: root.compact
    // A status is its colour and its mark together: Go is green, a hold and
    // an unconfirmed date yellow, a failure red -- the theme's own, where it
    // names them.
    readonly property color green: hue("green", "#4ade80", "#16a34a")
    readonly property color yellow: hue("yellow", "#facc15", "#ca8a04")
    readonly property color red: hue("red", "#f87171", "#dc2626")
    readonly property color cyan: hue("cyan", "#22d3ee", "#0891b2")
    readonly property color orange: hue("orange", "#fb923c", "#ea580c")
    readonly property color blue: hue("blue", "#60a5fa", "#2563eb")
    readonly property color star: yellow
    function role(name) {
      switch (name) {
      case "green": return green
      case "yellow": return yellow
      case "red": return red
      case "cyan": return cyan
      case "orange": return orange
      default: return blue
      }
    }
    // The countdown's ink: green inside the hour, red once a Go has slipped
    // past its NET, yellow while the date is only a guess.
    function tone(name) {
      switch (name) {
      case "soon": return green
      case "late": return red
      case "wait": return yellow
      default: return muted
      }
    }
  }

  tabs: [
    { key: "upcoming", label: "Upcoming", glyph: G.upcoming },
    { key: "starred", label: "Starred", glyph: KG.star }
  ]

  actions: Component {
    Row {
      spacing: 2
      IconButton {
        visible: !root.offline
        app: root
        glyph: KG.refresh
        label: "Refresh launches"
        active: root.fetching
        onClicked: root.fetch(true)
      }
    }
  }

  settings: Component {
    SettingsPage {
      app: root
      blurb: "The next twenty rocket launches from Launch Library 2, with countdowns, and the ones you star."
      AppearanceSection { app: root }
      LauncherSection { app: root }
      KeysSection {
        app: root
        keys: [
          ["1  2", "Upcoming, Starred"],
          ["/", "Search"],
          ["↑ ↓  Enter", "Move through the list, open a launch"],
          ["s", "Star or unstar the launch"],
          ["r", "Refresh now"],
          [",", "Settings"],
          ["Esc", "Back one step"]
        ]
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Where it comes from"
        note: "One request to Launch Library 2 (ll.thespacedevs.com) for the next twenty, with no key: fifteen calls an hour are allowed per address, so this asks at most every fifteen minutes, and every two when something is about to fly. Set MOARCHY_LAUNCHES_KEY to send a token. Nothing is asked while the window is closed."
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Where it keeps things"
        note: "~/.local/share/moarchy-launches: favourites.json, the launches you starred, and upcoming.json, the last answer, so it opens on countdowns with no signal."
      }
    }
  }

  // A launch as a page over the tab, on a phone: { id }.
  page: Component {
    DetailView {
      app: root
      paged: true
      item: root.topPage ? L.find(root.launches, root.topPage.id) : null
      starred: root.topPage ? root.favourites.indexOf(root.topPage.id) >= 0 : false
      now: root.now
      onStarToggled: if (root.topPage) root.toggleStar(root.topPage.id)
    }
  }

  // ------------------------------------------------------------ state

  property var launches: []
  property var favourites: []
  // Epoch seconds of the last good answer; 0 for never.
  property real fetched: 0
  property bool fetching: false
  property int failures: 0
  property real retryAt: 0
  property string trouble: ""
  // The launches changed since upcoming.json was written.
  property bool dirty: false

  // MOARCHY_LAUNCHES_OFFLINE: never open a socket -- the cache, and nothing
  // else. MOARCHY_LAUNCHES_NOW: a frozen clock, so two screenshots a minute
  // apart agree about the countdown.
  readonly property bool offline: (Quickshell.env("MOARCHY_LAUNCHES_OFFLINE") || "") !== ""
  readonly property real pinnedNow: L.pinned(Quickshell.env("MOARCHY_LAUNCHES_NOW"))
  property real now: pinnedNow || Date.now()

  readonly property var upcomingItems: L.filter(launches, upcomingList.query)
  readonly property var starredItems: L.starred(launches, favourites, starredList.query)
  readonly property var shownItems: tab === "starred" ? starredItems : upcomingItems
  readonly property var shownList: tab === "starred" ? starredList : upcomingList

  // The launch in the pane beside the list, on a desktop.
  property string selectedId: ""
  readonly property bool split: contentArea.width >= 860
  // The keyboard's place in the shown list.
  property int current: -1

  function freshnessText() {
    if (fetching) return "Updating…"
    if (!launches.length) return "No launches yet"
    var age = L.freshness(S.age(fetched, now / 1000))
    if (offline) return "Offline · " + age
    if (failures) return "Not updating · " + age
    return "Updated " + age
  }

  function isStarred(id) { return favourites.indexOf(id) >= 0 }

  function toggleStar(id) {
    var result = S.toggle(favourites, id)
    if (result.full) {
      toast(S.MAX_FAVOURITES + " starred launches is as many as this app keeps")
      return
    }
    favourites = result.favourites
    favFile.save(S.serializeFavourites(favourites))
  }

  // Beside the list when there is room, over it when there is not.
  function openLaunch(id) {
    if (!L.find(launches, id)) return
    resetFocus()
    var i = indexIn(shownItems, id)
    if (i >= 0) current = i
    if (split) selectedId = id
    else push({ id: id })
  }

  function indexIn(list, id) {
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return i
    return -1
  }

  onTabSelected: current = -1

  // A window that narrows with a launch in the pane shows it as a page, and
  // one that widens with a page up shows it in the pane: the launch somebody
  // was looking at stays on the screen either way.
  onSplitChanged: {
    if (!split && selectedId) {
      var id = selectedId
      selectedId = ""
      push({ id: id })
    } else if (split && topPage && topPage.id) {
      selectedId = topPage.id
      stack = []
    }
  }

  // Before the tabs: the search, then the pane.
  stepBack: function () {
    if (shownList.query !== "") { shownList.query = ""; return true }
    if (selectedId && split) { selectedId = ""; return true }
    return false
  }

  keyHandler: function (event) {
    if (topPage || inSettings) return
    var k = event.key
    var n = shownItems.length
    if (k === Qt.Key_Down || k === Qt.Key_Up) {
      if (!n) return
      current = Math.max(0, Math.min(n - 1, current + (k === Qt.Key_Down ? 1 : -1)))
      shownList.show(current)
      if (split && selectedId) selectedId = shownItems[current].id
      event.accepted = true
      return
    }
    if ((k === Qt.Key_Return || k === Qt.Key_Enter) && current >= 0 && current < n) {
      openLaunch(shownItems[current].id)
      event.accepted = true
      return
    }
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    if (event.text === "/") {
      Qt.callLater(shownList.focusField)
      event.accepted = true
      return
    }
    if (event.text === "s") {
      var id = split && selectedId ? selectedId : (current >= 0 && current < n ? shownItems[current].id : "")
      if (id) toggleStar(id)
      event.accepted = true
      return
    }
    if (event.text === "r") { fetch(true); event.accepted = true }
  }

  // ------------------------------------------------------------ the clock

  Timer {
    id: tick
    interval: 1000
    repeat: true
    running: root.opened
    triggeredOnStart: true
    onTriggered: {
      root.now = root.pinnedNow || Date.now()
      if (root.due()) root.fetch(false)
    }
  }

  function due() {
    if (offline || fetching) return false
    if (retryAt && now / 1000 < retryAt) return false
    return S.age(fetched, now / 1000) >= L.refreshAfter(launches, now)
  }

  // ------------------------------------------------------------ the network

  property bool manual: false
  function fetch(byHand) {
    if (offline || fetching) return
    fetching = true
    manual = !!byHand
    fetcher.command = L.command(Quickshell.env("MOARCHY_LAUNCHES_KEY") || "")
    fetcher.running = true
  }

  function arrived(code) {
    fetching = false
    var got = L.answer(code, fetchOut.text, fetchErr.text)
    if (got.error) {
      failures += 1
      var backoff = [60, 150, 300, 600]
      retryAt = Date.now() / 1000 + (got.retry || backoff[Math.min(failures - 1, backoff.length - 1)])
      trouble = got.error
      // A NET from four minutes ago is worth something and a blank page is
      // worth nothing, so the launches already on screen stay.
      if (manual || !launches.length) toast(got.error)
      return
    }
    failures = 0
    retryAt = 0
    trouble = ""
    launches = S.dedupe(got.launches)
    fetched = Date.now() / 1000
    dirty = true
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

  // ------------------------------------------------------------ the files

  DataFile {
    id: favFile
    app: "launches"
    name: "favourites.json"
    onParsed: function (data) { root.favourites = S.parseFavourites(data) }
    onQuarantined: function (to) { root.toast("The starred list was unreadable and was kept aside") }
  }

  DataFile {
    id: cacheFile
    app: "launches"
    name: "upcoming.json"
    onParsed: function (data) {
      var cached = S.parseUpcoming(data)
      // Only while nothing fresher has arrived.
      if (cached.launches.length && cached.fetched >= root.fetched) {
        root.launches = cached.launches
        root.fetched = cached.fetched
        root.harness()
      }
    }
  }

  // Written when the window closes, not on each refresh; and never an empty
  // list over a good one, which would turn "never fetched" into "the pad is
  // empty" on the next start.
  function saveCache() {
    if (!dirty || !launches.length) return
    cacheFile.save(S.serializeUpcoming(launches, fetched))
    dirty = false
  }

  onOpenedChanged: if (!opened) saveCache()
  onQuitting: saveCache()

  // ------------------------------------------------------------ harness

  // MOARCHY_LAUNCHES_PAGE (upcoming, favourites, detail), _SEARCH and _OPEN:
  // straight onto the screen a screenshot is of.
  property bool harnessed: false
  function harness() {
    if (harnessed || !launches.length) return
    harnessed = true
    var page = Quickshell.env("MOARCHY_LAUNCHES_PAGE") || ""
    if (page === "favourites" || page === "starred") setTab("starred")
    var search = Quickshell.env("MOARCHY_LAUNCHES_SEARCH")
    if (search) shownList.query = search
    var open = Quickshell.env("MOARCHY_LAUNCHES_OPEN") || ""
    if (page === "detail" || open) {
      var target = open || launches[0].id
      // The width is not known in the first frame.
      Qt.callLater(function () { root.openLaunch(target) })
    }
  }

  IpcHandler {
    target: "launches"
    function star(id: string): string { root.toggleStar(id); return root.isStarred(id) ? "starred" : "unstarred" }
    function starred(): string { return root.favourites.join(",") }
    function count(): int { return root.launches.length }
    function trouble(): string { return root.trouble }
    function close(): string { root.dismiss(); return "ok" }
  }

  // ------------------------------------------------------------ views

  Item {
    anchors.fill: parent

    Item {
      id: lists
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: root.split ? Math.min(560, Math.max(420, parent.width * 0.48)) : parent.width

      LaunchList {
        id: upcomingList
        anchors.fill: parent
        visible: root.tab === "upcoming"
        app: root
        items: root.upcomingItems
        favourites: root.favourites
        selectedId: root.split ? root.selectedId : ""
        current: root.tab === "upcoming" ? root.current : -1
        now: root.now
        busy: root.fetching && !root.launches.length && query === ""
        emptyGlyph: query !== "" ? KG.search : root.offline ? G.offline : G.rocket
        emptyTitle: query !== "" ? "No match" : "No launches yet"
        emptyText: query !== "" ? "Nothing here is called “" + query + "”."
          : root.trouble !== "" ? root.trouble
          : root.offline ? "This copy is running offline, and has nothing saved to show."
          : "Fetching launches…"
        onQueryChanged: { root.current = -1; toTop() }
        onOpened: function (id) { root.openLaunch(id) }
        onStarToggled: function (id) { root.toggleStar(id) }
      }

      LaunchList {
        id: starredList
        anchors.fill: parent
        visible: root.tab === "starred"
        app: root
        items: root.starredItems
        favourites: root.favourites
        selectedId: root.split ? root.selectedId : ""
        current: root.tab === "starred" ? root.current : -1
        now: root.now
        emptyGlyph: query !== "" ? KG.search : KG.starOutline
        emptyTitle: query !== "" ? "No match"
          : root.favourites.length ? "Your starred launches are not in the last answer" : "Nothing starred"
        emptyText: query !== "" ? "Nothing starred is called “" + query + "”."
          : root.favourites.length ? "They have flown, or they have slipped off the next twenty."
          : "Tap the star beside a launch and it stays on this page until it flies."
        onQueryChanged: { root.current = -1; toTop() }
        onOpened: function (id) { root.openLaunch(id) }
        onStarToggled: function (id) { root.toggleStar(id) }
      }
    }

    // The pane: a launch, or what to do to see one.
    Rectangle {
      visible: root.split
      anchors.left: lists.right
      anchors.leftMargin: 8
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.rightMargin: root.ui.gutter
      anchors.bottomMargin: root.ui.gutter
      radius: root.ui.radius
      color: root.ui.surface
      border.width: 1
      border.color: root.ui.line

      readonly property var shown: root.selectedId ? L.find(root.launches, root.selectedId) : null

      DetailView {
        anchors.fill: parent
        visible: parent.shown !== null
        app: root
        item: parent.shown
        starred: root.isStarred(root.selectedId)
        now: root.now
        onStarToggled: root.toggleStar(root.selectedId)
        onClosed: root.selectedId = ""
      }
      EmptyState {
        anchors.centerIn: parent
        visible: parent.shown === null
        app: root
        glyph: G.rocket
        title: "Pick a launch"
        text: "Its window, pad, orbit, probability and weather, and what it is carrying."
      }
    }
  }
}
