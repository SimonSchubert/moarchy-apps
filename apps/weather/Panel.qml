import QtQuick
import Quickshell
import Quickshell.Io
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G
import "Forecast.js" as Forecast
import "Store.js" as Places

// Weather: one place, one screen, seven days.
//
//     omarchy-shell shell toggle org.moarchy.weather
//     omarchy-shell weather refresh
//
// The screen is in the order the question is asked. What is it doing now, in
// the biggest type on the screen. What is it doing for the rest of today, as a
// strip of hours. What is it doing this week, as seven rows with a bar each.
//
// The places are the towns somebody typed, and the first of them is wherever
// the computer is, looked up from its connection's address. On a phone they
// are a page of their own, reached by the pin in the header; on a desktop they
// are a list beside the forecast, so switching towns is one click.
//
// Nothing is fetched with the window shut. The last forecast is in memory and
// in the cache file, so the answer is on screen before the network is asked.
App {
  id: root

  appId: "org.moarchy.weather"
  title: "Weather"
  heading: root.place ? root.place.name : ""
  subtitle: freshnessText()
  windowWidth: 1180
  windowHeight: 800

  store: Store { name: "moarchy-weather" }

  launcher.desktopId: "org.moarchy.Weather"
  launcher.genericName: "Weather forecast"
  launcher.comment: "Now, the next day and the week, where you are and in the places you named"
  launcher.categories: "Utility;"
  launcher.keywords: "weather;forecast;temperature;rain;wind;"

  mark: Component { Image { source: root.appDir + "/icon.svg"; sourceSize: Qt.size(60, 60) } }

  ui: Tokens {
    theme: root.hostTheme
    compact: root.compact
    // Rain, snow and the bolt's cloud in the theme's blue; the bolt itself
    // and the sun's glint in its yellow.
    readonly property color rain: hue("blue", "#60a5fa", "#2563eb")
    readonly property color sun: hue("yellow", "#facc15", "#ca8a04")
  }

  // The temperature bands, coldest to hottest, in the theme's own hues.
  readonly property var bands: ({
    cyan: ui.hue("cyan", "#22d3ee", "#0891b2"),
    blue: ui.hue("blue", "#60a5fa", "#2563eb"),
    green: ui.hue("green", "#4ade80", "#16a34a"),
    yellow: ui.hue("yellow", "#facc15", "#ca8a04"),
    orange: ui.hue("orange", "#fb923c", "#ea580c"),
    red: ui.hue("red", "#f87171", "#dc2626")
  })
  function tempColour(celsius) { return bands[Forecast.band(celsius)] || ui.accent }

  actions: Component {
    Row {
      spacing: 2
      Item {
        width: root.ui.target
        height: root.ui.target
        visible: root.busy
        Spinner { app: root; anchors.centerIn: parent; size: 20; running: root.busy }
      }
      IconButton {
        visible: !root.busy && !!root.place
        app: root
        glyph: KG.refresh
        label: "Refresh the forecast"
        onClicked: root.refresh()
      }
      IconButton {
        visible: root.compact
        app: root
        glyph: G.places
        label: "Places"
        onClicked: root.showPlaces()
      }
    }
  }

  // The places, on a phone.
  page: Component {
    Item {
      PageHeader { id: placesHead; app: root; width: parent.width; title: "Places" }
      PlacesView {
        id: placesPage
        app: root
        anchors.top: placesHead.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
      }
    }
  }

  settings: Component {
    SettingsPage {
      app: root
      blurb: "Open-Meteo's forecast for wherever you are and the places you named."
      SettingsSection {
        app: root
        width: parent.width
        title: "Units"
        Row {
          spacing: 8
          Chip { app: root; text: "°C, km/h"; selected: root.units === "metric"; onClicked: root.setUnits("metric") }
          Chip { app: root; text: "°F, mph"; selected: root.units === "imperial"; onClicked: root.setUnits("imperial") }
        }
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Where you are"
        note: "Looked up from this connection’s address, by GeoJS. It finds a town, not a street — and on mobile data, not always yours."
        Toggle {
          app: root
          width: parent.width
          text: "Show where I am"
          checked: root.locate
          onToggled: function (on) { root.setLocate(on) }
        }
      }
      AppearanceSection { app: root }
      LauncherSection { app: root }
      KeysSection {
        app: root
        keys: [
          ["r", "Refresh the forecast"],
          ["/", "Find a town"],
          ["↑ ↓", "The place above or below"],
          [",", "Settings"],
          ["Esc", "Back one step"]
        ]
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Where the numbers come from"
        note: "Open-Meteo, which needs no account and no key, every fifteen minutes at most and only while the window is open. The town list and the last forecast are in ~/.local/share/moarchy-weather."
      }
    }
  }

  // ------------------------------------------------------------ what is known

  property var places: []
  property string currentId: ""
  property string units: "metric"
  // Whether to ask where the computer is, and the last answer: a place with a
  // `found` stamp, or null. Never a guess, and never a town kept after
  // somebody said not to look.
  property bool locate: true
  property var here: null
  // placeId -> { fetched, forecast }, so switching towns draws the last thing
  // known about the new one rather than a blank screen.
  property var cache: ({})

  property double now: Date.now()
  property bool offline: false
  property string harnessUnits: ""
  // The clock, pinned, for the screenshots: a picture taken at nine in the
  // evening and one taken at noon disagree about the sky.
  property real pinnedNow: 0

  property string query: ""
  property var results: []
  property bool finding: false
  property bool searched: false

  property bool fetching: false
  property string trouble: ""
  property int failures: 0
  property real retryAt: 0
  property bool dirty: false

  property bool locating: false
  property string lost: ""
  property int lostCount: 0
  property real locateRetryAt: 0
  // No lookup until both files are read: the setting that says not to look is
  // in one and the last answer is in the other.
  property bool placesRead: false
  property bool cacheRead: false

  readonly property var backoff: [60, 150, 300, 600]
  readonly property real nowSec: now / 1000
  // Everything but the age in the header changes on the hour.
  readonly property real hourStart: Math.floor(nowSec / 3600) * 3600

  readonly property var place: currentId === Places.HERE ? here : Places.find(places, currentId)
  readonly property var entry: place ? (cache[place.id] || null) : null
  readonly property var forecast: entry ? entry.forecast : null
  readonly property real fetched: entry ? entry.fetched : 0
  readonly property int zoneOffset: forecast ? forecast.offset : 0
  readonly property bool busy: fetching || (locating && currentId === Places.HERE)
  // Whether there is anything the weather screen could show.
  readonly property bool somewhere: places.length > 0 || locate

  readonly property var reading: Forecast.readingAt(forecast, hourStart)
  readonly property var hours: Forecast.nextHours(forecast, hourStart, Forecast.STRIP_HOURS)
  readonly property var week: Forecast.days(forecast, hourStart)
  readonly property var todayRow: Forecast.today(forecast, hourStart)
  readonly property var range: Forecast.span(week)
  readonly property var tiles: Forecast.facts(reading, todayRow, zoneOffset, units)

  function freshnessText() {
    if (!place) return locating ? "Finding where you are…" : "Nowhere yet"
    if (busy) return "Updating…"
    if (fetched <= 0) return trouble ? trouble : "No forecast yet"
    var age = Math.max(0, nowSec - fetched)
    if (failures) return "Not updating · " + Forecast.freshness(age)
    return "Updated " + Forecast.freshness(age)
  }

  // A place's current temperature, clock and sky from the cache -- never a
  // fetch: a list of twelve towns that fetches twelve forecasts to draw
  // itself is a data bill for a screen somebody is passing through.
  function tempAt(id) {
    var e = cache[id]
    if (!e) return ""
    var r = Forecast.readingAt(e.forecast, hourStart)
    return r ? Forecast.temperature(r.temp, units) : ""
  }
  function clockAt(id) {
    var e = cache[id]
    return e ? Forecast.clock(nowSec, e.forecast.offset) : ""
  }
  function glyphAt(id) {
    var e = cache[id]
    if (!e) return ""
    var r = Forecast.readingAt(e.forecast, hourStart)
    return r ? Forecast.glyph(r.code, r.day) : ""
  }

  // ------------------------------------------------------------ the harness

  function clockNow() { return pinnedNow > 0 ? pinnedNow * 1000 : Date.now() }

  Component.onCompleted: {
    offline = (Quickshell.env("MOARCHY_WEATHER_OFFLINE") || "") !== ""
    var pinned = parseInt(Quickshell.env("MOARCHY_WEATHER_NOW") || "0", 10)
    pinnedNow = pinned > 0 ? pinned : 0
    now = clockNow()
    var u = Quickshell.env("MOARCHY_WEATHER_UNITS") || ""
    harnessUnits = u.length ? Places.units(u) : ""
  }

  // ------------------------------------------------------------ open and shut

  onSummoned: {
    now = clockNow()
    var page = Quickshell.env("MOARCHY_WEATHER_PAGE") || ""
    // The search is the one screen a harness cannot reach by tapping.
    var search = Quickshell.env("MOARCHY_WEATHER_SEARCH") || ""
    if (search.length) { query = search; Qt.callLater(runSearch) }
    if (page === "places" || search.length) wantPlaces = true
    if (page === "settings") setTab("settings")
    Qt.callLater(showPlacesIfWanted)
    Qt.callLater(maybeFetch)
  }

  // The places are a page on a phone and always showing on a desktop, and in
  // the first frame the window's width is not known yet.
  property bool wantPlaces: false
  function showPlacesIfWanted() {
    if (!wantPlaces || !opened) return
    if (compact) { wantPlaces = false; showPlaces() }
  }
  onCompactChanged: showPlacesIfWanted()

  readonly property bool placesShowing: !compact || (topPage !== null && topPage.kind === "places")
  function showPlaces() {
    if (compact && !(topPage && topPage.kind === "places")) push({ kind: "places" })
  }

  // The cache is written as the window goes: that is the event before the app
  // is reclaimed on a phone. Not per fetch -- a write onto flash every quarter
  // of an hour for a file whose purpose is the next cold start.
  onOpenedChanged: if (!opened) saveCache()

  stepBack: function () {
    if (query !== "") { query = ""; results = []; searched = false; return true }
    return false
  }

  keyHandler: function (event) {
    if (inSettings) return
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    if (event.text === "r") { refresh(); event.accepted = true; return }
    if (event.text === "/") {
      showPlaces()
      Qt.callLater(function () { root.focusSearch() })
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
      stepPlace(event.key === Qt.Key_Down ? 1 : -1)
      event.accepted = true
    }
  }

  // The search field asks for the keys itself; this is how `/` reaches it,
  // wherever the places list is drawn.
  signal searchWanted()
  function focusSearch() { searchWanted() }

  // The place above or below, in the list's order: here first, then saved.
  function stepPlace(by) {
    var ids = (locate && here ? [Places.HERE] : []).concat(places.map(function (p) { return p.id }))
    if (!ids.length) return
    var i = ids.indexOf(currentId)
    var next = ids[Math.max(0, Math.min(ids.length - 1, (i < 0 ? 0 : i + by)))]
    if (next !== currentId) selectPlace(next)
  }

  // ------------------------------------------------------------ the places

  function placesState() {
    return { places: places, current: currentId, units: units, locate: locate }
  }

  function apply(next) {
    places = next.places
    locate = next.locate
    currentId = next.current
    units = next.units
    placesFile.save(Places.serializePlaces(next))
  }

  function addPlace(p) {
    var result = Places.add(placesState(), p)
    if (result.full) { toast(Places.MAX_PLACES + " places is as many as this app keeps"); return }
    apply(result.state)
    query = ""
    results = []
    searched = false
    if (compact && topPage) pop()
    if (!result.added) toast(p.name + " is already on the list")
  }

  function removePlace(id) {
    apply(Places.remove(placesState(), id))
    // Dropped from the cache at the next write, which only keeps places that
    // still exist.
    dirty = true
  }

  function selectPlace(id) {
    apply(Places.select(placesState(), id))
    if (compact && topPage) pop()
  }

  function setUnits(name) { apply(Places.withUnits(placesState(), name)) }

  function setLocate(on) {
    apply(Places.withLocate(placesState(), on))
    lost = ""
    lostCount = 0
    locateRetryAt = 0
    if (!on && here) {
      // Off is forgotten, not hidden.
      here = null
      dirty = true
    }
  }

  // ------------------------------------------------------------ the network

  function curl(url) {
    return ["curl", "-sS", "--max-time", String(Forecast.TIMEOUT),
            "-H", "User-Agent: " + Forecast.AGENT,
            "-H", "Accept: application/json",
            "-w", "\n%{http_code}", url]
  }

  // The status code curl wrote on the last line, and the body without it.
  function split(payload) {
    var text = String(payload || "")
    var cut = text.lastIndexOf("\n")
    return {
      status: cut >= 0 ? parseInt(text.slice(cut + 1).trim(), 10) : 0,
      body: cut >= 0 ? text.slice(0, cut) : text
    }
  }

  function due() {
    if (offline || fetching || !place) return false
    // About to ask where the computer is: the forecast waits for the answer.
    if (currentId === Places.HERE && (locating || locateDue())) return false
    if (retryAt && nowSec < retryAt) return false
    if (fetched <= 0) return true
    return (nowSec - fetched) >= Forecast.refreshAfter()
  }

  // Only while the window is up: the cache write's own reload must not ask
  // the network a question with nothing on screen to show the answer on.
  function maybeFetch() {
    if (!opened) return
    if (locateDue()) findHere(false)
    if (due()) fetch(false)
  }

  // The button and `omarchy-shell weather refresh`. For wherever the computer
  // is, that is where first, then the weather there.
  function refresh() {
    if (currentId === Places.HERE && locate && !offline) findHere(true)
    else fetch(true)
  }

  function fetch(manual) {
    if (fetching || !place) return
    if (offline) { if (manual) toast("This run is offline"); return }
    fetching = true
    fetcher.manual = !!manual
    // Which place the answer belongs to, remembered at the moment of asking.
    fetcher.want = place.id
    fetcher.command = curl(Forecast.url(place.lat, place.lon))
    fetcher.running = true
  }

  function arrived(code, payload) {
    fetching = false
    var manual = fetcher.manual
    var want = fetcher.want
    if (code !== 0) { failed("No answer from Open-Meteo.", 0, manual); return }
    var answer = split(payload)
    if (answer.status === 429) { failed("Open-Meteo is rate-limiting this connection.", Forecast.RATE_LIMIT_S, manual); return }
    if (answer.status >= 500) { failed("Open-Meteo is having trouble.", 0, manual); return }
    if (answer.status !== 200) { failed("Open-Meteo refused the request (" + answer.status + ").", 0, manual); return }
    var parsed = Forecast.parseForecast(answer.body, nowSec)
    if (parsed.error) { failed(parsed.error, 0, manual); return }
    failures = 0
    retryAt = 0
    trouble = ""
    cache = Places.put(cache, want, parsed.forecast, clockNow() / 1000)
    dirty = true
    // The town on screen may have changed while this was out.
    Qt.callLater(maybeFetch)
  }

  function failed(message, retry, manual) {
    failures += 1
    var wait = retry || backoff[Math.min(failures - 1, backoff.length - 1)]
    retryAt = clockNow() / 1000 + wait
    trouble = message
    // A forecast from twenty minutes ago is worth more than a blank screen.
    if (manual || !forecast) toast(message)
  }

  function saveCache() {
    if (!dirty) return
    cacheFile.save(Places.serializeCache(cache, places, here))
    dirty = false
  }

  // ------------------------------------------------------------ where it is

  // Asked only when the answer would be on screen.
  function locateDue() {
    if (offline || !locate || locating) return false
    if (!placesRead || !cacheRead) return false
    if (currentId !== Places.HERE && !placesShowing) return false
    if (locateRetryAt && nowSec < locateRetryAt) return false
    if (!here) return true
    return (nowSec - here.found) >= Forecast.LOCATE_S
  }

  function findHere(manual) {
    if (offline || !locate) return
    if (locating) { if (manual) locator.manual = true; return }
    locating = true
    locator.manual = !!manual
    locator.command = curl(Forecast.LOCATE)
    locator.running = true
  }

  function located(code, payload) {
    locating = false
    var manual = locator.manual
    // Switched off while the question was out: dropped unread.
    if (!locate) return
    if (code !== 0) { lostHere("No answer from GeoJS.", 0, manual); return }
    var answer = split(payload)
    if (answer.status === 429) { lostHere("GeoJS is rate-limiting this connection.", Forecast.RATE_LIMIT_S, manual); return }
    if (answer.status !== 200) { lostHere("GeoJS refused the request (" + answer.status + ").", 0, manual); return }
    var parsed = Forecast.parseLocation(answer.body)
    if (parsed.error) { lostHere(parsed.error, 0, manual); return }
    var found = parsed.place
    found.found = clockNow() / 1000
    lostCount = 0
    locateRetryAt = 0
    lost = ""
    here = found
    dirty = true
    thenTheWeather(manual)
  }

  function lostHere(message, retry, manual) {
    lostCount += 1
    var wait = retry || backoff[Math.min(lostCount - 1, backoff.length - 1)]
    locateRetryAt = clockNow() / 1000 + wait
    lost = message
    // The last town found is still the best answer there is.
    if (manual && !here) toast(message)
    thenTheWeather(manual)
  }

  function thenTheWeather(manual) {
    if (manual && currentId === Places.HERE) fetch(true)
    else Qt.callLater(maybeFetch)
  }

  // ------------------------------------------------------------ finding a town

  function typed(text) {
    query = text
    searched = false
    if (query.trim().length < 2) results = []
    else debounce.restart()
  }

  function runSearch() {
    var needle = query.trim()
    if (needle.length < 2) { results = []; searched = false; return }
    if (offline) { toast("This run is offline"); return }
    // One request at a time: waiting a beat is cheaper than killing a curl
    // that is about to answer the question being retyped.
    if (finding) { debounce.restart(); return }
    finding = true
    finder.command = curl(Forecast.searchUrl(needle))
    finder.running = true
  }

  function found(code, payload) {
    finding = false
    searched = true
    if (code !== 0) { toast("No answer from Open-Meteo"); return }
    var answer = split(payload)
    if (answer.status !== 200) { toast("Open-Meteo refused the search (" + answer.status + ")"); return }
    var parsed = Forecast.parseSearch(answer.body)
    if (parsed.error) { toast(parsed.error); return }
    results = parsed.places
  }

  // ------------------------------------------------------------ plumbing

  // Half a minute: the only thing that changes between ticks is the age in
  // the header, and a clock that wakes the processor more often than it has
  // anything to say shows up in a battery graph.
  Timer {
    interval: 30000
    repeat: true
    running: root.opened
    onTriggered: {
      root.now = root.clockNow()
      root.maybeFetch()
    }
  }

  Timer {
    id: debounce
    interval: 350
    onTriggered: root.runSearch()
  }

  Process {
    id: fetcher
    property bool manual: false
    property string want: ""
    running: false
    stdout: StdioCollector { id: fetchOut; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { root.arrived(code, fetchOut.text) }
    // qmllint enable signal-handler-parameters
  }

  Process {
    id: locator
    property bool manual: false
    running: false
    stdout: StdioCollector { id: locateOut; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { root.located(code, locateOut.text) }
    // qmllint enable signal-handler-parameters
  }

  Process {
    id: finder
    running: false
    stdout: StdioCollector { id: findOut; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { root.found(code, findOut.text) }
    // qmllint enable signal-handler-parameters
  }

  DataFile {
    id: placesFile
    app: "weather"
    name: "places.json"
    onParsed: function (data) {
      var s = Places.parsePlaces(data)
      root.places = s.places
      root.locate = s.locate
      if (!root.locate) root.here = null
      root.currentId = s.current
      root.units = root.harnessUnits.length ? root.harnessUnits : s.units
      root.placesRead = true
      // Nowhere to show the weather of: open on the page that fixes it.
      if (!root.places.length && !root.locate) root.wantPlaces = true
      Qt.callLater(root.showPlacesIfWanted)
      Qt.callLater(root.maybeFetch)
    }
    onQuarantined: function (to) { root.toast("The places file was unreadable and was kept aside") }
  }

  DataFile {
    id: cacheFile
    app: "weather"
    name: "forecast.json"
    onParsed: function (data) {
      var cached = Places.parseCache(data)
      var merged = root.cache
      // Only where nothing fresher has already arrived.
      for (var id in cached) {
        var mine = merged[id]
        if (mine && mine.fetched >= cached[id].fetched) continue
        merged = Places.put(merged, id, cached[id].forecast, cached[id].fetched)
      }
      root.cache = merged
      var disk = Places.parseHere(data)
      if (root.locate && disk && (!root.here || root.here.found < disk.found)) root.here = disk
      root.cacheRead = true
      Qt.callLater(root.maybeFetch)
    }
    onQuarantined: function (to) { root.toast("The cached forecast was unreadable and was kept aside") }
  }

  onCurrentIdChanged: Qt.callLater(maybeFetch)
  onPlacesShowingChanged: Qt.callLater(maybeFetch)

  IpcHandler {
    target: "weather"
    function refresh(): string { root.refresh(); return "ok" }
    function place(): string { return root.place ? root.place.name : "" }
    function temperature(): string {
      return root.reading ? Forecast.temperature(root.reading.temp, root.units) : ""
    }
  }

  // ------------------------------------------------------------ the screen

  // Desktop: the places beside the forecast.
  Rectangle {
    id: side
    visible: !root.compact
    width: visible ? 300 : 0
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.leftMargin: root.ui.gutter
    anchors.bottomMargin: root.ui.gutter
    radius: root.ui.radius
    color: root.ui.surface
    border.width: 1
    border.color: root.ui.line
    PlacesView {
      anchors.fill: parent
      anchors.margins: 4
      app: root
      visible: side.visible
    }
  }

  ForecastView {
    anchors.left: side.visible ? side.right : parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    app: root
  }
}
