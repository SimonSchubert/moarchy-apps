import QtQuick
import Quickshell
import Quickshell.Io
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G
import "Path.js" as Path
import "Listing.js" as Listing
import "Ops.js" as Ops
import "Places.js" as Places
import "Store.js" as View

// Files: one directory at a time.
//
//     omarchy-shell shell toggle org.moarchy.files
//     moarchy-files ~/Downloads
//
// Everything that touches the disk is a short shell script with the paths
// passed in as arguments: Listing.js reads a directory, Ops.js changes one,
// Places.js finds the places worth a tap. None of the decisions are in those
// scripts. Which trash a file goes to, whether a folder may be pasted inside
// itself, and what a usable name is are functions with tests, because those
// are the three ways a file manager loses somebody's afternoon.
//
// Nothing here runs until the window is on the screen: the shell builds this
// Item during its own startup, so no directory is read before open(), and the
// list's model is empty while the window is shut.
//
// A phone gets the list with the places as a second tab, and a menu behind
// each row. A desktop gets the places beside the list, the size and the date
// in columns, and the picked file in a pane with every action as a button.
App {
  id: root

  appId: "org.moarchy.files"
  title: "Files"
  heading: headingText()
  subtitle: subtitleText()
  windowWidth: 1180
  windowHeight: 780

  store: Store { name: "moarchy-files" }

  launcher.desktopId: "org.moarchy.Files"
  launcher.genericName: "File manager"
  launcher.comment: "One folder at a time"
  launcher.categories: "Utility;Core;FileTools;FileManager;"
  launcher.keywords: "files;file;folder;browse;manager;storage;card;sd;trash;copy;move;rename;"

  mark: Component { Image { source: root.appDir + "/icon.svg"; sourceSize: Qt.size(60, 60) } }

  // The places are a tab only where there is no room for them beside the list.
  tabs: compact ? [
    { key: "files", label: "Files", glyph: G.files },
    { key: "places", label: "Places", glyph: G.places }
  ] : []
  readonly property bool onPlaces: compact && tab === "places"

  actions: Component {
    Row {
      spacing: 2
      IconButton {
        // Not inside home on a phone: the header has room for three, and the
        // crumb strip and the back gesture both go up from there.
        visible: !root.onPlaces && !Path.isRoot(root.path) && !(root.compact && Path.isUnder(root.path, root.home))
        app: root
        glyph: G.up
        label: "Up one folder"
        onClicked: root.up()
      }
      IconButton {
        visible: root.compact && !root.onPlaces
        app: root
        glyph: KG.search
        label: "Search this folder"
        active: root.searching
        onClicked: {
          root.searching = !root.searching
          if (!root.searching) root.query = ""
          else Qt.callLater(function () { phoneSearch.input.forceActiveFocus() })
        }
      }
      IconButton {
        visible: !root.compact
        app: root
        glyph: G.newFolder
        label: "New folder"
        onClicked: root.askNewFolder()
      }
      IconButton {
        visible: !root.compact
        app: root
        glyph: root.hidden ? G.hidden : G.hiddenOff
        label: root.hidden ? "Hide hidden files" : "Show hidden files"
        active: root.hidden
        onClicked: root.setHidden(!root.hidden)
      }
      IconButton {
        visible: root.compact
        app: root
        glyph: root.onPlaces ? KG.refresh : G.more
        label: root.onPlaces ? "Look again" : "More"
        onClicked: root.onPlaces ? root.probePlaces() : viewSheet.open()
      }
    }
  }

  settings: Component {
    SettingsPage {
      app: root
      blurb: "One folder at a time, and a delete that goes to the trash every other app can read."
      SettingsSection {
        app: root
        width: parent.width
        title: "Order"
        note: "Folders always come first. Names go up, sizes and dates go down: nobody opens a file manager to find the smallest file."
        Row {
          spacing: 8
          Repeater {
            model: View.SORTS
            delegate: Chip {
              required property string modelData
              app: root
              text: View.SORT_LABELS[modelData]
              selected: root.sort === modelData
              onClicked: root.setSort(modelData)
            }
          }
        }
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Hidden files"
        Toggle {
          app: root
          width: parent.width
          text: "Show files whose names start with a dot"
          checked: root.hidden
          onToggled: function (on) { root.setHidden(on) }
        }
      }
      AppearanceSection { app: root }
      LauncherSection { app: root }
      KeysSection {
        app: root
        keys: [
          ["↑ ↓  Enter", "Pick a row, open it"],
          ["Backspace", "Up one folder (also Alt+←)"],
          ["F2", "Rename"],
          ["Delete", "Move to the trash (asks, in the trash)"],
          ["Ctrl+C  X  V", "Copy, move, paste here"],
          ["/", "Find in this folder"],
          ["h", "Show or hide hidden files"],
          ["n", "New folder"],
          ["~", "Home"],
          [",", "Settings"],
          ["Esc", "Back one step"]
        ]
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "What it keeps"
        note: "~/.local/share/moarchy-files/view.json: the order, whether hidden files show, and the folder that was open. The trash is the one every other app reads, ~/.local/share/Trash, or the volume's own for a file on a card."
      }
    }
  }

  // ------------------------------------------------------------ where we are

  // The real home is where the trash is and where user-dirs.dirs lives.
  // MOARCHY_FILES_HOME is the harness's: a made-up tree for the screenshots.
  readonly property string realHome: Quickshell.env("HOME") || "/"
  readonly property string home: Quickshell.env("MOARCHY_FILES_HOME") || realHome
  readonly property string xdgData: Quickshell.env("XDG_DATA_HOME") || ""
  readonly property string trashDir: Path.join(
    xdgData.length ? Path.clean(xdgData) : Path.join(Path.clean(realHome), ".local/share"), "Trash")

  property string path: ""
  property var entries: []
  property bool listing: false
  property bool relist: false
  property string trouble: ""
  property bool loaded: false

  // "Yesterday" and "Tue" are answers about the clock. MOARCHY_FILES_NOW pins
  // the clock the list is read against, and dev/demo.py dates the fixture
  // from the same number.
  readonly property double pinnedNow: 1000 * parseFloat(Quickshell.env("MOARCHY_FILES_NOW") || "0")
  property double now: Date.now()

  property string query: ""
  property bool searching: false
  property string sort: "name"
  property bool hidden: false

  // What is waiting to be pasted: { kind: "copy" | "move", path, name }. One
  // thing rather than a selection: copy, walk somewhere, paste.
  property var holding: null
  // The row the menu is about, and the row picked on a desktop.
  property var menuFor: null
  property string picked: ""

  readonly property var shown: Listing.arrange(entries, sort, hidden, query)
  readonly property var crumbs: Path.crumbs(path, home)
  property var userDirs: ({})
  property var probe: null
  readonly property var placeRows: Places.rows(home, userDirs, probe, trashDir)
  readonly property bool inTrash: path.length > 0 && Path.isUnder(path, Path.join(trashDir, "files"))
  readonly property var pickedEntry: {
    if (!picked) return null
    for (var i = 0; i < shown.length; i++) if (shown[i].name === picked) return shown[i]
    return null
  }
  readonly property bool hasPane: !compact && contentArea.width >= 900 && pickedEntry !== null

  function headingText() {
    if (onPlaces) return "Places"
    if (!path.length) return "Files"
    if (path === home) return "Home"
    if (Path.isRoot(path)) return "Filesystem"
    return Path.base(path)
  }

  function subtitleText() {
    if (onPlaces) return "Where things are"
    if (trouble.length) return trouble
    if (listing && !entries.length) return "Reading…"
    if (query.length) return shown.length + (shown.length === 1 ? " match" : " matches")
    var line = Listing.summary(entries)
    if (hidden) line += " · hidden shown"
    return line
  }

  // ------------------------------------------------------------ opening

  onSummoned: function (payload) {
    root.now = root.pinnedNow > 0 ? root.pinnedNow : Date.now()
    if (payload && payload.path) {
      var wanted = Path.clean(String(payload.path))
      if (root.loaded) root.go(wanted)
      else root.path = wanted
    }
    Qt.callLater(root.ensureLoaded)
    if (root.onPlaces) root.probePlaces()
  }

  // The folder is written down when the window goes, which on a phone is the
  // event before the app is reclaimed. Not on every step: that would be a
  // write onto flash per tap.
  onOpenedChanged: if (!opened) {
    saveView()
    menuFor = null
  }
  onQuitting: saveView()

  // The first directory is read here and nowhere earlier. MOARCHY_FILES_PATH
  // beats the folder from open(), which beats the remembered one, which beats
  // home.
  function ensureLoaded() {
    if (loaded) return
    loaded = true
    var forced = Quickshell.env("MOARCHY_FILES_PATH") || ""
    if (forced.length) go(forced)
    else if (path.length) list()
    else go(home)
    // Asked for before the window has its width: the tab is set anyway, and
    // is only a page of its own once the window turns out to be a phone's.
    if (wantPlaces) {
      wantPlaces = false
      setTab("places")
      probePlaces()
    }
  }

  onTabSelected: function (key) { if (key === "places") root.probePlaces() }
  onCompactChanged: if (!compact) probePlaces()

  // ------------------------------------------------------------ walking

  function go(target) {
    var next = Path.clean(target)
    query = ""
    searching = false
    trouble = ""
    picked = ""
    if (compact && tab !== "files" && tabs.length) setTab("files")
    if (next !== path) {
      path = next
      entries = []
      browse.positionViewAtBeginning()
    }
    list()
  }

  function up() {
    if (Path.isRoot(path)) return
    var from = Path.base(path)
    go(Path.parent(path))
    // Back up a level, the folder just left is the one picked.
    if (!compact) picked = from
  }

  function list() {
    if (!loaded) return
    // A tap that arrives while a directory is still being read is remembered
    // and run once the read is back. Dropping it is how a second tap on a
    // folder appears to do nothing on a slow card.
    if (lister.running) { relist = true; return }
    listing = true
    now = pinnedNow > 0 ? pinnedNow : Date.now()
    lister.command = Listing.command(path)
    lister.running = true
  }

  function listed(code, blob) {
    listing = false
    if (relist) { relist = false; Qt.callLater(list); return }
    if (code === Listing.OK) {
      trouble = ""
      entries = Listing.parse(blob)
      staged()
      return
    }
    entries = []
    trouble = Listing.trouble(code)
    // A folder that is gone is the ordinary case after a card has been pulled,
    // and the useful answer is to be somewhere. A folder that is merely not
    // ours to read stays on screen with its reason on it.
    if (code !== Listing.UNREADABLE && path !== home) {
      toast(trouble)
      go(home)
    }
  }

  function find(name) {
    for (var i = 0; i < entries.length; i++) if (entries[i].name === name) return entries[i]
    return null
  }

  function enter(entry) {
    if (!entry) return
    var target = Path.join(path, entry.name)
    if (entry.broken) { toast("That link points at something that is not there."); return }
    if (entry.folder) { go(target); return }
    if (opener.running) return
    toast("Opening " + entry.name + "…")
    opener.command = Ops.openCommand(target)
    opener.running = true
  }

  // ------------------------------------------------------------ changing things

  function run(job, what, command) {
    worker.job = job
    worker.subject = what
    worker.command = command
    worker.running = true
  }

  function busyText() {
    if (!worker.running) return ""
    if (worker.job === "place") return worker.subject && worker.subject.kind === "move" ? "Moving…" : "Copying…"
    if (worker.job === "trash-tops" || worker.job === "trash-move" || worker.job === "purge") return "Deleting…"
    return "Working…"
  }

  function hold(kind, entry) {
    if (!entry) return
    holding = { kind: kind, path: Path.join(path, entry.name), name: entry.name }
    toast(kind === "move" ? "Ready to move. Open a folder and paste." : "Ready to copy. Open a folder and paste.")
  }

  function paste() {
    if (!holding || worker.running) return
    var problem = Ops.pasteProblem(holding.kind, holding.path, path)
    if (problem.length) { toast(problem); return }
    run("place", { kind: holding.kind, name: holding.name }, Ops.place(holding.kind, holding.path, path))
  }

  // Delete, which here means the trash -- except inside the trash, where it
  // means gone and is the one thing here that asks first.
  function remove(entry) {
    if (!entry || worker.running) return
    var target = Path.join(path, entry.name)
    var trashed = Ops.trashedName(target, trashDir)
    if (trashed.length) {
      purgeDialog.open({ path: target, name: entry.name, trashed: trashed })
      return
    }
    var problem = Ops.trashProblem(target, home)
    if (problem.length) { toast(problem); return }
    run("trash-tops", { path: target, name: entry.name }, Ops.tops(target, realHome))
  }

  function finished(code, text) {
    var job = worker.job
    var what = worker.subject
    worker.job = ""

    if (job === "trash-tops") {
      var plan = Ops.trashPlan(what.path, realHome, xdgData, Ops.parseTops(text))
      if (code !== 0 || plan.problem) {
        toast(plan.problem || "Could not work out which volume that is on.")
        return
      }
      // Later rather than from inside this handler: the process that just
      // exited is the one being asked to run again.
      Qt.callLater(function () { root.run("trash-move", what, Ops.trashCommand(plan.dir, what.path, plan.line)) })
      return
    }
    if (job === "trash-move") {
      if (code !== 0) toast(Ops.trashTrouble(code))
      else toast("Moved " + what.name + " to the trash.")
      if (picked === what.name) picked = ""
      list()
      return
    }
    if (job === "purge") {
      toast(code !== 0 ? "That could not be deleted." : "Deleted " + what.name + ".")
      if (picked === what.name) picked = ""
      list()
      return
    }
    if (job === "place") {
      if (code !== 0) { toast(Ops.why(code, "That")); return }
      toast((what.kind === "move" ? "Moved " : "Copied ") + what.name + " here.")
      holding = null
      picked = what.name
      list()
      return
    }
    if (job === "mkdir") {
      if (code !== 0) { toast(Ops.why(code, "The folder")); return }
      picked = what.name
      list()
      return
    }
    if (job === "rename") {
      if (code !== 0) { toast(Ops.why(code, "The rename")); return }
      picked = what.name
      list()
    }
  }

  function askNewFolder() {
    nameDialog.kind = "folder"
    nameDialog.open(null)
    nameField.text = ""
    Qt.callLater(function () { nameField.takeFocus() })
  }

  function askRename(entry) {
    if (!entry) return
    nameDialog.kind = "rename"
    nameDialog.open({ path: Path.join(path, entry.name), name: entry.name })
    nameField.text = entry.name
    Qt.callLater(function () { nameField.takeFocus() })
  }

  function confirmName() {
    var name = nameField.text
    var problem = Ops.nameProblem(name)
    if (problem.length) { toast(problem); return false }
    if (nameDialog.kind === "folder") {
      run("mkdir", { name: name }, Ops.makeDir(path, name))
    } else {
      var what = nameDialog.subject
      if (name !== what.name) run("rename", { name: name }, Ops.rename(path, what.name, name))
    }
    return true
  }

  // ------------------------------------------------------------ places

  function probePlaces() {
    if (prober.running || !opened) return
    var paths = Places.candidates(home)
    var wanted = Places.wanted(home, userDirs)
    for (var i = 0; i < wanted.length; i++)
      if (paths.indexOf(wanted[i].path) < 0) paths.push(wanted[i].path)
    prober.command = Places.command(paths)
    prober.running = true
  }

  // ------------------------------------------------------------ remembered

  function saveView() {
    if (!loaded) return
    viewFile.save(View.serialize(sort, hidden, path))
  }
  function setSort(which) {
    if (sort === which) return
    sort = which
    saveView()
  }
  function setHidden(on) {
    if (hidden === on) return
    hidden = on
    saveView()
  }

  // ------------------------------------------------------------ the keyboard

  // Before the tabs: the search, then the pick.
  stepBack: function () {
    if (searching || query.length) { searching = false; query = ""; return true }
    if (onPlaces) return false
    if (picked && !compact) { picked = ""; return true }
    if (path !== home && !Path.isRoot(path) && Path.isUnder(path, home)) { up(); return true }
    return false
  }

  function move(step) {
    if (!shown.length) return
    var at = -1
    for (var i = 0; i < shown.length; i++) if (shown[i].name === picked) { at = i; break }
    var next = at < 0 ? (step > 0 ? 0 : shown.length - 1) : Math.max(0, Math.min(shown.length - 1, at + step))
    picked = shown[next].name
    browse.positionViewAtIndex(next, ListView.Contain)
  }

  keyHandler: function (event) {
    if (onPlaces || inSettings) return
    var k = event.key
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var alt = (event.modifiers & Qt.AltModifier) !== 0
    if (k === Qt.Key_Down) { move(1); event.accepted = true; return }
    if (k === Qt.Key_Up && !alt) { move(-1); event.accepted = true; return }
    if (k === Qt.Key_PageDown) { move(10); event.accepted = true; return }
    if (k === Qt.Key_PageUp) { move(-10); event.accepted = true; return }
    if (k === Qt.Key_Home && !ctrl) { if (shown.length) { picked = shown[0].name; browse.positionViewAtBeginning() } event.accepted = true; return }
    if (k === Qt.Key_End) { move(shown.length); event.accepted = true; return }
    if (k === Qt.Key_Return || k === Qt.Key_Enter) { enter(pickedEntry); event.accepted = true; return }
    if (k === Qt.Key_Backspace || (alt && (k === Qt.Key_Left || k === Qt.Key_Up))) { up(); event.accepted = true; return }
    if (k === Qt.Key_F2) { askRename(pickedEntry); event.accepted = true; return }
    if (k === Qt.Key_F5) { list(); event.accepted = true; return }
    if (k === Qt.Key_Delete) { remove(pickedEntry); event.accepted = true; return }
    if (ctrl && k === Qt.Key_C) { hold("copy", pickedEntry); event.accepted = true; return }
    if (ctrl && k === Qt.Key_X) { hold("move", pickedEntry); event.accepted = true; return }
    if (ctrl && k === Qt.Key_V) { paste(); event.accepted = true; return }
    if (ctrl && k === Qt.Key_H) { setHidden(!hidden); event.accepted = true; return }
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    if (event.text === "/") {
      searching = true
      Qt.callLater(function () { (root.compact ? phoneSearch : deskSearch).input.forceActiveFocus() })
      event.accepted = true
      return
    }
    if (event.text === "h") { setHidden(!hidden); event.accepted = true; return }
    if (event.text === "n") { askNewFolder(); event.accepted = true; return }
    if (event.text === "~") { go(home); event.accepted = true }
  }

  // ------------------------------------------------------------ the harness

  // States somebody has to be *in* to be photographed, applied after the first
  // listing because each names a row that has to exist.
  property bool wantPlaces: false
  property string wantMenu: ""
  property string wantHolding: ""
  property string wantPick: ""

  Component.onCompleted: {
    wantPlaces = (Quickshell.env("MOARCHY_FILES_PAGE") || "") === "places"
    wantMenu = Quickshell.env("MOARCHY_FILES_MENU") || ""
    wantHolding = Quickshell.env("MOARCHY_FILES_HOLDING") || ""
    wantPick = Quickshell.env("MOARCHY_FILES_PICK") || ""
  }

  function staged() {
    if (wantMenu.length) {
      var menu = wantMenu
      wantMenu = ""
      if (menu === "view") viewSheet.open()
      else { menuFor = find(menu); if (menuFor) rowSheet.open() }
    }
    if (wantHolding.length) {
      var held = find(wantHolding)
      wantHolding = ""
      if (held) holding = { kind: "copy", name: held.name, path: Path.join(path, held.name) }
    }
    if (wantPick.length) { picked = wantPick; wantPick = "" }
  }

  // ------------------------------------------------------------ plumbing

  Process {
    id: lister
    running: false
    stdout: StdioCollector { id: listOut; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { root.listed(code, listOut.text) }
    // qmllint enable signal-handler-parameters
  }

  Process {
    id: worker
    property string job: ""
    property var subject: null
    running: false
    stdout: StdioCollector { id: workOut; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { root.finished(code, workOut.text) }
    // qmllint enable signal-handler-parameters
  }

  Process {
    id: prober
    running: false
    stdout: StdioCollector { id: probeOut; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { if (code === 0) root.probe = Places.parseProbe(probeOut.text) }
    // qmllint enable signal-handler-parameters
  }

  Process {
    id: opener
    running: false
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { if (code !== 0) root.toast(Ops.openTrouble(code)) }
    // qmllint enable signal-handler-parameters
  }

  // Read once and then followed, so a phone whose language changes offers
  // "Bilder" the next time it is opened.
  FileView {
    id: userDirsFile
    path: Path.join(root.home, ".config/user-dirs.dirs")
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.userDirs = Places.parseUserDirs(text(), root.home)
      if (root.opened) root.probePlaces()
    }
    onFileChanged: Qt.callLater(function () { userDirsFile.reload() })
  }

  DataFile {
    id: viewFile
    app: "files"
    name: "view.json"
    onParsed: function (data) {
      var state = View.parse(data)
      root.sort = state.sort
      root.hidden = state.hidden
      // The folder is taken only before the app has opened. After that, a
      // change to this file is somebody's editor or a sync, and being carried
      // to another directory mid-scroll is not a feature.
      if (!root.loaded && !root.path.length && state.path.length) root.path = state.path
    }
    onQuarantined: function (movedTo) { root.toast("view.json would not parse; it is at " + Path.base(movedTo) + ".") }
  }

  IpcHandler {
    target: "files"
    function cd(where: string): string { root.go(where); return root.path }
    function here(): string { return root.path }
    function pick(name: string): string { root.picked = name; return root.pickedEntry ? "ok" : "not here" }
    function copy(): string { root.hold("copy", root.pickedEntry); return root.holding ? root.holding.name : "" }
    function paste(): string { root.paste(); return "ok" }
    function trash(): string { root.remove(root.pickedEntry); return "ok" }
    function mkdir(name: string): string {
      var problem = Ops.nameProblem(name)
      if (problem.length) return problem
      root.run("mkdir", { name: name }, Ops.makeDir(root.path, name))
      return "ok"
    }
    function close(): string { root.dismiss(); return "ok" }
    function names(): string { return root.shown.map(function (e) { return e.name }).join("\n") }
    // What a script waits for: a directory read and nothing in flight.
    function settled(): bool { return root.loaded && !lister.running && !worker.running }
  }

  // ------------------------------------------------------------ sheets

  ActionSheet {
    id: rowSheet
    app: root
    title: root.menuFor ? root.menuFor.name : ""
    actions: {
      var e = root.menuFor
      if (!e) return []
      return [
        { glyph: e.folder ? G.folder : G.open, text: e.folder ? "Open folder" : "Open", run: function () { root.enter(e) } },
        { glyph: G.copy, text: "Copy", run: function () { root.hold("copy", e) } },
        { glyph: G.cut, text: "Move", run: function () { root.hold("move", e) } },
        { glyph: G.rename, text: "Rename", run: function () { root.askRename(e) } },
        // The word changes because the act does: everywhere else the trash is
        // the undo; in the trash there is nothing under it.
        { glyph: root.inTrash ? G.purge : G.trash, text: root.inTrash ? "Delete for ever" : "Move to trash",
          destructive: true, run: function () { root.remove(e) } }
      ]
    }
  }

  ActionSheet {
    id: viewSheet
    app: root
    title: "This folder"
    actions: [
      { glyph: G.newFolder, text: "New folder", run: function () { root.askNewFolder() } },
      { glyph: KG.sort, text: "By name", current: root.sort === "name", run: function () { root.setSort("name") } },
      { glyph: KG.sort, text: "By size", current: root.sort === "size", run: function () { root.setSort("size") } },
      { glyph: KG.sort, text: "By date", current: root.sort === "modified", run: function () { root.setSort("modified") } },
      { glyph: root.hidden ? G.hiddenOff : G.hidden, text: root.hidden ? "Hide hidden files" : "Show hidden files",
        run: function () { root.setHidden(!root.hidden) } }
    ]
  }

  Dialog {
    id: nameDialog
    app: root
    property string kind: "folder"
    title: kind === "folder" ? "New folder" : "Rename"
    acceptText: kind === "folder" ? "Make it" : "Rename"
    canAccept: nameField.text.length > 0
    onAccepted: if (!root.confirmName()) Qt.callLater(function () { nameDialog.open() })
    TextField {
      id: nameField
      app: root
      width: parent.width
      placeholder: "Name"
      inputHints: Qt.ImhNoPredictiveText
      onAccepted: nameDialog.accept()
    }
  }

  Dialog {
    id: purgeDialog
    app: root
    title: "Delete for ever?"
    text: subject ? "“" + subject.name + "” is in the trash. There is nothing under the trash: this cannot be undone." : ""
    acceptText: "Delete"
    acceptGlyph: G.purge
    destructive: true
    onAccepted: root.run("purge", subject, Ops.purge(subject.path, root.trashDir, subject.trashed))
  }

  // ------------------------------------------------------------ the screen

  // The places, beside everything on a desktop.
  Rectangle {
    id: side
    visible: !root.compact
    width: visible ? 220 : 0
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.leftMargin: root.compact ? 0 : 16
    anchors.bottomMargin: 16
    radius: root.ui.radius + 4
    color: root.ui.surface
    border.width: 1
    border.color: root.ui.divider
    Text {
      id: sideTitle
      x: 18
      y: 14
      text: "Places"
      color: root.ui.muted
      font.family: root.ui.font
      font.pixelSize: root.ui.fs.sm
      font.weight: Font.DemiBold
    }
    PlacesList {
      anchors.top: sideTitle.bottom
      anchors.topMargin: 4
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      app: root
      rows: root.opened ? root.placeRows : []
      current: root.path
      onGo: function (where) { root.go(where) }
    }
  }

  // The list, and what sits over it.
  Item {
    id: browseArea
    visible: !root.onPlaces
    anchors.left: side.right
    anchors.leftMargin: root.compact ? 0 : 16
    anchors.right: pane.visible ? pane.left : parent.right
    anchors.rightMargin: root.compact ? 0 : 16
    anchors.top: parent.top
    anchors.bottom: parent.bottom

    Column {
      id: tops
      x: root.compact ? root.ui.gutter : 0
      width: parent.width - x * 2
      spacing: 8

      Row {
        width: parent.width
        spacing: 10
        Crumbs {
          width: parent.width - (deskSearch.visible ? deskSearch.width + 10 : 0)
          app: root
          crumbs: root.crumbs
          onGo: function (where) { root.go(where) }
        }
        SearchField {
          id: deskSearch
          visible: !root.compact
          width: 240
          app: root
          placeholder: "Find in this folder"
          text: root.query
          onTextChanged: root.query = text
          onEscaped: { root.query = ""; root.resetFocus() }
        }
      }

      SearchField {
        id: phoneSearch
        visible: root.compact && root.searching
        width: parent.width
        app: root
        placeholder: "Name, in this folder"
        text: root.query
        onTextChanged: root.query = text
        onEscaped: { root.searching = false; root.query = ""; root.resetFocus() }
      }

      // What is waiting to be pasted.
      Rectangle {
        visible: root.holding !== null
        width: parent.width
        height: 52
        radius: root.ui.radius + 2
        color: root.ui.accentSoft
        border.width: 1
        border.color: root.ui.alpha(root.ui.accent, 0.4)
        Icon {
          id: holdGlyph
          app: root
          x: 10
          anchors.verticalCenter: parent.verticalCenter
          text: root.holding && root.holding.kind === "move" ? G.cut : G.copy
          size: 18
          color: root.ui.accent
        }
        Text {
          anchors.left: holdGlyph.right
          anchors.leftMargin: 6
          anchors.right: holdActions.left
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          text: root.holding ? (root.holding.kind === "move" ? "Move " : "Copy ") + root.holding.name : ""
          color: root.ui.text
          font.family: root.ui.font
          font.pixelSize: root.ui.fs.sm
          elide: Text.ElideMiddle
        }
        Row {
          id: holdActions
          anchors.right: parent.right
          anchors.rightMargin: 4
          anchors.verticalCenter: parent.verticalCenter
          spacing: 2
          Button {
            anchors.verticalCenter: parent.verticalCenter
            app: root
            primary: true
            glyph: G.paste
            text: root.busyText().length ? root.busyText() : "Paste here"
            onClicked: root.paste()
          }
          IconButton {
            anchors.verticalCenter: parent.verticalCenter
            app: root
            glyph: KG.close
            size: 16
            label: "Forget it"
            onClicked: root.holding = null
          }
        }
      }

      // The columns' names, which are the sort on a desktop.
      Item {
        visible: !root.compact && root.shown.length > 0
        width: parent.width
        height: 26
        Repeater {
          model: [
            { key: "name", label: "Name", x: 38, w: 200, right: false },
            { key: "size", label: "Size", x: -1, w: 96, right: true },
            { key: "modified", label: "Modified", x: -2, w: 120, right: true }
          ]
          delegate: Text {
            id: colHead
            required property var modelData
            x: modelData.x >= 0 ? modelData.x : modelData.x === -1 ? parent.width - 12 - 120 - 96 : parent.width - 12 - 120
            width: modelData.w
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: modelData.right ? Text.AlignRight : Text.AlignLeft
            text: modelData.label + (root.sort === modelData.key ? (modelData.key === "name" ? "  ↑" : "  ↓") : "")
            color: root.sort === modelData.key ? root.ui.text : root.ui.muted
            font.family: root.ui.font
            font.pixelSize: root.ui.fs.xs
            font.weight: root.sort === modelData.key ? Font.DemiBold : Font.Normal
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setSort(colHead.modelData.key)
            }
          }
        }
      }
    }

    ListView {
      id: browse
      anchors.top: tops.bottom
      anchors.topMargin: 6
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: root.compact ? root.ui.gutter - 4 : 0
      anchors.rightMargin: root.compact ? root.ui.gutter - 4 : 0
      anchors.bottomMargin: root.compact ? 0 : 16
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      spacing: root.compact ? 0 : 1
      // Empty while the window is shut: a list that lays itself out while the
      // shell is still starting is the fault that takes a phone down.
      model: root.opened ? root.shown : []
      delegate: EntryRow {
        id: row
        required property var modelData
        width: browse.width
        app: root
        entry: modelData
        now: root.now
        details: !root.compact
        selected: !root.compact && root.picked === modelData.name
        onActivated: root.enter(row.modelData)
        onPicked: root.picked = row.modelData.name
        onMenuWanted: { root.menuFor = row.modelData; rowSheet.open() }
      }
    }

    EmptyState {
      anchors.centerIn: browse
      visible: !root.listing && root.shown.length === 0 && root.loaded
      app: root
      glyph: root.trouble.length ? G.of("action-unavailable-symbolic") : root.query.length ? KG.search : G.folder
      title: root.trouble.length ? "Nothing to show"
        : root.query.length ? "No match"
        : root.entries.length ? "Nothing but hidden files" : "This folder is empty"
      text: root.trouble.length ? root.trouble
        : root.query.length ? "Nothing in this folder is called " + root.query + "."
        : root.entries.length ? "There are " + root.entries.length + " hidden files here." : "Paste something in, or make a folder."
      actionText: !root.trouble.length && !root.query.length && root.entries.length ? "Show them" : ""
      onAction: root.setHidden(true)
    }
  }

  Preview {
    id: pane
    visible: root.hasPane
    width: visible ? Math.min(340, root.contentArea.width * 0.32) : 0
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.rightMargin: 16
    anchors.bottomMargin: 16
    app: root
    entry: root.pickedEntry
    dir: root.path
    now: root.now
    inTrash: root.inTrash
    onClose: root.picked = ""
  }

  // The places, as a tab of their own on a phone.
  PlacesList {
    anchors.fill: parent
    visible: root.onPlaces
    app: root
    rows: root.onPlaces ? root.placeRows : []
    current: root.path
    onGo: function (where) { root.go(where) }
  }
}
