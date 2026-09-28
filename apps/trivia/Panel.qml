import QtQuick
import Quickshell
import Quickshell.Io
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G
import "Trivia.js" as T
import "Store.js" as S

// Trivia: multiple-choice rounds from Open Trivia DB, by category and
// difficulty, and a record of how you do at each.
//
//     omarchy-shell shell toggle org.moarchy.trivia
//
// The one game here that needs the network, and it is built so that the
// network is asked once a round and never while a question is on the screen:
// a round is one request for all of its questions, kept in the file the moment
// it arrives, so a phone that reclaims the app, or loses its signal in a
// tunnel, comes back to the same question with the same answers under it.
//
// Four screens in one place, chosen by what is going on rather than by tabs:
// the categories, a round being asked for, a question, and a score. The
// record is a page on a phone and a pane beside the categories on a desktop.
App {
  id: root

  appId: "org.moarchy.trivia"
  title: "Trivia"
  heading: view === "home" ? "" : T.category(roundPick.category).name
  subtitle: subtitleText()
  windowWidth: 1180
  windowHeight: 800

  store: Store { name: "moarchy-trivia" }

  launcher.desktopId: "org.moarchy.Trivia"
  launcher.genericName: "Quiz game"
  launcher.comment: "Multiple-choice quizzes by category and difficulty, from Open Trivia DB"
  launcher.categories: "Game;"
  launcher.keywords: "trivia;quiz;questions;pub quiz;general knowledge;game;"

  mark: Component { Image { source: root.appDir + "/icon.svg"; sourceSize: Qt.size(60, 60) } }

  ui: Tokens {
    theme: root.hostTheme
    compact: root.compact
    // A colour per category, from the theme's own hues where it names them.
    readonly property color blue: hue("blue", "#60a5fa", "#2563eb")
    readonly property color green: hue("green", "#4ade80", "#16a34a")
    readonly property color yellow: hue("yellow", "#facc15", "#ca8a04")
    readonly property color orange: hue("orange", "#fb923c", "#ea580c")
    readonly property color red: hue("red", "#f87171", "#dc2626")
    readonly property color magenta: hue("magenta", "#c084fc", "#9333ea")
    readonly property color cyan: hue("cyan", "#22d3ee", "#0891b2")
  }

  // A category's colour: its hue in the theme, or the accent for Anything.
  function tone(id) {
    var name = T.category(id).hue
    return name === "accent" ? ui.accent : ui[name]
  }
  function difficultyTone(key) {
    return key === "easy" ? ui.good : key === "hard" ? ui.bad : key === "medium" ? ui.warn : ui.muted
  }

  actions: Component {
    Row {
      spacing: 2
      IconButton {
        visible: root.view === "quiz"
        app: root
        glyph: KG.close
        label: "Leave this round"
        onClicked: leave.open()
      }
      IconButton {
        visible: root.compact && root.view === "home"
        app: root
        glyph: G.record
        label: "Record"
        onClicked: root.showRecord()
      }
    }
  }

  page: Component {
    Item {
      PageHeader { id: recordHead; app: root; width: parent.width; title: "Record" }
      Flickable {
        anchors.top: recordHead.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentHeight: recordBody.implicitHeight + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        RecordView {
          id: recordBody
          app: root
          book: root.book
          x: root.ui.gutter
          y: 8
          width: parent.width - root.ui.gutter * 2
        }
      }
    }
  }

  settings: Component {
    SettingsPage {
      app: root
      blurb: "Multiple-choice rounds from Open Trivia DB, by category and difficulty."
      AppearanceSection { app: root }
      LauncherSection { app: root }
      KeysSection {
        app: root
        keys: [
          ["1 – 4, a – d", "Answer"],
          ["Enter", "Next question, or play again"],
          ["p", "Play the last pick"],
          ["r", "Record"],
          [",", "Settings"],
          ["Esc", "Back one step"]
        ]
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Where the questions come from"
        note: "The Open Trivia Database (opentdb.com): about five thousand questions, written and checked by its users, under CC BY-SA 4.0. It needs no account. A round is one request, and it takes one every five seconds. A session token stops it asking you the same question twice until every one in a pick has been asked."
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Where it keeps the record"
        note: "~/.local/share/moarchy-trivia/trivia.json: the round on the screen, every answer counted as it is given, and your last pick. Nothing is sent anywhere."
        Button {
          app: root
          text: "Clear the record"
          glyph: KG.remove
          enabled: root.book.stats.answered > 0
          onClicked: forget.open()
        }
      }
    }
  }

  // ------------------------------------------------------------ what is known

  property var book: S.fresh()
  property bool loaded: false
  readonly property var round: book.round
  readonly property var pick: book.pick
  // What the round being asked for, or played, is of.
  readonly property var roundPick: asking || failure !== "" ? wanted : (round || pick)

  // A round left for the categories with questions still to answer. It is
  // still in the file, and the categories offer it back.
  property bool away: false

  property bool offline: false
  property bool asking: false
  property string failure: ""
  // The pick being asked for, and how many -- fewer after a code 1 or 4.
  property var wanted: pick
  property int amount: T.DEFAULT_LENGTH
  // Rate limits and lost tokens: three more goes at each, a round.
  property int retries: 0
  property bool resetDone: false
  // Why the round is taking a while, when there is a reason worth saying.
  property string note: ""
  property real lastAsked: 0
  property real waitUntil: 0
  property real now: Date.now()

  readonly property string view: {
    if (asking) return "loading"
    if (failure !== "") return "error"
    if (round && !away && T.finished(round)) return "done"
    if (round && !away) return "quiz"
    return "home"
  }
  readonly property bool resumable: !!round && !T.finished(round)
  readonly property int waitSeconds: Math.max(0, Math.ceil((waitUntil - now) / 1000))

  function subtitleText() {
    if (view === "quiz") return T.score(round) + " right so far"
    if (view === "error") return ""
    if (view === "done") return T.score(round) + " of " + round.questions.length + " right"
    if (view === "loading") return "Asking Open Trivia DB…"
    var s = book.stats
    return s.answered ? T.percent(s.right, s.answered) + "% of " + s.answered + " answered right" : "Open Trivia DB"
  }

  function save() { file.save(S.serialize(book)) }

  function setPick(changes) {
    book = S.withPick(book, changes)
    save()
  }

  // ------------------------------------------------------------ playing

  // A category tapped: a round of it, on the difficulty, kind and length the
  // chips say. The unfinished round, if any, goes -- its answers are counted.
  function play(categoryId) {
    if (categoryId !== undefined) setPick({ category: categoryId })
    begin(pick)
  }

  function again() { begin(pick) }

  function resume() { if (resumable) away = false }

  function choose(i) {
    if (view !== "quiz" || T.answered(round)) return
    var q = T.current(round)
    if (!q || i < 0 || i >= q.answers.length) return
    book = S.answer(book, i)
    save()
  }

  function next() {
    if (view !== "quiz" || !T.answered(round)) return
    book = S.advance(book, Date.now())
    save()
    if (T.finished(round)) {
      var s = T.score(round)
      if (s === round.questions.length) toast("Every one of them. " + T.verdict(s, s) + ".")
    }
  }

  // Back to the categories: an unfinished round is kept to come back to; a
  // finished one is done with.
  function home() {
    cancel()
    if (round && T.finished(round)) { book = S.withRound(book, null); save() }
    else if (round) away = true
  }

  function abandon() {
    book = S.withRound(book, null)
    away = false
    save()
  }

  function showRecord() {
    if (compact && !(topPage && topPage.kind === "record")) push({ kind: "record" })
  }

  // ------------------------------------------------------------ asking

  function begin(p) {
    cancel()
    wanted = Object.assign({}, p)
    amount = p.amount
    retries = 0
    resetDone = false
    note = ""
    failure = ""
    if (offline) { failure = "This run is offline."; return }
    asking = true
    if (T.tokenFresh(book.token, Date.now())) askQuestions()
    else ask("token", T.tokenUrl())
  }

  function cancel() {
    waiter.stop()
    asker.running = false
    asking = false
    failure = ""
    waitUntil = 0
  }

  // Questions wait out the five seconds since the last question request;
  // the token endpoint is not counted and goes at once.
  function askQuestions() {
    var wait = lastAsked + T.GAP_MS - Date.now()
    if (wait > 50) {
      waitUntil = Date.now() + wait
      now = Date.now()
      waiter.interval = wait
      waiter.restart()
      return
    }
    waitUntil = 0
    lastAsked = Date.now()
    ask("questions", T.questionsUrl(wanted, amount, book.token ? book.token.value : ""))
  }

  function ask(kind, url) {
    asker.kind = kind
    asker.command = ["curl", "-sS", "--max-time", String(T.TIMEOUT),
                     "-H", "User-Agent: " + T.AGENT,
                     "-H", "Accept: application/json",
                     "-w", "\n%{http_code}", url]
    asker.running = true
  }

  function replied(code, payload) {
    if (!asking) return
    var text = String(payload || "")
    var cut = text.lastIndexOf("\n")
    var status = cut >= 0 ? parseInt(text.slice(cut + 1).trim(), 10) : 0
    var body = cut >= 0 ? text.slice(0, cut) : text
    var kind = asker.kind

    if (code !== 0) { fail("No answer from Open Trivia DB."); return }

    if (kind === "token" || kind === "reset") {
      var token = kind === "token" ? T.parseToken(body) : (book.token ? book.token.value : "")
      // A round without a token is a round that may repeat itself, which is
      // better than no round.
      book = S.withToken(book, token, Date.now())
      askQuestions()
      return
    }

    if (status === 429) { rateLimited(); return }
    if (status >= 500) { fail("Open Trivia DB is having trouble."); return }
    var seed = (Date.now() ^ (Math.random() * 0x7fffffff)) >>> 0
    var parsed = T.parseQuestions(body, T.random(seed))
    switch (parsed.code) {
    case T.OK:
      arrived(parsed.questions)
      return
    case T.RATE_LIMITED:
      rateLimited()
      return
    case T.NO_TOKEN:
      if (++retries > 3) { fail(parsed.error); return }
      book = S.withToken(book, "", 0)
      ask("token", T.tokenUrl())
      return
    case T.TOO_FEW:
    case T.TOKEN_EMPTY:
      // Not that many. With a token that is code 4 rather than 1, and it
      // means "not that many left for you", which is usually still "not that
      // many at all": hard mathematics has twenty questions, a handful of
      // them true or false. So fewer first, down to one...
      if (amount > 1) { shrink(); return }
      // ...and only then, if the token is what ran dry, a fresh start on it.
      if (parsed.code === T.TOKEN_EMPTY && !resetDone && book.token) {
        resetDone = true
        amount = wanted.amount
        toast("Every question for that pick has been asked. Starting it over.")
        ask("reset", T.resetUrl(book.token.value))
        return
      }
      fail(T.problem(T.TOO_FEW))
      return
    default:
      fail(parsed.error || "Open Trivia DB refused the request (" + status + ").")
    }
  }

  function shrink() {
    amount = Math.max(1, Math.floor(amount / 2))
    note = "Not that many for this pick. Asking for " + amount + "."
    askQuestions()
  }

  function rateLimited() {
    if (++retries > 3) { fail(T.problem(T.RATE_LIMITED)); return }
    lastAsked = Date.now()
    askQuestions()
  }

  function arrived(questions) {
    asking = false
    waitUntil = 0
    away = false
    if (questions.length < wanted.amount)
      toast(questions.length === 1 ? "Only one question for that pick" : "Only " + questions.length + " questions for that pick")
    book = S.withToken(S.withRound(book, T.round(wanted, questions, Date.now())), book.token ? book.token.value : "", Date.now())
    save()
  }

  function fail(message) {
    asking = false
    waitUntil = 0
    failure = message
  }

  Process {
    id: asker
    property string kind: ""
    running: false
    stdout: StdioCollector { id: askOut; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { root.replied(code, askOut.text) }
    // qmllint enable signal-handler-parameters
  }

  Timer {
    id: waiter
    onTriggered: root.askQuestions()
  }

  // The countdown under the spinner, while there is one.
  Timer {
    interval: 250
    repeat: true
    running: root.waitUntil > 0 && root.opened
    onTriggered: root.now = Date.now()
  }

  DataFile {
    id: file
    app: "trivia"
    name: "trivia.json"
    onParsed: function (raw) {
      var next = S.parse(raw)
      if (root.loaded && S.serialize(next) === S.serialize(root.book)) return
      root.book = next
      root.loaded = true
    }
    onQuarantined: function (to) { root.toast("The saved record was unreadable and was kept aside") }
  }

  // ------------------------------------------------------------ open and shut

  Component.onCompleted: offline = (Quickshell.env("MOARCHY_TRIVIA_OFFLINE") || "") !== ""

  onSummoned: {
    var page = Quickshell.env("MOARCHY_TRIVIA_PAGE") || ""
    if (page === "settings") setTab("settings")
    if (page === "home") away = true
    if (page === "error") failure = "No answer from Open Trivia DB."
    wantRecord = page === "record"
    Qt.callLater(showRecordIfWanted)
  }
  // The record is beside the categories on a desktop and a page on a phone,
  // and the window's width is not known yet in the first frame.
  property bool wantRecord: false
  function showRecordIfWanted() {
    if (!wantRecord || !compact) return
    wantRecord = false
    away = true
    showRecord()
  }
  onCompactChanged: showRecordIfWanted()

  // Nothing is asked with the window shut.
  onOpenedChanged: if (!opened && asking) cancel()

  stepBack: function () {
    if (view !== "home") { home(); return true }
    return false
  }

  keyHandler: function (event) {
    if (topPage || inSettings) return
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    var enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
    if (view === "quiz") {
      var n = event.text !== "" ? Math.max("1234".indexOf(event.text), "abcd".indexOf(event.text.toLowerCase())) : -1
      if (n >= 0) { choose(n); event.accepted = true; return }
      if (enter || event.key === Qt.Key_Space || event.key === Qt.Key_Right) { next(); event.accepted = true; return }
    }
    if (view === "done" && enter) { again(); event.accepted = true; return }
    if (view === "error" && enter) { begin(wanted); event.accepted = true; return }
    if (view === "home" && (enter || event.text === "p")) { play(); event.accepted = true; return }
    if (view === "home" && event.text === "r") { showRecord(); event.accepted = true }
  }

  IpcHandler {
    target: "trivia"
    function play(category: string): string {
      var id = parseInt(category, 10)
      root.play(T.isCategory(id) ? id : undefined)
      return "ok"
    }
    function answer(choice: string): string {
      var n = parseInt(choice, 10)
      if (isNaN(n)) return "not an answer"
      root.choose(n)
      return "ok"
    }
    function next(): string { root.next(); return "ok" }
    function question(): string {
      var q = root.round ? T.current(root.round) : null
      return q ? q.text : ""
    }
    function view(): string { return root.view }
  }

  // ------------------------------------------------------------ dialogs

  Dialog {
    id: leave
    app: root
    title: "Leave this round?"
    text: "The answers so far are already in your record."
    acceptText: "Leave"
    destructive: true
    onAccepted: root.abandon()
  }

  Dialog {
    id: forget
    app: root
    title: "Clear the record?"
    text: "Every answer counted so far, and the recent rounds, go. The round on the screen stays."
    acceptText: "Clear"
    destructive: true
    onAccepted: {
      var next = S.fresh()
      next.pick = root.book.pick
      next.token = root.book.token
      next.round = root.book.round
      root.book = next
      root.save()
    }
  }

  // ------------------------------------------------------------ the screen

  // The categories, and on a desktop the record beside them.
  Item {
    anchors.fill: parent
    visible: root.view === "home"
    HomeView {
      id: homeView
      app: root
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.right: side.visible ? side.left : parent.right
      anchors.rightMargin: side.visible ? 12 : 0
    }
    Rectangle {
      id: side
      visible: !root.compact
      width: visible ? Math.min(380, parent.width * 0.36) : 0
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.rightMargin: root.ui.gutter
      anchors.bottomMargin: root.ui.gutter
      anchors.topMargin: root.ui.gutter
      radius: root.ui.radius
      color: root.ui.surface
      border.width: 1
      border.color: root.ui.line
      Flickable {
        anchors.fill: parent
        anchors.margins: 1
        contentHeight: sideRecord.implicitHeight + 36
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        RecordView {
          id: sideRecord
          app: root
          book: root.book
          x: 18
          y: 18
          width: parent.width - 36
        }
      }
    }
  }

  QuizView {
    anchors.fill: parent
    app: root
    visible: root.view === "quiz"
  }

  ResultView {
    anchors.fill: parent
    app: root
    visible: root.view === "done"
  }

  // Asking, or failed to.
  Item {
    anchors.fill: parent
    visible: root.view === "loading" || root.view === "error"
    EmptyState {
      anchors.centerIn: parent
      anchors.verticalCenterOffset: -30
      app: root
      busy: root.view === "loading"
      glyph: G.offline
      title: root.view === "loading"
        ? (root.waitSeconds > 0 ? "Asking in " + root.waitSeconds + " s" : "Asking for " + root.amount + (root.amount === 1 ? " question…" : " questions…"))
        : root.failure
      text: root.view === "loading"
        ? (root.note !== "" ? root.note
          : root.waitSeconds > 0 ? "Open Trivia DB takes one request every five seconds from each address."
          : T.category(root.wanted.category).name + " · " + T.difficultyLabel(root.wanted.difficulty) + " · " + T.typeLabel(root.wanted.type))
        : "Check the connection, or pick something with more questions in it: Mixed difficulty and Both kinds have the most."
      actionText: root.view === "error" ? "Try again" : ""
      onAction: root.begin(root.wanted)
    }
    Button {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 24
      app: root
      text: root.view === "loading" ? "Cancel" : "Categories"
      onClicked: root.home()
    }
  }
}
