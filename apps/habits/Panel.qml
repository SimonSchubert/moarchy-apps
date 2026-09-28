import QtQuick
import Quickshell
import Quickshell.Io
import "kit"
import "kit/Glyphs.js" as KG
import "Habits.js" as H
import "Game.js" as Game
import "Glyphs.js" as G

// Habits: a tap a day, a streak, and how strong that makes it -- points that
// only go up, ten achievements, and a level they add up to.
//
//     omarchy-shell shell toggle org.moarchy.habits
//
// The file is the GTK version's own (~/.local/share/moarchy-habits/
// habits.json), so a day ticked in 0.1.2 is ticked here. A habit is kept on a
// local calendar day: "today" is read off the clock and carried as a bare ISO
// label, the same reason habits.py ignored timezones entirely.
//
// A phone gets Today and Achievements as tabs, with a habit a page away. A
// desktop gets them in the rail, and the habit picked opens beside the list.
App {
  id: root

  appId: "org.moarchy.habits"
  title: "Habits"
  caption: "Habit tracker"
  subtitle: {
    if (tab !== "today" || revision < 0) return ""
    var p = H.todayProgress(habits, today)
    if (!p.due) return ""
    return p.done === p.due ? "All done today" : p.done + " of " + p.due + " today"
  }
  windowWidth: 1180
  windowHeight: 800

  store: Store {
    name: "moarchy-habits"
    defaults: ({ lastTab: "today" })
    clean: function (p) {
      if (["today", "achievements"].indexOf(p.lastTab) < 0) p.lastTab = "today"
      return p
    }
    onReadyChanged: if (ready && !root.pinnedPage) root.tab = prefs.lastTab
  }

  launcher.desktopId: "org.moarchy.Habits"
  launcher.genericName: "Habit tracker"
  launcher.comment: "Track habits with a tap a day, kept on the device"
  launcher.categories: "Utility;Office;ProjectManagement;"
  launcher.keywords: "habit;habits;streak;routine;daily;tracker;goal;"

  mark: Component { Image { source: root.appDir + "/icon.svg"; sourceSize: Qt.size(60, 60) } }

  tabs: [
    { key: "today", label: "Today", glyph: G.today },
    { key: "achievements", label: "Achievements", glyph: G.trophy }
  ]
  readonly property string todayGlyph: G.today

  ui: Tokens {
    theme: root.hostTheme
    compact: root.compact
  }

  // The eight habit colours: the theme's own hue by name where it has one,
  // and GNOME's where it does not, as the GTK version did.
  readonly property var gnome: ({
    red: "#e01b24", orange: "#ff7800", yellow: "#f5c211", green: "#33d17a",
    cyan: "#00b8c4", blue: "#3584e4", magenta: "#c061cb", brown: "#986a44"
  })
  function habitHue(key) {
    return hostTheme.hue(key) || gnome[key] || hostTheme.hue("green") || gnome.green
  }
  // The fill of one day: an untouched day is a step up from the card, not an
  // outline -- a 1 px border disappears on a phone in daylight -- and a kept
  // one is the habit's hue over the background, in four widely spaced steps.
  function markColour(habit, day, rev) {
    var step = H.stepFor(habit, day)
    if (step === 0) return ui.surfaceHigh
    return Qt.tint(ui.bg, ui.alpha(Qt.color(habitHue(habit.colour)), H.rampAt(ui.dark, step)))
  }
  function isKept(habit, day) { return H.kept(habit, day) }
  function captionFor(habit, rev) {
    var run = H.streak(habit, today)
    var strength = Math.round(H.score(habit, today) * 100)
    var bits = []
    if (run) bits.push(run + (run === 1 ? " day" : " day streak"))
    bits.push(strength + "% strength")
    if (!H.isDaily(habit)) bits.push(H.frequencyLabel(habit))
    return bits.join(" · ")
  }

  actions: Component {
    Row {
      spacing: 2
      IconButton { app: root; glyph: KG.plus; label: "New habit"; onClicked: root.newHabit() }
    }
  }

  settings: Component {
    SettingsPage {
      app: root
      blurb: "A tap a day, a streak, and how strong that makes it."
      AppearanceSection { app: root }
      LauncherSection { app: root }
      KeysSection {
        app: root
        keys: [
          ["1  2", "Today, Achievements"],
          ["n", "New habit"],
          ["↑ ↓", "Move through the habits"],
          ["Space", "Tick today for the habit picked"],
          ["Enter", "Open it"],
          ["e", "Edit it"],
          ["Delete", "Delete it"],
          [",", "Settings"],
          ["Esc", "Back one step"]
        ]
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Where the habits are kept"
        note: "~/.local/share/moarchy-habits/habits.json: every habit, every day it was kept, and the achievements earned. The same file the GTK version kept, saved after every tap."
      }
    }
  }

  // A habit over the tab on a phone, and the editor anywhere:
  // { kind: "detail", id } or { kind: "edit", id } ("" for a new one).
  page: Component {
    Loader {
      sourceComponent: root.topPage && root.topPage.kind === "edit" ? editorPage : detailPage
    }
  }
  Component {
    id: detailPage
    DetailView { app: root; habit: root.habitById(root.topPage ? root.topPage.id : ""); paged: true }
  }
  Component {
    id: editorPage
    EditorView { app: root; habit: root.topPage && root.topPage.id ? root.habitById(root.topPage.id) : null }
  }

  // ------------------------------------------------------------ the habits

  property var habits: []
  property var achievements: ({})
  property bool loaded: false
  property string today: H.todayFrom(Date.now(), Quickshell.env("MOARCHY_HABITS_TODAY"))

  // Bumped on every write so the bindings that walk a habit's history -- the
  // streak, the score, the strip -- recompute. The habit objects are changed
  // in place, as habits.py changed them, so nothing else tells QML to look.
  property int revision: 0

  readonly property var shownHabits: revision >= 0 ? H.active(habits) : []

  function habitById(id) {
    var r = revision
    var i = H.indexOf(habits, id)
    return i >= 0 ? habits[i] : null
  }

  // The habit shown beside the list on a desktop, and the one the arrow keys
  // are on.
  property string selectedId: ""
  property int cursor: 0
  readonly property var selectedHabit: selectedId ? habitById(selectedId) : null
  readonly property bool splitDetail: !compact && contentArea.width >= 820

  function openHabit(id) {
    var i = H.indexOf(shownHabits, id)
    if (i >= 0) cursor = i
    if (tab === "today" && splitDetail) selectedId = id
    else push({ kind: "detail", id: id })
  }
  function newHabit() { push({ kind: "edit", id: "" }) }
  function editHabit(habit) { if (habit) push({ kind: "edit", id: habit.id }) }

  // A window narrowed past the breakpoint with a habit open beside the list:
  // the habit becomes the page over the list, rather than disappearing.
  onCompactChanged: {
    if (!compact || !selectedId || tab !== "today" || topPage) return
    var id = selectedId
    selectedId = ""
    push({ kind: "detail", id: id })
  }

  stepBack: function () {
    if (selectedId && tab === "today") { selectedId = ""; return true }
    return false
  }

  onTabSelected: function (key) { if (key === "today" || key === "achievements") store.set("lastTab", key) }

  function save() { file.save(H.serialize(habits, achievements) + "\n") }

  // A tap on a day. Returns whether the day is now kept, so the mark can
  // light up; tomorrow is not a day anybody has done anything on yet.
  function tick(habit, day) {
    if (!habit || day > today) return false
    var wasStreak = H.streak(habit, today)
    var before = H.todayProgress(habits, today)
    var wasComplete = before.due > 0 && before.done === before.due
    var kept = H.tap(habit, day)
    revision += 1
    save()
    // Unticking is not a thing to celebrate: a halo on the way down would
    // read as a reward for undoing the work.
    if (!kept) return false
    celebrate(habit, wasStreak, wasComplete)
    return true
  }

  // Say something, but only when there is something to say, and at most one
  // thing a tap -- a new achievement, then a milestone crossed, then the day
  // finished. A tracker that fires three toasts at a thumb gets muted.
  function celebrate(habit, wasStreak, wasComplete) {
    var earned = award()
    if (earned.length) {
      var first = Game.describe(earned[0])
      toast("Achievement: " + first.name + (earned.length > 1 ? " (+" + (earned.length - 1) + " more)" : ""))
      return
    }
    var run = H.streak(habit, today)
    var crossed = H.milestoneCrossed(wasStreak, run)
    if (crossed) {
      var best = H.bestStreak(habit, today)
      toast(crossed + " days of " + (habit.name || "this") + "." + (crossed >= best ? " Longest yet." : ""))
      return
    }
    var p = H.todayProgress(habits, today)
    if (p.due > 0 && p.done === p.due && !wasComplete) toast("That is all " + p.due + " today.")
  }

  // Credit whatever the history deserves. Returns the keys newly earned;
  // the caller decides whether to say so.
  function award() {
    var fresh = Game.newlyEarned(habits, achievements, today)
    if (!fresh.length) return []
    var earned = Object.assign({}, achievements)
    for (var i = 0; i < fresh.length; i++) earned[fresh[i]] = today
    achievements = earned
    save()
    return fresh
  }

  function saveHabit(habit, fields) {
    if (habit) {
      H.apply(habit, fields)
      revision += 1
      save()
      pop()
      return
    }
    var made = H.apply(H.make({ created: Date.now() / 1000 }), fields)
    habits = habits.concat([made])
    revision += 1
    award()
    save()
    pop()
    toast("Added " + made.name)
    if (splitDetail) selectedId = made.id
  }

  // Deleting is asked first, and can be taken back for a few seconds after.
  function askDelete(habit) { if (habit) confirmDelete.open(habit) }

  property var removed: null
  function deleteHabit(habit) {
    var out = H.remove(habits, habit.id)
    if (out.index < 0) return
    habits = out.habits
    removed = { habit: out.habit, index: out.index }
    if (selectedId === habit.id) selectedId = ""
    stack = stack.filter(function (e) { return e.id !== habit.id })
    revision += 1
    save()
    undoTimer.restart()
  }
  function undoDelete() {
    if (!removed) return
    habits = H.restore(habits, removed.habit, removed.index)
    removed = null
    undoTimer.stop()
    revision += 1
    save()
  }
  Timer { id: undoTimer; interval: 6000; onTriggered: root.removed = null }

  Dialog {
    id: confirmDelete
    app: root
    title: "Delete " + (subject ? subject.name || "this habit" : "") + "?"
    text: "Its history goes with it."
    acceptText: "Delete"
    destructive: true
    onAccepted: root.deleteHabit(subject)
  }

  DataFile {
    id: file
    app: "habits"
    name: "habits.json"
    onParsed: function (data) {
      // Our own save, read back: nothing to do.
      if (root.loaded && data && H.serialize(H.parse(data).habits, H.parse(data).achievements)
          === H.serialize(root.habits, root.achievements)) return
      var got = H.parse(data)
      root.habits = got.habits
      root.achievements = got.achievements
      root.loaded = true
      root.revision += 1
      // Whatever the history already deserves, credited at once and quietly:
      // six achievements on the first run are a fact, not six pieces of news.
      root.award()
      Qt.callLater(root.harness)
    }
    onQuarantined: function (to) { root.toast("The habits file was unreadable and was kept aside") }
  }

  // The day can change under a window left open overnight.
  Timer {
    interval: 60000
    repeat: true
    running: root.opened
    onTriggered: {
      var now = H.todayFrom(Date.now(), Quickshell.env("MOARCHY_HABITS_TODAY"))
      if (now !== root.today) { root.today = now; root.revision += 1 }
    }
  }

  onSummoned: {
    var now = H.todayFrom(Date.now(), Quickshell.env("MOARCHY_HABITS_TODAY"))
    if (now !== today) { today = now; revision += 1 }
  }

  // ------------------------------------------------------------ the harness

  // For the screenshots: _OPEN names a habit, _PAGE a screen, _NEW opens the
  // editor, _TODAY pins the day so two shots either side of midnight agree.
  property bool pinnedPage: false
  property bool harnessed: false
  Component.onCompleted: {
    if ((Quickshell.env("MOARCHY_HABITS_PAGE") || "") === "achievements") { tab = "achievements"; pinnedPage = true }
    if ((Quickshell.env("MOARCHY_HABITS_PAGE") || "") === "settings") { tab = "settings"; pinnedPage = true }
  }
  function harness() {
    if (harnessed) return
    harnessed = true
    var want = Quickshell.env("MOARCHY_HABITS_OPEN") || ""
    if (want) {
      for (var i = 0; i < habits.length; i++)
        if (habits[i].name.toLowerCase() === want.toLowerCase()) { Qt.callLater(openHabit, habits[i].id); break }
    }
    if (Quickshell.env("MOARCHY_HABITS_NEW")) Qt.callLater(newHabit)
  }

  // ------------------------------------------------------------ keys

  keyHandler: function (event) {
    if (topPage || inSettings || tab !== "today") return
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    var list = shownHabits
    var k = event.key
    if (event.text === "n") { newHabit(); event.accepted = true; return }
    if (!list.length) return
    var here = list[Math.max(0, Math.min(cursor, list.length - 1))]
    if (k === Qt.Key_Down || k === Qt.Key_Up) {
      cursor = Math.max(0, Math.min(list.length - 1, cursor + (k === Qt.Key_Down ? 1 : -1)))
      if (selectedId) selectedId = list[cursor].id
      todayView.ensureVisible(cursor)
      event.accepted = true
      return
    }
    if (k === Qt.Key_Space) { tick(selectedHabit || here, today); event.accepted = true; return }
    if (k === Qt.Key_Return || k === Qt.Key_Enter) { openHabit(here.id); event.accepted = true; return }
    if (event.text === "e") { editHabit(selectedHabit || here); event.accepted = true; return }
    if (k === Qt.Key_Delete) { askDelete(selectedHabit || here); event.accepted = true }
  }

  IpcHandler {
    target: "habits"
    function tick(name: string, day: string): string {
      for (var i = 0; i < root.habits.length; i++)
        if (root.habits[i].name === name || root.habits[i].id === name) {
          root.tick(root.habits[i], day || root.today)
          return H.kept(root.habits[i], day || root.today) ? "kept" : "not kept"
        }
      return "no such habit"
    }
    function progress(): string {
      var p = H.todayProgress(root.habits, root.today)
      return p.done + "/" + p.due
    }
    function settled(): bool { return root.loaded }
  }

  // ------------------------------------------------------------ the screen

  TodayView { id: todayView; anchors.fill: parent; app: root; visible: root.tab === "today" }
  AchievementsView { anchors.fill: parent; app: root; visible: root.tab === "achievements" }

  // A deleted habit, for a few seconds more.
  Rectangle {
    z: 5
    visible: root.removed !== null
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 16
    width: Math.min(parent.width - 32, undoRow.implicitWidth + 32)
    height: 42
    radius: root.ui.radius
    color: root.ui.surfaceHigh
    border.width: 1
    border.color: root.ui.line
    Row {
      id: undoRow
      anchors.centerIn: parent
      spacing: 12
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "Deleted " + (root.removed ? root.removed.habit.name : "")
        color: root.ui.text
        font.family: root.ui.font
        font.pixelSize: root.ui.fs.sm
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "Undo"
        color: root.ui.accent
        font.family: root.ui.font
        font.pixelSize: root.ui.fs.sm
        font.weight: Font.Bold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: root.ui.tracking
        MouseArea { anchors.fill: parent; anchors.margins: -12; onClicked: root.undoDelete() }
      }
    }
  }
}
