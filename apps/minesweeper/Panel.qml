import QtQuick
import Quickshell
import Quickshell.Io
import "kit"
import "kit/Glyphs.js" as KG
import "Minesweeper.js" as M
import "Store.js" as S

// Minesweeper: a portrait board, a latching flag, and a clock that stops with
// the window. Three boards shaped for a phone, the first tap never a mine and
// never a number, and the same mines again after losing one.
//
//     omarchy-shell shell toggle org.moarchy.minesweeper
//
// The file holds a seed and the taps, not the mines (Store.js), and the board
// is replayed from them; Random.js is CPython's Mersenne Twister, so a board
// left in the GTK version comes back with the same mines under it.
//
// A phone gets the readings, the board and two buttons in one column; a
// desktop gets the board beside a pane with the readings, the buttons and the
// record. There, the right button flags and the arrow keys move a cursor.
App {
  id: root

  appId: "org.moarchy.minesweeper"
  title: "Minesweeper"
  subtitle: compact ? level.label + " · " + level.mines + " mines"
    : level.label + " · " + level.width + " × " + level.height + ", " + level.mines + " mines"
  windowWidth: 1100
  windowHeight: 800

  store: Store { name: "moarchy-minesweeper" }

  launcher.desktopId: "org.moarchy.Minesweeper"
  launcher.genericName: "Puzzle"
  launcher.comment: "Clear the field without opening a mine"
  launcher.categories: "Game;LogicGame;"
  launcher.keywords: "minesweeper;mines;sweeper;puzzle;flags;"

  mark: Component { Image { source: root.appDir + "/icon.svg"; sourceSize: Qt.size(60, 60) } }

  ui: Tokens {
    theme: root.hostTheme
    compact: root.compact
    // A covered cell stands off the window and an opened one sinks into it:
    // both are the theme's text mixed into its background, which moves the
    // right way on a light theme and a dark one alike.
    readonly property color lid: Qt.tint(bg, alpha(text, 0.17))
    readonly property color lidTop: Qt.tint(lid, Qt.rgba(1, 1, 1, dark ? 0.16 : 0.6))
    readonly property color pit: Qt.tint(bg, alpha(text, 0.05))
    // Eight numbers and eight hues: the classic 1 blue, 2 green, 3 red, then
    // the two nobody remembers. Lifted toward the text, so a brown 5 on a dark
    // theme is not brown on brown.
    readonly property var numbers: [
      Qt.tint(hue("blue", "#60a5fa", "#2563eb"), alpha(text, 0.22)),
      Qt.tint(hue("green", "#4ade80", "#16a34a"), alpha(text, 0.22)),
      Qt.tint(hue("red", "#f87171", "#dc2626"), alpha(text, 0.22)),
      Qt.tint(hue("magenta", "#c084fc", "#9333ea"), alpha(text, 0.22)),
      Qt.tint(hue("brown", "#d6a36b", "#92400e"), alpha(text, 0.22)),
      Qt.tint(hue("cyan", "#22d3ee", "#0891b2"), alpha(text, 0.22)),
      Qt.tint(hue("orange", "#fb923c", "#ea580c"), alpha(text, 0.22)),
      Qt.tint(hue("yellow", "#facc15", "#a16207"), alpha(text, 0.22))
    ]
    readonly property color flag: hue("red", "#f87171", "#dc2626")
    readonly property color inkOnFlag: dark ? "#111111" : "#ffffff"
    readonly property color pole: text
    readonly property color mine: text
    readonly property color boom: hue("red", "#f87171", "#dc2626")
    readonly property color wrong: hue("orange", "#fb923c", "#ea580c")
  }

  // A phone's two buttons for a board are under it and its record is a page;
  // a desktop has all three in the pane beside the board.
  actions: Component {
    Row {
      spacing: 2
      visible: root.compact
      IconButton {
        app: root
        glyph: KG.history
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
      blurb: "Clear the field without opening a mine. The first tap is never one."
      AppearanceSection { app: root }
      LauncherSection { app: root }
      KeysSection {
        app: root
        keys: [
          ["Arrows", "Move the cursor over the board"],
          ["Space  Enter", "Open, or clear round a number"],
          ["f", "Flag the cell under the cursor"],
          ["m", "Latch the flag button"],
          ["Right button", "Flag"],
          ["n", "New game"],
          ["a", "This board again"],
          [",", "Settings"],
          ["Esc", "Back one step"]
        ]
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Where it keeps the game"
        note: "~/.local/share/moarchy-minesweeper/minesweeper.json: the board's level and seed and every tap on it -- not the mines, which the seed puts back -- the clock, and the record for each board. Saved after every tap."
      }
    }
  }

  // ------------------------------------------------------------ the game

  property var game: S.fresh()
  // The board replayed from `game`, and changed in place by a tap; `revision`
  // is how a binding hears about that.
  property var board: S.game(game)
  property int revision: 0
  property bool marking: false
  property bool loaded: false

  readonly property var level: M.levelFor(game.level)
  readonly property int seconds: game.seconds
  readonly property bool started: revision >= 0 && M.started(board)
  readonly property bool over: revision >= 0 && M.isOver(board)
  readonly property bool running: started && !over
  readonly property int remaining: revision >= 0 ? M.remaining(board) : 0

  readonly property string status: {
    var r = revision
    if (M.won(board)) return "Cleared in " + M.clock(seconds)
    if (M.lost(board)) {
      var wrong = M.wrongFlags(board).length
      return wrong ? "A mine — and " + wrong + " flag" + (wrong === 1 ? "" : "s") + " wrong" : "A mine."
    }
    if (!M.started(board)) return "The first tap is never a mine"
    if (compact) return marking ? "Tap to flag · hold to open" : "Tap to open · hold to flag"
    return marking ? "Click to flag · right-click to open" : "Click to open · right-click to flag"
  }

  function setGame(next) {
    game = next
    board = S.game(next)
    revision += 1
  }

  function save() { file.save(S.serialize(game)) }

  // A tap: open, or flag when the flag is latched, or clear round a number.
  function press(cell) {
    if (over) { toast("That board is finished. Tap New game."); return }
    if (marking) act(M.mark(board, cell))
    else if (board.opened[cell]) act(M.clearAround(board, cell))
    else act(M.tap(board, cell))
  }

  // A hold does the other thing, whichever way the button is latched.
  function hold(cell) {
    if (over) return
    if (board.opened[cell]) act(M.clearAround(board, cell))
    else if (marking) act(M.tap(board, cell))
    else act(M.mark(board, cell))
  }

  // A press that changed nothing -- an open cell, a number whose flags do not
  // add up -- is silent. An app that scolds you for a miss on a touch screen
  // scolds you all day long.
  function act(changed) {
    if (!changed) return
    game = S.withMoves(game, board.moves)
    revision += 1
    if (over) finish()
    save()
  }

  // Count the result once, and say what it was.
  function finish() {
    if (game.recorded || !over) return
    var won = M.won(board)
    game = S.record(game, won ? S.WON : S.LOST, seconds)
    marking = false
    if (won) {
      var entry = S.recordFor(game, game.level)
      toast("Cleared in " + M.clock(seconds) + (entry.best === seconds && entry.won > 1 ? " — a best" : ""))
    }
  }

  // A board walked away from counts as a loss once it has been started:
  // tapping nothing and choosing another level is not a game anybody played,
  // opening half a board and leaving because it was going badly is.
  function abandon() {
    if (started && !over && !game.recorded) game = S.record(game, S.LOST, seconds)
  }

  function begin(levelKey, seed) {
    abandon()
    marking = false
    setGame(S.begin(game, levelKey, seed))
    save()
  }

  // The same mines again. What everybody wants after losing one.
  function sameBoard() {
    begin(game.level, game.seed)
    toast("The same mines again")
  }

  // Whether somebody can be looking at the board. As its own process, that is
  // whether the app has the focus: another app over it takes it. Inside the
  // shell the process is the shell's, which always has it, so there it is
  // whether the window is open.
  // qmllint disable missing-property
  readonly property bool looked: opened && (!standalone || Qt.application.state === Qt.ApplicationActive)
  // qmllint enable missing-property

  // The clock, a second at a time, only while the board is looked at and a
  // game is on. Saved once a minute rather than once a second -- an fsync a
  // second for an hour is thousands of writes to a phone's flash -- and
  // whenever it stops.
  Timer {
    id: tick
    interval: 1000
    repeat: true
    running: root.looked && root.running
    onTriggered: {
      root.game = S.withSeconds(root.game, root.game.seconds + 1)
      if (root.game.seconds % 60 === 0) root.save()
    }
    onRunningChanged: if (!running && root.loaded) root.save()
  }

  DataFile {
    id: file
    app: "minesweeper"
    name: "minesweeper.json"
    onParsed: function (data) {
      // Our own save, read back: nothing to do.
      if (root.loaded && data && S.serialize(S.parse(data)) === S.serialize(root.game)) return
      // Only on the way in, or when something else wrote the file while the
      // window was shut: a clock tick is not worth losing a game over.
      if (root.loaded && root.opened) return
      root.setGame(S.parse(data))
      root.loaded = true
      // A game finished and saved, then killed before its result was counted.
      if (root.over && !root.game.recorded) { root.finish(); root.save() }
    }
    onQuarantined: function (to) { root.toast("The saved game was unreadable and was kept aside") }
  }

  property bool wantRecord: false
  function showRecord() {
    if (!wantRecord || !compact) return
    wantRecord = false
    push({ kind: "record" })
  }
  onCompactChanged: showRecord()

  onSummoned: {
    wantRecord = (Quickshell.env("MOARCHY_MINESWEEPER_PAGE") || "") === "record"
    Qt.callLater(showRecord)
    if (Quickshell.env("MOARCHY_MINESWEEPER_NEW")) chooser.ask()
    if (Quickshell.env("MOARCHY_MINESWEEPER_MARKING")) marking = true
    if (Quickshell.env("MOARCHY_MINESWEEPER_SETTINGS")) setTab("settings")
  }

  // ------------------------------------------------------------ keys

  property int cursor: -1
  function moveCursor(dr, dc) {
    if (cursor < 0) { cursor = M.index(Math.floor(level.height / 2), Math.floor(level.width / 2), level.width); return }
    var r = Math.max(0, Math.min(level.height - 1, M.rowOf(cursor, level.width) + dr))
    var c = Math.max(0, Math.min(level.width - 1, M.columnOf(cursor, level.width) + dc))
    cursor = M.index(r, c, level.width)
  }

  keyHandler: function (event) {
    if (topPage || inSettings) return
    var k = event.key
    if (k === Qt.Key_Left) { moveCursor(0, -1); event.accepted = true; return }
    if (k === Qt.Key_Right) { moveCursor(0, 1); event.accepted = true; return }
    if (k === Qt.Key_Up) { moveCursor(-1, 0); event.accepted = true; return }
    if (k === Qt.Key_Down) { moveCursor(1, 0); event.accepted = true; return }
    if ((k === Qt.Key_Space || k === Qt.Key_Return || k === Qt.Key_Enter) && cursor >= 0) { press(cursor); event.accepted = true; return }
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    if (event.text === "f" && cursor >= 0) { hold(cursor); event.accepted = true; return }
    if (event.text === "m" && !over) { marking = !marking; event.accepted = true; return }
    if (event.text === "n") { chooser.ask(); event.accepted = true; return }
    if (event.text === "a") { sameBoard(); event.accepted = true }
  }

  IpcHandler {
    target: "minesweeper"
    function open(cell: int): string { root.press(cell); return root.status }
    function flag(cell: int): string { root.hold(cell); return root.status }
    function state(): string {
      return JSON.stringify({ level: root.game.level, moves: root.game.moves.length,
                              remaining: root.remaining, seconds: root.seconds, status: root.status })
    }
  }

  // ------------------------------------------------------------ new game

  Dialog {
    id: chooser
    app: root
    title: "New game"
    text: root.running ? "The game in progress will count as a loss." : ""
    acceptText: "Start"
    property string pick: "standard"
    function ask() { pick = root.game.level; open() }
    onAccepted: root.begin(pick)

    Repeater {
      model: M.LEVELS
      delegate: ListRow {
        required property var modelData
        readonly property var entry: S.recordFor(root.game, modelData.key)
        app: root
        width: parent.width
        title: modelData.label
        text: modelData.width + " × " + modelData.height + ", " + modelData.mines + " mines · one cell in "
          + Math.round(M.cellCount(modelData) / modelData.mines)
        trailing: entry.best ? M.clock(entry.best) : "—"
        selected: chooser.pick === modelData.key
        glyph: selected ? KG.check : ""
        glyphColor: root.ui.accent
        onClicked: chooser.pick = modelData.key
      }
    }
  }

  // ------------------------------------------------------------ the screen

  // Phone: the readings, the board and the status in one column.
  Item {
    anchors.fill: parent
    visible: root.compact
    Readings {
      id: phoneReadings
      app: root
      x: root.ui.gutter
      y: 4
      width: parent.width - root.ui.gutter * 2
    }
    Text {
      id: phoneStatus
      anchors.top: phoneReadings.bottom
      anchors.topMargin: 10
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: root.status
      color: root.over ? root.ui.accent : root.ui.muted
      font.family: root.ui.font
      font.pixelSize: root.ui.fs.md
      font.weight: root.over ? Font.Bold : Font.Normal
    }
    Field {
      app: root
      anchors.top: phoneStatus.bottom
      anchors.topMargin: 8
      anchors.bottom: phoneButtons.top
      anchors.bottomMargin: 8
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: 6
      anchors.rightMargin: 6
      game: root.board
      revision: root.revision
      onPressed: function (cell) { root.press(cell) }
      onHeld: function (cell) { root.hold(cell) }
    }
    Row {
      id: phoneButtons
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 12
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 10
      Button {
        app: root
        text: "New game"
        glyph: KG.plus
        primary: root.over
        onClicked: chooser.ask()
      }
      Button {
        app: root
        text: "This board again"
        glyph: KG.refresh
        onClicked: root.sameBoard()
      }
    }
  }

  // Desktop: the board, and a pane beside it.
  Item {
    anchors.fill: parent
    visible: !root.compact
    Field {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.right: pane.left
      anchors.margins: 20
      app: root
      game: root.board
      revision: root.revision
      cursor: root.cursor
      onPressed: function (cell) { root.cursor = -1; root.press(cell) }
      onHeld: function (cell) { root.cursor = -1; root.hold(cell) }
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
        spacing: 18
        Readings { app: root; width: parent.width }
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: root.status
          color: root.over ? root.ui.accent : root.ui.text
          font.family: root.ui.font
          font.pixelSize: root.ui.fs.lg
          font.weight: Font.Bold
        }
        Row {
          spacing: 10
          Button {
            app: root
            text: "New game"
            glyph: KG.plus
            primary: root.over
            onClicked: chooser.ask()
          }
          Button {
            app: root
            text: "This board again"
            glyph: KG.refresh
            onClicked: root.sameBoard()
          }
        }
        RecordView { app: root; game: root.game; width: parent.width }
      }
    }
  }
}
