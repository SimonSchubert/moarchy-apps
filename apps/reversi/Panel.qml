import QtQuick
import Quickshell
import Quickshell.Io
import "kit"
import "kit/Glyphs.js" as KG
import "Bits.js" as Bits
import "Reversi.js" as R
import "Ai.js" as Ai
import "Store.js" as S

// Reversi: a board, an opponent on a clock, and a record kept by difficulty.
// Against the computer at three levels, or two people passing the phone.
//
//     omarchy-shell shell toggle org.moarchy.reversi
//
// The search runs in a WorkerScript (search.js), so the board keeps turning
// discs while the computer thinks. A worker cannot be interrupted, so a reply
// carries the generation it was asked under, and one for a board that has
// since been taken back or restarted is dropped.
//
// A phone gets the score, the board and the buttons in one column, the record
// a page away; a desktop gets the board beside a pane with all three.
App {
  id: root

  appId: "org.moarchy.reversi"
  title: "Reversi"
  subtitle: solo ? level.name + " · you are " + (game.human === R.DARK ? "dark" : "light") : "Two players"
  windowWidth: 1100
  windowHeight: 780

  store: Store { name: "moarchy-reversi" }

  launcher.desktopId: "org.moarchy.Reversi"
  launcher.genericName: "Board game"
  launcher.comment: "Play Reversi against the phone, or across a table"
  launcher.categories: "Game;BoardGame;"
  launcher.keywords: "reversi;othello;board;game;strategy;discs;"

  mark: Component { Image { source: root.appDir + "/icon.svg"; sourceSize: Qt.size(60, 60) } }

  ui: Tokens {
    theme: root.hostTheme
    compact: root.compact
    // The felt, in the theme's green where it names one. The discs stay dark
    // and light rather than two of the theme's hues, in a light theme too: a
    // pair of hues fails in daylight and for the eight percent of men who
    // cannot tell the popular pair apart. So a disc takes a tint from the
    // theme and not its identity.
    readonly property color felt: Qt.tint(bg, alpha(hue("green", "#33d17a", "#33d17a"), dark ? 0.34 : 0.58))
    // A shade of the felt, not of the window: the grid stays darker than the
    // board in both directions.
    readonly property color feltLine: Qt.tint(felt, alpha("#000000", 0.30))
    readonly property color darkDisc: Qt.tint("#0d0d10", alpha(bg, 0.22))
    readonly property color lightDisc: Qt.tint("#f4f3f1", alpha(text, 0.14))
    readonly property color darkRim: Qt.tint(darkDisc, alpha("#ffffff", 0.20))
    readonly property color lightRim: Qt.tint(lightDisc, alpha("#000000", 0.14))
  }

  actions: Component {
    Row {
      spacing: 2
      // Undo is along the bottom on a phone.
      IconButton {
        visible: !root.compact
        app: root
        glyph: KG.undo
        label: "Undo"
        enabled: root.canUndo
        opacity: enabled ? 1 : 0.4
        onClicked: root.undo()
      }
      IconButton {
        visible: root.compact
        app: root
        glyph: KG.history
        label: "Record"
        onClicked: root.push({ kind: "record" })
      }
      IconButton {
        app: root
        glyph: KG.plus
        label: "New game"
        onClicked: root.askNewGame()
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
          game: root.game
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
      blurb: "Reversi against the computer at three levels, or across a table."
      AppearanceSection { app: root }
      LauncherSection { app: root }
      KeysSection {
        app: root
        keys: [
          ["← → ↑ ↓", "Move over the board"],
          ["Enter, Space", "Play the square"],
          ["u", "Undo"],
          ["n", "New game"],
          [",", "Settings"],
          ["Esc", "Back one step"]
        ]
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Where it keeps the game"
        note: "~/.local/share/moarchy-reversi/reversi.json: the moves of the game on the board, and the record against each level. Saved after every move."
      }
    }
  }

  // ------------------------------------------------------------ the game

  property var game: S.fresh()
  property bool loaded: false
  property bool thinking: false
  property int generation: 0

  readonly property var level: Ai.levelFor(game.level)
  readonly property var position: R.replay(game.moves).position
  readonly property bool over: R.isOver(position)
  readonly property bool solo: game.mode === S.SOLO
  readonly property bool theirTurn: solo && !over && position.turn !== game.human
  readonly property bool canUndo: game.moves.length > 0 && !over && !thinking && !reply.running
  readonly property var counts: R.counts(position)
  readonly property var hints: over || theirTurn || thinking ? Bits.ZERO : R.moves(position)
  readonly property int last: R.lastMove(game.moves)

  readonly property var names: {
    if (!solo) return { 0: "Dark", 1: "Light" }
    var out = ({})
    out[game.human] = "You"
    out[R.other(game.human)] = level.name
    return out
  }

  readonly property string status: {
    if (over) return resultText()
    if (thinking || reply.running) return names[position.turn] + " is thinking…"
    if (solo && position.turn === game.human) return "Your move"
    // By the display name, not the colour: the header has just told someone
    // they are dark, and "Light to play" makes them work out who that is.
    return names[position.turn] + " to play"
  }

  function resultText() {
    var d = counts[0], l = counts[1]
    var w = R.winner(position)
    if (w === null) return "A draw, " + d + " each"
    var score = Math.max(d, l) + "–" + Math.min(d, l)
    if (!solo) return R.NAMES[w] + " wins " + score
    if (w === game.human) return "You win " + score + ", by " + Math.abs(d - l)
    return level.name + " wins " + score
  }

  function save() { file.save(S.serialize(game)) }

  function tap(cell) {
    if (thinking || reply.running) return
    if (over) { toast("That game is finished. Tap New game."); return }
    if (theirTurn) return
    // Silent: a tap on a square with no move in it is a miss, and an app that
    // scolds you for a miss on a touch screen scolds you constantly.
    if (!R.isLegal(position, cell)) return
    play(cell)
  }

  function play(cell) {
    var mover = position.turn
    var t = R.playTurn(game.moves, cell)
    var wasOver = game.finished
    game = S.withMoves(game, t.moves)
    if (t.passes) toast(names[R.other(mover)] + " has no move")
    settle(wasOver)
  }

  // After every move: count a finished game once, or hand the turn over.
  function settle(wasOver) {
    if (over && !wasOver) finish()
    else if (theirTurn) reply.restart()
    save()
  }

  function finish() {
    var r = S.resultOf(game)
    game = S.record(game, r.result, r.margin)
    toast(resultText())
  }

  // A beat before the computer starts, so its disc does not land while yours
  // is still turning over.
  Timer { id: reply; interval: 380; onTriggered: root.ponder() }

  function ponder() {
    if (!theirTurn || thinking || !opened) return
    if (!brainLoader.active) brainLoader.active = true
    if (!brain) return
    thinking = true
    generation += 1
    brain.sendMessage({ position: position, level: game.level, generation: generation })
  }

  function thought(answer) {
    // A different game now: the answer is for a board nobody is looking at.
    if (answer.generation !== generation) return
    thinking = false
    if (!theirTurn) return
    if (answer.trouble) toast("The opponent stumbled; playing on")
    var cell = answer.cell
    if (!R.isLegal(position, cell)) {
      // Never seen, and guarded anyway: a board nobody can play on is worse
      // than a weak move.
      var legal = R.legal(position)
      if (!legal.length) return
      cell = legal[0]
    }
    play(cell)
  }

  function undo() {
    if (!canUndo) return
    var moves = solo ? R.takeback(game.moves, game.human) : R.undo(game.moves)
    if (moves === null) return
    generation += 1   // any search in flight is for a board that is gone
    game = S.withMoves(game, moves)
    save()
    // Taking back the computer's opening move leaves it on move again -- the
    // one undo that does not end on the person's turn.
    if (theirTurn) reply.restart()
  }

  function begin(mode, levelKey, human) {
    reply.stop()
    generation += 1
    thinking = false
    game = S.begin(game, mode, levelKey, human)
    save()
    if (theirTurn) reply.restart()
  }

  function askNewGame() { newGame.ask() }

  // The search, behind a Loader so it can be taken down before the process
  // is: tearing the engine down with a WorkerScript thread still alive takes
  // the process with it ("QEventLoop: Cannot be used without
  // QCoreApplication"). Unloading joins the thread first.
  Loader {
    id: brainLoader
    active: false
    sourceComponent: WorkerScript {
      source: "search.js"
      onMessage: function (answer) { root.thought(answer) }
    }
  }
  readonly property WorkerScript brain: brainLoader.item as WorkerScript

  onQuitting: brainLoader.active = false

  // Closed, nothing thinks: the reply is cancelled and a search in flight is
  // orphaned. It is picked up again when the window opens.
  onOpenedChanged: if (!opened) {
    reply.stop()
    generation += 1
    thinking = false
  }

  DataFile {
    id: file
    app: "reversi"
    name: "reversi.json"
    onParsed: function (data) {
      // Our own save, read back: nothing to do.
      if (root.loaded && data && S.serialize(S.parse(data)) === S.serialize(root.game)) return
      root.generation += 1
      root.thinking = false
      root.game = S.parse(data)
      root.loaded = true
      if (root.theirTurn && root.opened) reply.restart()
    }
    onQuarantined: function (to) { root.toast("The saved game was unreadable and was kept aside") }
  }

  onSummoned: {
    // A phone app is closed by being killed, often on the computer's turn:
    // the search starts again by itself, with no tap coming.
    if (theirTurn) reply.restart()
    wantRecord = (Quickshell.env("MOARCHY_REVERSI_PAGE") || "") === "record"
    Qt.callLater(showRecord)
    if (Quickshell.env("MOARCHY_REVERSI_NEW")) newGame.ask()
    if (Quickshell.env("MOARCHY_REVERSI_SETTINGS")) setTab("settings")
  }

  // The record is beside the board on a desktop and a page on a phone, and
  // the window's width is not known yet in the first frame.
  property bool wantRecord: false
  function showRecord() {
    if (!wantRecord || !compact) return
    wantRecord = false
    push({ kind: "record" })
  }
  onCompactChanged: showRecord()

  // The keyboard's square: shown once an arrow key has been pressed.
  property int cursor: -1
  function moveCursor(dr, dc) {
    var c = cursor < 0 ? 19 : cursor
    var r = Math.max(0, Math.min(7, Math.floor(c / 8) + dr))
    var k = Math.max(0, Math.min(7, c % 8 + dc))
    cursor = r * 8 + k
  }

  keyHandler: function (event) {
    if (topPage || inSettings) return
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    var k = event.key
    if (k === Qt.Key_Left) { moveCursor(0, -1); event.accepted = true; return }
    if (k === Qt.Key_Right) { moveCursor(0, 1); event.accepted = true; return }
    if (k === Qt.Key_Up) { moveCursor(-1, 0); event.accepted = true; return }
    if (k === Qt.Key_Down) { moveCursor(1, 0); event.accepted = true; return }
    if ((k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) && cursor >= 0) {
      tap(cursor); event.accepted = true; return
    }
    if (event.text === "u") { undo(); event.accepted = true; return }
    if (event.text === "n") { newGame.ask(); event.accepted = true }
  }

  IpcHandler {
    target: "reversi"
    // A square by name, so a script that says "play d3" cannot play the
    // wrong one.
    function play(square: string): string {
      for (var i = 0; i < R.CELLS; i++)
        if (R.notation(i) === square) { root.tap(i); return "ok" }
      return "no such square"
    }
    function board(): string {
      return Bits.toHex(root.position.dark) + ":" + Bits.toHex(root.position.light)
    }
    function score(): string { return root.counts.join("-") }
    function settled(): bool { return !root.thinking && !reply.running }
  }

  // ------------------------------------------------------------ new game

  Dialog {
    id: newGame
    app: root
    title: "New game"
    // Said here rather than after Start: a warning that arrives after the
    // decision makes people tap twice, not think.
    text: root.game.moves.length && !root.over ? "The game in progress will be given up." : ""
    acceptText: "Start"
    property string mode: S.SOLO
    property string levelKey: "medium"
    property int human: R.DARK
    function ask() {
      mode = root.game.mode
      levelKey = root.game.level
      human = root.game.human
      open()
    }
    onAccepted: root.begin(mode, levelKey, human)

    Text {
      text: "Against"
      color: root.ui.text
      font.family: root.ui.font
      font.pixelSize: root.ui.fs.md
      font.weight: Font.DemiBold
    }
    Flow {
      width: parent.width
      spacing: 8
      Chip { app: root; text: "The computer"; selected: newGame.mode === S.SOLO; onClicked: newGame.mode = S.SOLO }
      Chip { app: root; text: "Another person"; selected: newGame.mode === S.HOTSEAT; onClicked: newGame.mode = S.HOTSEAT }
    }
    // Hidden, not greyed, across a table: a row that is visible but
    // insensitive is a question the app is asking and refusing to hear.
    Text {
      visible: newGame.mode === S.SOLO
      text: "Difficulty"
      color: root.ui.text
      font.family: root.ui.font
      font.pixelSize: root.ui.fs.md
      font.weight: Font.DemiBold
    }
    Flow {
      visible: newGame.mode === S.SOLO
      width: parent.width
      spacing: 8
      Repeater {
        model: Ai.LEVELS
        delegate: Chip {
          required property var modelData
          app: root
          text: modelData.name
          selected: newGame.levelKey === modelData.key
          onClicked: newGame.levelKey = modelData.key
        }
      }
    }
    Text {
      visible: newGame.mode === S.SOLO
      width: parent.width
      wrapMode: Text.Wrap
      text: Ai.levelFor(newGame.levelKey).blurb
      color: root.ui.muted
      font.family: root.ui.font
      font.pixelSize: root.ui.fs.sm
    }
    Text {
      visible: newGame.mode === S.SOLO
      text: "You play"
      color: root.ui.text
      font.family: root.ui.font
      font.pixelSize: root.ui.fs.md
      font.weight: Font.DemiBold
    }
    Flow {
      visible: newGame.mode === S.SOLO
      width: parent.width
      spacing: 8
      Chip { app: root; text: "Dark — first"; selected: newGame.human === R.DARK; onClicked: newGame.human = R.DARK }
      Chip { app: root; text: "Light — second"; selected: newGame.human === R.LIGHT; onClicked: newGame.human = R.LIGHT }
    }
  }

  // ------------------------------------------------------------ the screen

  // Phone: the score, the board and what it is saying travel together,
  // centred in the height the buttons leave, and the buttons are along the
  // bottom, under the thumb already holding the phone -- 0.1.0's layout. A
  // sentence at the bottom of the screen about a board in the middle of it is
  // one nobody connects to the board.
  Item {
    anchors.fill: parent
    visible: root.compact
    Item {
      id: phoneArea
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: phoneButtons.top
      Column {
        id: phoneBlock
        readonly property real boardSide: Math.max(64, Math.min(phoneArea.width - 16, phoneArea.height - 64 - 24 - 36))
        anchors.centerIn: parent
        width: phoneArea.width - 16
        spacing: 12
        ScoreStrip {
          app: root
          width: parent.width
          counts: root.counts
          names: root.names
          turn: root.over ? -1 : root.position.turn
        }
        Board {
          app: root
          width: parent.width
          height: phoneBlock.boardSide
          position: root.position
          hints: root.hints
          last: root.last
          onTapped: function (cell) { root.tap(cell) }
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          text: root.status
          color: root.over ? root.ui.accent : root.ui.muted
          font.family: root.ui.font
          font.pixelSize: root.ui.fs.md
          font.weight: root.over ? Font.DemiBold : Font.Normal
        }
      }
    }
    Row {
      id: phoneButtons
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 12
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 10
      Button {
        app: root
        width: (phoneArea.width - 16 * 2 - 10) / 2
        text: "Undo"
        glyph: KG.undo
        enabled: root.canUndo
        onClicked: root.undo()
      }
      Button {
        app: root
        width: (phoneArea.width - 16 * 2 - 10) / 2
        text: "New game"
        glyph: KG.refresh
        primary: root.over
        onClicked: root.askNewGame()
      }
    }
  }

  // Desktop: the board, and a pane beside it.
  Item {
    anchors.fill: parent
    visible: !root.compact
    Board {
      app: root
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.right: pane.left
      anchors.margins: 32
      position: root.position
      hints: root.hints
      last: root.last
      cursor: root.cursor
      onTapped: function (cell) { root.tap(cell) }
    }
    Flickable {
      id: pane
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.rightMargin: 24
      width: Math.min(380, parent.width * 0.4)
      contentHeight: paneCol.implicitHeight + 24
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      Column {
        id: paneCol
        width: parent.width
        y: 8
        spacing: 24
        Controls { app: root; width: parent.width }
        RecordView { app: root; game: root.game; width: parent.width }
      }
    }
  }
}
