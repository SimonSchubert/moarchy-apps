import QtQuick
import Quickshell
import Quickshell.Io
import "kit"
import "kit/Theme.js" as Theme
import "Sysinfo.js" as Sysinfo
import "Collect.js" as Collect
import "Glyphs.js" as G

// Vitals: what the processor, the memory, the storage, the battery and the
// network are doing, what is doing it, and a tap to stop it. Out of /proc and
// /sys, and nothing else.
//
//     omarchy-shell shell toggle org.moarchy.vitals
//
// The window, the two layouts, the theme and the way back out are the kit's
// (kit/App.qml). What is here is the machine: reading it, remembering the
// last two minutes of it, and ending what is using it.
//
// The clock stops when the window leaves the screen. The plugin is kept
// loaded by the shell, and a monitor walking /proc every two seconds from
// inside a pocket is the battery bug this app is for finding.
App {
  id: root

  appId: "org.moarchy.vitals"
  title: "Vitals"
  caption: sample && sample.machine.host ? sample.machine.host : "System monitor"
  subtitle: {
    if (!sample) return recorded ? "Reading a recorded machine…" : "Reading /proc…"
    var m = sample.machine
    var bits = []
    if (m.model) bits.push(m.model)
    else if (m.host) bits.push(m.host)
    bits.push("up " + Sysinfo.humanSeconds(sample.uptime))
    return bits.join(" · ")
  }
  windowWidth: 1240
  windowHeight: 820

  store: Store {
    name: "moarchy-vitals"
    defaults: ({
      lastTab: "overview",
      // "apps" groups processes of one name into one row; "all" is every pid.
      taskMode: "apps",
      // "cpu", "memory" or "name".
      taskSort: "cpu",
      interval: 2000
    })
    clean: function (p) {
      if (root.tabKeys.indexOf(p.lastTab) < 0) p.lastTab = "overview"
      if (["apps", "all"].indexOf(p.taskMode) < 0) p.taskMode = "apps"
      if (["cpu", "memory", "name"].indexOf(p.taskSort) < 0) p.taskSort = "cpu"
      if (root.intervals.indexOf(p.interval) < 0) p.interval = 2000
      return p
    }
    onReadyChanged: {
      if (!ready) return
      if (!root.pinnedPage) root.tab = prefs.lastTab
      if (root.pinnedMode) set("taskMode", root.pinnedMode)
    }
  }

  launcher.desktopId: "org.moarchy.Vitals"
  launcher.genericName: "System monitor"
  launcher.comment: "Processor, memory, storage, battery and network, and what is using them"
  launcher.categories: "System;Monitor;"
  launcher.keywords: "system;monitor;task manager;cpu;memory;process;network;battery;disk;"

  mark: Component { Mark { size: 30 } }

  tabs: [
    { key: "overview", label: "Overview", glyph: G.overview },
    { key: "processor", label: "Processor", glyph: G.processor },
    { key: "memory", label: "Memory", glyph: G.memory },
    { key: "tasks", label: "Tasks", glyph: G.tasks },
    { key: "network", label: "Network", glyph: G.network }
  ]
  readonly property var tabKeys: ["overview", "processor", "memory", "tasks", "network"]
  readonly property var intervals: [1000, 2000, 5000]

  settings: Component { SettingsView { app: root } }

  // A detail page over the tab, on a phone: { kind: "detail", sel }.
  page: Component {
    DetailView {
      app: root
      sel: root.topPage ? root.topPage.sel : null
      paged: true
    }
  }

  actions: Component {
    Row {
      spacing: 2
      IconButton {
        app: root
        glyph: root.paused ? G.play : G.pause
        label: root.paused ? "Resume" : "Pause"
        active: root.paused
        onClicked: root.paused = !root.paused
      }
    }
  }

  // The machine at a glance, at the foot of the rail: on every page, so the
  // Tasks page still says how busy the processor is.
  railFooter: Component {
    Column {
      visible: root.sample !== null
      spacing: 10

      Repeater {
        model: [
          { label: "Processor", value: root.sample ? root.sample.cpu.total : 0, text: root.sample ? Sysinfo.humanPercent(root.sample.cpu.total) : "", color: root.ui.cpu },
          { label: "Memory", value: root.sample ? root.sample.memory.fraction : 0, text: root.sample ? Sysinfo.humanPercent(root.sample.memory.fraction) : "", color: root.ui.mem }
        ]
        delegate: Column {
          required property var modelData
          width: parent.width
          spacing: 5
          Item {
            width: parent.width
            height: 16
            Text {
              text: modelData.label
              color: root.ui.muted
              font.family: root.ui.font
              font.pixelSize: root.ui.fs.xs
            }
            Text {
              anchors.right: parent.right
              text: modelData.text
              color: root.ui.text
              font.family: root.ui.font
              font.pixelSize: root.ui.fs.xs
              font.weight: Font.DemiBold
              font.features: ({ "tnum": 1 })
            }
          }
          Meter { app: root; width: parent.width; implicitHeight: 6; value: modelData.value; fill: modelData.color }
        }
      }

      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: root.paused ? "Paused · Space to resume" : "Every " + root.interval / 1000 + " s · Space to pause"
        color: root.alpha(root.ui.muted, 0.85)
        font.family: root.ui.font
        font.pixelSize: root.ui.fs.xs
      }
    }
  }

  // ------------------------------------------------------------ tokens

  // Two or three cards across, from the width the pages have.
  readonly property int columns: contentArea.width >= 1180 ? 3 : contentArea.width >= 700 ? 2 : 1

  // A theme's hue for a role, unless it is too close to one already taken --
  // a theme's "cyan" is sometimes a rose, and download and upload in one
  // colour is a graph that says nothing.
  function alike(a, b) { return Theme.alike(a, b) }
  function pickHue(name, fallback, taken) {
    var h = hostTheme.hue(name)
    if (!h) return fallback
    for (var i = 0; i < taken.length; i++) if (alike(h, taken[i])) return fallback
    return h
  }

  ui: Tokens {
    theme: root.hostTheme
    compact: root.compact

    // One measurement, one hue, everywhere it appears: the processor is the
    // accent, memory magenta, storage blue, and the network's two directions
    // cyan and orange -- the theme's own, where it names them. A phone has no
    // room for a legend, so the colour is the legend, which only works if
    // nothing else is that colour.
    readonly property color cpu: accent
    readonly property color mem: root.pickHue("magenta", dark ? "#a78bfa" : "#7c3aed", [accent])
    readonly property color swap: alpha(mem, 0.6)
    readonly property color disk: root.pickHue("blue", dark ? "#2dd4bf" : "#0d9488", [accent, mem])
    readonly property color down: root.pickHue("cyan", dark ? "#22d3ee" : "#0891b2", [accent])
    // Upload after download: if the theme's orange sits beside its cyan, the
    // fallback is checked too, and a violet is the last word.
    readonly property color up: {
      var h = root.pickHue("orange", dark ? "#fb923c" : "#ea580c", [down])
      return root.alike(h, down) ? (dark ? "#c084fc" : "#9333ea") : h
    }
  }

  // Green until it is worth noticing, then yellow, then red. The number is
  // beside it in every case, so the colour is what makes a screenful
  // scannable rather than what says what the value is.
  function loadColor(fraction) {
    if (fraction >= 0.85) return ui.bad
    if (fraction >= 0.6) return ui.warn
    return ui.good
  }

  function heatColor(celsius) {
    if (celsius === null || celsius === undefined) return ui.muted
    if (celsius >= 80) return ui.bad
    if (celsius >= 65) return ui.warn
    return ui.text
  }

  // The task table's columns, on a desktop.
  readonly property int colCpu: 76
  readonly property int colMem: 84
  readonly property int colCount: 58

  // ------------------------------------------------------------ pages

  property bool pinnedPage: false
  property string pinnedMode: ""

  Component.onCompleted: {
    var page = Quickshell.env("MOARCHY_VITALS_PAGE") || ""
    if (tabKeys.indexOf(page) >= 0 || page === "settings") { tab = page; pinnedPage = true }
    var mode = Quickshell.env("MOARCHY_VITALS_TASKS") || ""
    if (mode === "apps" || mode === "all") pinnedMode = mode
    pick = Quickshell.env("MOARCHY_VITALS_PICK") || ""
  }

  // MOARCHY_VITALS_PICK: open straight onto an app by name, or a pid -- for
  // screenshots, and for a script that wants to show somebody one thing.
  property string pick: ""
  function pickNow() {
    if (!pick || !sample || !sample.apps.length) return
    var want = pick
    pick = ""
    var pid = parseInt(want, 10)
    if (String(pid) === want && findProcess(pid)) openDetail({ kind: "process", pid: pid })
    else if (findApp("name:" + want)) openDetail({ kind: "app", key: "name:" + want })
  }

  onTabSelected: function (key) {
    if (tabKeys.indexOf(key) >= 0) store.set("lastTab", key)
    // A page that names processes after one that did not: read now rather
    // than show last minute's table for a tick.
    if (key !== "network" && key !== "settings") Qt.callLater(root.collect)
  }

  // What the task list's side pane shows on a desktop: { kind: "app", key }
  // or { kind: "process", pid }, or null.
  property var selection: null
  // Wide enough for the task list and a detail pane beside it.
  readonly property bool splitTasks: contentArea.width >= 900

  // An app or a process: beside the list when there is room, over it when
  // there is not.
  function openDetail(sel) {
    if (!sel) return
    resetFocus()
    if (tab === "tasks" && splitTasks) selection = sel
    else push({ kind: "detail", sel: sel })
    Qt.callLater(root.collect)
  }

  // Before the tabs: the search, then the selection.
  stepBack: function () {
    if (tab === "tasks" && tasksView.query !== "") { tasksView.clearQuery(); return true }
    if (selection && tab === "tasks") { selection = null; return true }
    return false
  }

  // The detail shown right now, wherever it is.
  readonly property var shownSel: topPage && topPage.kind === "detail" ? topPage.sel
    : (tab === "tasks" && splitTasks ? selection : null)

  keyHandler: function (event) {
    var k = event.key
    if (tab === "tasks" && !topPage && !inSettings) {
      if (k === Qt.Key_Down) { tasksView.move(1); event.accepted = true; return }
      if (k === Qt.Key_Up) { tasksView.move(-1); event.accepted = true; return }
      if (k === Qt.Key_PageDown) { tasksView.move(8); event.accepted = true; return }
      if (k === Qt.Key_PageUp) { tasksView.move(-8); event.accepted = true; return }
      if (k === Qt.Key_Return || k === Qt.Key_Enter) { tasksView.activateCurrent(); event.accepted = true; return }
      if (k === Qt.Key_Delete) {
        askEnd(shownSel || tasksView.currentSel(), (event.modifiers & Qt.ShiftModifier) !== 0)
        event.accepted = true
        return
      }
    } else if (shownSel && k === Qt.Key_Delete) {
      askEnd(shownSel, (event.modifiers & Qt.ShiftModifier) !== 0)
      event.accepted = true
      return
    }
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    if (k === Qt.Key_Space) { paused = !paused; event.accepted = true; return }
    if (event.text === "/") {
      setTab("tasks")
      Qt.callLater(tasksView.focusField)
      event.accepted = true
      return
    }
    if (event.text === "a" && tab === "tasks") { store.set("taskMode", store.prefs.taskMode === "apps" ? "all" : "apps"); event.accepted = true; return }
    if (event.text === "s" && tab === "tasks") {
      var order = ["cpu", "memory", "name"]
      store.set("taskSort", order[(order.indexOf(store.prefs.taskSort) + 1) % 3])
      event.accepted = true
    }
  }

  // ------------------------------------------------------------ the reading

  // The last reading, and the one before it that every rate is measured
  // against.
  property var sample: null
  property bool paused: false
  readonly property int interval: store.prefs.interval || 2000

  // Two minutes at the default clock; the width of a graph and no more.
  readonly property int historyLength: 60
  property var cpuHistory: []
  property var memHistory: []
  property var swapHistory: []
  // { name: { rx: [], tx: [] } }, in bytes a second.
  property var netHistory: ({})

  // MOARCHY_VITALS_ROOT: a directory shaped like /, read instead of it.
  // MOARCHY_VITALS_DIR: demo.py's recorded phone, frames/000 onward, one
  // frame a tick. A monitor photographed two seconds after it opened has one
  // reading and a flat line; a reel has a past, so it is played through at
  // once and then held on its last frame.
  readonly property string reelDir: Quickshell.env("MOARCHY_VITALS_DIR") || ""
  readonly property string plainRoot: Quickshell.env("MOARCHY_VITALS_ROOT") || "/"
  property int frame: 0
  property bool reelEnded: reelDir === ""
  readonly property bool recorded: reelDir !== "" || plainRoot !== "/"
  readonly property string sysroot: {
    if (reelDir === "") return plainRoot
    if (reelEnded && frame < 0) return reelDir
    var n = String(Math.max(0, frame))
    while (n.length < 3) n = "0" + n
    return reelDir + "/frames/" + n
  }

  // The processes are read on every page that names them, which is all of
  // them but the network and the settings -- a few hundred files, and reading
  // them to draw an interface's rates is work nobody sees.
  readonly property bool wantProcesses: (tab !== "network" && tab !== "settings") || shownSel !== null

  function collect() {
    if (reader.running) { again = true; return }
    var pid = shownSel && shownSel.kind === "process" ? shownSel.pid : 0
    reader.command = Collect.command(sysroot, wantProcesses, pid)
    reader.running = true
  }
  property bool again: false

  function arrived(code, blob) {
    if (code !== 0) {
      // The reel ran out: hold its last frame.
      if (reelDir !== "" && !reelEnded) {
        reelEnded = true
        frame = frame > 0 ? frame - 1 : -1
        pickNow()
      }
      return
    }
    var pid = shownSel && shownSel.kind === "process" ? shownSel.pid : 0
    var next = Sysinfo.read(blob, sample, pid)
    if (next === sample) return
    sample = next
    cpuHistory = pushSample(cpuHistory, next.cpu.total)
    memHistory = pushSample(memHistory, next.memory.fraction)
    swapHistory = pushSample(swapHistory, next.memory.swap_fraction)
    var nh = ({})
    for (var i = 0; i < next.interfaces.length; i++) {
      var f = next.interfaces[i]
      var was = netHistory[f.name] || { rx: [], tx: [] }
      nh[f.name] = { rx: pushSample(was.rx, f.rx_rate), tx: pushSample(was.tx, f.tx_rate) }
    }
    netHistory = nh
    if (reelDir !== "" && !reelEnded) frame += 1
    else if (reelDir === "") pickNow()
  }

  function pushSample(series, value) {
    var out = series.slice()
    out.push(value)
    while (out.length > historyLength) out.shift()
    return out
  }

  Timer {
    id: tick
    // Two seconds by default: fast enough to watch something happen, slow
    // enough that the app is not itself the load. A recorded machine is
    // played through as fast as it reads.
    interval: root.reelEnded ? root.interval : 40
    repeat: true
    running: root.opened && !root.paused
    triggeredOnStart: true
    onTriggered: root.collect()
  }

  Process {
    id: reader
    running: false
    stdout: StdioCollector { id: readOut; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) {
      root.arrived(code, readOut.text)
      if (root.again) { root.again = false; Qt.callLater(root.collect) }
    }
    // qmllint enable signal-handler-parameters
  }

  // ------------------------------------------------------------ lookups

  function findApp(key) {
    if (!sample) return null
    var a = sample.apps
    for (var i = 0; i < a.length; i++) if (a[i].key === key) return a[i]
    return null
  }

  function findProcess(pid) {
    if (!sample) return null
    var p = sample.processes
    for (var i = 0; i < p.length; i++) if (p[i].pid === pid) return p[i]
    return null
  }

  function processesOf(appItem) {
    if (!appItem || !sample) return []
    var want = ({})
    for (var i = 0; i < appItem.pids.length; i++) want[appItem.pids[i]] = true
    return sample.processes.filter(function (p) { return want[p.pid] === true })
  }

  function appKeyOf(proc) {
    if (!proc) return ""
    return proc.pid === 2 || proc.ppid === 2 ? "kernel" : "name:" + proc.name
  }

  // Five on the overview, eight on a page of their own.
  function busiest(n) { return sample ? Sysinfo.busiest(sample.apps, n) : [] }
  function largest(n) { return sample ? Sysinfo.largest(sample.apps, n) : [] }

  // The interface anybody means by "the network": the busiest one that is up
  // and is not the loopback. Sorted that way by Sysinfo already.
  readonly property var mainInterface: {
    if (!sample) return null
    var list = sample.interfaces
    for (var i = 0; i < list.length; i++) if (list[i].up && list[i].name !== "lo") return list[i]
    return list.length ? list[0] : null
  }

  // A round number at or above the peak: 1, 2 or 5 times a power of ten.
  function niceScale(values) {
    var peak = 0
    for (var i = 0; i < values.length; i++) if (values[i] > peak) peak = values[i]
    if (peak < 1024) return 1024
    var p = Math.pow(10, Math.floor(Math.log(peak) / Math.LN10))
    var steps = [1, 2, 5, 10]
    for (var j = 0; j < steps.length; j++) if (steps[j] * p >= peak) return steps[j] * p
    return 10 * p
  }

  function netScale(name) {
    var h = netHistory[name]
    if (!h) return 1024
    return niceScale(h.rx.concat(h.tx))
  }

  // ------------------------------------------------------------ ending

  // Ending something: asked first, in words that say which signal.
  // The subject is { force, name, pids, app }.
  function askEnd(sel, force) {
    if (!sel) return
    var what = null
    if (sel.kind === "app") {
      var a = findApp(sel.key)
      if (!a) return
      if (a.kernel) { toast("Kernel threads can't be ended"); return }
      what = { force: force, name: a.name, pids: a.pids.slice(), app: true }
    } else {
      var p = findProcess(sel.pid)
      if (!p) { toast("That process has exited"); return }
      if (p.kernel) { toast("Kernel threads can't be ended"); return }
      what = { force: force, name: p.name, pids: [p.pid], app: false }
    }
    confirm.open(what)
  }

  Dialog {
    id: confirm
    app: root
    readonly property var what: subject || ({ force: false, name: "", pids: [], app: false })
    title: (what.force ? "Force stop " : "End ") + what.name + "?"
    text: (what.app && what.pids.length > 1 ? "All " + what.pids.length + " of its processes are signalled. " : "")
      + (what.force
         ? "It is stopped immediately, mid-write: anything it had not saved is lost."
         : "It is asked to stop, and can save what it was doing first.")
    destructive: true
    acceptGlyph: what.force ? G.kill : G.stop
    acceptText: what.force ? "Force stop" : "End task"
    onAccepted: root.end(what)
  }

  // Ending an app signals every process in it, lowest pid first. pid 1 is
  // refused outright: nothing an app of this shape wants to do is served by
  // signalling init, and in a container the kernel would not refuse it.
  function end(what) {
    if (!what) return
    var pids = what.pids.filter(function (p) { return p > 1 })
    if (!pids.length) { toast("Refusing to signal pid 1"); return }
    if (recorded) { toast("A recorded machine: nothing was signalled"); return }
    killer.what = what
    killer.command = ["kill", what.force ? "-KILL" : "-TERM"].concat(pids.map(String))
    killer.running = true
  }

  Process {
    id: killer
    property var what: null
    running: false
    stderr: StdioCollector { id: killErr; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) {
      var w = killer.what
      if (!w) return
      var err = killErr.text
      // kill exits 1 when any one pid fails, and a process of an app that
      // exited on its own between the reading and the tap is the usual one:
      // gone is what was asked for. Refused is another matter.
      var refused = /permitted/i.test(err)
      var vanished = /no such process/i.test(err)
      if (code === 0 || (vanished && !refused)) {
        root.toast(code !== 0 && w.pids.length === 1 ? w.name + " had already exited"
                   : (w.force ? "Force stopped " : "Ended ") + w.name)
        root.stack = root.stack.filter(function (e) { return e.kind !== "detail" })
        root.selection = null
      } else if (refused) {
        root.toast(w.name + " belongs to another user")
      } else {
        root.toast("Couldn't end " + w.name)
      }
      Qt.callLater(root.collect)
    }
    // qmllint enable signal-handler-parameters
  }

  // Closed, it forgets the machine: the next open starts a new history rather
  // than drawing a graph with a hole in it the length of the time it was shut.
  onOpenedChanged: {
    if (opened) return
    sample = null
    cpuHistory = []
    memHistory = []
    swapHistory = []
    netHistory = ({})
    paused = false
  }

  // ------------------------------------------------------------ views

  OverviewView { anchors.fill: parent; app: root; visible: root.tab === "overview" }
  ProcessorView { anchors.fill: parent; app: root; visible: root.tab === "processor" }
  MemoryView { anchors.fill: parent; app: root; visible: root.tab === "memory" }
  TasksView { id: tasksView; anchors.fill: parent; app: root; visible: root.tab === "tasks" }
  NetworkView { anchors.fill: parent; app: root; visible: root.tab === "network" }

  // Before the first reading: something rather than nothing.
  Column {
    anchors.centerIn: parent
    visible: root.sample === null
    spacing: 12
    Spinner { app: root; anchors.horizontalCenter: parent.horizontalCenter; running: parent.visible }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.recorded ? "Reading a recorded machine" : "Reading /proc"
      color: root.ui.muted
      font.family: root.ui.font
      font.pixelSize: root.ui.fs.sm
    }
  }
}
