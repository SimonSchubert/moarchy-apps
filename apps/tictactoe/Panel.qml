import QtQuick
import Quickshell
import Quickshell.Io
import "kit"
import "kit/Glyphs.js" as KG
import "Tictactoe.js" as T
import "Store.js" as S

// Noughts and crosses: the game solved at startup, then told to err. Against
// the computer at three levels, or two people passing the phone across a
// table, and a score kept across the sitting.
//
//     omarchy-shell shell toggle org.moarchy.tictactoe
//
// The solver runs on this thread and not in a worker: the whole game is 5478
// positions and solving it once takes a moment. It is warmed the first time
// the window opens, while somebody is looking at an empty board.
//
// A phone gets the board with the score over it and the two buttons under it;
// a desktop gets the board beside a pane with the score, the buttons and the
// record, so nothing is a page away.
App {
  id: root

  appId: "org.moarchy.tictactoe"
  title: "Tic-tac-toe"
  subtitle: game.mode === S.SOLO ? level.label + " · you are " + T.NAMES[game.mark] : "Two players"
  windowWidth: 980
  windowHeight: 720

  store: Store { name: "moarchy-tictactoe" }

  launcher.desktopId: "org.moarchy.TicTacToe"
  launcher.genericName: "Board game"
  launcher.comment: "Noughts and crosses against the phone, or across a table"
  launcher.categories: "Game;BoardGame;"
  launcher.keywords: "tic;tac;toe;noughts;crosses;xo;board;game;"

  mark: Component { Image { source: root.appDir + "/icon.svg"; sourceSize: Qt.size(60, 60) } }

  ui: Tokens {
    theme: root.hostTheme
    compact: root.compact
    // The two marks, in the theme's own blue and orange where it names them.
    readonly property color cross: hue("blue", "#60a5fa", "#2563eb")
    readonly property color nought: hue("orange", "#fb923c", "#ea580c")
  }

  actions: Component {
    Row {
      spacing: 2
      IconButton {
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
        onClicked: newGame.ask()
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
      blurb: "Noughts and crosses, solved when it starts and then told to err."
      AppearanceSection { app: root }
      LauncherSection { app: root }
      KeysSection {
        app: root
        keys: [
          ["1 – 9", "Play a square, left to right, top to bottom"],
          ["u", "Undo"],
          ["Enter", "Play again, when a game is over"],
          ["n", "New game"],
          [",", "Settings"],
          ["Esc", "Back one step"]
        ]
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Where it keeps the game"
        note: "~/.local/share/moarchy-tictactoe/tictactoe.json: the moves of the game on the board, the score of this sitting and the record against each level. Saved after every move."
      }
    }
  }

  // ------------------------------------------------------------ the game

  property var game: S.fresh()
  property bool loaded: false
  property bool thinking: false

  readonly property var level: T.levelFor(game.level)
  readonly property var position: T.replay(game.moves)
  readonly property bool over: T.isOver(position)
  readonly property var line: T.winningLine(position) || []
  readonly property bool solo: game.mode === S.SOLO
  readonly property bool theirTurn: solo && !over && position.turn !== game.mark
  readonly property bool canUndo: game.moves.length > 0 && !over && !thinking && !reply.running

  readonly property var names: solo ? { a: "You", b: level.label } : S.SEATS
  readonly property var marks: ({ a: game.mark, b: T.other(game.mark) })

  readonly property string status: {
    if (over) return resultText()
    if (solo) return position.turn === game.mark ? "Your move" : level.label + " is playing…"
    return T.NAMES[position.turn] + " to play"
  }

  function resultText() {
    var w = T.winner(position)
    if (w === null) return "A draw — as it should be"
    if (!solo) return S.SEATS[w === game.mark ? "a" : "b"] + " wins as " + T.NAMES[w]
    if (w === game.mark) return "You win as " + T.NAMES[w]
    return level.label + " wins as " + T.NAMES[w]
  }

  function save() { file.save(S.serialize(game)) }

  function tap(cell) {
    if (thinking || reply.running) return
    if (over) { toast("That game is finished. Tap Play again."); return }
    if (theirTurn) return
    // Silent: a tap on a marked square is a miss, and an app that scolds you
    // for a miss on a touch screen scolds you all day long.
    if (!T.isLegal(position, cell)) return
    play(cell)
  }

  function play(cell) {
    game = S.withMoves(game, game.moves.concat([cell]))
    settle()
  }

  // After every move: count a finished game once, or hand the turn over.
  function settle() {
    if (over) {
      if (!game.recorded) {
        game = S.record(game, S.resultOf(game))
        toast(resultText())
      }
    } else if (theirTurn) {
      reply.restart()
    }
    save()
  }

  // A beat before the computer answers. Instant is unsettling on a board this
  // small -- it reads as the app having moved before you did.
  Timer { id: reply; interval: 420; onTriggered: root.answer() }

  function answer() {
    if (!theirTurn) return
    thinking = true
    var cell = T.choose(position, level, null, null)
    thinking = false
    if (cell >= 0 && T.isLegal(position, cell)) play(cell)
  }

  function undo() {
    if (!canUndo) return
    var moves = solo ? T.takeback(game.moves, game.mark) : game.moves.slice(0, -1)
    game = S.withMoves(game, moves)
    save()
    // Taking back the computer's opening mark leaves it on move again -- the
    // one undo that does not end on the person's turn.
    if (theirTurn) reply.restart()
  }

  function rematch() {
    reply.stop()
    game = S.rematch(game)
    save()
    if (theirTurn) reply.restart()
  }

  function begin(mode, levelKey, markValue) {
    reply.stop()
    game = S.begin(game, mode, levelKey, markValue)
    save()
    if (theirTurn) reply.restart()
  }

  DataFile {
    id: file
    app: "tictactoe"
    name: "tictactoe.json"
    onParsed: function (data) {
      // Our own save, read back: nothing to do.
      if (root.loaded && data && S.serialize(S.parse(data)) === S.serialize(root.game)) return
      root.game = S.parse(data)
      root.loaded = true
      // A game finished and saved, then killed before its result was counted.
      if (root.over && !root.game.recorded) root.settle()
      else if (root.theirTurn && root.opened) reply.restart()
    }
    onQuarantined: function (to) { root.toast("The saved game was unreadable and was kept aside") }
  }

  onSummoned: {
    Qt.callLater(function () { T.warm() })
    if (theirTurn) reply.restart()
    // The record is beside the board on a desktop and a page on a phone, and
    // the window's width is not known yet in the first frame.
    wantRecord = (Quickshell.env("MOARCHY_TICTACTOE_PAGE") || "") === "record"
    Qt.callLater(showRecord)
    if (Quickshell.env("MOARCHY_TICTACTOE_NEW")) newGame.ask()
    if (Quickshell.env("MOARCHY_TICTACTOE_SETTINGS")) setTab("settings")
  }
  property bool wantRecord: false
  function showRecord() {
    if (!wantRecord || !compact) return
    wantRecord = false
    push({ kind: "record" })
  }
  onCompactChanged: showRecord()

  // Nothing thinks with the window shut.
  onOpenedChanged: if (!opened) reply.stop()

  keyHandler: function (event) {
    if (topPage || inSettings) return
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    var n = "123456789".indexOf(event.text)
    if (n >= 0 && event.text !== "") { tap(n); event.accepted = true; return }
    if (event.text === "u") { undo(); event.accepted = true; return }
    if (event.text === "n") { newGame.ask(); event.accepted = true; return }
    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && over) { rematch(); event.accepted = true }
  }

  IpcHandler {
    target: "tictactoe"
    function play(square: string): string {
      var cell = parseInt(square, 10)
      if (isNaN(cell)) return "not a square"
      root.tap(cell)
      return "ok"
    }
    function board(): string {
      var out = ""
      for (var i = 0; i < T.CELLS; i++)
        out += (root.position.x >> i) & 1 ? "x" : (root.position.o >> i) & 1 ? "o" : "."
      return out
    }
    function settled(): bool { return !root.thinking && !reply.running }
  }

  // ------------------------------------------------------------ new game

  Dialog {
    id: newGame
    app: root
    title: "New game"
    text: root.game.moves.length || root.game.series.a || root.game.series.b || root.game.series.drawn
      ? "The game on the board and this sitting's score are put away." : ""
    acceptText: "Start"
    property string mode: S.SOLO
    property string levelKey: "fair"
    property int markValue: T.CROSS
    function ask() {
      mode = root.game.mode
      levelKey = root.game.level
      markValue = root.game.mark
      open()
    }
    onAccepted: root.begin(mode, levelKey, markValue)

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
        model: T.LEVELS
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
      text: T.levelFor(newGame.levelKey).blurb
      color: root.ui.muted
      font.family: root.ui.font
      font.pixelSize: root.ui.fs.sm
    }
    Text {
      text: newGame.mode === S.SOLO ? "You play" : "Player one plays"
      color: root.ui.text
      font.family: root.ui.font
      font.pixelSize: root.ui.fs.md
      font.weight: Font.DemiBold
    }
    Flow {
      width: parent.width
      spacing: 8
      Chip { app: root; text: "X — first"; selected: newGame.markValue === T.CROSS; onClicked: newGame.markValue = T.CROSS }
      Chip { app: root; text: "O — second"; selected: newGame.markValue === T.NOUGHT; onClicked: newGame.markValue = T.NOUGHT }
    }
  }

  // ------------------------------------------------------------ the screen

  // Phone: score, board, status and buttons in one column.
  Item {
    anchors.fill: parent
    visible: root.compact
    Controls {
      id: phoneTop
      app: root
      x: root.ui.gutter
      y: 4
      width: parent.width - root.ui.gutter * 2
    }
    Board {
      app: root
      anchors.top: phoneTop.bottom
      anchors.topMargin: 16
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 16
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.margins: root.ui.gutter
      position: root.position
      line: root.line
      onTapped: function (cell) { root.tap(cell) }
    }
  }

  // Desktop: the board, and a pane beside it.
  Item {
    anchors.fill: parent
    visible: !root.compact
    Board {
      id: deskBoard
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.right: pane.left
      anchors.margins: 24
      position: root.position
      line: root.line
      app: root
      onTapped: function (cell) { root.tap(cell) }
    }
    Flickable {
      id: pane
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.rightMargin: 24
      width: Math.min(380, parent.width * 0.42)
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
