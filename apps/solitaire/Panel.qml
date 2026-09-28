import QtQuick
import Quickshell
import Quickshell.Io
import "kit"
import "kit/Glyphs.js" as KG
import "Klondike.js" as K
import "Store.js" as S

// Solitaire: Klondike, one tap a move, and an app that says when a deal is
// lost.
//
//     omarchy-shell shell toggle org.moarchy.solitaire
//
// **A tap moves the card when there is one place for it to go, and asks when
// there is more than one.** That is the whole interaction on a phone, where
// dragging a 46 px card with the finger that covers it is a gesture nobody can
// aim. So an unambiguous tap simply happens; an ambiguous one picks the run up
// and rings everywhere it may go until one of those is tapped. With a mouse a
// run can be dragged as well.
//
// The other thing is the banner, the app noticing on the player's behalf.
// Klondike has no rule that ends a lost game, so a person can cycle a pack for
// ever without being told there is nothing in it; and a table with every card
// face up is won already and needs a hundred taps to prove it. The banner says
// both, and offers the one button that answers.
//
// A phone gets the table and two buttons under the thumb, the record a page
// away; a desktop gets the table beside a pane with the buttons and the record.
App {
  id: root

  appId: "org.moarchy.solitaire"
  title: "Solitaire"
  subtitle: (current.draw === 3 ? "Draw three" : "Draw one") + " · " + current.moves.length + (current.moves.length === 1 ? " move" : " moves")
  windowWidth: 1180
  windowHeight: 820

  store: Store { name: "moarchy-solitaire" }

  launcher.desktopId: "org.moarchy.Solitaire"
  launcher.genericName: "Card game"
  launcher.comment: "Klondike patience, one tap a move"
  launcher.categories: "Game;CardGame;"
  launcher.keywords: "solitaire;patience;klondike;cards;game;"

  mark: Component { Image { source: root.appDir + "/icon.svg"; sourceSize: Qt.size(60, 60) } }

  function mix(a, b, amount) {
    var x = Qt.color(a), y = Qt.color(b)
    return Qt.rgba(x.r * amount + y.r * (1 - amount), x.g * amount + y.g * (1 - amount), x.b * amount + y.b * (1 - amount), 1)
  }

  ui: Tokens {
    id: tokens
    theme: root.hostTheme
    compact: root.compact
    // The baize, in the theme's own green: on a dark theme a little green in
    // the background, on a light one a deeper green shaded down, because a
    // pale table is a table the white cards disappear into.
    readonly property color baize: dark ? root.mix(hue("green", "#33d17a", "#26a269"), bg, 0.16)
      : root.mix("#000000", root.mix(hue("green", "#33d17a", "#26a269"), bg, 0.42), 0.14)
    // Not pure white on a dark theme -- seven columns of #ffffff at midnight
    // is a torch -- and not tinted, because the ink on it has to be ink.
    readonly property color cardFace: root.mix("#ffffff", bg, dark ? 0.88 : 0.99)
    // The card's own outline, so two overlapping cards are two cards.
    readonly property color cardEdge: root.mix("#000000", cardFace, 0.22)
    readonly property color cardInk: root.mix("#000000", cardFace, 0.88)
    readonly property color cardRed: root.mix(hue("red", "#e01b24", "#c01c28"), cardFace, 0.90)
    readonly property color cardBack: root.mix(accent, bg, 0.82)
    readonly property color cardBackLine: root.mix("#000000", cardBack, 0.22)
    // An empty pile is a hole in the baize: darker than the table on both
    // themes, because a lighter one reads as a face-up card with nothing on it.
    readonly property color slot: root.mix("#000000", baize, 0.16)
    readonly property color slotInk: root.mix(text, baize, 0.28)
    readonly property color pick: accent
    readonly property color drop: root.mix(accent, baize, 0.55)
  }

  actions: Component {
    Row {
      spacing: 2
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
        app: root
        glyph: KG.refresh
        label: "Deal this one again"
        onClicked: root.dealAgain()
      }
      IconButton {
        visible: root.compact
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
      blurb: "Klondike patience: one tap a move, and a word when a deal has nothing left in it."
      AppearanceSection { app: root }
      LauncherSection { app: root }
      KeysSection {
        app: root
        keys: [
          ["Space, d", "Turn the stock over"],
          ["u", "Undo"],
          ["a", "Send every card home, when nothing is face down"],
          ["r", "Deal this one again"],
          ["n", "New deal"],
          [",", "Settings"],
          ["Esc", "Put a picked-up run back, then back one step"]
        ]
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Drag or tap"
        note: "A tap moves a card when it has one place to go and picks it up when it has more. With a mouse, a run can be dragged onto the column or foundation it belongs on."
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Where it keeps the game"
        note: "~/.local/share/moarchy-solitaire/solitaire.json: the deck, the moves played on it and the record for each deal. Saved after every move."
      }
    }
  }

  // ------------------------------------------------------------ the game

  // What is saved, and the game it replays to.
  property var game: S.fresh()
  property var current: S.game(game)
  property bool loaded: false

  readonly property var table: current.table
  readonly property bool won: K.won(table)
  readonly property bool finishable: !won && queue.length === 0 && K.finishable(table)
  readonly property bool stuck: !won && !finishable && K.isStuck(current)
  readonly property bool canUndo: current.moves.length > 0 && queue.length === 0

  // The run a tap picked up and could not place on its own, and where it may
  // go. Empty the rest of the time, which is most of the time.
  property var selected: null
  property var drops: []
  // Moves still to play from Send them home.
  property var queue: []

  function save() { file.save(S.serialize(game)) }

  function clear() { selected = null; drops = [] }

  function commit(next) {
    current = next
    game = S.remember(game, next)
    save()
    if (K.won(next.table) && !game.recorded) finish()
  }

  function play(m) {
    var next = K.play(current, m)
    if (next) commit(next)
    return next !== null
  }

  function tap(pile, position) {
    if (queue.length) { flush(); return }
    var t = table
    if (pile === K.STOCK) {
      clear()
      turnStock()
      return
    }
    if (selected) {
      var held = selected[0], at = selected[1]
      if (drops.indexOf(pile) >= 0) {
        var count = K.runFrom(t, held, at).length
        clear()
        play(K.move(held, pile, count))
        return
      }
      clear()
      // Tapping the run you picked up puts it back down.
      if (pile === held) return
    }
    var run = K.runFrom(t, pile, position)
    if (!run.length) return
    var ds = K.destinations(t, pile, position)
    if (ds.length === 1) { play(K.move(pile, ds[0], run.length)); return }
    if (ds.length) { selected = [pile, position]; drops = ds }
    // No destinations is silent: a tap on a card with nowhere to go is a
    // miss, and an app that scolds you for a miss scolds you all day long.
  }

  function turnStock() {
    var t = table
    if (t.stock.length) play(K.move(K.STOCK, K.WASTE, Math.min(t.draw, t.stock.length)))
    else if (t.waste.length) play(K.move(K.WASTE, K.STOCK, t.waste.length))
  }

  function drop(pile, position, target) {
    if (queue.length) return
    clear()
    var run = K.runFrom(table, pile, position)
    if (run.length && K.destinations(table, pile, position).indexOf(target) >= 0)
      play(K.move(pile, target, run.length))
  }

  // Record the win once, and say what it was.
  function finish() {
    game = S.record(game, S.WON, current.moves.length)
    save()
    toast("Won in " + current.moves.length + " moves")
  }

  function undo() {
    if (!canUndo) return
    clear()
    var back = K.undo(current)
    if (!back) return
    // A win taken back has been counted already, and there is no way to
    // count it off that is not a way to count it twice.
    current = back
    game = S.remember(game, back)
    save()
  }

  // Play out a table with nothing left face down: the rules' own moves, sent
  // home one at a time, each into the move list so undo still walks back
  // through them. A tap during it plays the rest at once.
  function sendHome() {
    if (!finishable || queue.length) return
    clear()
    queue = K.homeward(table)
  }
  Timer {
    interval: 110
    repeat: true
    running: root.queue.length > 0 && root.opened
    onTriggered: {
      var q = root.queue.slice()
      var m = q.shift()
      root.queue = q
      if (m) root.play(m)
    }
  }
  function flush() {
    var q = queue
    queue = []
    var g = current
    for (var i = 0; i < q.length; i++) {
      var next = K.play(g, q[i])
      if (!next) break
      g = next
    }
    commit(g)
  }

  // The same fifty-two cards, from the top.
  function dealAgain() {
    queue = []
    clear()
    game = S.again(S.abandon(game))
    current = S.game(game)
    save()
    toast("The same deal again")
  }

  function newDeal(draw) {
    queue = []
    clear()
    game = S.begin(S.abandon(game), draw)
    current = S.game(game)
    save()
  }

  DataFile {
    id: file
    app: "solitaire"
    name: "solitaire.json"
    onParsed: function (data) {
      // Our own save, read back: nothing to do.
      if (root.loaded && data && S.serialize(S.parse(data)) === S.serialize(root.game)) return
      var state = S.parse(data)
      var g = S.game(state)
      root.clear()
      root.queue = []
      root.current = g
      root.game = S.remember(state, g)
      root.loaded = true
      // A win saved and then killed before it was counted.
      if (K.won(g.table) && !root.game.recorded) root.finish()
      if (!data) root.save()
      root.pickForShots()
    }
    onQuarantined: function (to) { root.toast("The saved game was unreadable and was kept aside") }
  }

  onOpenedChanged: if (!opened && queue.length) flush()

  onSummoned: {
    wantRecord = (Quickshell.env("MOARCHY_SOLITAIRE_PAGE") || "") === "record"
    Qt.callLater(showRecord)
    if (Quickshell.env("MOARCHY_SOLITAIRE_NEW")) newDealDialog.ask()
    if (Quickshell.env("MOARCHY_SOLITAIRE_SETTINGS")) setTab("settings")
  }
  // The record is beside the table on a desktop and a page on a phone, and
  // the window's width is not known in the first frame.
  property bool wantRecord: false
  function showRecord() {
    if (!wantRecord || !compact) return
    wantRecord = false
    push({ kind: "record" })
  }
  onCompactChanged: showRecord()

  // MOARCHY_SOLITAIRE_PICK: pick up the first run with a choice to make, for
  // the screenshots -- the rings are the one thing no fixture can reach.
  function pickForShots() {
    if (!Quickshell.env("MOARCHY_SOLITAIRE_PICK")) return
    var at = K.somethingToPick(table)
    if (at) { selected = at; drops = K.destinations(table, at[0], at[1]) }
  }

  stepBack: function () {
    if (selected) { clear(); return true }
    return false
  }

  keyHandler: function (event) {
    if (topPage || inSettings) return
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    var t = event.text
    if (event.key === Qt.Key_Space || t === "d") { tap(K.STOCK, 0); event.accepted = true; return }
    if (t === "u") { undo(); event.accepted = true; return }
    if (t === "a") { sendHome(); event.accepted = true; return }
    if (t === "r") { dealAgain(); event.accepted = true; return }
    if (t === "n") { newDealDialog.ask(); event.accepted = true }
  }

  IpcHandler {
    target: "solitaire"
    function tap(pile: string, position: string): string {
      root.tap(parseInt(pile, 10), parseInt(position, 10))
      return "ok"
    }
    function undo(): string { root.undo(); return "ok" }
    function home(): string { root.sendHome(); return "ok" }
    function state(): string {
      return JSON.stringify({
        moves: root.current.moves.length, home: K.home(root.table),
        stock: root.table.stock.length, waste: root.table.waste.length,
        down: root.table.down, won: root.won, stuck: root.stuck,
        selected: root.selected, drops: root.drops
      })
    }
    function settled(): bool { return root.queue.length === 0 }
  }

  // ------------------------------------------------------------ new deal

  // How many cards a tap on the stock turns over. Asked when a deal starts
  // rather than in Settings: it belongs to a deal, and a game under way
  // cannot answer it differently halfway through.
  Dialog {
    id: newDealDialog
    app: root
    title: "New deal"
    text: root.current.moves.length && !root.won ? "The deal in progress will count as a loss." : ""
    acceptText: "Deal"
    property int draw: 1
    function ask() { draw = root.current.draw; open() }
    onAccepted: root.newDeal(draw)

    Text {
      text: "Turn over"
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
      Chip { app: root; text: "One card"; selected: newDealDialog.draw === 1; onClicked: newDealDialog.draw = 1 }
      Chip { app: root; text: "Three cards"; selected: newDealDialog.draw === 3; onClicked: newDealDialog.draw = 3 }
    }
    Text {
      width: parent.width
      wrapMode: Text.Wrap
      text: newDealDialog.draw === 3
        ? "The game as it is printed on the box. Rather fewer can be won."
        : "Every card in the stock is reachable. Most deals can be won."
      color: root.ui.muted
      font.family: root.ui.font
      font.pixelSize: root.ui.fs.sm
    }
  }

  // ------------------------------------------------------------ the screen

  // What the app has noticed, if it has noticed anything.
  readonly property var notice: won ? { text: "Every card home, in " + current.moves.length + " moves", action: "New deal" }
    : finishable ? { text: "Nothing left face down", action: "Send them home" }
    : stuck ? { text: "No moves left on this deal", action: "New deal" }
    : null
  function answerNotice() { finishable ? sendHome() : newDealDialog.ask() }

  Rectangle {
    anchors.fill: parent
    color: tokens.baize
  }

  // Phone: the notice, the table, and two buttons under the thumb.
  Rectangle {
    id: phoneNotice
    visible: root.compact && root.notice !== null
    width: parent.width
    height: visible ? 48 : 0
    color: root.ui.accentSoft
    Text {
      anchors.left: parent.left
      anchors.leftMargin: 14
      anchors.right: phoneNoticeButton.left
      anchors.rightMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      text: root.notice ? root.notice.text : ""
      elide: Text.ElideRight
      color: root.ui.text
      font.family: root.ui.font
      font.pixelSize: root.ui.fs.sm
      font.weight: Font.Bold
    }
    Button {
      id: phoneNoticeButton
      anchors.right: parent.right
      anchors.rightMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      app: root
      primary: true
      text: root.notice ? root.notice.action : ""
      onClicked: root.answerNotice()
    }
  }

  Flickable {
    id: tableView
    anchors.top: root.compact ? phoneNotice.bottom : parent.top
    anchors.left: parent.left
    anchors.right: root.compact ? parent.right : pane.left
    anchors.bottom: root.compact ? phoneBar.top : parent.bottom
    anchors.topMargin: root.compact ? 2 : 4
    anchors.leftMargin: root.compact ? 0 : 16
    anchors.rightMargin: root.compact ? 0 : 16
    contentWidth: width
    contentHeight: Math.max(height, board.implicitHeight)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height && !board.dragging

    Table {
      id: board
      app: root
      width: tableView.width
      height: tableView.contentHeight
      viewHeight: tableView.height
      table: root.table
      selected: root.selected
      drops: root.drops
      onTapped: function (pile, position) { root.tap(pile, position) }
      onDropped: function (pile, position, target) { root.drop(pile, position, target) }
    }
  }

  Row {
    id: phoneBar
    visible: root.compact
    anchors.bottom: parent.bottom
    anchors.bottomMargin: visible ? 10 : 0
    anchors.horizontalCenter: parent.horizontalCenter
    height: visible ? implicitHeight : 0
    spacing: 10
    Button {
      width: (root.contentArea.width - 34) / 2
      app: root
      glyph: KG.undo
      text: "Undo"
      enabled: root.canUndo
      onClicked: root.undo()
    }
    Button {
      width: (root.contentArea.width - 34) / 2
      app: root
      glyph: KG.plus
      text: "New deal"
      primary: root.won
      onClicked: newDealDialog.ask()
    }
  }

  // Desktop: a pane beside the table with the notice, the buttons and the
  // record.
  Rectangle {
    id: pane
    visible: !root.compact
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: visible ? Math.min(360, parent.width * 0.34) : 0
    color: root.ui.bg

    Flickable {
      anchors.fill: parent
      anchors.margins: 20
      contentHeight: paneCol.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      Column {
        id: paneCol
        width: parent.width
        spacing: 18

        Rectangle {
          visible: root.notice !== null
          width: parent.width
          height: visible ? noticeCol.implicitHeight + 28 : 0
          radius: root.ui.radius
          color: root.ui.accentSoft
          border.width: 1
          border.color: root.ui.accent
          Column {
            id: noticeCol
            x: 14
            y: 14
            width: parent.width - 28
            spacing: 10
            Text {
              width: parent.width
              wrapMode: Text.Wrap
              text: root.notice ? root.notice.text : ""
              color: root.ui.text
              font.family: root.ui.font
              font.pixelSize: root.ui.fs.md
              font.weight: Font.Bold
            }
            Button {
              app: root
              primary: true
              text: root.notice ? root.notice.action : ""
              onClicked: root.answerNotice()
            }
          }
        }

        Flow {
          width: parent.width
          spacing: 8
          Button { app: root; glyph: KG.undo; text: "Undo"; enabled: root.canUndo; onClicked: root.undo() }
          Button { app: root; glyph: KG.plus; text: "New deal"; primary: root.won; onClicked: newDealDialog.ask() }
          Button { app: root; glyph: KG.refresh; text: "Deal again"; onClicked: root.dealAgain() }
        }

        RecordView { app: root; game: root.game; width: parent.width }
      }
    }
  }
}
