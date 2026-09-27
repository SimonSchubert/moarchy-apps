// A clock: the time, an alarm, a stopwatch and a timer.
//
// Three tabs and no fourth. Android's clock has a world-clock page and this
// does not, because the one thing a world clock needs is a list of somewhere
// else -- and the page that would carry it is the page a phone already has a
// clock on, in its own status bar. The first screen is a dial, because an app
// called Clock whose first screen is a list has hidden the thing it is named
// after.
//
//     omarchy-shell shell toggle org.moarchy.clock
//
// Inside the Omarchy shell this is the only arrangement in which an alarm
// works at all. `keepLoaded` means this Item exists from the moment the shell
// starts, so the timer that watches for an alarm runs while the window is
// nowhere on screen -- one Timer, aimed at the next thing due and capped at a
// minute, and nothing else. Run on its own (`moarchy-clock` with no shell) the
// app is a window, and closing it is quitting: its alarms ring while it is open.
//
// What it cannot do is wake a phone that is asleep. Nothing a user process can
// do will: `WakeSystem=true` on a systemd timer is root's, and so is `rtcwake`.
// So an alarm that came due while the phone was off rings when it comes back,
// and says how late it is, up to an hour. Past that it is recorded as missed
// and said out loud, because a phone that rings at ten for a seven o'clock
// alarm is worse than one that admits it slept through.
//
// Below 720 px the tabs are at the bottom and the alarm editor is a page; above
// it they are a rail, the dial sits beside the alarms and the laps beside the
// stopwatch.
import QtQuick
import Quickshell
import Quickshell.Io
import "kit"
import "kit/Glyphs.js" as KG
import "Alarms.js" as Alarms
import "Watch.js" as Watch
import "Store.js" as Saved

App {
  id: root

  appId: "org.moarchy.clock"
  title: "Clock"
  subtitle: subtitleText()
  windowWidth: 1100
  windowHeight: 760

  store: Store { name: "moarchy-clock" }

  launcher.desktopId: "org.moarchy.Clock"
  launcher.genericName: "Clock"
  launcher.comment: "The time, an alarm that says when it is late, a stopwatch and a timer"
  launcher.categories: "Utility;Clock;"
  launcher.keywords: "clock;alarm;stopwatch;timer;countdown;time;"

  mark: Component { Image { source: root.appDir + "/icon.svg"; sourceSize: Qt.size(60, 60) } }

  ui: Tokens {
    theme: root.hostTheme
    compact: root.compact
    // A missed alarm and a late ring are said in the theme's orange.
    readonly property color late: hue("orange", "#fb923c", "#c2410c")
    // An alarm that is off is drawn on a fainter card as well as with its
    // switch: one signal is a switch somebody has to look for.
    readonly property color offCard: Qt.tint(bg, alpha(text, dark ? 0.025 : 0.02))
  }

  // The size text is measured from: the digits, the wheels and the dial.
  readonly property int body: compact ? 16 : 18

  tabs: [
    { key: "alarm", label: "Alarm", glyph: String.fromCodePoint(0xF0020) },        // md-alarm
    { key: "stopwatch", label: "Stopwatch", glyph: String.fromCodePoint(0xF051B) }, // md-timer_outline
    { key: "timer", label: "Timer", glyph: String.fromCodePoint(0xF051F) }          // md-timer_sand
  ]

  actions: Component {
    Row {
      spacing: 2
      IconButton {
        visible: root.tab === "alarm" && !root.compact
        app: root
        glyph: KG.plus
        label: "New alarm"
        onClicked: root.startNew()
      }
    }
  }

  // The alarm being set, over the tab.
  page: Component { AlarmEditor { app: root } }

  settings: Component {
    SettingsPage {
      app: root
      blurb: "The time, an alarm that says when it is late, a stopwatch and a timer."
      SettingsSection {
        app: root
        width: parent.width
        title: "Clock"
        note: "Twelve or twenty-four hours. Until you choose, it is what the locale's own time format says."
        Flow {
          width: parent.width
          spacing: 8
          Chip {
            app: root
            text: "Locale (" + (root.localeHour24 ? "24" : "12") + "-hour)"
            selected: typeof root.clockPrefs.hour24 !== "boolean"
            onClicked: root.setSetting("hour24", null)
          }
          Chip {
            app: root
            text: "12-hour"
            selected: root.clockPrefs.hour24 === false
            onClicked: root.setSetting("hour24", false)
          }
          Chip {
            app: root
            text: "24-hour"
            selected: root.clockPrefs.hour24 === true
            onClicked: root.setSetting("hour24", true)
          }
        }
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Ringing"
        Toggle {
          app: root
          width: parent.width
          text: "Ring on the screen only"
          note: "No sound: the ringing screen, and nothing else."
          checked: !!root.clockPrefs.silent
          onToggled: function (on) {
            root.setSetting("silent", on)
            root.say(on ? "Alarms will ring on the screen only." : "Alarms will make a sound.")
          }
        }
      }
      AppearanceSection { app: root }
      LauncherSection { app: root }
      KeysSection {
        app: root
        keys: [
          ["1 – 3", "Alarm, Stopwatch, Timer"],
          ["n", "A new alarm"],
          ["Space", "Start or stop the stopwatch; start, pause or resume the timer"],
          ["l", "Lap"],
          ["r", "Reset the stopwatch, or cancel the timer"],
          ["0 – 9", "Type a timer's length, on the Timer tab"],
          ["Enter", "Start the timer; stop a ring"],
          ["s", "Snooze a ringing alarm"],
          [",", "Settings"],
          ["Esc", "Back one step"]
        ]
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "When it can ring"
        note: "Inside the Omarchy shell, whether the window is open or not: the shell keeps the clock loaded. Started on its own, only while its window is open. Neither can wake a phone that is asleep; an alarm that came due then rings when the phone wakes, and says how late it is."
      }
    }
  }

  // ------------------------------------------------------------ what is known

  property var alarms: []
  // Rows of the file this app cannot read, kept so that saving does not
  // destroy them. Store.js says why at length.
  property var strays: []
  property var watch: Watch.blankWatch()
  property var timer: Watch.blankTimer()
  property var clockPrefs: Saved.defaults()

  property bool loaded: false
  property bool dirty: false

  // The clock, in milliseconds, sampled rather than counted. Everything on
  // every screen is drawn from this one number, which is what lets the
  // screenshot harness pin it.
  property double now: Date.now()
  // MOARCHY_CLOCK_NOW, in seconds: two pictures of a clock taken a second
  // apart are two different pictures, for reasons that are not the app's.
  property double pinnedNow: 0
  readonly property bool pinned: pinnedNow > 0

  // The alarm being edited, or null. A copy, always: nothing in `alarms`
  // changes until Save is pressed, which is what makes Back a cancel.
  property var draft: null
  property bool draftIsNew: false
  // The bin asks twice. There is no undo in a file with one version of
  // itself, so the second tap is the undo.
  property bool armed: false

  // An alarm that did not ring. It stays until it is dismissed, because the
  // whole of what this app can honestly promise about a sleeping phone is that
  // it will tell you afterwards. Not written to the file.
  property string missedNote: ""

  // What is going off, or null: { kind: "alarm" | "timer", id, at, since, label, time }
  property var ringing: null

  // The timer's keypad, as digits pushed in from the right.
  property var digits: []

  property string harnessPage: ""
  property string harnessTyped: ""
  property bool quiet: false

  // A ring nobody answers gives up rather than going on for ever, and says so
  // afterwards. Five minutes is roughly what a bedside clock radio managed.
  readonly property int ringSeconds: 300

  // ------------------------------------------------------------ derived

  // Twelve or twenty-four hours: the locale's until somebody chooses.
  readonly property bool localeHour24:
    String(Qt.locale().timeFormat(Locale.ShortFormat)).toLowerCase().indexOf("a") < 0
  readonly property bool hour24: typeof clockPrefs.hour24 === "boolean" ? clockPrefs.hour24 : localeHour24

  readonly property var ordered: Saved.sorted(alarms)
  readonly property var next: Alarms.soonest(alarms, now)
  readonly property double elapsed: Watch.elapsed(watch, now)
  readonly property var laps: Watch.lapRows(watch, now)
  readonly property double remaining: Watch.timerLeft(timer, now)
  readonly property double typed: Watch.keypadMs(digits)
  readonly property bool editing: draft !== null

  // The hands, as three fractions, read off `now` so a pinned clock has
  // pinned hands.
  readonly property var face: {
    var d = new Date(now)
    return { hours: d.getHours() % 12, minutes: d.getMinutes(), seconds: d.getSeconds() + d.getMilliseconds() / 1000 }
  }

  // The days in the order this locale's week runs; Qt and Date both number
  // Sunday 0, so the two agree without a map.
  readonly property var weekOrder: {
    var first = Qt.locale().firstDayOfWeek
    var out = []
    for (var i = 0; i < 7; i++) out.push((first + i) % 7)
    return out
  }

  // ------------------------------------------------------------ the clock

  function clockNow() { return pinned ? pinnedNow : Date.now() }

  // Re-read the clock and hand it back, for anything a thumb just did. A
  // stopwatch started on a second-old reading is wrong by up to a second,
  // which is the one number in this app nobody would forgive.
  function stamp() {
    now = clockNow()
    return now
  }

  // Most of what this app has to say, it has to say while the window is
  // nowhere: an alarm that went by, a row it could not read, a ring nobody
  // answered. So it is kept until there is a window to say it in.
  property string pending: ""
  function say(text) {
    if (opened) { toast(text); return }
    pending = String(text || "")
  }

  // ------------------------------------------------------------ harness

  function applyHarness() {
    var at = parseInt(Quickshell.env("MOARCHY_CLOCK_NOW") || "0", 10)
    pinnedNow = at > 0 ? at * 1000 : 0
    now = clockNow()
    harnessPage = String(Quickshell.env("MOARCHY_CLOCK_PAGE") || "")
    harnessTyped = String(Quickshell.env("MOARCHY_CLOCK_TYPED") || "")
    // _OFFLINE is what the harnesses set, and for a clock it means one thing:
    // no sound on a machine that is taking photographs.
    quiet = (Quickshell.env("MOARCHY_CLOCK_OFFLINE") || "") !== ""
  }

  function applyHarnessPage() {
    if (harnessTyped.length) {
      timer = Watch.blankTimer()
      var keys = []
      for (var i = 0; i < harnessTyped.length; i++) {
        var d = parseInt(harnessTyped.charAt(i), 10)
        if (isFinite(d)) keys = Watch.push(keys, d)
      }
      digits = keys
    }
    var want = harnessPage
    if (!want.length) return
    if (want === "stopwatch") setTab("stopwatch")
    else if (want === "timer" || want === "keypad") setTab("timer")
    else if (want === "settings") setTab("settings")
    else setTab("alarm")
    if (want === "editor" && ordered.length) Qt.callLater(function () { root.edit(root.ordered[0].id) })
    if (want === "ring") {
      // Four minutes ago, with an alarm set for then: the app would never ring
      // the fixture's own alarms that late, and a screenshot of a screen the
      // app cannot reach would be a screenshot that lies.
      var when = now - 4 * 60000
      var clock = new Date(when)
      var probe = Alarms.blank(clock.getHours(), clock.getMinutes())
      probe.label = ordered.length ? ordered[0].label : ""
      ring("alarm", probe, when)
    }
  }

  Component.onCompleted: applyHarness()

  // ------------------------------------------------------------ host

  onSummoned: function (payload) {
    now = clockNow()
    if (payload.page === "stopwatch" || payload.page === "timer" || payload.page === "alarm") setTab(payload.page)
    Qt.callLater(root.settle)
    if (pending.length) {
      toast(pending)
      pending = ""
    }
  }

  onOpenedChanged: {
    if (opened) return
    saveIfDirty()
    // Nothing that can happen by accident may lose an alarm that is going
    // off, and a tap on a launcher is the definition of an accident.
    if (ringing && !standalone) Qt.callLater(root.raise)
  }

  // Bring the window up for something the app decided.
  function raise() {
    if (shell && typeof shell.summon === "function") shell.summon(pluginId, "{}")
    else open("")
  }

  // Back while something is ringing does nothing: a gesture must not be able
  // to lose an alarm. Stop and Snooze are two large buttons.
  stepBack: function () { return root.ringing !== null }

  // The editor is a page; leaving it any way at all is a cancel.
  onTopPageChanged: if (!topPage) { draft = null; armed = false }

  keyHandler: function (event) {
    var k = event.key
    if (ringing) {
      if (k === Qt.Key_Return || k === Qt.Key_Enter) { stopRing(); event.accepted = true }
      else if (event.text === "s") { snoozeRing(); event.accepted = true }
      else event.accepted = true
      return
    }
    if (topPage || inSettings) return
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    if (event.text === "n") { setTab("alarm"); startNew(); event.accepted = true; return }
    if (tab === "stopwatch") {
      if (k === Qt.Key_Space) { watch.running ? watchStop() : watchStart(); event.accepted = true; return }
      if (event.text === "l" && watch.running) { watchLap(); event.accepted = true; return }
      if (event.text === "r" && !watch.running) { watchReset(); event.accepted = true; return }
    }
    if (tab === "timer") {
      if (timer.total > 0) {
        if (k === Qt.Key_Space) { timer.running ? timerPause() : timerResume(); event.accepted = true; return }
        if (event.text === "r") { timerCancel(); event.accepted = true; return }
      } else {
        var d = "0123456789".indexOf(event.text)
        if (d >= 0 && event.text !== "") { keyDigit(d); event.accepted = true; return }
        if (k === Qt.Key_Backspace) { keyBack(); event.accepted = true; return }
        if (k === Qt.Key_Delete) { keyClear(); event.accepted = true; return }
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) { timerStart(); event.accepted = true; return }
      }
    }
  }

  // ------------------------------------------------------------ the file

  function stateOut() {
    return { alarms: alarms, strays: strays, watch: watch, timer: timer, settings: clockPrefs }
  }

  function save() {
    file.save(Saved.serialize(stateOut()))
    dirty = false
  }

  function saveIfDirty() { if (dirty) save() }

  // An alarm somebody set, a lap somebody took: written at once, because every
  // one of them is rare and every one is the thing that would be missed. What
  // is never written per change is the clock -- no tick in this app touches
  // the disk.
  function commit() {
    dirty = true
    save()
  }

  function setSetting(key, value) {
    var n = { hour24: clockPrefs.hour24, silent: clockPrefs.silent }
    n[key] = value
    clockPrefs = n
    commit()
  }

  DataFile {
    id: file
    app: "clock"
    name: "clock.json"
    onParsed: function (data) {
      // Our own save, read back.
      if (root.loaded && data && Saved.serialize(Saved.parse(data)) === Saved.serialize(root.stateOut())) return
      var state = Saved.parse(data)
      // An enabled alarm with no `fired` came from a text editor, not from
      // here. Arming it from now is the rule the editor uses -- otherwise a
      // line typed at nine would be announced as an alarm slept through at
      // seven.
      for (var i = 0; i < state.alarms.length; i++)
        if (state.alarms[i].enabled && !state.alarms[i].fired) state.alarms[i].fired = root.clockNow()
      root.alarms = state.alarms
      root.strays = state.strays
      root.watch = state.watch
      root.timer = state.timer
      root.clockPrefs = state.settings
      root.now = root.clockNow()
      if (!root.loaded) {
        root.loaded = true
        root.applyHarnessPage()
      }
      // After the state is in, never before: an alarm that came due while the
      // phone was off is only knowable once the file has been read.
      Qt.callLater(root.settle)
      if (state.strays.length)
        root.say(state.strays.length + " row" + (state.strays.length === 1 ? "" : "s")
                 + " in the file could not be read, and were left alone.")
    }
    onQuarantined: function (to) { root.say("The clock file was unreadable and was kept aside.") }
  }

  // ------------------------------------------------------------ alarms

  function startNew() {
    var d = new Date(now)
    // Seven, the alarm most people are setting -- unless there is one already,
    // then the hour after this one, so a second alarm is not a fight with the
    // wheel.
    var hour = 7
    if (Alarms.soonest(alarms, now)) hour = (d.getHours() + 1) % 24
    draft = Alarms.blank(hour, 0)
    draftIsNew = true
    armed = false
    push({ kind: "editor" })
  }

  function edit(id) {
    var alarm = Alarms.find(alarms, id)
    if (!alarm) return
    draft = Alarms.clone(alarm)
    draftIsNew = false
    armed = false
    push({ kind: "editor" })
  }

  function change(key, value) {
    if (!draft) return
    // A write that changes nothing changes nothing: without this the wheels
    // are a binding loop, each one's value read off the draft it writes.
    if (draft[key] === value) return
    var n = Alarms.clone(draft)
    n[key] = value
    draft = n
  }

  function toggleDay(day) {
    if (!draft) return
    var days = draft.days.slice()
    var at = days.indexOf(day)
    if (at >= 0) days.splice(at, 1)
    else days.push(day)
    days.sort(function (a, b) { return a - b })
    change("days", days)
  }

  function setRepeat(days) { change("days", days.slice()) }

  function saveDraft() {
    if (!draft) return
    if (draftIsNew && alarms.length >= Alarms.MAX) {
      say(Alarms.MAX + " alarms is as many as this app keeps.")
      return
    }
    var n = Alarms.clone(draft)
    if (!n.id.length) n.id = Alarms.newId(alarms.length + 1)
    n.enabled = true
    // Armed from now, not from zero: an alarm just set has dealt with every
    // occurrence before this instant. Zero was a bug -- at 10:09 an alarm set
    // for 10:15 has a most recent occurrence yesterday at 10:15, unrung, and a
    // new alarm was announced as one slept through.
    n.fired = stamp()
    n.snoozed = 0
    alarms = Saved.put(alarms, n)
    commit()
    pop()
    var at = Alarms.nextFire(n, now)
    say(Alarms.timeText(n.hour, n.minute, hour24) + (hour24 ? "" : " " + Alarms.meridiem(n.hour))
        + " · " + (at ? Alarms.untilLabel(at - now) : "off"))
  }

  function deleteDraft() {
    if (!draft) return
    if (!armed) { armed = true; return }
    alarms = Saved.drop(alarms, draft.id)
    commit()
    pop()
    say("Alarm deleted.")
  }

  function toggleAlarm(id) {
    var alarm = Alarms.find(alarms, id)
    if (!alarm) return
    var n = Alarms.clone(alarm)
    n.enabled = !n.enabled
    n.snoozed = 0
    // Switching on is a decision about the future: an alarm switched on at
    // 07:05 must not fire at once for the seven o'clock it was off for.
    if (n.enabled) n.fired = stamp()
    alarms = Saved.put(alarms, n)
    commit()
    if (n.enabled) {
      var at = Alarms.nextFire(n, now)
      if (at) say(Alarms.untilLabel(at - now))
    }
  }

  // When the alarm on the wheels would go off. The draft may be a copy of an
  // alarm that is off or snoozed, and neither is what the editor asks about.
  function previewFire() {
    if (!draft) return 0
    var probe = Alarms.clone(draft)
    probe.enabled = true
    probe.snoozed = 0
    probe.fired = 0
    return Alarms.nextFire(probe, now)
  }

  // ------------------------------------------------------------ ringing

  function ring(kind, subject, at) {
    ringing = {
      kind: kind,
      id: kind === "alarm" ? subject.id : "timer",
      at: at,
      since: now,
      label: kind === "alarm" ? (subject.label.length ? subject.label : "Alarm") : (Watch.spanLabel(timer.total) + " timer"),
      time: kind === "alarm" ? Alarms.timeText(subject.hour, subject.minute, hour24) : Watch.timerText(0)
    }
    startSound()
  }

  // Everything that has to happen because the clock moved. Called by every
  // timer here and by nothing else, so there is one place an alarm goes off.
  function settle() {
    if (!loaded) return
    if (ringing) {
      // A ring unanswered for long enough stops, and says so.
      if (now - ringing.since > ringSeconds * 1000) {
        var what = ringing.label
        stopSound()
        if (ringing.kind === "timer") timer = Watch.blankTimer()
        ringing = null
        commit()
        say(what + " rang for " + Math.round(ringSeconds / 60) + " minutes with nobody listening.")
      }
      return
    }
    for (var i = 0; i < alarms.length; i++) {
      var alarm = alarms[i]
      var at = Alarms.due(alarm, now)
      if (at) {
        alarms = Saved.put(alarms, Alarms.rang(alarm, at))
        commit()
        ring("alarm", alarm, at)
        raise()
        return
      }
      var lost = Alarms.missed(alarm, now)
      if (lost) {
        alarms = Saved.put(alarms, Alarms.rang(alarm, lost))
        commit()
        missedNote = Alarms.timeText(alarm.hour, alarm.minute, hour24)
          + (alarm.label.length ? " · " + alarm.label : "")
          + " went by " + Alarms.whichDay(lost, now) + " while the phone was off."
      }
    }
    var over = Watch.timerDue(timer, now)
    if (over) {
      ring("timer", null, over)
      raise()
      return
    }
    var gone = Watch.timerMissed(timer, now)
    if (gone) {
      var span = Watch.spanLabel(timer.total)
      timer = Watch.blankTimer()
      commit()
      missedNote = "The " + span + " timer ended while the phone was off."
    }
  }

  function snoozeRing() {
    if (!ringing || ringing.kind !== "alarm") return
    var alarm = Alarms.find(alarms, ringing.id)
    stopSound()
    ringing = null
    if (!alarm) return
    var n = Alarms.snooze(alarm, stamp())
    alarms = Saved.put(alarms, n)
    commit()
    say("Again " + Alarms.untilLabel(n.snoozed - now) + ".")
  }

  function stopRing() {
    if (!ringing) return
    var wasTimer = ringing.kind === "timer"
    stopSound()
    ringing = null
    if (wasTimer) {
      timer = Watch.blankTimer()
      setTab("timer")
    }
    commit()
  }

  function ringLate() { return ringing ? Alarms.lateLabel(now - ringing.at) : "" }

  // ------------------------------------------------------------ the sound
  //
  // Nothing here ships a tone. The one an alarm should make is on the machine
  // already -- `alarm-clock-elapsed` in the freedesktop sound theme -- and the
  // player is whichever of pipewire's, pulse's or libcanberra's is installed,
  // found by trying each and reading the exit code. Every candidate goes
  // through `sh -c`: a Process handed a binary that is not installed never
  // emits `exited`, so the walk would stop at the first missing player and
  // the ring would be quietly mute. With the wrapper, missing is exit 127.
  // When the list runs out the ring is silent and the screen says so.

  readonly property var players: [
    ["pw-play", "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"],
    ["paplay", "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"],
    ["canberra-gtk-play", "-i", "alarm-clock-elapsed"],
    ["pw-play", "/usr/share/sounds/freedesktop/stereo/complete.oga"],
    ["paplay", "/usr/share/sounds/freedesktop/stereo/complete.oga"]
  ]

  function playCommand(spec) {
    var line = "exec \"$0\""
    for (var i = 1; i < spec.length; i++) line += " \"$" + i + "\""
    return ["sh", "-c", line].concat(spec)
  }

  property int player: 0
  // Nothing on this machine could play it. Kept for as long as the process
  // runs, so the walk costs five processes once.
  property bool mute: false
  readonly property bool silent: quiet || !!clockPrefs.silent

  function startSound() {
    if (silent || mute) return
    player = 0
    playOnce()
  }

  function playOnce() {
    if (!ringing || silent || mute) return
    if (player >= players.length) { mute = true; return }
    tone.command = playCommand(players[player])
    tone.running = true
  }

  function stopSound() {
    gap.stop()
    tone.running = false
  }

  function toneEnded(code) {
    if (!ringing) return
    if (code !== 0) {
      player += 1
      playOnce()
      return
    }
    // A tone on a loop with no space in it is a siren. The gap makes it an
    // alarm clock.
    gap.restart()
  }

  // ------------------------------------------------------------ stopwatch

  function watchStart() { watch = Watch.startWatch(watch, stamp()); commit() }
  function watchStop() { watch = Watch.stopWatch(watch, stamp()); commit() }
  function watchLap() {
    var before = watch.laps.length
    watch = Watch.lapWatch(watch, stamp())
    if (watch.laps.length === before && before >= Watch.MAX_LAPS) say(Watch.MAX_LAPS + " laps is as many as this keeps.")
    else commit()
  }
  function watchReset() { watch = Watch.blankWatch(); commit() }

  // ------------------------------------------------------------ timer

  function keyDigit(digit) { digits = Watch.push(digits, digit) }
  function keyBack() { digits = Watch.pop(digits) }
  function keyClear() { digits = [] }
  function keyPreset(seconds) { digits = Watch.digitsFor(seconds * 1000) }
  function keyPress(key) {
    if (key === -1) { keyBack(); return }
    if (key === -2) { keyDigit(0); keyDigit(0); return }
    keyDigit(key)
  }

  function timerStart() {
    var ms = Watch.keypadMs(digits)
    if (ms <= 0) return
    timer = Watch.startTimer(ms, stamp())
    digits = []
    commit()
  }
  function timerPause() { timer = Watch.pauseTimer(timer, stamp()); commit() }
  function timerResume() { timer = Watch.resumeTimer(timer, stamp()); commit() }
  function timerAdd() { timer = Watch.extendTimer(timer, stamp(), 60000); commit() }
  function timerCancel() { timer = Watch.blankTimer(); commit() }

  // ------------------------------------------------------------ the beats

  // While the window is up: one second, re-aimed at the next whole one every
  // time it fires. A QML Timer goes off on the first frame after its interval,
  // and without the re-aim that error accumulates until the clock skips a
  // minute boundary by a beat.
  Timer {
    id: beat
    interval: 1000
    repeat: true
    running: root.opened && !root.pinned
    onTriggered: {
      root.now = root.clockNow()
      beat.interval = Math.max(120, 1000 - (root.now % 1000))
      root.settle()
    }
  }

  // The one screen that needs more than a second, while it is the screen:
  // tenths for the stopwatch, four a second for a countdown.
  Timer {
    interval: root.tab === "stopwatch" ? 100 : 250
    repeat: true
    running: root.opened && !root.pinned && !root.topPage
             && ((root.tab === "stopwatch" && root.watch.running)
                 || (root.tab === "timer" && root.timer.running))
    onTriggered: root.now = root.clockNow()
  }

  // The alarm's own clock, for when there is no window. Its interval is the
  // time to the next thing that has to happen, capped at a minute and floored
  // at a second: an alarm eight hours away wakes this sixty times an hour, not
  // three thousand six hundred. Only while the window is down -- the beat
  // above does it while it is up, and two timers moving `now` would restart
  // each other for ever.
  readonly property int wakeIn: {
    var at = 0
    if (ringing) {
      at = ringing.since + ringSeconds * 1000
    } else {
      if (next) at = next.at
      if (timer.running && timer.endsAt > now) at = at ? Math.min(at, timer.endsAt) : timer.endsAt
    }
    if (!at) return 60000
    return Math.max(1000, Math.min(60000, at - now))
  }

  Timer {
    id: wake
    interval: root.wakeIn
    repeat: true
    running: !root.opened && !root.pinned && root.loaded
    onTriggered: {
      root.now = root.clockNow()
      root.settle()
    }
    onIntervalChanged: if (wake.running) wake.restart()
  }

  Timer {
    id: gap
    interval: 900
    onTriggered: root.playOnce()
  }

  Process {
    id: tone
    running: false
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { root.toneEnded(code) }
    // qmllint enable signal-handler-parameters
  }

  IpcHandler {
    target: "clock"
    function state(): string { return root.opened ? "open" : "closed" }
    // The three questions a status bar or a script would ask.
    function next(): string {
      if (!root.next) return ""
      return Alarms.timeText(root.next.alarm.hour, root.next.alarm.minute, root.hour24)
             + " " + Alarms.untilLabel(root.next.at - root.now)
    }
    function elapsed(): string {
      return root.watch.running || root.elapsed > 0 ? Watch.watchText(root.elapsed) : ""
    }
    function remaining(): string {
      return root.timer.total > 0 ? Watch.timerText(root.remaining) : ""
    }
    // And the two a headset button would.
    function snooze(): string {
      if (!root.ringing) return "nothing is ringing"
      root.snoozeRing()
      return "ok"
    }
    function stop(): string {
      if (!root.ringing) return "nothing is ringing"
      root.stopRing()
      return "ok"
    }
  }

  // ------------------------------------------------------------ subtitle

  function subtitleText() {
    if (tab === "stopwatch") return watch.running ? "Running" : (elapsed > 0 ? "Stopped" : "")
    if (tab === "timer") {
      if (timer.total <= 0) return ""
      if (!timer.running) return "Paused"
      return "Ends " + Qt.formatTime(new Date(timer.endsAt), hour24 ? "HH:mm" : "h:mm AP")
    }
    if (!alarms.length) return "No alarms"
    if (!next) return "All off"
    var when = Alarms.untilLabel(next.at - now)
    return next.alarm.label.length ? next.alarm.label + " · " + when : when
  }

  // ------------------------------------------------------------ views

  AlarmsView { anchors.fill: parent; app: root; visible: root.tab === "alarm" }
  StopwatchView { anchors.fill: parent; app: root; visible: root.tab === "stopwatch" }
  TimerView { anchors.fill: parent; app: root; visible: root.tab === "timer" }

  RingScreen { app: root }
}
