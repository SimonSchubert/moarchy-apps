import QtQuick
import Quickshell
import Quickshell.Io
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G
import "Pegs.js" as P
import "Store.js" as S
import "Solver.js" as Solver

// Peg solitaire: nine figures that can all be finished, and a hint that is a
// proof rather than a guess.
//
//     omarchy-shell shell toggle org.moarchy.pegsolitaire
//
// A tap jumps a peg when it has one jump to make and picks it up when it has
// more than one, with the holes it can reach ringed: most pegs on most boards
// have exactly one thing to do, and a two-tap protocol for every one of those
// is a tap spent on ceremony.
//
// Hint runs the solver (Solver.js) in a WorkerScript (solve.js), on a
// two-second clock, and answers with a jump, a proof that there is none, or an
// honest "no answer in two seconds". A found line is kept whole: following it
// makes the next hint free, and playing anything else throws it away. A worker
// cannot be interrupted, so an answer carries the generation it was asked
// under, and one for a board that has since changed is dropped.
//
// A phone gets the board with Undo and Hint under the thumb; a desktop gets
// the board beside a pane with the buttons, the nine figures and the record.
App {
  id: root

  appId: "org.moarchy.pegsolitaire"
  title: "Peg Solitaire"
  subtitle: figure.label
  windowWidth: 1120
  windowHeight: 800

  store: Store { name: "moarchy-pegsolitaire" }

  launcher.desktopId: "org.moarchy.PegSolitaire"
  launcher.genericName: "Puzzle"
  launcher.comment: "Jump pegs until one is left, on nine solvable figures"
  launcher.categories: "Game;LogicGame;"
  launcher.keywords: "peg;solitaire;solo;noble;marbles;puzzle;brainvita;"

  mark: Component { Image { source: root.appDir + "/icon.svg"; sourceSize: Qt.size(60, 60) } }

  // Colour b with a share t of colour a over it: pegs.py's mix().
  function mix(a, b, t) { return Qt.tint(b, ui.alpha(a, t)) }

  ui: Tokens {
    theme: root.hostTheme
    compact: root.compact
    // A wooden thing, and every theme's brown where it names one. A dark theme
    // wants the wood dark enough that a lit peg sits on it; a light one wants
    // enough of the hue that it is wood rather than beige.
    readonly property color wood: root.mix(hue("brown", "#986a44", "#986a44"), bg, dark ? 0.24 : 0.46)
    // A hole is darker than the board on both themes: a lighter one reads as
    // a peg somebody has painted the wrong colour.
    readonly property color hole: root.mix("#000000", wood, 0.42)
    readonly property color holeRim: root.mix("#ffffff", wood, 0.10)
    // The pegs are the subject, and want to be the brightest thing there.
    readonly property color peg: accent
    readonly property color pegRim: root.mix("#000000", peg, 0.30)
    readonly property color pegTop: root.mix("#ffffff", peg, 0.28)
    readonly property color shadow: alpha("#000000", 0.22)
    readonly property color pick: hue("yellow", "#f5c211", "#c88800")
    readonly property color drop: hue("green", "#33d17a", "#1f9d55")
  }

  actions: Component {
    Row {
      spacing: 2
      IconButton {
        app: root
        glyph: G.figures
        label: "Figures"
        visible: root.compact
        onClicked: root.push({ kind: "figures" })
      }
      IconButton {
        visible: root.compact
        app: root
        glyph: G.record
        label: "Record"
        onClicked: root.push({ kind: "record" })
      }
    }
  }

  page: Component {
    Item {
      PageHeader {
        id: pageHead
        app: root
        width: parent.width
        title: root.topPage && root.topPage.kind === "figures" ? "Figures" : "Record"
      }
      Flickable {
        anchors.top: pageHead.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentHeight: pageBody.implicitHeight + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
          id: pageBody
          x: root.ui.gutter
          y: 8
          width: parent.width - root.ui.gutter * 2
          spacing: 14
          // The phone's way to begin the figure on the board over: the header
          // has room for two buttons and a title, and this is where the other
          // ways of starting live.
          Button {
            visible: root.topPage && root.topPage.kind === "figures"
            app: root
            glyph: KG.refresh
            text: "Start " + root.figure.label + " again"
            enabled: root.game.moves.length > 0
            onClicked: { root.pop(); root.startAgain() }
          }
          FigureList {
            visible: root.topPage && root.topPage.kind === "figures"
            app: root
            width: parent.width
            game: root.game
            current: root.figure.key
            onChosen: function (key) { root.pop(); root.begin(key) }
          }
          RecordView {
            visible: root.topPage && root.topPage.kind === "record"
            app: root
            width: parent.width
            game: root.game
          }
        }
      }
    }
  }

  settings: Component {
    SettingsPage {
      app: root
      blurb: "Peg solitaire on nine figures that can all be finished, with a hint that runs the solver."
      AppearanceSection { app: root }
      LauncherSection { app: root }
      KeysSection {
        app: root
        keys: [
          ["← ↑ → ↓", "Move round the board"],
          ["Enter, Space", "Tap the hole the ring is on"],
          ["h", "Hint"],
          ["u", "Undo"],
          ["n", "Start this figure again"],
          ["1 – 9", "Start a figure"],
          [",", "Settings"],
          ["Esc", "Put a picked-up peg down, then back"]
        ]
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Where it keeps the game"
        note: "~/.local/share/moarchy-pegsolitaire/pegsolitaire.json: the figure on the board, the jumps made on it, and the fewest pegs every figure has been left at. Saved after every jump."
      }
    }
  }

  // ------------------------------------------------------------ the game

  property var game: S.fresh()
  property bool loaded: false

  readonly property var played: P.resume(game.figure, game.moves)
  readonly property var figure: played.figure
  readonly property var position: played.position
  readonly property int pegsLeft: P.pegCount(position)
  readonly property var legal: P.moves(position)
  readonly property bool over: legal.length === 0
  readonly property bool perfect: P.perfect(played)

  // The peg picked up and where it can land; the hint's arrow; the rest of a
  // line the solver found.
  property int picked: -1
  property var drops: []
  property var hintShown: []
  property var line: []
  property bool thinking: false
  property int generation: 0
  property int cursor: P.CENTRE

  readonly property bool canUndo: game.moves.length > 0 && !thinking && !activeBoard.busy
  readonly property bool canHint: !over && !thinking

  readonly property string status: {
    if (thinking) return "Looking for a way through…"
    if (over) {
      var jumps = game.moves.length
      var best = S.recordFor(game, figure.key).best
      var made = jumps + (jumps === 1 ? " jump" : " jumps")
      return best ? made + " · best here " + best : made
    }
    var n = legal.length
    return n + (n === 1 ? " jump" : " jumps") + " · finish on " + (figure.centre ? "one peg, in the middle" : "one peg")
  }

  readonly property string resultText: {
    if (perfect) return "One peg, in the middle. That is the whole puzzle."
    if (pegsLeft === 1)
      return figure.centre ? "One peg — but not the one in the middle." : "One peg. That is as far as this figure goes."
    return "Stuck with " + pegsLeft + " pegs."
  }

  function save() { file.save(S.serialize(game)) }

  function clearPick() { picked = -1; drops = [] }

  function tap(cell) {
    if (activeBoard.busy || thinking) return
    if (over) { toast("Nothing else will move. Tap Start again."); return }
    if (picked >= 0) {
      var at = drops.indexOf(cell)
      if (at >= 0) {
        var from = P.jumpsFrom(position, picked)
        for (var i = 0; i < from.length; i++)
          if (P.landing(from[i])[1] === cell) { clearPick(); play(from[i]); return }
      }
      // Tapping the peg you picked up puts it back down.
      var same = cell === picked
      clearPick()
      if (same) return
    }
    var jumps = P.jumpsFrom(position, cell)
    // Silent: a tap on a peg that cannot move, or on an empty hole, is a miss,
    // and an app that scolds you for a miss scolds you all day long.
    if (!jumps.length) return
    if (jumps.length === 1) { play(jumps[0]); return }
    picked = cell
    drops = jumps.map(function (m) { return P.landing(m)[1] })
  }

  function play(move) {
    if (!P.isLegal(position, move)) return
    // Following the hint keeps the rest of it; anything else throws it away.
    if (line.length && line[0] === move) line = line.slice(1)
    else line = []
    hintShown = []
    game = S.withMoves(game, game.moves.concat([move]))
    save()
    activeBoard.animate(move)
  }

  // After a hop has landed: count a finished board once, and say so.
  function settled() {
    if (over && !game.recorded) {
      game = S.record(game, pegsLeft, perfect)
      save()
      toast(resultText)
    }
  }

  function undo() {
    if (!canUndo) return
    clearPick()
    hintShown = []
    // The line was for a board that no longer exists, and so is any search.
    line = []
    generation += 1
    thinking = false
    game = S.withMoves(game, game.moves.slice(0, -1))
    save()
  }

  function reset(next) {
    generation += 1
    thinking = false
    clearPick()
    hintShown = []
    line = []
    game = next
    cursor = P.CENTRE
    save()
  }

  // The same figure from the top. Nothing is recorded for giving up: backing
  // out and trying a different third jump is how this game is played.
  function startAgain() { reset(S.again(game)) }
  function begin(key) { reset(S.begin(game, key)) }

  // ------------------------------------------------------------ the hint

  function hint() {
    if (!canHint || activeBoard.busy) return
    clearPick()
    if (line.length && P.isLegal(position, line[0])) {
      // Already known: a line the solver found is being followed.
      showHint(line[0])
      return
    }
    if (!brainLoader.active) brainLoader.active = true
    if (!brain) return
    thinking = true
    generation += 1
    brain.sendMessage({ holes: position.holes, pegs: position.pegs,
                        target: figure.centre ? P.CENTRE : -1,
                        seconds: Solver.SECONDS, generation: generation })
  }

  function thought(answer) {
    if (answer.generation !== generation) return   // a different board now
    thinking = false
    if (answer.verdict === Solver.SOLVED && answer.line.length) {
      line = answer.line
      showHint(line[0])
      return
    }
    line = []
    if (answer.verdict === Solver.IMPOSSIBLE)
      toast("No way to finish from here — " + pegsLeft + " pegs is as low as it goes")
    else
      toast("No answer inside two seconds. Try a jump and ask again")
  }

  function showHint(move) { hintShown = [P.decode(move)[0], P.landing(move)[1]] }

  // The solver's thread, behind a Loader so it can be taken down before the
  // process is: tearing the engine down with a WorkerScript thread alive takes
  // the process with it. Unloading joins the thread first.
  Loader {
    id: brainLoader
    active: false
    sourceComponent: WorkerScript {
      source: "solve.js"
      onMessage: function (answer) { root.thought(answer) }
    }
  }
  readonly property WorkerScript brain: brainLoader.item as WorkerScript
  onQuitting: brainLoader.active = false

  // Closed, nothing thinks: a search in flight is orphaned by its generation.
  onOpenedChanged: if (!opened) {
    generation += 1
    thinking = false
    clearPick()
  }

  DataFile {
    id: file
    app: "pegsolitaire"
    name: "pegsolitaire.json"
    onParsed: function (data) {
      // Our own save, read back: nothing to do.
      if (root.loaded && data && S.serialize(S.parse(data)) === S.serialize(root.game)) return
      root.generation += 1
      root.thinking = false
      root.clearPick()
      root.hintShown = []
      root.line = []
      root.game = S.parse(data)
      root.loaded = true
      // A board played out and saved, then killed before it was counted.
      root.settled()
    }
    onQuarantined: function (to) { root.toast("The saved game was unreadable and was kept aside") }
  }

  // Screenshots, and a script that wants one screen: the record, the
  // figures, or the hint already asked for.
  property bool wantPage: false
  onSummoned: {
    var page = Quickshell.env("MOARCHY_PEGSOLITAIRE_PAGE") || ""
    wantPage = page !== "" || !!Quickshell.env("MOARCHY_PEGSOLITAIRE_FIGURES")
    Qt.callLater(showWanted)
    if (Quickshell.env("MOARCHY_PEGSOLITAIRE_HINT")) hintLater.start()
  }
  function showWanted() {
    if (!wantPage || !compact) return
    wantPage = false
    var page = Quickshell.env("MOARCHY_PEGSOLITAIRE_PAGE") || ""
    push({ kind: page === "record" ? "record" : "figures" })
  }
  onCompactChanged: showWanted()
  Timer { id: hintLater; interval: 400; onTriggered: root.hint() }

  // One step out before the app's own: a picked-up peg goes back down.
  stepBack: function () {
    if (picked >= 0) { clearPick(); return true }
    if (hintShown.length) { hintShown = []; return true }
    return false
  }

  keyHandler: function (event) {
    if (topPage || inSettings) return
    var k = event.key
    var r = P.rowOf(cursor), c = P.columnOf(cursor)
    var moveCursor = function (dr, dc) {
      // Skip the cut-off corners: the next hole along, if there is one.
      var rr = r + dr, cc = c + dc
      while (rr >= 0 && rr < P.SIZE && cc >= 0 && cc < P.SIZE) {
        if (P.has(root.position.holes, P.index(rr, cc))) { root.cursor = P.index(rr, cc); return }
        rr += dr; cc += dc
      }
    }
    if (k === Qt.Key_Left) { moveCursor(0, -1); event.accepted = true; return }
    if (k === Qt.Key_Right) { moveCursor(0, 1); event.accepted = true; return }
    if (k === Qt.Key_Up) { moveCursor(-1, 0); event.accepted = true; return }
    if (k === Qt.Key_Down) { moveCursor(1, 0); event.accepted = true; return }
    if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) { tap(cursor); event.accepted = true; return }
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    if (event.text === "h") { hint(); event.accepted = true; return }
    if (event.text === "u") { undo(); event.accepted = true; return }
    if (event.text === "n") { startAgain(); event.accepted = true; return }
    var n = "123456789".indexOf(event.text)
    if (n >= 0 && event.text !== "") { begin(P.FIGURES[n].key); event.accepted = true }
  }

  IpcHandler {
    target: "pegsolitaire"
    function tap(hole: string): string {
      var cell = parseInt(hole, 10)
      if (isNaN(cell)) return "not a hole"
      root.tap(cell)
      return "ok"
    }
    function play(move: string): string {
      var m = parseInt(move, 10)
      if (!P.isLegal(root.position, m)) return "not a legal jump"
      root.play(m)
      return "ok"
    }
    function hint(): string { root.hint(); return "ok" }
    function board(): string {
      var out = ""
      for (var i = 0; i < P.CELLS; i++)
        out += !P.has(root.position.holes, i) ? " " : P.has(root.position.pegs, i) ? "o" : "."
      return out
    }
    function figure(): string { return root.figure.key }
    function settled(): bool { return !root.thinking && !root.activeBoard.busy }
  }

  // ------------------------------------------------------------ the screen

  // Phone: result, count, board, status, and Undo and Hint along the bottom,
  // under the thumb already holding the device.
  Item {
    anchors.fill: parent
    visible: root.compact
    Controls {
      id: phoneTop
      app: root
      buttons: false
      x: root.ui.gutter
      y: 4
      width: parent.width - root.ui.gutter * 2
    }
    Board {
      id: board
      app: root
      anchors.top: phoneTop.bottom
      anchors.topMargin: 8
      anchors.bottom: phoneStatus.top
      anchors.bottomMargin: 8
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: 10
      anchors.rightMargin: 10
      position: root.position
      picked: root.picked
      drops: root.drops
      hint: root.hintShown
      cursor: -1
      onTapped: function (cell) { root.tap(cell) }
      onSettled: root.settled()
    }
    Text {
      id: phoneStatus
      anchors.bottom: phoneBar.top
      anchors.bottomMargin: 10
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      text: root.status
      color: root.over ? root.ui.accent : root.ui.muted
      font.family: root.ui.font
      font.pixelSize: root.ui.fs.sm
    }
    Row {
      id: phoneBar
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 14
      x: root.ui.gutter
      width: parent.width - root.ui.gutter * 2
      spacing: 10
      Button {
        width: (parent.width - 10) / 2
        app: root
        glyph: KG.undo
        text: "Undo"
        enabled: root.canUndo
        onClicked: root.undo()
      }
      Button {
        width: (parent.width - 10) / 2
        app: root
        glyph: G.hint
        text: root.thinking ? "Looking…" : "Hint"
        enabled: root.canHint
        onClicked: root.hint()
      }
    }
  }

  // Desktop: the board, and a pane beside it.
  Item {
    anchors.fill: parent
    visible: !root.compact
    Board {
      id: deskBoard
      app: root
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.right: pane.left
      anchors.margins: 24
      position: root.position
      picked: root.picked
      drops: root.drops
      hint: root.hintShown
      cursor: root.cursor
      onTapped: function (cell) { root.cursor = cell; root.tap(cell) }
      onSettled: root.settled()
    }
    Flickable {
      id: pane
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.rightMargin: 24
      width: Math.min(400, parent.width * 0.42)
      contentHeight: paneCol.implicitHeight + 24
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      Column {
        id: paneCol
        width: parent.width
        y: 8
        spacing: 22
        Controls { app: root; width: parent.width }
        RecordView { app: root; game: root.game; perFigure: false; width: parent.width }
        Card {
          app: root
          width: parent.width
          title: "Figures"
          FigureList {
            app: root
            width: parent.width
            game: root.game
            current: root.figure.key
            onChosen: function (key) { root.begin(key) }
          }
        }
      }
    }
  }

  // Whichever board is on screen: the one the rules wait for while it hops.
  readonly property Board activeBoard: compact ? board : deskBoard
}
