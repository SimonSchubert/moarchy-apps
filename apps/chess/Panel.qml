import QtQuick
import Quickshell
import Quickshell.Io
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G
import "Chess.js" as C
import "Ai.js" as Ai
import "Store.js" as S

// Chess: two taps a move, an opponent in the app on a clock, and a record kept
// by difficulty. Against the computer at three levels, or two people passing
// the phone across a table.
//
//     omarchy-shell shell toggle org.moarchy.chess
//
// A move is two taps: the first picks a piece up -- its square is marked and
// every square it may go to is dotted -- and the second puts it down. Tapping
// the piece in hand puts it back.
//
// The search runs in a WorkerScript (search.js), so the board keeps sliding
// while the computer thinks. A worker cannot be interrupted, so an answer
// carries the generation it was asked under, and one for a board that has
// since been taken back or restarted is dropped.
//
// A phone gets the players, the board and the buttons in one column, the
// record a page away; a desktop gets the board beside a pane with the
// players, the moves written down and the record.
App {
  id: root

  appId: "org.moarchy.chess"
  title: "Chess"
  subtitle: solo ? level.label + " · you are " + (game.human === C.WHITE ? "white" : "black") : "Two players"
  windowWidth: 1180
  windowHeight: 800

  store: Store { name: "moarchy-chess" }

  launcher.desktopId: "org.moarchy.Chess"
  launcher.genericName: "Board game"
  launcher.comment: "Play chess against the phone, or across a table"
  launcher.categories: "Game;BoardGame;"
  launcher.keywords: "chess;board;game;strategy;checkmate;"

  // A knight, in the men's own colours: icon.svg is a dark knight drawn for a
  // light plate, and on a dark header it is not there.
  mark: Component {
    Piece {
      app: root
      code: (C.WHITE << 3) | C.KNIGHT
      size: parent ? Math.min(parent.width, parent.height) : 30
      share: 0.96
    }
  }

  ui: Tokens {
    theme: root.hostTheme
    compact: root.compact
    // One hue in two strengths: the theme's brown (GNOME's where it names
    // none), laid over the palest colour the theme has -- its text on a dark
    // theme, its background on a light one -- so a dark theme and a light one
    // each get a board that belongs to them and never a negative of it.
    readonly property color brown: hue("brown", "#986a44", "#986a44")
    readonly property color pale: dark ? text : bg
    readonly property color darkSquare: Qt.tint(bg, alpha(brown, dark ? 0.44 : 0.78))
    readonly property color lightSquare: Qt.tint(pale, alpha(brown, dark ? 0.42 : 0.34))
    // A shade of the dark square: the frame stays darker than the board.
    readonly property color boardLine: Qt.tint("#000000", alpha(darkSquare, 0.34))
    // The men stay nearly white and nearly black, tinted by the theme rather
    // than taken from it: two hues fail in daylight and for the eight percent
    // of men who cannot tell the popular pair apart.
    readonly property color pieceWhite: Qt.tint("#f7f6f4", alpha(text, 0.08))
    readonly property color pieceWhiteRim: Qt.tint(pieceWhite, alpha("#000000", 0.45))
    readonly property color pieceBlack: Qt.tint("#101014", alpha(bg, 0.18))
    readonly property color pieceBlackRim: Qt.tint(pieceBlack, alpha("#ffffff", 0.32))
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
      // On a desktop; a phone's header has room for three, and `f` does it.
      IconButton {
        visible: !root.compact
        app: root
        glyph: G.flip
        label: "Turn the board round"
        onClicked: root.turned = !root.turned
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
      blurb: "Chess against the computer at three levels, or across a table."
      AppearanceSection { app: root }
      LauncherSection { app: root }
      KeysSection {
        app: root
        keys: [
          ["← → ↑ ↓", "Move over the board"],
          ["Enter, Space", "Pick a piece up, put it down"],
          ["u", "Undo"],
          ["f", "Turn the board round"],
          ["n", "New game"],
          [",", "Settings"],
          ["Esc", "Put the piece down, then back one step"]
        ]
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Where it keeps the game"
        note: "~/.local/share/moarchy-chess/chess.json: the moves of the game on the board, written as e2e4, and the record against each level. Saved after every move."
      }
    }
  }

  // ------------------------------------------------------------ the game

  // The file's state (Store.js), and the game its moves play to (Chess.js).
  // The game is played into in place, so `revision` is what tells bindings
  // that it changed, and `position` is a copy each time.
  property var game: S.fresh()
  property var chess: C.game()
  property int revision: 0
  property bool loaded: false
  property bool thinking: false
  property int generation: 0
  // A finished game that was loaded went into the record when it finished;
  // without this it would be counted again every time the app opened on it.
  property bool recorded: false
  property int selected: -1
  property bool turned: false
  // Whether the last move slides in: not after a load, an undo or a new
  // game, when "the last move" is history rather than something happening.
  property bool slides: false

  readonly property var position: { var r = revision; return C.copy(chess.position) }
  readonly property var outcome: { var r = revision; return C.outcome(chess.position) }
  readonly property bool over: outcome.state !== C.ONGOING
  readonly property bool checked: { var r = revision; return C.inCheck(chess.position) }
  readonly property var level: Ai.levelFor(game.level)
  readonly property bool solo: game.mode === S.SOLO
  readonly property bool theirTurn: solo && !over && position.turn !== game.human
  readonly property bool mine: !theirTurn && !thinking && !over
  readonly property bool canUndo: chess.moves.length > 0 && !over && !thinking && !reply.running && revision >= 0
  readonly property var taken: { var r = revision; return C.captured(chess) }
  readonly property int balance: C.balance(position)
  readonly property int last: { var r = revision; return C.lastMove(chess) }
  readonly property var sans: { var r = revision; return C.sanList(chess) }
  readonly property bool flipped: (solo && game.human === C.BLACK) !== turned
  readonly property var targets: {
    var r = revision
    if (selected < 0 || !mine) return []
    return C.movesFrom(chess.position, selected).map(C.moveTo)
  }

  readonly property var names: {
    if (!solo) return { 0: "White", 1: "Black" }
    var out = ({})
    out[game.human] = "You"
    out[game.human ^ 1] = level.label
    return out
  }

  readonly property string status: {
    if (over) return resultText()
    if (thinking || reply.running) return names[position.turn] + " is thinking…"
    var check = checked ? "Check — " : ""
    if (solo && position.turn === game.human) return check + (check ? "your move" : "Your move")
    // By the display name: the header has just told somebody they are white,
    // and "Black to play" makes them work out that this means the computer.
    return check + names[position.turn] + " to play"
  }

  function resultText() {
    var o = outcome
    if (o.state === C.CHECKMATE) {
      if (!solo) return "Checkmate — " + C.COLOUR_NAMES[o.winner] + " wins"
      return o.winner === game.human ? "Checkmate — you win" : "Checkmate — " + level.label + " wins"
    }
    if (o.state === C.STALEMATE) return "Stalemate — a draw"
    if (o.state === C.FIFTY_MOVE) return "A draw — fifty moves with nothing taken"
    if (o.state === C.INSUFFICIENT) return "A draw — not enough left to mate with"
    if (o.state === C.REPETITION) return "A draw — the same position three times"
    return ""
  }

  function save() { file.save(S.serialize(game)) }
  function changed() { revision += 1 }

  // --- picking a piece up ----------------------------------------------

  function tap(cell) {
    if (thinking || reply.running) return
    if (over) { toast("That game is finished. Tap New game."); return }
    if (!mine) return
    var p = chess.position
    if (selected >= 0) {
      var codes = C.movesFrom(p, selected).filter(function (m) { return C.moveTo(m) === cell })
      if (codes.length) { choose(codes); return }
    }
    var code = p.squares[cell]
    if (code && (code >> 3) === p.turn && C.movesFrom(p, cell).length)
      // Tapping the piece already up puts it down: "no, not that one".
      selected = cell === selected ? -1 : cell
    else
      // Silent: a tap on an empty square is a miss, and an app that scolds
      // you for a miss on a touch screen scolds you constantly.
      selected = -1
  }

  // More than one move between two squares means one thing: a pawn on the
  // last rank. Everything else in chess is unambiguous.
  function choose(codes) {
    if (codes.length === 1) { playMove(codes[0]); return }
    promote.ask(codes)
  }

  function playMove(code) {
    if (!C.apply(chess, code)) return
    selected = -1
    root.slides = true
    changed()
    game = S.remember(game, chess, over)
    save()
    // The computer starts once the piece has stopped sliding.
    settle.restart()
  }

  Timer { id: settle; interval: 210; onTriggered: root.settled() }
  function settled() {
    if (over) finish()
    else if (theirTurn) reply.restart()
  }

  // Record the result once, and say what it was.
  function finish() {
    if (recorded) return
    recorded = true
    if (solo) {
      var w = outcome.winner
      var result = w === null ? S.DRAWN : (w === game.human ? S.WON : S.LOST)
      game = S.record(game, result, Math.floor((chess.moves.length + 1) / 2))
    }
    game = S.remember(game, chess, true)
    save()
    toast(resultText())
  }

  // --- the opponent ------------------------------------------------------

  // A beat after the slide, before the search starts.
  Timer { id: reply; interval: 60; onTriggered: root.ponder() }

  function ponder() {
    if (!theirTurn || thinking || !opened) return
    if (!brainLoader.active) brainLoader.active = true
    if (!brain) return
    thinking = true
    generation += 1
    var p = chess.position
    brain.sendMessage({ fen: C.fen(p), keysH: p.keysH, keysL: p.keysL,
                        level: game.level, generation: generation })
  }

  function thought(answer) {
    // A different game now: the answer is for a board nobody is looking at.
    if (answer.generation !== generation) return
    thinking = false
    if (!theirTurn) return
    if (answer.trouble) toast("The opponent stumbled; playing on")
    var code = answer.move
    if (!C.isLegal(chess.position, code)) {
      // Never seen, and guarded anyway: a board nobody can move on is worse
      // than a weak move.
      var legal = C.moves(chess.position)
      if (!legal.length) return
      code = legal[0]
    }
    playMove(code)
  }

  function undo() {
    if (!canUndo) return
    var undone = solo ? C.takeback(chess, game.human) : C.undo(chess)
    if (!undone) return
    generation += 1   // any search in flight is for a board that is gone
    selected = -1
    root.slides = false
    changed()
    game = S.remember(game, chess, false)
    save()
    // Taking back the computer's opening move leaves it on move again -- the
    // one undo that does not end on the person's turn.
    if (theirTurn) reply.restart()
  }

  function begin(mode, levelKey, human) {
    reply.stop()
    settle.stop()
    generation += 1
    thinking = false
    selected = -1
    recorded = false
    game = S.begin(game, mode, levelKey, human)
    chess = C.game()
    root.slides = false
    changed()
    save()
    if (theirTurn) reply.restart()
  }

  function askNewGame() { newGame.ask() }

  // The search, behind a Loader so it can be taken down before the process
  // is: a WorkerScript thread alive at exit takes the process with it.
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
    selected = -1
  }

  DataFile {
    id: file
    app: "chess"
    name: "chess.json"
    onParsed: function (data) {
      // Our own save, read back: nothing to do.
      if (root.loaded && data && S.serialize(S.parse(data)) === S.serialize(root.game)) return
      var r = S.gameOf(S.parse(data))
      root.generation += 1
      root.thinking = false
      root.selected = -1
      root.game = r.state
      root.chess = r.game
      root.recorded = r.state.finished
      root.slides = false
      root.changed()
      root.loaded = true
      if (root.over && !root.recorded) root.finish()
      else if (root.theirTurn && root.opened) reply.restart()
      root.hold()
    }
    onQuarantined: function (to) { root.toast("The saved game was unreadable and was kept aside") }
  }

  onSummoned: {
    // A phone app is closed by being killed, often on the computer's turn:
    // the search starts again by itself, with no tap coming.
    if (theirTurn) reply.restart()
    wantRecord = (Quickshell.env("MOARCHY_CHESS_PAGE") || "") === "record"
    Qt.callLater(showRecord)
    if (Quickshell.env("MOARCHY_CHESS_NEW")) newGame.ask()
    if (Quickshell.env("MOARCHY_CHESS_PROMOTE")) promote.ask([])
    if (Quickshell.env("MOARCHY_CHESS_SETTINGS")) setTab("settings")
    hold()
  }

  // MOARCHY_CHESS_SELECT: pick a piece up without a tap, for the screenshots.
  // `auto` is whichever piece has the most to say.
  property bool held: false
  function hold() {
    var wanted = Quickshell.env("MOARCHY_CHESS_SELECT") || ""
    if (!wanted || held || !loaded || !mine) return
    held = true
    var p = chess.position
    var cell = -1
    if (wanted === "auto") {
      var best = 0
      for (var c = 0; c < 64; c++) {
        if (!p.squares[c] || (p.squares[c] >> 3) !== p.turn) continue
        var n = C.movesFrom(p, c).length
        if (n > best) { best = n; cell = c }
      }
    } else {
      cell = C.parseSquare(wanted)
      if (cell >= 0 && !C.movesFrom(p, cell).length) cell = -1
    }
    if (cell >= 0) selected = cell
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

  // Put the piece in hand down before anything else steps back.
  stepBack: function () {
    if (selected >= 0) { selected = -1; return true }
    return false
  }

  // The keyboard's square: shown once an arrow key has been pressed, and
  // moved in the direction the board is drawn.
  property int cursor: -1
  function moveCursor(dc, dr) {
    var c = cursor < 0 ? (selected >= 0 ? selected : (flipped ? 52 : 12)) : cursor
    var col = flipped ? 7 - (c & 7) : (c & 7)
    var rw = flipped ? (c >> 3) : 7 - (c >> 3)
    col = Math.max(0, Math.min(7, col + dc))
    rw = Math.max(0, Math.min(7, rw + dr))
    cursor = flipped ? rw * 8 + 7 - col : (7 - rw) * 8 + col
  }

  keyHandler: function (event) {
    if (topPage || inSettings) return
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    var k = event.key
    if (k === Qt.Key_Left) { moveCursor(-1, 0); event.accepted = true; return }
    if (k === Qt.Key_Right) { moveCursor(1, 0); event.accepted = true; return }
    if (k === Qt.Key_Up) { moveCursor(0, -1); event.accepted = true; return }
    if (k === Qt.Key_Down) { moveCursor(0, 1); event.accepted = true; return }
    if ((k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) && cursor >= 0) {
      tap(cursor); event.accepted = true; return
    }
    if (event.text === "u") { undo(); event.accepted = true; return }
    if (event.text === "f") { turned = !turned; event.accepted = true; return }
    if (event.text === "n") { newGame.ask(); event.accepted = true }
  }

  IpcHandler {
    target: "chess"
    // A move as written, e2e4 or e7e8q, played as the person would: two taps,
    // and a promotion answered.
    function play(text: string): string {
      var code = C.parseUci(text)
      if (code < 0) return "not a move"
      if (!root.mine) return "not your move"
      if (!C.isLegal(root.chess.position, code)) return "illegal"
      root.selected = -1
      root.playMove(code)
      return "ok"
    }
    function tap(square: string): string {
      var cell = C.parseSquare(square)
      if (cell < 0) return "no such square"
      root.tap(cell)
      return "ok"
    }
    function board(): string { return C.fen(root.chess.position) }
    function moves(): string { return C.gameUci(root.chess).join(" ") }
    function settled(): bool { return !root.thinking && !reply.running && !settle.running }
  }

  // ------------------------------------------------------------ dialogs

  Dialog {
    id: newGame
    app: root
    title: "New game"
    // Said here rather than after Start: a warning that arrives after the
    // decision makes people tap twice, not think.
    text: root.chess.moves.length && !root.over ? "The game in progress will be given up." : ""
    acceptText: "Start"
    property string mode: S.SOLO
    property string levelKey: "medium"
    property int human: C.WHITE
    function ask() {
      mode = root.game.mode
      levelKey = root.game.level
      human = root.game.human
      open()
    }
    onAccepted: root.begin(mode, levelKey, human)

    Text {
      text: "Against"
      color: root.ui.muted
      font.family: root.ui.font
      font.pixelSize: root.ui.fs.xs
      font.weight: Font.Bold
      font.capitalization: Font.AllUppercase
      font.letterSpacing: root.ui.tracking
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
      color: root.ui.muted
      font.family: root.ui.font
      font.pixelSize: root.ui.fs.xs
      font.weight: Font.Bold
      font.capitalization: Font.AllUppercase
      font.letterSpacing: root.ui.tracking
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
          text: modelData.label
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
      color: root.ui.muted
      font.family: root.ui.font
      font.pixelSize: root.ui.fs.xs
      font.weight: Font.Bold
      font.capitalization: Font.AllUppercase
      font.letterSpacing: root.ui.tracking
    }
    Flow {
      visible: newGame.mode === S.SOLO
      width: parent.width
      spacing: 8
      Chip { app: root; text: "White — moves first"; selected: newGame.human === C.WHITE; onClicked: newGame.human = C.WHITE }
      Chip { app: root; text: "Black — moves second"; selected: newGame.human === C.BLACK; onClicked: newGame.human = C.BLACK }
    }
  }

  // What the pawn becomes. Four pictures rather than four words, and the
  // queen -- right in all but a rounding error of games -- is the button
  // Enter presses.
  Dialog {
    id: promote
    app: root
    title: "Promote"
    acceptText: "Queen"
    property var codes: []
    property int kind: C.QUEEN
    readonly property int colour: root.position.turn
    function ask(list) {
      codes = list
      kind = C.QUEEN
      open()
    }
    onAccepted: {
      var want = kind
      kind = C.QUEEN
      for (var i = 0; i < codes.length; i++)
        if (C.movePromotion(codes[i]) === want) { root.playMove(codes[i]); return }
    }
    Row {
      spacing: 8
      anchors.horizontalCenter: parent.horizontalCenter
      Repeater {
        model: [C.QUEEN, C.ROOK, C.BISHOP, C.KNIGHT]
        delegate: Rectangle {
          id: choice
          required property int modelData
          width: 64
          height: 64
          radius: root.ui.radius
          color: modelData === C.QUEEN ? root.ui.accentSoft
            : pick.pressed ? root.ui.pressed : root.ui.surface
          border.width: 1
          border.color: modelData === C.QUEEN ? root.ui.accent : root.ui.line
          Accessible.role: Accessible.Button
          Accessible.name: "Promote to " + C.KIND_NAMES[modelData]
          Piece {
            anchors.centerIn: parent
            app: root
            code: (promote.colour << 3) | choice.modelData
            size: 56
          }
          MouseArea {
            id: pick
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { promote.kind = choice.modelData; promote.accept() }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ the screen

  // Phone: the players, the board and what it is saying travel together,
  // centred in the height the buttons leave, and the buttons are along the
  // bottom under the thumb -- 0.1.0's layout.
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
        spacing: 10
        ScoreStrip {
          app: root
          width: parent.width
          names: root.names
          taken: root.taken
          balance: root.balance
          turn: root.over ? -1 : root.position.turn
        }
        Board {
          app: root
          animate: root.slides
          width: parent.width
          height: phoneBlock.boardSide
          visible: root.compact
          position: root.position
          flipped: root.flipped
          selected: root.selected
          targets: root.targets
          last: root.last
          onTapped: function (cell) { root.tap(cell) }
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          text: root.status
          color: root.over ? root.ui.accent : root.checked ? root.ui.bad : root.ui.muted
          font.family: root.ui.font
          font.pixelSize: root.ui.fs.md
          font.weight: root.over || root.checked ? Font.Bold : Font.Normal
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
      anchors.margins: 28
      animate: root.slides
      position: root.position
      flipped: root.flipped
      selected: root.selected
      targets: root.targets
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
      width: Math.min(400, parent.width * 0.4)
      contentHeight: paneCol.implicitHeight + 24
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      Column {
        id: paneCol
        width: parent.width
        y: 8
        spacing: 20
        Controls { app: root; width: parent.width }
        MoveList { app: root; width: parent.width; sans: root.sans }
        RecordView { app: root; game: root.game; width: parent.width }
      }
    }
  }
}
