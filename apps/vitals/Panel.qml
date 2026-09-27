import QtQuick
import Quickshell
import Quickshell.Io
import "Sysinfo.js" as Sysinfo
import "Collect.js" as Collect
import "Glyphs.js" as G

// Vitals: what the processor, the memory, the storage, the battery and the
// network are doing, what is doing it, and a tap to stop it. Out of /proc and
// /sys, and nothing else.
//
//     omarchy-shell shell toggle org.moarchy.vitals
//
// An ordinary window, tiled, focused and closed like any other app, and laid
// out from its own size: a rail of pages on the left and room for two or three
// cards across when it is wide, and a phone app -- tabs at the bottom, one
// column, detail pages that stack -- when it is narrow, as on Omarchy Mobile,
// where the window is the whole screen. Escape (the phone's back) steps out
// one level at a time.
//
// The clock stops when the window leaves the screen. The plugin is kept
// loaded by the shell, and a monitor walking /proc every two seconds from
// inside a pocket is the battery bug this app is for finding.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  // True when shell.qml runs it as its own process, with no Omarchy shell.
  property bool standalone: false

  // ------------------------------------------------------------ tokens

  readonly property bool compact: stage.width < 720
  // Two or three cards across, from the width the pages have.
  readonly property int columns: main.width >= 1180 ? 3 : main.width >= 700 ? 2 : 1

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  // Whether two colours read as one at a glance: hues within 45 degrees of
  // each other, or two greys. A rose and an orange are both "warm" on a
  // graph, however far apart their channels are.
  function alike(a, b) {
    var x = Qt.color(a), y = Qt.color(b)
    if (x.hslSaturation < 0.15 || y.hslSaturation < 0.15) return x.hslSaturation < 0.15 && y.hslSaturation < 0.15
    var d = Math.abs(x.hslHue - y.hslHue) * 360
    return Math.min(d, 360 - d) < 45
  }
  // A theme's hue for a role, unless it is too close to one already taken --
  // a theme's "cyan" is sometimes a rose, and download and upload in one
  // colour is a graph that says nothing.
  function pickHue(name, fallback, taken) {
    var h = theme.hue(name)
    if (!h) return fallback
    for (var i = 0; i < taken.length; i++) if (alike(h, taken[i])) return fallback
    return h
  }
  function luminance(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
  readonly property color onAccent: luminance(ui.accent) > 0.6 ? "#111111" : "#ffffff"

  // Omarchy's theme inside its shell, a plain one under any other Quickshell.
  HostTheme {
    id: theme
    appearance: storeObj.prefs.appearance || "theme"
  }
  readonly property bool inShell: theme.inShell
  readonly property alias hostTheme: theme
  Component.onCompleted: {
    theme.probe(root)
    var page = Quickshell.env("MOARCHY_VITALS_PAGE") || ""
    if (storeObj.tabs.indexOf(page) >= 0 || page === "settings") { tab = page; pinnedPage = true }
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

  readonly property QtObject ui: QtObject {
    readonly property bool dark: root.luminance(theme.background) < 0.5
    readonly property color bg: theme.background
    readonly property color text: theme.text
    // Some themes' muted is a border colour, too faint for a caption; then
    // the text, faded, which reads as the same role.
    readonly property color muted: Math.abs(root.luminance(theme.muted) - root.luminance(theme.background)) >= 0.28
      ? theme.muted : Qt.tint(bg, root.alpha(text, 0.62))
    readonly property color accent: theme.accent
    readonly property color border: theme.border
    readonly property color surface: Qt.tint(bg, root.alpha(text, dark ? 0.05 : 0.035))
    readonly property color surfaceHigh: Qt.tint(bg, root.alpha(text, dark ? 0.10 : 0.07))
    // The inside of a graph or a bar's track: a step down from the card.
    readonly property color well: Qt.tint(bg, root.alpha(text, dark ? 0.09 : 0.065))
    // No hover on a touch screen: a finger leaves the last row it lifted
    // from looking pointed at.
    readonly property color hover: root.compact ? "transparent" : root.alpha(text, 0.06)
    readonly property color pressed: root.alpha(text, 0.12)
    readonly property color selected: root.alpha(accent, 0.14)
    readonly property color accentSoft: root.alpha(accent, 0.16)
    readonly property color divider: root.alpha(text, 0.08)

    // One measurement, one hue, everywhere it appears: the processor is the
    // accent, memory magenta, storage blue, and the network's two directions
    // cyan and orange -- the theme's own, where it names them. A phone has no
    // room for a legend, so the colour is the legend, which only works if
    // nothing else is that colour.
    readonly property color cpu: accent
    readonly property color mem: root.pickHue("magenta", dark ? "#a78bfa" : "#7c3aed", [accent])
    readonly property color swap: root.alpha(mem, 0.6)
    readonly property color disk: root.pickHue("blue", dark ? "#2dd4bf" : "#0d9488", [accent, mem])
    readonly property color down: root.pickHue("cyan", dark ? "#22d3ee" : "#0891b2", [accent])
    // Upload after download: if the theme's orange sits beside its cyan, the
    // fallback is checked too, and a violet is the last word.
    readonly property color up: {
      var h = root.pickHue("orange", dark ? "#fb923c" : "#ea580c", [down])
      return root.alike(h, down) ? (dark ? "#c084fc" : "#9333ea") : h
    }
    // Load is a ramp rather than a hue: "this core is at 97%" and "this one
    // is at 12%" have to be told apart at arm's length in daylight.
    readonly property color good: theme.hue("green") || (dark ? "#4ade80" : "#16a34a")
    readonly property color warn: theme.hue("yellow") || (dark ? "#facc15" : "#ca8a04")
    readonly property color bad: theme.hue("red") || (dark ? "#f87171" : "#dc2626")

    readonly property string font: theme.fontFamily
    readonly property int radius: Math.max(6, Math.min(10, theme.cornerRadius))
    readonly property int target: root.compact ? 44 : 38
    readonly property int chip: root.compact ? 34 : 32
    readonly property int gutter: root.compact ? 12 : 20
    readonly property QtObject fs: QtObject {
      readonly property int xs: 11
      readonly property int sm: 13
      readonly property int md: 14
      readonly property int lg: 17
      readonly property int xl: root.compact ? 26 : 30
      readonly property int xxl: root.compact ? 34 : 40
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

  // Omarchy Mobile draws its gesture bar over the bottom of every app -- on
  // purpose: an app's background reaches the glass, and its controls stay
  // above the strip. 20 px, as the phone's Tokens.gestureHeight, and only
  // where the phone's gesture bar is installed. Inside the shell as well: the
  // strip is drawn over plugin windows the same way.
  property bool gestureBar: false
  readonly property int bottomInset: gestureBar && compact ? 20 : 0
  FileView {
    path: "/usr/share/omarchy/shell/plugins/mobile/gesture-bar/manifest.json"
    preload: true
    printErrors: false
    onLoaded: root.gestureBar = true
  }

  // The task table's columns, on a desktop.
  readonly property int colCpu: 76
  readonly property int colMem: 84
  readonly property int colCount: 58

  // ------------------------------------------------------------ pages

  readonly property var tabs: [
    { key: "overview", label: "Overview", glyph: G.overview },
    { key: "processor", label: "Processor", glyph: G.processor },
    { key: "memory", label: "Memory", glyph: G.memory },
    { key: "tasks", label: "Tasks", glyph: G.tasks },
    { key: "network", label: "Network", glyph: G.network }
  ]

  property string tab: "overview"
  property bool pinnedPage: false
  property string pinnedMode: ""
  // Pages over the current tab, on a phone: { kind: "detail", sel }.
  property var stack: []
  readonly property var page: stack.length ? stack[stack.length - 1] : null

  // What the task list's side pane shows on a desktop: { kind: "app", key }
  // or { kind: "process", pid }, or null.
  property var selection: null
  // Wide enough for the task list and a detail pane beside it.
  readonly property bool splitTasks: main.width >= 900

  function titleText() {
    if (tab === "settings") return "Settings"
    for (var i = 0; i < tabs.length; i++) if (tabs[i].key === tab) return tabs[i].label
    return "Vitals"
  }

  function setTab(key) {
    resetFocus()
    stack = []
    tab = key
    if (storeObj.tabs.indexOf(key) >= 0) storeObj.set("lastTab", key)
    // A page that names processes after one that did not: read now rather
    // than show last minute's table for a tick.
    if (key !== "network" && key !== "settings") Qt.callLater(root.collect)
  }

  function resetFocus() { keys.forceActiveFocus() }

  // An app or a process: beside the list when there is room, over it when
  // there is not.
  function openDetail(sel) {
    if (!sel) return
    resetFocus()
    if (tab === "tasks" && splitTasks) {
      selection = sel
    } else {
      var s = stack.slice()
      if (s.length > 5) s.splice(0, s.length - 5)
      s.push({ kind: "detail", sel: sel })
      stack = s
    }
    Qt.callLater(root.collect)
  }

  // One step out: the page, the selection, the tab, then nothing. True when
  // it stepped. On a phone the gesture bar calls this directly and hides the
  // panel itself when it answers false, so at the root it must not also close.
  function back() {
    resetFocus()
    if (confirm.item) { confirm.item = null; return true }
    if (stack.length) { var s = stack.slice(); s.pop(); stack = s; return true }
    if (tab === "tasks" && tasksView.query !== "") { tasksView.clearQuery(); return true }
    if (selection && tab === "tasks") { selection = null; return true }
    if (tab !== "overview") { setTab("overview"); return true }
    return false
  }

  // The detail shown right now, wherever it is.
  readonly property var shownSel: page && page.kind === "detail" ? page.sel
    : (tab === "tasks" && splitTasks ? selection : null)

  // ------------------------------------------------------------ the reading

  // The last reading, and the one before it that every rate is measured
  // against.
  property var sample: null
  property bool paused: false
  readonly property int interval: storeObj.prefs.interval || 2000

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
    cpuHistory = push(cpuHistory, next.cpu.total)
    memHistory = push(memHistory, next.memory.fraction)
    swapHistory = push(swapHistory, next.memory.swap_fraction)
    var nh = ({})
    for (var i = 0; i < next.interfaces.length; i++) {
      var f = next.interfaces[i]
      var was = netHistory[f.name] || { rx: [], tx: [] }
      nh[f.name] = { rx: push(was.rx, f.rx_rate), tx: push(was.tx, f.tx_rate) }
    }
    netHistory = nh
    if (reelDir !== "" && !reelEnded) frame += 1
    else if (reelDir === "") pickNow()
  }

  function push(series, value) {
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

  readonly property string subtitle: {
    if (!sample) return recorded ? "Reading a recorded machine…" : "Reading /proc…"
    var m = sample.machine
    var bits = []
    if (m.model) bits.push(m.model)
    else if (m.host) bits.push(m.host)
    bits.push("up " + Sysinfo.humanSeconds(sample.uptime))
    return bits.join(" · ")
  }

  // ------------------------------------------------------------ ending

  // What the confirmation sheet is asking about: { force, name, pids, what }.
  QtObject {
    id: confirm
    property var item: null
  }
  readonly property var confirming: confirm.item

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
    confirm.item = what
  }

  // Ending an app signals every process in it, lowest pid first. pid 1 is
  // refused outright: nothing an app of this shape wants to do is served by
  // signalling init, and in a container the kernel would not refuse it.
  function end(what) {
    confirm.item = null
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

  property string toastText: ""
  function toast(text) {
    toastText = text
    toastTimer.restart()
  }
  Timer {
    id: toastTimer
    interval: 2600
    onTriggered: root.toastText = ""
  }

  // ------------------------------------------------------------ host API

  function open(payloadJson) {
    theme.reload()
    opened = true
    window.visible = true
    Qt.callLater(function () { keys.forceActiveFocus() })
  }

  // From the host (`shell hide`, the keybinding). The window goes without
  // telling the host back: it already knows.
  property bool closingFromHost: false
  function close() {
    closingFromHost = true
    window.visible = false
    closingFromHost = false
    opened = false
  }

  function toggle() { opened ? close() : open("") }

  // Closing from inside -- the window manager -- goes through the host.
  // Dropping `opened` alone leaves the host counting the panel open, and the
  // next `shell toggle` would "hide" it and show nothing.
  function dismiss() {
    var id = manifest && manifest.id ? manifest.id : "org.moarchy.vitals"
    if (shell && typeof shell.hide === "function") shell.hide(id)
    else close()
  }

  // Closed, it forgets the machine: the next open starts a new history rather
  // than drawing a graph with a hole in it the length of the time it was shut.
  onOpenedChanged: {
    if (opened) return
    confirm.item = null
    stack = []
    sample = null
    cpuHistory = []
    memHistory = []
    swapHistory = []
    netHistory = ({})
    paused = false
  }

  // ------------------------------------------------------------ plumbing

  Store {
    id: storeObj
    onReadyChanged: {
      if (!ready) return
      if (!root.pinnedPage) root.tab = prefs.lastTab
      if (root.pinnedMode) set("taskMode", root.pinnedMode)
    }
  }

  LauncherEntry {
    id: launcherObj
    app: root
    pluginId: root.manifest && root.manifest.id ? root.manifest.id : "org.moarchy.vitals"
  }

  // The version, for the standalone app: the shell hands the manifest over,
  // shell.qml does not.
  property string ownVersion: ""
  readonly property string version: manifest && manifest.version ? manifest.version : ownVersion
  FileView {
    path: String(Qt.resolvedUrl("manifest.json")).replace(/^file:\/\//, "")
    preload: root.manifest === null
    printErrors: false
    onLoaded: {
      try { root.ownVersion = String(JSON.parse(text()).version || "").slice(0, 20) } catch (e) {}
    }
  }

  readonly property alias store: storeObj
  readonly property alias launcher: launcherObj

  // ------------------------------------------------------------ window

  // Shown and hidden by open() and close(), not bound to `opened`: the window
  // manager closes it too, and a binding would fight that.
  FloatingWindow {
    id: window
    visible: false
    title: "Vitals"
    color: root.ui.bg
    implicitWidth: 1240
    implicitHeight: 820
    minimumSize: Qt.size(360, 480)

    onVisibleChanged: if (!visible && !root.closingFromHost && root.opened) root.dismiss()

    Item {
      id: stage
      anchors.fill: parent

      Rectangle {
        anchors.fill: parent
        color: root.ui.bg
        clip: true

        // A plain Item and not a FocusScope: forceActiveFocus() on a scope
        // hands focus back to whatever inside it had it last -- the search
        // field -- and the phone's keyboard comes straight back up.
        Item {
          id: keys
          anchors.fill: parent
          focus: true

          Keys.onPressed: function (event) {
            var k = event.key
            if (k === Qt.Key_Escape || k === Qt.Key_Back) { root.back(); event.accepted = true; return }
            if (root.confirming) {
              if (k === Qt.Key_Return || k === Qt.Key_Enter) { root.end(root.confirming); event.accepted = true }
              return
            }
            if (root.tab === "tasks" && !root.page) {
              if (k === Qt.Key_Down) { tasksView.move(1); event.accepted = true; return }
              if (k === Qt.Key_Up) { tasksView.move(-1); event.accepted = true; return }
              if (k === Qt.Key_PageDown) { tasksView.move(8); event.accepted = true; return }
              if (k === Qt.Key_PageUp) { tasksView.move(-8); event.accepted = true; return }
              if (k === Qt.Key_Return || k === Qt.Key_Enter) { tasksView.activateCurrent(); event.accepted = true; return }
              if (k === Qt.Key_Delete) {
                root.askEnd(root.shownSel || tasksView.currentSel(), (event.modifiers & Qt.ShiftModifier) !== 0)
                event.accepted = true
                return
              }
            } else if (root.shownSel && k === Qt.Key_Delete) {
              root.askEnd(root.shownSel, (event.modifiers & Qt.ShiftModifier) !== 0)
              event.accepted = true
              return
            }
            if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
            if (k === Qt.Key_Space) { root.paused = !root.paused; event.accepted = true; return }
            if (event.text === "/") {
              root.setTab("tasks")
              Qt.callLater(tasksView.focusField)
              event.accepted = true
              return
            }
            if (event.text === "a" && root.tab === "tasks") { root.store.set("taskMode", root.store.prefs.taskMode === "apps" ? "all" : "apps"); event.accepted = true; return }
            if (event.text === "s" && root.tab === "tasks") {
              var order = ["cpu", "memory", "name"]
              root.store.set("taskSort", order[(order.indexOf(root.store.prefs.taskSort) + 1) % 3])
              event.accepted = true
              return
            }
            var n = "12345".indexOf(event.text)
            if (n >= 0 && event.text !== "") { root.setTab(root.tabs[n].key); event.accepted = true; return }
            if (event.text === ",") { root.setTab("settings"); event.accepted = true }
          }

          // Rail: desktop only.
          Rectangle {
            id: rail
            visible: !root.compact
            width: root.compact ? 0 : 216
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            color: root.ui.surface

            Column {
              id: railColumn
              anchors.fill: parent
              anchors.topMargin: 18
              anchors.leftMargin: 12
              anchors.rightMargin: 12
              spacing: 2

              Row {
                x: 6
                height: 44
                spacing: 10
                Mark { anchors.verticalCenter: parent.verticalCenter; size: 30 }
                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  Text {
                    text: "Vitals"
                    color: root.ui.text
                    font.family: root.ui.font
                    font.pixelSize: 19
                    font.weight: Font.Bold
                  }
                  Text {
                    text: root.sample && root.sample.machine.host ? root.sample.machine.host : "System monitor"
                    color: root.ui.muted
                    font.family: root.ui.font
                    font.pixelSize: root.ui.fs.xs
                    width: 150
                    elide: Text.ElideRight
                  }
                }
              }
              Item { width: 1; height: 14 }

              Repeater {
                model: root.tabs.concat([{ key: "settings", label: "Settings", glyph: G.settings }])
                delegate: Rectangle {
                  id: railItem
                  required property var modelData
                  required property int index
                  readonly property bool current: root.tab === modelData.key
                  width: parent.width
                  height: 40
                  radius: root.ui.radius
                  color: current ? root.ui.accentSoft : railMouse.containsMouse ? root.ui.hover : "transparent"
                  Row {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 8
                    spacing: 8
                    Icon { app: root; text: railItem.modelData.glyph; size: 18; color: railItem.current ? root.ui.accent : root.ui.text }
                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: railItem.modelData.label
                      color: railItem.current ? root.ui.accent : root.ui.text
                      font.family: root.ui.font
                      font.pixelSize: root.ui.fs.md
                      font.weight: railItem.current ? Font.DemiBold : Font.Normal
                    }
                  }
                  Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: railItem.index < root.tabs.length ? railItem.index + 1 : ","
                    color: root.ui.muted
                    font.family: root.ui.font
                    font.pixelSize: root.ui.fs.xs
                  }
                  Rectangle {
                    visible: railItem.index === root.tabs.length
                    y: -6
                    x: 8
                    width: parent.width - 16
                    height: 1
                    color: root.ui.divider
                  }
                  MouseArea {
                    id: railMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setTab(railItem.modelData.key)
                  }
                }
              }
            }

            // The machine at a glance, at the foot of the rail: on every
            // page, so the Tasks page still says how busy the processor is.
            Column {
              // Below the pages, when there is room for it: the rail's own column is
              // about 330 px.
              visible: root.sample !== null && rail.height >= 520
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 16
              x: 20
              width: parent.width - 40
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

          // Everything right of the rail (all of it, on a phone).
          Item {
            id: main
            anchors.left: rail.visible ? rail.right : parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: nav.visible ? nav.top : parent.bottom
            anchors.bottomMargin: nav.visible ? 0 : root.bottomInset

            Item {
              id: header
              width: parent.width
              height: root.compact ? 60 : 68

              IconButton {
                id: headerBack
                x: 4
                anchors.verticalCenter: parent.verticalCenter
                visible: root.compact && root.tab === "settings"
                width: visible ? implicitWidth : 0
                app: root
                glyph: G.back
                label: "Back"
                onClicked: root.back()
              }
              Row {
                anchors.left: headerBack.visible ? headerBack.right : parent.left
                anchors.leftMargin: headerBack.visible ? 4 : (root.compact ? 16 : 26)
                anchors.right: headerActions.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Mark {
                  visible: root.compact && root.tab === "overview"
                  anchors.verticalCenter: parent.verticalCenter
                  size: 30
                }
                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - (root.compact && root.tab === "overview" ? 40 : 0)
                  Text {
                    width: parent.width
                    text: root.compact && root.tab === "overview" ? "Vitals" : root.titleText()
                    color: root.ui.text
                    font.family: root.ui.font
                    font.pixelSize: root.compact ? 21 : 24
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width
                    visible: root.tab !== "settings"
                    text: root.subtitle
                    color: root.ui.muted
                    font.family: root.ui.font
                    font.pixelSize: root.ui.fs.xs
                    elide: Text.ElideRight
                  }
                }
              }
              Row {
                id: headerActions
                anchors.right: parent.right
                anchors.rightMargin: root.compact ? 4 : 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                IconButton {
                  visible: root.tab !== "settings"
                  app: root
                  glyph: root.paused ? G.play : G.pause
                  label: root.paused ? "Resume" : "Pause"
                  active: root.paused
                  onClicked: root.paused = !root.paused
                }
                IconButton {
                  visible: root.compact && root.tab !== "settings"
                  app: root
                  glyph: G.settings
                  label: "Settings"
                  onClicked: root.setTab("settings")
                }
              }
            }

            Item {
              id: views
              anchors.top: header.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom

              OverviewView { anchors.fill: parent; app: root; visible: root.tab === "overview" }
              ProcessorView { anchors.fill: parent; app: root; visible: root.tab === "processor" }
              MemoryView { anchors.fill: parent; app: root; visible: root.tab === "memory" }
              TasksView { id: tasksView; anchors.fill: parent; app: root; visible: root.tab === "tasks" }
              NetworkView { anchors.fill: parent; app: root; visible: root.tab === "network" }
              SettingsView { anchors.fill: parent; app: root; visible: root.tab === "settings" }

              // Before the first reading: something rather than nothing.
              Column {
                anchors.centerIn: parent
                visible: root.sample === null && root.tab !== "settings"
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
          }

          // A detail page over the whole of the main side, header included.
          Loader {
            id: pageLoader
            z: 3
            active: root.page !== null
            anchors.left: main.left
            anchors.right: main.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            sourceComponent: Rectangle {
              color: root.ui.bg
              MouseArea { anchors.fill: parent }
              DetailView {
                anchors.fill: parent
                anchors.bottomMargin: root.bottomInset
                app: root
                sel: root.page ? root.page.sel : null
                paged: true
              }
            }
          }

          // Tabs: phone only, and not under a page.
          Rectangle {
            id: nav
            z: 4
            visible: root.compact && root.page === null
            anchors.bottom: parent.bottom
            width: parent.width
            height: visible ? 64 + root.bottomInset : 0
            color: root.ui.surface

            Rectangle { width: parent.width; height: 1; color: root.ui.divider }

            Row {
              width: parent.width
              height: 64
              Repeater {
                model: root.tabs
                delegate: Item {
                  id: navItem
                  required property var modelData
                  readonly property bool current: root.tab === modelData.key
                  width: nav.width / root.tabs.length
                  height: 64
                  Accessible.role: Accessible.PageTab
                  Accessible.name: modelData.label

                  Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 8
                    width: 56
                    height: 30
                    radius: 15
                    color: navItem.current ? root.ui.accentSoft : navMouse.pressed ? root.ui.pressed : "transparent"
                  }
                  Icon {
                    app: root
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 8
                    height: 30
                    text: navItem.modelData.glyph
                    size: 20
                    color: navItem.current ? root.ui.accent : root.ui.muted
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 41
                    text: navItem.modelData.label
                    color: navItem.current ? root.ui.text : root.ui.muted
                    font.family: root.ui.font
                    font.pixelSize: root.ui.fs.xs
                    font.weight: navItem.current ? Font.DemiBold : Font.Normal
                  }
                  MouseArea {
                    id: navMouse
                    anchors.fill: parent
                    onClicked: root.setTab(navItem.modelData.key)
                  }
                }
              }
            }
          }

          // Ending something: asked first, in words that say which signal.
          Rectangle {
            id: scrim
            z: 10
            anchors.fill: parent
            color: root.alpha("#000000", 0.45)
            visible: root.confirming !== null
            MouseArea { anchors.fill: parent; onClicked: root.back() }
          }
          Rectangle {
            id: sheet
            z: 11
            visible: root.confirming !== null
            readonly property var what: root.confirming || ({ force: false, name: "", pids: [], app: false })
            width: root.compact ? parent.width : Math.min(440, parent.width - 48)
            height: sheetCol.implicitHeight + 44
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.compact ? parent.height - height : (parent.height - height) / 2
            radius: root.ui.radius + 6
            color: root.ui.bg
            border.width: 1
            border.color: root.ui.border
            MouseArea { anchors.fill: parent }

            Column {
              id: sheetCol
              x: 22
              y: 22
              width: parent.width - 44
              spacing: 14
              Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: (sheet.what.force ? "Force stop " : "End ") + sheet.what.name + "?"
                color: root.ui.text
                font.family: root.ui.font
                font.pixelSize: root.ui.fs.lg + 2
                font.weight: Font.Bold
              }
              Text {
                width: parent.width
                wrapMode: Text.Wrap
                lineHeight: 1.15
                text: (sheet.what.app && sheet.what.pids.length > 1
                        ? "All " + sheet.what.pids.length + " of its processes are signalled. "
                        : "")
                      + (sheet.what.force
                         ? "It is stopped immediately, mid-write: anything it had not saved is lost."
                         : "It is asked to stop, and can save what it was doing first.")
                color: root.ui.muted
                font.family: root.ui.font
                font.pixelSize: root.ui.fs.sm
              }
              Row {
                anchors.right: parent.right
                spacing: 10
                Button { app: root; text: "Cancel"; onClicked: root.back() }
                Button {
                  app: root
                  primary: true
                  tint: root.ui.bad
                  glyph: sheet.what.force ? G.kill : G.stop
                  text: sheet.what.force ? "Force stop" : "End task"
                  onClicked: root.end(root.confirming)
                }
              }
              Item { width: 1; height: root.compact ? 8 + root.bottomInset : 0 }
            }
          }

          // A short word about what just happened.
          Rectangle {
            id: toastBox
            z: 20
            anchors.horizontalCenter: main.horizontalCenter
            anchors.bottom: main.bottom
            anchors.bottomMargin: 16
            width: Math.min(toastLabel.implicitWidth + 36, main.width - 32)
            height: 40
            radius: 20
            color: root.ui.dark ? "#f2f2f2" : "#1f1f1f"
            opacity: root.toastText !== "" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Text {
              id: toastLabel
              anchors.centerIn: parent
              width: Math.min(implicitWidth, parent.width - 24)
              text: root.toastText
              color: root.ui.dark ? "#111111" : "#f5f5f5"
              font.family: root.ui.font
              font.pixelSize: root.ui.fs.sm
              font.weight: Font.DemiBold
              elide: Text.ElideRight
            }
          }
        }
      }
    }
  }
}
