import QtQuick
import Quickshell
import Quickshell.Io
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G
import "Countries.js" as C
import "Quiz.js" as Q
import "Store.js" as S

// Atlas: every country's flag, capital and figures from REST Countries, and a
// flag quiz.
//
//     omarchy-shell shell toggle org.moarchy.atlas
//
// The world is 250 records, asked for as three pages of a hundred with the
// key somebody gave it, and kept for a month in countries.json: browsing and
// the quiz never ask the network anything. The flags are fetched once, in
// one curl, into flags/ beside it, so the quiz works with no signal. Nothing
// is asked while the window is closed.
//
// A phone gets two tabs at the bottom and a country as a page over them; a
// desktop gets the tabs in the rail and a country in a pane beside the grid.
App {
  id: root

  appId: "org.moarchy.atlas"
  title: "Atlas"
  subtitle: freshnessText()
  caption: "From REST Countries"
  windowWidth: 1240
  windowHeight: 820

  store: Store {
    name: "moarchy-atlas"
    defaults: ({ region: "all", sort: "name", quizMode: "flags", quizScope: "world" })
    clean: function (p) {
      if (p.region !== "all" && C.REGIONS.indexOf(p.region) < 0) p.region = "all"
      if (C.SORTS.indexOf(p.sort) < 0) p.sort = "name"
      p.quizMode = Q.mode(p.quizMode).key
      if (p.quizScope !== "world" && C.REGIONS.indexOf(p.quizScope) < 0) p.quizScope = "world"
      return p
    }
  }

  launcher.desktopId: "org.moarchy.Atlas"
  launcher.genericName: "World atlas"
  launcher.comment: "Flags, capitals and facts for every country, and a flag quiz"
  launcher.categories: "Education;Geography;"
  launcher.keywords: "atlas;country;countries;flag;flags;capital;quiz;geography;world;population;"

  mark: Component { Image { source: root.appDir + "/icon.svg"; sourceSize: Qt.size(60, 60) } }

  tabs: [
    { key: "countries", label: "Countries", glyph: G.earth },
    { key: "quiz", label: "Quiz", glyph: G.quiz }
  ]

  actions: Component {
    Row {
      spacing: 2
      IconButton {
        visible: root.countries.length > 0
        app: root
        glyph: G.random
        label: "A country at random"
        onClicked: root.randomCountry()
      }
      IconButton {
        visible: !root.offline && root.key !== ""
        app: root
        glyph: KG.refresh
        label: "Fetch the world again"
        active: root.fetching
        onClicked: root.fetch(true)
      }
    }
  }

  settings: Component {
    SettingsPage {
      app: root
      blurb: "Flags, capitals and facts for every country from REST Countries, and a flag quiz that works offline."
      SettingsSection {
        id: keySection
        app: root
        width: parent.width
        title: "REST Countries key"
        note: root.envKey !== "" ? "Set by MOARCHY_ATLAS_KEY, which wins over anything saved here."
          : root.accountKey !== "" ? "A key is saved. Paste another to replace it."
          : "REST Countries asks for a key. A free account allows 1,000 requests a month; Atlas uses three, once a month."
        TextField {
          id: keyField
          width: parent.width
          app: root
          placeholder: root.accountKey !== "" ? "••••••••" + root.accountKey.slice(-4) : "rc_live_…"
          echoMode: TextInput.Password
          inputHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhSensitiveData
          onAccepted: if (root.saveKey(text)) text = ""
        }
        Flow {
          width: parent.width
          spacing: 8
          Button {
            app: root
            primary: true
            text: "Save key"
            enabled: keyField.text.trim() !== ""
            onClicked: if (root.saveKey(keyField.text)) keyField.text = ""
          }
          Button {
            visible: root.accountKey !== ""
            app: root
            text: "Forget key"
            onClicked: root.forgetKey()
          }
          Button {
            app: root
            glyph: KG.open
            text: "Get a free key"
            onClicked: Qt.openUrlExternally(C.SIGN_UP)
          }
        }
      }
      AppearanceSection { app: root }
      LauncherSection { app: root }
      KeysSection {
        app: root
        keys: [
          ["1  2", "Countries, Quiz"],
          ["/", "Search"],
          ["← → ↑ ↓  Enter", "Move through the flags, open one"],
          ["?", "A country at random"],
          ["1 – 4", "Answer, in the quiz"],
          ["Enter", "Next question, start, again"],
          ["r", "Fetch the world again"],
          [",", "Settings"],
          ["Esc", "Back one step"]
        ]
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Where it comes from"
        note: "Countries from REST Countries (api.restcountries.com, v5): three requests for all 250, once a month, and never while the window is closed. Flags from its flag CDN (flags.restcountries.com), which needs no key: about two megabytes, fetched once."
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Where it keeps things"
        note: "~/.local/share/moarchy-atlas: countries.json, the world as it was last described; flags/, one picture per country; quiz.json, your rounds and your best scores; account.json, your key."
      }
    }
  }

  // A country as a page over the tab: { code }.
  page: Component {
    CountryView {
      app: root
      paged: true
      country: root.topPage ? root.country(root.topPage.code) : null
      index: root.idx
      total: root.countries.length
      onOpened: function (code) { root.push({ code: code }) }
    }
  }

  // ------------------------------------------------------------ state

  property var countries: []
  readonly property var idx: C.index(countries)
  readonly property var regions: C.regionsIn(countries)
  // Epoch seconds of the last good answer; 0 for never.
  property real fetched: 0
  property bool fetching: false
  property var pages: []
  property int failures: 0
  property string trouble: ""
  // REST Countries refused the key itself: nothing to retry until it changes.
  property bool authFailed: false

  // MOARCHY_ATLAS_OFFLINE: never open a socket -- the files, and nothing
  // else. MOARCHY_ATLAS_NOW: a frozen clock, for the screenshots.
  readonly property bool offline: (Quickshell.env("MOARCHY_ATLAS_OFFLINE") || "") !== ""
  readonly property real pinnedNow: parseFloat(Quickshell.env("MOARCHY_ATLAS_NOW") || "0") * 1000 || 0
  property real now: pinnedNow || Date.now()

  readonly property string envKey: S.cleanKey(Quickshell.env("MOARCHY_ATLAS_KEY"))
  property string accountKey: ""
  readonly property string key: envKey || accountKey
  // Nothing to show and nothing to show it with.
  readonly property bool needsKey: countries.length === 0 && (key === "" || authFailed)

  readonly property string flagDir: cacheFile.dir + "/flags"
  property var flagHave: ({})
  property bool flagsListed: false
  property int flagTries: 0

  readonly property string region: store.prefs.region
  readonly property string sort: store.prefs.sort
  readonly property string quizMode: store.prefs.quizMode
  readonly property string quizScope: store.prefs.quizScope

  // Only while the window is up: a grid of 250 flags laid out in a window
  // nobody can see is a shell that starts slowly.
  readonly property var shownItems: opened ? C.shown(countries, region, grid.query, sort) : []

  // The country in the pane beside the grid, on a desktop.
  property string selectedCode: ""
  readonly property bool split: contentArea.width >= 980
  // The keyboard's place in the grid.
  property int current: -1

  // The quiz: the round, the question on screen, the record.
  property var round: null
  property int shownQuestion: 0
  property var stats: Q.emptyStats()
  property bool newBest: false
  property var rnd: Q.rng(parseInt(Quickshell.env("MOARCHY_ATLAS_SEED") || "0", 10) || Date.now())

  function country(code) { return idx.byCode[code] || null }

  function freshnessText() {
    if (fetching) return "Fetching the world…"
    if (!countries.length) return ""
    var n = countries.length + " countries"
    var age = C.freshness(S.age(fetched, now / 1000))
    if (offline) return n + " · offline"
    if (failures) return n + " · not updating"
    return n + " · updated " + age
  }

  // ------------------------------------------------------------ moving

  // Beside the grid when there is room, over it when there is not; from the
  // quiz, always over it.
  function openCountry(code) {
    if (!country(code)) return
    resetFocus()
    if (tab !== "countries") { push({ code: code }); return }
    var i = indexIn(shownItems, code)
    if (i >= 0) current = i
    if (split) selectedCode = code
    else push({ code: code })
  }

  function showCountry(code) { openCountry(code) }

  function randomCountry() {
    var from = tab === "countries" && shownItems.length ? shownItems : countries
    if (!from.length) return
    var pickIt = from[Math.floor(Math.random() * from.length)]
    if (tab !== "countries") setTab("countries")
    grid.show(indexIn(shownItems, pickIt.code))
    openCountry(pickIt.code)
  }

  function indexIn(list, code) {
    for (var i = 0; i < list.length; i++) if (list[i].code === code) return i
    return -1
  }

  onTabSelected: current = -1

  // A window that narrows with a country in the pane shows it as a page, and
  // one that widens with a page up shows it in the pane.
  onSplitChanged: {
    if (!split && selectedCode) {
      var code = selectedCode
      selectedCode = ""
      if (tab === "countries") push({ code: code })
    } else if (split && tab === "countries" && topPage && topPage.code) {
      selectedCode = topPage.code
      stack = []
    }
  }

  // Before the tabs: the search, the pane, a finished round.
  stepBack: function () {
    if (tab === "countries") {
      if (grid.query !== "") { grid.query = ""; return true }
      if (selectedCode && split) { selectedCode = ""; return true }
    }
    if (tab === "quiz" && round && shownQuestion >= round.questions.length) { leaveQuiz(); return true }
    return false
  }

  keyHandler: function (event) {
    if (topPage || inSettings) return
    var k = event.key
    var text = event.text
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    var enter = k === Qt.Key_Return || k === Qt.Key_Enter

    if (tab === "quiz") {
      var q = round && shownQuestion < round.questions.length ? round.questions[shownQuestion] : null
      var revealed = q && round.picks.length > shownQuestion
      if (q && !revealed && text >= "1" && text <= "4") {
        var n = parseInt(text, 10) - 1
        if (n < q.options.length) answerQuiz(q.options[n])
        event.accepted = true
      } else if (q && revealed && (enter || k === Qt.Key_Space || text === "n")) {
        nextQuestion()
        event.accepted = true
      } else if (!q && enter && countries.length) {
        startQuiz()
        event.accepted = true
      }
      return
    }

    var n2 = shownItems.length
    var step = k === Qt.Key_Right ? 1 : k === Qt.Key_Left ? -1
      : k === Qt.Key_Down ? grid.columns : k === Qt.Key_Up ? -grid.columns : 0
    if (step && n2) {
      current = current < 0 ? 0 : Math.max(0, Math.min(n2 - 1, current + step))
      grid.show(current)
      if (split && selectedCode) selectedCode = shownItems[current].code
      event.accepted = true
      return
    }
    if (enter && current >= 0 && current < n2) {
      openCountry(shownItems[current].code)
      event.accepted = true
      return
    }
    if (text === "/") { Qt.callLater(grid.focusField); event.accepted = true; return }
    if (text === "?") { randomCountry(); event.accepted = true; return }
    if (text === "r") { fetch(true); event.accepted = true }
  }

  // ------------------------------------------------------------ the quiz

  function startQuiz() {
    if (!Q.playable(countries, quizScope, quizMode)) {
      toast("Not enough countries there for four answers")
      return
    }
    round = Q.round(countries, quizMode, quizScope, rnd)
    shownQuestion = 0
    newBest = false
  }

  function answerQuiz(code) {
    if (!round || round.picks.length > shownQuestion) return
    round = Q.pick(round, code)
    if (Q.finished(round)) {
      var r = Q.record(stats, round)
      stats = r.stats
      newBest = r.record
      quizFile.save(Q.serializeStats(stats))
    }
  }

  function nextQuestion() {
    if (!round || round.picks.length <= shownQuestion) return
    shownQuestion = Math.min(shownQuestion + 1, round.questions.length)
  }

  function leaveQuiz() {
    round = null
    shownQuestion = 0
    newBest = false
  }

  // ------------------------------------------------------------ the key

  function saveKey(value) {
    var k = S.cleanKey(value)
    if (!k) {
      toast("That does not look like a REST Countries key")
      return false
    }
    accountKey = k
    accountFile.save(S.serializeAccount(k))
    authFailed = false
    failures = 0
    trouble = ""
    retry.stop()
    if (envKey === "") fetch(true)
    else toast("Saved, but MOARCHY_ATLAS_KEY is the key in use")
    return true
  }

  function forgetKey() {
    accountKey = ""
    accountFile.save(S.serializeAccount(""))
    toast("Key forgotten. The world already here stays.")
  }

  // ------------------------------------------------------------ the network

  property bool manual: false

  function due() {
    if (offline || fetching || key === "" || authFailed || retry.running) return false
    return S.age(fetched, now / 1000) >= C.STALE_S
  }

  function maybeFetch() {
    if (opened && due()) fetch(false)
  }

  function fetch(byHand) {
    if (offline || fetching) return
    if (key === "") {
      if (byHand) toast("Atlas needs a REST Countries key: Settings has the place for one")
      return
    }
    fetching = true
    manual = !!byHand
    pages = []
    askPage(0)
  }

  function askPage(offset) {
    fetcher.offset = offset
    fetcher.command = C.command(key, offset)
    fetcher.running = true
  }

  function arrived(code) {
    var got = C.answer(code, fetchOut.text, fetchErr.text)
    if (got.error) {
      fetching = false
      failures += 1
      trouble = got.error
      authFailed = got.auth
      if (!got.auth) {
        var backoff = [60, 300, 900, 3600]
        retry.interval = 1000 * (got.retry || backoff[Math.min(failures - 1, backoff.length - 1)])
        retry.restart()
      }
      // A world from last month is worth more than a blank page, so what is
      // on screen stays.
      if (manual || !countries.length) toast(got.error)
      return
    }
    var p = pages.slice()
    p.push(got.countries)
    pages = p
    if (got.more && pages.length < C.MAX_PAGES) {
      askPage(fetcher.offset + C.PAGE)
      return
    }
    fetching = false
    var list = C.merge(pages)
    pages = []
    if (!list.length) {
      failures += 1
      trouble = "REST Countries sent no countries."
      if (manual) toast(trouble)
      return
    }
    failures = 0
    trouble = ""
    authFailed = false
    countries = list
    fetched = Date.now() / 1000
    now = pinnedNow || Date.now()
    // Written now rather than on close: this is three requests of somebody's
    // month.
    cacheFile.save(S.serializeCache(countries, fetched))
    if (manual) toast(list.length + " countries")
    listFlags()
  }

  Timer {
    id: retry
    repeat: false
    onTriggered: root.maybeFetch()
  }

  Process {
    id: fetcher
    property int offset: 0
    running: false
    stdout: StdioCollector { id: fetchOut; waitForEnd: true }
    stderr: StdioCollector { id: fetchErr; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { root.arrived(code) }
    // qmllint enable signal-handler-parameters
  }

  // ------------------------------------------------------------ the flags

  // What is on disk, then whatever is missing, in one curl. Three goes a
  // session at most: a flag the CDN does not have stays two letters.
  function listFlags() {
    if (flagLister.running) return
    flagLister.command = ["sh", "-c", "mkdir -p -- \"$1\" && ls -1 -- \"$1\"", "sh", flagDir]
    flagLister.running = true
  }

  function flagsListedNow() {
    flagHave = C.flagsIn(flagList.text)
    flagsListed = true
    if (!opened || offline || flagFetcher.running || flagTries >= 3) return
    var missing = C.missingFlags(countries, flagHave)
    if (!missing.length) return
    flagTries += 1
    flagFetcher.command = C.flagCommand(flagDir, missing)
    flagFetcher.running = true
  }

  Process {
    id: flagLister
    running: false
    stdout: StdioCollector { id: flagList; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { root.flagsListedNow() }
    // qmllint enable signal-handler-parameters
  }

  Process {
    id: flagFetcher
    running: false
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { root.listFlags() }
    // qmllint enable signal-handler-parameters
  }

  // ------------------------------------------------------------ the files

  DataFile {
    id: cacheFile
    app: "atlas"
    name: "countries.json"
    onParsed: function (data) {
      var cached = S.parseCache(data)
      // Only while nothing fresher has arrived.
      if (cached.countries.length && cached.fetched >= root.fetched) {
        root.countries = cached.countries
        root.fetched = cached.fetched
      }
      root.cacheRead = true
      root.harness()
      root.maybeFetch()
    }
    onQuarantined: function (to) { root.toast("The saved world was unreadable and was kept aside") }
  }
  property bool cacheRead: false

  DataFile {
    id: accountFile
    app: "atlas"
    name: "account.json"
    onParsed: function (data) {
      root.accountKey = S.parseAccount(data).key
      root.maybeFetch()
    }
  }

  DataFile {
    id: quizFile
    app: "atlas"
    name: "quiz.json"
    onParsed: function (data) { root.stats = Q.parseStats(data) }
    onQuarantined: function (to) { root.toast("The quiz record was unreadable and was kept aside") }
  }

  onOpenedChanged: if (opened) {
    now = pinnedNow || Date.now()
    listFlags()
    maybeFetch()
  }

  // ------------------------------------------------------------ harness

  // Straight onto the screen a screenshot is of:
  //   MOARCHY_ATLAS_PAGE=quiz, _REGION, _SORT, _SEARCH, _OPEN=<code>
  //   MOARCHY_ATLAS_QUIZ=<mode> [_SCOPE] [_SEED]: a round, started
  //   MOARCHY_ATLAS_ANSWERED=<n>: that many answered, every third one wrong
  //   MOARCHY_ATLAS_REVEAL=right|wrong: and the next one answered, shown
  property bool harnessed: false
  function harness() {
    // After the preferences are read, or reading them would undo the region
    // and the order set here.
    if (harnessed || !countries.length || !store.ready) return
    harnessed = true
    var env = function (name) { return Quickshell.env("MOARCHY_ATLAS_" + name) || "" }
    if (env("REGION")) store.set("region", env("REGION"))
    if (env("SORT")) store.set("sort", env("SORT"))
    if (env("SEARCH")) grid.query = env("SEARCH")
    if (env("PAGE") === "quiz" || env("QUIZ")) setTab("quiz")
    if (env("QUIZ")) {
      store.set("quizMode", env("QUIZ"))
      if (env("SCOPE")) store.set("quizScope", env("SCOPE"))
      round = Q.round(countries, Q.mode(env("QUIZ")).key, env("SCOPE") || "world", rnd)
      shownQuestion = 0
      var answered = Math.min(parseInt(env("ANSWERED") || "0", 10), round.questions.length)
      for (var i = 0; i < answered; i++) {
        var q = round.questions[i]
        var wrongOne = q.options[0] === q.answer ? q.options[1] : q.options[0]
        answerQuiz(i % 3 === 2 ? wrongOne : q.answer)
        nextQuestion()
      }
      var reveal = env("REVEAL")
      if (reveal && shownQuestion < round.questions.length) {
        var q2 = round.questions[shownQuestion]
        var miss = q2.options[0] === q2.answer ? q2.options[1] : q2.options[0]
        answerQuiz(reveal === "wrong" ? miss : q2.answer)
      }
    }
    var open = env("OPEN").toUpperCase()
    // The width is not known in the first frame.
    if (open) Qt.callLater(function () { root.openCountry(open) })
  }

  Connections {
    target: root.store
    function onReadyChanged() { root.harness() }
  }

  IpcHandler {
    target: "atlas"
    function show(code: string): string {
      var c = root.country(code.toUpperCase())
      if (!c) return "unknown"
      if (!root.opened) root.open("")
      root.setTab("countries")
      root.openCountry(c.code)
      return c.name
    }
    function count(): int { return root.countries.length }
    function trouble(): string { return root.trouble }
    function refresh(): string { root.fetch(true); return root.fetching ? "fetching" : "not fetching" }
    function close(): string { root.dismiss(); return "ok" }
  }

  // ------------------------------------------------------------ views

  Item {
    anchors.fill: parent

    SetupView {
      anchors.fill: parent
      visible: root.tab === "countries" && root.needsKey && root.cacheRead
      app: root
      busy: root.fetching
      trouble: root.authFailed ? root.trouble : ""
    }

    Item {
      anchors.fill: parent
      visible: root.tab === "countries" && !(root.needsKey && root.cacheRead)

      CountriesView {
        id: grid
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.split ? parent.width - pane.width - 8 - root.ui.gutter : parent.width
        app: root
        items: root.shownItems
        hasWorld: root.countries.length > 0
        regions: root.regions
        region: root.region
        sort: root.sort
        selectedCode: root.split ? root.selectedCode : ""
        current: root.current
        busy: root.fetching && !root.countries.length
        emptyGlyph: query !== "" ? KG.search : root.offline ? G.offline : G.earth
        emptyTitle: query !== "" ? "No match"
          : root.fetching ? "Fetching the world" : root.trouble !== "" ? "No world yet" : "No countries yet"
        emptyText: query !== "" ? "No country or capital here is called “" + query + "”."
          : root.fetching ? "Three requests to REST Countries, then the flags."
          : root.trouble !== "" ? root.trouble
          : root.offline ? "This copy is running offline, and has nothing saved to show." : ""
        onQueryChanged: { root.current = -1; toTop() }
        onOpened: function (code) { root.openCountry(code) }
        onRegionPicked: function (r) { root.store.set("region", r); root.current = -1; toTop() }
        onSortPicked: function (s) { root.store.set("sort", s); root.current = -1; toTop() }
      }

      // The pane: a country, or what picking one shows.
      Rectangle {
        id: pane
        visible: root.split
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: 4
        anchors.rightMargin: root.ui.gutter
        anchors.bottomMargin: root.ui.gutter
        width: Math.min(560, Math.max(400, parent.width * 0.42))
        radius: root.ui.radius
        color: root.ui.bg
        border.width: 1
        border.color: root.ui.line

        readonly property var shown: root.selectedCode ? root.country(root.selectedCode) : null

        CountryView {
          anchors.fill: parent
          anchors.margins: 1
          visible: pane.shown !== null
          app: root
          country: pane.shown
          index: root.idx
          total: root.countries.length
          onOpened: function (code) { root.selectedCode = code; root.current = root.indexIn(root.shownItems, code) }
          onClosed: root.selectedCode = ""
        }
        EmptyState {
          anchors.centerIn: parent
          visible: pane.shown === null
          app: root
          glyph: G.flag
          title: "Pick a country"
          text: "Its flag, capital, people and land, what it belongs to, and its neighbours."
        }
      }
    }

    Loader {
      anchors.fill: parent
      active: root.tab === "quiz" && root.countries.length > 0
      sourceComponent: Component { QuizView { app: root } }
    }

    EmptyState {
      anchors.centerIn: parent
      visible: root.tab === "quiz" && root.countries.length === 0
      app: root
      glyph: G.quiz
      title: "The quiz needs the world first"
      text: root.key === "" ? "Give Atlas a REST Countries key, and the flags come with it." : "It arrives with the next fetch."
      actionText: root.key === "" ? "Set it up" : ""
      onAction: root.setTab("countries")
    }
  }
}
