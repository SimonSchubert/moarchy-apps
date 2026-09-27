import QtQuick
import Quickshell
import Quickshell.Io
import "kit"
import "Game.js" as G
import "Words.js" as W
import "Store.js" as S
import "Glyphs.js" as FG

// Five Letters: one word a day, six guesses, and a keyboard of its own that
// is coloured by what is known about each letter.
//
//     omarchy-shell shell toggle org.moarchy.fiveletters
//
// The day's word is a function of the date (Words.js), the same function the
// GTK version used, so a day has one word in both; the file holds the guesses
// and the record, not the answer (Store.js).
//
// A phone gets the board with the keyboard under it; a desktop gets the board
// and a smaller keyboard beside a pane with the buttons and the record, and
// takes letters, Backspace and Enter from the keyboard it has.
App {
  id: root

  appId: "org.moarchy.fiveletters"
  title: "Five Letters"
  subtitle: store_.mode === S.PRACTICE ? "Practice" : "Today · no. " + number
  windowWidth: 1100
  windowHeight: 820

  store: Store { name: "moarchy-fiveletters" }

  launcher.desktopId: "org.moarchy.FiveLetters"
  launcher.genericName: "Word game"
  launcher.comment: "Guess the five-letter word in six tries"
  launcher.categories: "Game;LogicGame;"
  launcher.keywords: "word;letters;guess;puzzle;daily;"

  mark: Component { Image { source: root.appDir + "/icon.svg"; sourceSize: Qt.size(60, 60) } }

  // The colours are the rules in this game: green is in place, yellow is
  // elsewhere, grey is not in the word. The theme's own green and yellow,
  // pushed toward the window so a letter on them stays readable -- and on a
  // theme whose green and yellow are too close to tell apart side by side,
  // the yellow moves to orange.
  ui: Tokens {
    id: tokens
    theme: root.hostTheme
    compact: root.compact
    readonly property real solid: dark ? 0.86 : 0.92
    function mixed(c) { return Qt.tint(bg, alpha(c, solid)) }
    function apart(a, b) {
      var x = Qt.color(a), y = Qt.color(b)
      return (Math.abs(x.r - y.r) + Math.abs(x.g - y.g) + Math.abs(x.b - y.b)) * 255 > 90
    }
    // Whichever of the text and the window is further from the tile.
    function inkOn(c) {
      function light(k) { var q = Qt.color(k); return 0.299 * q.r + 0.587 * q.g + 0.114 * q.b }
      return Math.abs(light(bg) - light(c)) > Math.abs(light(text) - light(c)) ? bg : text
    }
    readonly property color correct: mixed(hue("green", "#4ade80", "#16a34a"))
    readonly property color present: {
      var y = mixed(hue("yellow", "#facc15", "#ca8a04"))
      return apart(correct, y) ? y : mixed(hue("orange", "#fb923c", "#ea580c"))
    }
    readonly property color absent: Qt.tint(bg, alpha(text, 0.34))
    readonly property color inkOnCorrect: inkOn(correct)
    readonly property color inkOnPresent: inkOn(present)
    readonly property color inkOnAbsent: inkOn(absent)
    readonly property color edge: Qt.tint(bg, alpha(text, 0.20))
    readonly property color typedEdge: Qt.tint(bg, alpha(text, 0.42))
    readonly property color key: Qt.tint(bg, alpha(text, 0.16))
    readonly property color keyAbsent: Qt.tint(bg, alpha(text, 0.30))
    readonly property color keyAbsentText: Qt.tint(bg, alpha(text, 0.55))
  }

  // On a phone: the practice word and the record. The copy button waits
  // under the board until there is something to copy. A desktop has all of
  // it in the pane.
  actions: Component {
    Row {
      spacing: 2
      visible: root.compact
      IconButton {
        app: root
        glyph: root.store_.mode === S.PRACTICE ? FG.today : FG.practice
        label: root.store_.mode === S.PRACTICE ? "Today's word" : "A practice word"
        onClicked: root.store_.mode === S.PRACTICE ? root.showDaily() : root.newPractice()
      }
      IconButton {
        app: root
        glyph: FG.record
        label: "Record"
        onClicked: root.push({ kind: "record" })
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
          store: root.store_
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
      blurb: "One five-letter word a day, six guesses, and a keyboard that knows what you know."
      AppearanceSection { app: root }
      LauncherSection { app: root }
      KeysSection {
        app: root
        keys: [
          ["A – Z", "Type a letter"],
          ["Backspace", "Take the last letter back"],
          ["Enter", "Guess the word"],
          ["Ctrl+C", "Copy the result, when the day is done"],
          [",", "Settings"],
          ["Esc", "Back one step"]
        ]
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Where it keeps the game"
        note: "~/.local/share/moarchy-fiveletters/fiveletters.json: today's guesses, a practice word's seed and guesses, and the record. Not the answer, which is the date's, and not a practice word, which is its seed's. Saved after every guess."
      }
    }
  }

  // ------------------------------------------------------------ the game

  readonly property var words: W.all()
  property string day: W.today(Quickshell.env("MOARCHY_FIVELETTERS_TODAY") || "")
  // Named with an underscore: `store` is the kit's preferences.
  property var store_: S.fresh()
  property var game: S.game(S.rollOver(S.fresh(0), day), words, day)
  property string typed: ""
  property string said: ""
  property bool loaded: false

  readonly property int number: W.index(words, day) + 1
  readonly property bool over: G.over(game)

  // Six ways to say well done, one per number of guesses. This is the only
  // line in the app allowed to be pleased about it.
  readonly property var praise: ["Extraordinary", "Wonderful", "Very good", "Good", "Close one", "Got there"]

  readonly property string status: {
    if (said) return said
    if (G.solved(game)) return praise[Math.min(G.used(game), G.GUESSES) - 1] + " — in " + G.used(game)
    if (G.out(game)) return "It was " + game.secret
    if (!words.complete) return "Running on a handful of built-in words"
    var left = G.left(game)
    return left + " guess" + (left === 1 ? "" : "es") + " left"
  }

  function save() { file.save(S.serialize(store_)) }

  // Load the game the file says is on, on the day it is.
  function settleDay() {
    day = W.today(Quickshell.env("MOARCHY_FIVELETTERS_TODAY") || "")
    var next = S.rollOver(store_, day)
    var rolled = next !== store_
    store_ = next
    game = S.game(store_, words, day)
    if (rolled && loaded) { typed = ""; said = ""; save() }
  }

  function typeLetter(letter) {
    if (G.over(game) || board.busy || inSettings || topPage) return
    var l = String(letter).toUpperCase()
    if (G.ALPHABET.indexOf(l) < 0 || l.length !== 1 || typed.length >= G.LENGTH) return
    typed += l
    said = ""
  }

  function backspace() {
    if (G.over(game) || board.busy || !typed) return
    typed = typed.slice(0, -1)
    said = ""
  }

  // Submit the row, or say why it is not going anywhere. The word is kept in
  // the row when refused: somebody who mistyped one letter should not have to
  // type the other four again.
  function enter() {
    if (G.over(game) || board.busy) return
    var row = G.used(game)
    if (typed.length < G.LENGTH) { refuse(row, "Not enough letters"); return }
    if (!G.accepts(typed, game.allowed)) { refuse(row, "Not a word this app knows"); return }
    game = G.submit(game, typed)
    typed = ""
    said = ""
    store_ = S.remember(store_, game)
    save()
    board.reveal(row)
  }

  function refuse(row, reason) {
    said = reason
    board.refuse(row)
  }

  // Count the day once, and say what it was.
  function finish() {
    if (!G.over(game) || store_.mode !== S.DAILY || S.counted(store_, day)) return
    store_ = S.record(store_, game, day)
    save()
    if (G.solved(game)) {
      var streak = store_.stats.streak
      toast(praise[G.used(game) - 1] + " — " + streak + " day" + (streak === 1 ? "" : "s") + " in a row")
    } else {
      toast("The word was " + game.secret)
    }
  }

  function showDaily() {
    store_ = S.showDaily(store_)
    settleDay()
    typed = ""
    said = ""
    save()
  }

  // A word to play when today's is done. Never counted: a streak is about days.
  function newPractice() {
    store_ = S.beginPractice(store_)
    game = S.game(store_, words, day)
    typed = ""
    said = ""
    save()
  }

  function copyResult() {
    if (!G.over(game)) { toast("Finish it first"); return }
    Quickshell.clipboardText = S.share(game, number)
    toast("Copied")
  }

  DataFile {
    id: file
    app: "fiveletters"
    name: "fiveletters.json"
    onParsed: function (data) {
      // Our own save, read back: nothing to do.
      if (root.loaded && data && S.serialize(S.parse(data, root.store_.seed)) === S.serialize(root.store_)) return
      root.store_ = S.parse(data)
      root.loaded = true
      root.settleDay()
      // A day finished and saved, then closed before it was counted.
      root.finish()
    }
    onQuarantined: function (to) { root.toast("The saved game was unreadable and was kept aside") }
  }

  // A phone left open overnight comes back to yesterday's board: the date is
  // checked every time the window opens.
  onSummoned: {
    if (loaded) settleDay()
    wantRecord = (Quickshell.env("MOARCHY_FIVELETTERS_PAGE") || "") === "record"
    Qt.callLater(showRecord)
    var pre = Quickshell.env("MOARCHY_FIVELETTERS_TYPED") || ""
    if (pre) Qt.callLater(function () { for (var i = 0; i < pre.length; i++) root.typeLetter(pre[i]) })
  }
  onOpenedChanged: if (!opened && loaded) { store_ = S.remember(store_, game); save() }

  property bool wantRecord: false
  function showRecord() {
    if (!wantRecord || !compact) return
    wantRecord = false
    push({ kind: "record" })
  }
  onCompactChanged: showRecord()

  keyHandler: function (event) {
    if (topPage || inSettings) return
    if (event.modifiers & Qt.ControlModifier) {
      if (event.key === Qt.Key_C) { copyResult(); event.accepted = true }
      return
    }
    if (event.modifiers & (Qt.AltModifier | Qt.MetaModifier)) return
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { enter(); event.accepted = true; return }
    if (event.key === Qt.Key_Backspace) { backspace(); event.accepted = true; return }
    var t = event.text.toUpperCase()
    if (t.length === 1 && G.ALPHABET.indexOf(t) >= 0) { typeLetter(t); event.accepted = true }
  }

  IpcHandler {
    target: "fiveletters"
    // Type a word and press Enter, as a person would.
    function guess(word: string): string {
      for (var i = 0; i < word.length; i++) root.typeLetter(word[i])
      root.enter()
      return root.status
    }
    function rows(): string { return G.words(root.game).join(",") }
    function settled(): bool { return !board.busy }
  }

  // ------------------------------------------------------------ the screen

  // Phone: the board, the line of text, the keyboard.
  // Desktop: the same column, narrower keys, beside a pane.
  Item {
    id: playArea
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    width: root.compact ? parent.width : Math.min(parent.width - pane.width - 48, 560)
    anchors.leftMargin: root.compact ? 0 : Math.max(24, (parent.width - pane.width - 48 - width) / 2)

    Board {
      id: board
      app: root
      anchors.top: parent.top
      anchors.topMargin: 8
      anchors.bottom: statusLine.top
      anchors.bottomMargin: 8
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: 16
      anchors.rightMargin: 16
      game: root.game
      typed: root.typed
      onSettled: root.finish()
    }
    Text {
      id: statusLine
      anchors.bottom: doneRow.visible ? doneRow.top : keyboard.top
      anchors.bottomMargin: 12
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      text: root.status
      color: root.over ? root.ui.accent : root.ui.muted
      font.family: root.ui.font
      font.pixelSize: root.ui.fs.md
      font.weight: root.over ? Font.DemiBold : Font.Normal
    }
    // A finished day, on a phone: what there is to do next.
    Row {
      id: doneRow
      visible: root.compact && root.over
      anchors.bottom: keyboard.top
      anchors.bottomMargin: 12
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 10
      Button {
        app: root
        text: "Copy result"
        glyph: FG.copy
        primary: true
        onClicked: root.copyResult()
      }
      Button {
        app: root
        text: root.store_.mode === S.PRACTICE ? "Another word" : "A practice word"
        glyph: FG.practice
        onClicked: root.newPractice()
      }
    }
    Keyboard {
      id: keyboard
      app: root
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 10
      anchors.horizontalCenter: parent.horizontalCenter
      width: parent.width - 8
      known: G.keys(root.game)
      onLetter: function (l) { root.typeLetter(l) }
      onEnter: root.enter()
      onBack: root.backspace()
    }
  }

  Flickable {
    id: pane
    visible: !root.compact
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.rightMargin: 24
    width: root.compact ? 0 : Math.min(400, parent.width * 0.4)
    contentHeight: paneCol.implicitHeight + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    Column {
      id: paneCol
      width: parent.width
      y: 8
      spacing: 20
      Flow {
        width: parent.width
        spacing: 10
        Button {
          app: root
          text: root.store_.mode === S.PRACTICE ? "Today's word" : "A practice word"
          glyph: root.store_.mode === S.PRACTICE ? FG.today : FG.practice
          onClicked: root.store_.mode === S.PRACTICE ? root.showDaily() : root.newPractice()
        }
        Button {
          app: root
          text: "Copy result"
          glyph: FG.copy
          primary: root.over
          enabled: root.over
          onClicked: root.copyResult()
        }
      }
      RecordView { app: root; store: root.store_; width: parent.width }
    }
  }
}
