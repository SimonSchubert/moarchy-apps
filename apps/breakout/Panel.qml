import QtQuick
import Quickshell
import Quickshell.Io
import "kit"
import "kit/Glyphs.js" as KG
import "Breakout.js" as B
import "Store.js" as S

// Breakout: a bat that follows your thumb from anywhere on the field, a wall
// in the theme's colours, and a frame loop that stops the moment the window
// does.
//
//     omarchy-shell shell toggle org.moarchy.breakout
//
// Every other game here is a game of turns. This one runs, and the loop is the
// thing to get right: it ticks only while the window is open, the game is not
// paused and the ball is in the air (or about to be). Closed, it does nothing
// at all -- the plugin stays loaded in the shell, and a frame loop running in
// a pocket is sixty wake-ups a second somebody will blame on the wrong app.
//
// A phone gets the score over the field, the field as tall as the screen
// allows, and the menu in the header; a desktop gets the field beside a pane
// with the score, the buttons and the record.
App {
  id: root

  appId: "org.moarchy.breakout"
  title: "Breakout"
  subtitle: "Level " + (saved.level + 1) + " · " + S.levelName(saved.level)
  windowWidth: 1000
  windowHeight: 820

  store: Store { name: "moarchy-breakout" }

  launcher.desktopId: "org.moarchy.Breakout"
  launcher.genericName: "Arcade game"
  launcher.comment: "Knock the wall down without losing the ball"
  launcher.categories: "Game;ArcadeGame;"
  launcher.keywords: "breakout;arkanoid;bricks;ball;bat;arcade;"

  mark: Component { Image { source: root.appDir + "/icon.svg"; sourceSize: Qt.size(60, 60) } }

  // Solid colours, mixed rather than layered: a translucent shape per brick
  // per frame is not free on a PinePhone.
  function mix(a, b, t) {
    var x = Qt.color(a), y = Qt.color(b)
    return Qt.rgba(x.r * t + y.r * (1 - t), x.g * t + y.g * (1 - t), x.b * t + y.b * (1 - t), 1)
  }

  ui: Tokens {
    theme: root.hostTheme
    compact: root.compact
    // The field is sunk below the window: darker on a dark theme, a shade of
    // the text on a light one.
    readonly property color field: dark ? root.mix(bg, "#000000", 0.55) : root.mix(text, bg, 0.10)
    // A row per hue, in the theme's own colours where it names them and
    // GNOME's where it does not -- the wall is the theme, and a theme switch
    // repaints it mid-rally.
    readonly property var rows: [
      root.mix(hue("red", "#e01b24", "#e01b24"), field, 0.88),
      root.mix(hue("orange", "#ff7800", "#ff7800"), field, 0.88),
      root.mix(hue("yellow", "#f5c211", "#f5c211"), field, 0.88),
      root.mix(hue("green", "#33d17a", "#33d17a"), field, 0.88),
      root.mix(hue("cyan", "#00b8c4", "#00b8c4"), field, 0.88),
      root.mix(hue("blue", "#3584e4", "#3584e4"), field, 0.88),
      root.mix(hue("magenta", "#c061cb", "#c061cb"), field, 0.88),
      root.mix(hue("brown", "#986a44", "#986a44"), field, 0.88)
    ]
    readonly property color bat: accent
    readonly property color batRim: root.mix("#ffffff", accent, 0.30)
    readonly property color ball: dark ? root.mix("#ffffff", text, 0.72) : text
    readonly property color ballRim: root.mix("#000000", ball, 0.25)
  }

  actions: Component {
    Row {
      spacing: 2
      IconButton {
        visible: root.served && !root.dead
        app: root
        glyph: root.paused ? KG.play : KG.pause
        label: root.paused ? "Go on" : "Pause"
        active: root.paused
        onClicked: root.togglePause()
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
        onClicked: root.newGame()
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
          stats: root.saved.stats
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
      blurb: "Knock the wall down without losing the ball."
      AppearanceSection { app: root }
      LauncherSection { app: root }
      KeysSection {
        app: root
        keys: [
          ["← → or A D", "Move the bat (the pointer moves it too)"],
          ["Space", "Serve; pause and go on"],
          ["Enter", "Serve"],
          ["n", "New game"],
          [",", "Settings"],
          ["Esc", "Back one step"]
        ]
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Where it keeps the game"
        note: "~/.local/share/moarchy-breakout/breakout.json: the wall, the score, the lives and the level, and the record. Not the ball -- a game picked up again starts with it on the bat. Saved when a brick falls, a life goes, a wall is cleared and the window closes."
      }
    }
  }

  // ------------------------------------------------------------ the game

  // The saved game (Store.js) and the live world (Breakout.js). The world is
  // changed in place sixty times a second; what the view draws is copied out
  // of it into the properties below, once a frame.
  property var saved: S.fresh()
  property var world: B.world(B.LEVELS[0])
  property bool loaded: false

  property real ballX: world.ballX
  property real ballY: world.ballY
  property real bat: world.bat
  property var bricks: world.bricks.slice()
  property bool served: false
  property bool readyToServe: false
  property int score: 0
  property int lives: B.LIVES
  property int standing: B.standing(world)
  readonly property bool dead: lives <= 0

  // Paused by hand, with the pause button or Space.
  property bool paused: false
  // Held still for a photograph, and for nothing else.
  property bool frozen: false
  property bool recorded: false

  // Whether anybody can see the game. Inside the shell the window is shown or
  // it is not; as its own process, another app over it takes the focus.
  // qmllint disable missing-property
  readonly property bool looked: opened && (!standalone || Qt.application.state === Qt.ApplicationActive)
  // qmllint enable missing-property

  // The loop. Only while somebody is looking, the game is on, and something
  // is moving -- the ball in the air, or the pause before a serve running out.
  // A ball sitting on the bat moves only when the bat does, and that is drawn
  // from aimAt() without a frame loop.
  readonly property bool running: looked && !paused && !frozen && !dead && (served || !readyToServe)

  // The longest step the world is ever given, whatever the clock says: past
  // three frames of stutter, the honest thing is to drop the time.
  readonly property real longestFrame: 0.05

  FrameAnimation {
    running: root.running
    onTriggered: root.stepFrame(Math.min(frameTime, root.longestFrame))
  }

  // Copy what the view draws out of the world.
  function sync(bricksToo) {
    ballX = world.ballX
    ballY = world.ballY
    bat = world.bat
    served = world.served
    readyToServe = B.ready(world)
    score = world.score
    lives = world.lives
    if (bricksToo) {
      bricks = world.bricks.slice()
      standing = B.standing(world)
    }
  }

  function stepFrame(seconds) {
    var b = B.advance(world, seconds)
    sync(b.broken.length > 0 || b.events.indexOf(B.HIT_BRICK) >= 0)
    if (b.events.length) react(b)
  }

  function react(b) {
    if (b.broken.length) {
      dirty = true
      maybeSave()
    }
    if (b.events.indexOf(B.CLEARED) >= 0) {
      var next = S.nextLevel(saved, world)
      saved = next.store
      world = next.world
      sync(true)
      flush()
      toast("Level " + (saved.level + 1) + " of " + S.levelCount() + " · " + S.levelName(saved.level))
      return
    }
    if (b.events.indexOf(B.LOST_BALL) >= 0) {
      dirty = true
      flush()
      if (B.dead(world)) finish()
    }
  }

  function aimAt(x) {
    if (dead) return
    B.aim(world, Math.min(Math.max(x, 0), B.WIDTH))
    bat = world.bat
    if (!world.served) { ballX = world.ballX; ballY = world.ballY }
  }

  // A tap on the field, Space, Enter: go on after a pause, or serve.
  function press() {
    if (dead) return
    if (paused) { paused = false; return }
    if (B.serve(world)) sync(false)
  }

  function togglePause() {
    if (dead || !served) return
    paused = !paused
  }

  // Record the game once, and say what it was.
  function finish() {
    if (recorded) return
    recorded = true
    var best = saved.stats.best
    saved = S.record(saved, world)
    dirty = true
    flush()
    toast(world.score > best ? world.score + " — a best" : world.score + " points. New game for another.")
  }

  function newGame() {
    // A game given up is still a game played: a table that counted only the
    // games somebody saw out would be a table of the ones going well.
    if (!dead && world.score) saved = S.record(saved, world)
    var g = S.begin(saved, 0)
    saved = g.store
    world = g.world
    recorded = false
    paused = false
    frozen = false
    sync(true)
    dirty = true
    flush()
  }

  // ------------------------------------------------------------ the file

  // At most one write per SAVE_EVERY while a rally is going: bricks fall a
  // few a second in a good one, and a write per brick is a write per brick.
  property bool dirty: false
  property real lastSave: 0
  readonly property int saveEvery: 1500

  function maybeSave() {
    if (Date.now() - lastSave >= saveEvery) flush()
  }

  function flush() {
    if (!loaded) return
    saved = S.remember(saved, world)
    lastSave = Date.now()
    dirty = false
    file.save(S.serialize(saved))
  }

  DataFile {
    id: file
    app: "breakout"
    name: "breakout.json"
    onParsed: function (data) {
      // Our own save, read back: nothing to do.
      if (root.loaded && data && S.serialize(S.parse(data)) === S.serialize(root.saved)) return
      var g = S.resume(S.parse(data))
      root.saved = g.store
      root.world = g.world
      root.recorded = false
      root.sync(true)
      root.loaded = true
      root.applyShot()
    }
    onQuarantined: function (to) { root.toast("The saved game was unreadable and was kept aside") }
  }

  // Closed: paused where it stands, and written down.
  onOpenedChanged: {
    if (opened) return
    if (served && !dead) paused = true
    if (loaded) { dirty = true; flush() }
  }
  onQuitting: if (loaded) flush()
  // Somebody else's window on top: the game waits for them.
  onLookedChanged: if (!looked && served && !dead) paused = true

  // ------------------------------------------------------------ screenshots

  // MOARCHY_BREAKOUT_SERVED: a ball in flight, for a picture -- aimed a little
  // off centre, half a second of play, and then held still. A saved game
  // always comes back with the ball on the bat, so a rally has to be asked for.
  function applyShot() {
    if (!Quickshell.env("MOARCHY_BREAKOUT_SERVED")) return
    B.aim(world, B.WIDTH * 0.42)
    world.waiting = 0
    B.serve(world)
    B.advance(world, 0.5)
    frozen = true
    sync(true)
  }

  property bool wantRecord: false
  function showRecord() {
    if (!wantRecord || !compact) return
    wantRecord = false
    push({ kind: "record" })
  }
  onCompactChanged: showRecord()
  onSummoned: {
    wantRecord = (Quickshell.env("MOARCHY_BREAKOUT_PAGE") || "") === "record"
    Qt.callLater(showRecord)
  }

  // ------------------------------------------------------------ keys

  keyHandler: function (event) {
    if (topPage || inSettings) return
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    var k = event.key
    // A nudge a press, and the key's own repeat for holding it.
    if (k === Qt.Key_Left || event.text === "a") { aimAt(world.bat - 0.06); event.accepted = true; return }
    if (k === Qt.Key_Right || event.text === "d") { aimAt(world.bat + 0.06); event.accepted = true; return }
    if (k === Qt.Key_Space) {
      if (served && !paused) togglePause()
      else press()
      event.accepted = true
      return
    }
    if (k === Qt.Key_Return || k === Qt.Key_Enter) { press(); event.accepted = true; return }
    if (event.text === "n") { newGame(); event.accepted = true }
  }

  IpcHandler {
    target: "breakout"
    function state(): string {
      return JSON.stringify({ level: root.saved.level, score: root.score, lives: root.lives,
                              standing: root.standing, served: root.served, running: root.running })
    }
    function aim(x: string): string { root.aimAt(parseFloat(x)); return "ok" }
    function serve(): string { root.press(); return "ok" }
    function pause(): string { root.togglePause(); return root.paused ? "paused" : "playing" }
    function hide(): string { root.close(); return "ok" }
    function show(): string { root.open(""); return "ok" }
  }

  // ------------------------------------------------------------ the screen

  // Phone: the score, the field as tall as it can be, a line under it.
  Item {
    anchors.fill: parent
    visible: root.compact
    Readings {
      id: phoneReadings
      app: root
      x: root.ui.gutter + 6
      width: parent.width - x * 2
    }
    Field {
      app: root
      anchors.top: phoneReadings.bottom
      anchors.topMargin: 4
      anchors.bottom: phoneStatus.top
      anchors.bottomMargin: 6
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: root.ui.gutter
      anchors.rightMargin: root.ui.gutter
    }
    Text {
      id: phoneStatus
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 10
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.status
      color: root.dead ? root.ui.bad : root.ui.muted
      font.family: root.ui.font
      font.pixelSize: root.ui.fs.sm
    }
  }

  readonly property string status: {
    if (dead) return "Game over — " + score + " points"
    if (!looked || (paused && served)) return "Paused"
    if (!served) return compact ? "Slide anywhere to aim" : "Move the pointer to aim"
    return standing + (standing === 1 ? " brick left" : " bricks left")
  }

  // Desktop: the field, and a pane beside it.
  Item {
    anchors.fill: parent
    visible: !root.compact
    Field {
      app: root
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
      width: Math.min(360, parent.width * 0.4)
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
          text: root.status
          color: root.dead ? root.ui.bad : root.ui.text
          font.family: root.ui.font
          font.pixelSize: root.ui.fs.lg
          font.weight: Font.DemiBold
        }
        Row {
          spacing: 10
          Button {
            app: root
            primary: !root.served && root.readyToServe && !root.dead
            enabled: !root.dead && (root.served || root.readyToServe)
            glyph: root.served ? (root.paused ? KG.play : KG.pause) : KG.play
            text: root.served ? (root.paused ? "Go on" : "Pause") : "Serve"
            onClicked: root.served ? root.togglePause() : root.press()
          }
          Button {
            app: root
            primary: root.dead
            glyph: KG.plus
            text: "New game"
            onClicked: root.newGame()
          }
        }
        RecordView { app: root; stats: root.saved.stats; width: parent.width }
      }
    }
  }
}
