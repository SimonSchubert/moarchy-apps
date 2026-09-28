import QtQuick
import Quickshell
import Quickshell.Io
import "kit"
import "kit/Glyphs.js" as KG
import "Mill.js" as M
import "Ai.js" as Ai
import "Store.js" as S

// Mill: Nine Men's Morris against the computer at three levels, or two people
// passing the phone, with a record kept by difficulty.
//
//     omarchy-shell shell toggle org.moarchy.mill
//
// One tap while there is a piece in your hand, two once there is not. In the
// placing phase there is nothing to pick up, so a tap on an empty point is the
// whole move; in the moving phase the piece matters as much as the point, so a
// tap picks one up, rings where it may go, and waits. Taking a piece is one tap
// on one of the pieces ringed in red.
//
// The search runs in a WorkerScript (search.js), after the board has stopped
// moving. A worker cannot be interrupted, so a reply carries the generation it
// was asked under, and one for a board since taken back is dropped.
//
// A phone gets the score, the board and the buttons in one column, the record
// a page away; a desktop gets the board beside a pane with all of it.
App {
  id: root

  appId: "org.moarchy.mill"
  title: "Mill"
  subtitle: solo ? level.label + " · you are " + (game.human === M.WHITE ? "white" : "black") : "Two players"
  windowWidth: 1100
  windowHeight: 780

  store: Store { name: "moarchy-mill" }

  launcher.desktopId: "org.moarchy.Mill"
  launcher.genericName: "Board game"
  launcher.comment: "Nine Men's Morris against the phone, or across a table"
  launcher.categories: "Game;BoardGame;"
  launcher.keywords: "mill;morris;merels;nine;men;board;game;strategy;"

  mark: Component { Image { source: root.appDir + "/icon.svg"; sourceSize: Qt.size(60, 60) } }

  ui: Tokens {
    theme: root.hostTheme
    compact: root.compact
    // The board is the theme's own brown and changes with it; the men stay
    // white and black, because a circle and a circle are told apart only by
    // colour, and two of a theme's hues fail in daylight and for the eight
    // percent of men who cannot tell the popular pair apart.
    readonly property color wood: Qt.tint(bg, alpha(hue("brown", "#986a44", "#986a44"), dark ? 0.22 : 0.40))
    // Shades of the wood, not of the window: the lines stay darker than the
    // board in a light theme as well as a dark one.
    readonly property color boardLine: Qt.tint(wood, alpha("#000000", 0.42))
    readonly property color boardSpot: Qt.tint(wood, alpha("#000000", 0.24))
    readonly property color whiteMan: Qt.tint("#f4f3f1", alpha(text, 0.14))
    readonly property color whiteRim: Qt.tint(whiteMan, alpha("#000000", 0.16))
    readonly property color blackMan: Qt.tint("#0d0d10", alpha(bg, 0.22))
    readonly property color blackRim: Qt.tint(blackMan, alpha("#ffffff", 0.22))
    readonly property color shadow: alpha("#000000", 0.20)
    readonly property color pick: hue("yellow", "#f6d32d", "#e5a50a")
    readonly property color drop: good
    readonly property color take: bad
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
        Column {
          id: recordBody
          x: root.ui.gutter
          y: 8
          width: parent.width - root.ui.gutter * 2
          spacing: 24
          RecordView { app: root; game: root.game; width: parent.width }
          Rules { app: root; width: parent.width }
        }
      }
    }
  }

  settings: Component {
    SettingsPage {
      app: root
      blurb: "Nine Men's Morris against the computer at three levels, or across a table."
      AppearanceSection { app: root }
      LauncherSection { app: root }
      KeysSection {
        app: root
        keys: [
          ["← → ↑ ↓", "Move along the lines of the board"],
          ["Enter, Space", "Tap the point"],
          ["u", "Undo"],
          ["n", "New game"],
          [",", "Settings"],
          ["Esc", "Put a piece back, then back one step"]
        ]
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Where it keeps the game"
        note: "~/.local/share/moarchy-mill/mill.json: the moves of the game on the board, and the record against each level. Saved after every move."
      }
    }
  }

  // ------------------------------------------------------------ the game

  property var game: S.fresh()
  property bool loaded: false
  property bool thinking: false
  property int generation: 0
  // The piece in hand, in the moving phase, and where it may go.
  property int picked: -1
  property var drops: []
  // The board is still moving; nothing plays until it has stopped.
  property bool moving: false

  readonly property var level: Ai.levelFor(game.level)
  readonly property var replay: M.resume(game.moves)
  readonly property var position: replay.position
  readonly property bool drawn: M.drawn(replay)
  readonly property bool over: M.gameOver(replay)
  readonly property bool solo: game.mode === S.SOLO
  readonly property bool theirTurn: solo && !over && position.turn !== game.human
  readonly property bool canUndo: game.moves.length > 0 && !over && !thinking && !reply.running && !moving
  readonly property bool mine: !theirTurn && !thinking && !over
  readonly property var takeable: mine && position.removing ? M.removable(position) : []
  readonly property int last: {
    var m = M.lastMove(game.moves)
    return m === null ? -1 : M.unpack(m)[1]
  }

  readonly property var names: {
    if (!solo) return { 0: "White", 1: "Black" }
    var out = ({})
    out[game.human] = "You"
    out[M.other(game.human)] = level.label
    return out
  }

  readonly property string status: {
    if (over) return resultText()
    if (thinking) return names[position.turn] + " is thinking…"
    var who = names[position.turn]
    if (theirTurn) return who + " to play"
    if (position.removing) return "A mill — take one of " + names[M.other(position.turn)] + "'s pieces"
    if (M.placing(position, position.turn))
      return "Place a piece — " + M.left(position, position.turn) + " left in hand"
    if (M.flying(position, position.turn)) return "Three left: move anywhere"
    return "Move a piece along a line"
  }

  function resultText() {
    if (drawn) return "A draw — fifty moves with nothing taken"
    var w = M.winner(position)
    if (w === null) return "A draw"
    var left = M.count(position, w)
    if (!solo) return M.NAMES[w] + " wins with " + left + " left"
    if (w === game.human) return "You win with " + left + " left"
    return level.label + " wins with " + left + " left"
  }

  function save() { file.save(S.serialize(game)) }

  function clearHand() { picked = -1; drops = [] }

  function tap(spot) {
    if (thinking || reply.running || moving) return
    if (over) { toast("That game is finished. Tap New game."); return }
    if (theirTurn) return
    var p = position

    if (p.removing) {
      // Silent otherwise: the red rings have already said which ones.
      if (M.removable(p).indexOf(spot) >= 0) play(M.placeMove(spot))
      return
    }
    if (M.placing(p, p.turn)) {
      if ((M.empty(p) >> spot) & 1) play(M.placeMove(spot))
      return
    }
    if (picked >= 0) {
      if (drops.indexOf(spot) >= 0) {
        var held = picked
        clearHand()
        play(M.travel(held, spot))
        return
      }
      // Tapping the piece in hand puts it back down: there is no other way to
      // change your mind.
      var same = spot === picked
      clearHand()
      if (same) return
    }
    if ((M.own(p) >> spot) & 1) {
      var to = M.destinations(p, spot)
      if (to.length) { picked = spot; drops = to }
    }
  }

  function play(move) {
    var what = M.describe(position, move)
    clearHand()
    game = S.withMoves(game, game.moves.concat([move]))
    save()
    moving = true
    board.animate(what)
  }

  // The board has stopped moving: count a finished game once, or hand over.
  function settled() {
    moving = false
    if (over) { if (!game.recorded) finish() }
    else if (theirTurn) reply.restart()
  }

  function finish() {
    if (solo) {
      var r = S.resultOf(game)
      game = S.record(game, r.result, r.margin)
    } else {
      game = S.settled(game)
    }
    save()
    toast(resultText())
  }

  // A beat before the computer starts, so its piece does not land while
  // yours is still sliding.
  Timer { id: reply; interval: 260; onTriggered: root.ponder() }

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
    var move = answer.move
    if (!M.isLegal(position, move)) {
      // Never seen, and guarded anyway: a board nobody can play on is worse
      // than a weak move.
      var legal = M.moves(position)
      if (!legal.length) return
      move = legal[0]
    }
    play(move)
  }

  function undo() {
    if (!canUndo) return
    clearHand()
    var moves = solo ? M.takeback(game.moves, game.human) : M.undo(game.moves)
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
    clearHand()
    game = S.begin(game, mode, levelKey, human)
    save()
    if (theirTurn) reply.restart()
  }

  function askNewGame() { newGame.ask() }

  // For the screenshots: pick up the first piece that can move. The rings
  // round a piece in hand are the one thing no environment variable can
  // otherwise reach, because reaching it is a tap on a point that depends on
  // the game.
  function pickSomething() {
    var p = position
    if (p.removing || M.placing(p, p.turn)) return
    for (var s = 0; s < M.POINTS; s++) {
      if ((M.own(p) >> s) & 1 && M.destinations(p, s).length) {
        picked = s
        drops = M.destinations(p, s)
        return
      }
    }
  }

  // The search, behind a Loader so it can be taken down before the process
  // is: tearing the engine down with a WorkerScript thread alive takes the
  // process with it. Unloading joins the thread first.
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
    clearHand()
  }

  stepBack: function () {
    if (picked >= 0) { clearHand(); return true }
    if (cursor >= 0) { cursor = -1; return true }
    return false
  }

  DataFile {
    id: file
    app: "mill"
    name: "mill.json"
    onParsed: function (data) {
      // Our own save, read back: nothing to do.
      if (root.loaded && data && S.serialize(S.parse(data)) === S.serialize(root.game)) return
      root.generation += 1
      root.thinking = false
      root.clearHand()
      root.game = S.parse(data)
      root.loaded = true
      if (!root.opened) return
      // A result owed from a session killed between the move and the count.
      if (root.over && !root.game.recorded) root.finish()
      else if (root.theirTurn) reply.restart()
      if (root.wantPick) Qt.callLater(root.pickSomething)
    }
    onQuarantined: function (to) { root.toast("The saved game was unreadable and was kept aside") }
  }

  property bool wantPick: false
  onSummoned: {
    // A phone app is closed by being killed, often on the computer's turn:
    // the search starts again by itself, with no tap coming.
    if (over && loaded && !game.recorded) finish()
    else if (theirTurn) reply.restart()
    wantRecord = (Quickshell.env("MOARCHY_MILL_PAGE") || "") === "record"
    Qt.callLater(showRecord)
    if (Quickshell.env("MOARCHY_MILL_NEW")) newGame.ask()
    if (Quickshell.env("MOARCHY_MILL_SETTINGS")) setTab("settings")
    wantPick = !!Quickshell.env("MOARCHY_MILL_PICK")
    if (wantPick && loaded) Qt.callLater(pickSomething)
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

  // ------------------------------------------------------------ keyboard

  // The keyboard's point: shown once an arrow key has been pressed. The board
  // is a 7x7 lattice with holes, and an arrow goes to the nearest point that
  // way, along the line first.
  property int cursor: -1
  function lattice(spot) {
    var o = [[-1, -1], [0, -1], [1, -1], [1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0]][M.placeOf(spot)]
    var r = 3 - M.ringOf(spot)
    return { x: 3 + o[0] * r, y: 3 + o[1] * r }
  }
  function moveCursor(dx, dy) {
    if (cursor < 0) { cursor = picked >= 0 ? picked : 1; return }
    var here = lattice(cursor)
    var best = -1, score = Infinity
    for (var s = 0; s < M.POINTS; s++) {
      var c = lattice(s)
      var along = dx ? (c.x - here.x) * dx : (c.y - here.y) * dy
      var across = dx ? Math.abs(c.y - here.y) : Math.abs(c.x - here.x)
      if (along <= 0) continue
      var sc = across * 10 + along
      if (sc < score) { score = sc; best = s }
    }
    if (best >= 0) cursor = best
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
    if (event.text === "n") { newGame.ask(); event.accepted = true }
  }

  IpcHandler {
    target: "mill"
    // A move by name -- "a1" to place or take, "a2-a3" to slide -- so a
    // script cannot play the wrong point.
    function play(move: string): string {
      var parts = move.split("-")
      var spots = []
      for (var i = 0; i < parts.length; i++) {
        var found = -1
        for (var s = 0; s < M.POINTS; s++) if (M.notation(s) === parts[i]) found = s
        if (found < 0) return "no such point: " + parts[i]
        spots.push(found)
      }
      var before = root.game.moves.length
      root.clearHand()
      for (var j = 0; j < spots.length; j++) root.tap(spots[j])
      return root.game.moves.length > before ? "ok" : "not a move"
    }
    function board(): string {
      var out = ""
      for (var s = 0; s < M.POINTS; s++)
        out += (root.position.white >> s) & 1 ? "w" : (root.position.black >> s) & 1 ? "b" : "."
      return out
    }
    function moves(): int { return root.game.moves.length }
    function status(): string { return root.status }
    function settled(): bool { return !root.thinking && !reply.running && !root.moving }
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
    property int human: M.WHITE
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
      Chip { app: root; text: "White — first"; selected: newGame.human === M.WHITE; onClicked: newGame.human = M.WHITE }
      Chip { app: root; text: "Black — second"; selected: newGame.human === M.BLACK; onClicked: newGame.human = M.BLACK }
    }
  }

  // ------------------------------------------------------------ the screen

  // The one board, moved between the two layouts rather than drawn twice, so
  // a slide in progress survives the window being resized across the line.
  Board {
    id: board
    app: root
    parent: root.compact ? phoneSlot : deskSlot
    anchors.fill: parent
    position: root.position
    picked: root.picked
    drops: root.drops
    takeable: root.takeable
    last: root.last
    cursor: root.cursor
    onTapped: function (spot) { root.tap(spot) }
    onSettled: root.settled()
  }

  // Phone: the score, the board and what it is saying travel together,
  // centred in the height the buttons leave, and the buttons are along the
  // bottom, under the thumb already holding the phone -- 0.1.0's layout.
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
        readonly property real boardSide: Math.max(64, Math.min(phoneArea.width - 8, phoneArea.height - 64 - 24 - 40))
        anchors.centerIn: parent
        width: phoneArea.width - 16
        spacing: 10
        ScoreStrip {
          app: root
          width: parent.width
          position: root.position
          names: root.names
          turn: root.over ? -1 : root.position.turn
        }
        Item {
          id: phoneSlot
          width: parent.width
          height: phoneBlock.boardSide
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          text: root.status
          color: root.over ? root.ui.accent : root.ui.muted
          font.family: root.ui.font
          font.pixelSize: root.ui.fs.md
          font.weight: root.over ? Font.Bold : Font.Normal
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
    Item {
      id: deskSlot
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.right: pane.left
      anchors.margins: 24
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
        Rules { app: root; width: parent.width }
      }
    }
  }
}
