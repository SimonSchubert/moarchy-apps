pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "kit"
import "kit/Glyphs.js" as KG
import "Doc.js" as Doc
import "Store.js" as S
import "Glyphs.js" as G

// Text Editor: one file at a time, and the files you opened.
//
//     omarchy-shell shell summon org.moarchy.editor /path/to/file
//
// On a phone, two screens. **The list** is the files this has opened, newest
// first. **The file** is the text in a box, with undo and save in the bar
// above it, because the phone's keyboard has no Ctrl key to reach either
// with. On a desktop the list is a column beside the text, and the keyboard
// has its Ctrl: S saves, N starts a file, W closes it.
//
// It is also $EDITOR, which is the part that is not obvious from the screen.
// `moarchy-editor --wait FILE` hands over a marker path with the file and
// stays running until the marker exists; this touches it when that file is
// closed, replaced, or the window goes away. That is what lets `git commit`
// read the message back after the window, and not before. Run on its own,
// without the shell, the same launcher simply waits for this process.
//
// Nothing here reads a file until it has been asked what the file is: FileView
// reads a file whole into this process -- inside the shell, the shell's own --
// and a mistaken tap on a 400 MB log is refused by one `stat` rather than
// found out by the phone.
App {
  id: root

  appId: "org.moarchy.editor"
  title: "Text Editor"
  heading: screen === "file" ? docTitle : ""
  subtitle: screen === "file" ? docState
    : recent.length ? recent.length + (recent.length === 1 ? " file" : " files") : ""
  // The file's own bar, with a way back, stands in for the header on a phone.
  header: !(compact && screen === "file")
  windowWidth: 1100
  windowHeight: 760

  store: Store {
    name: "moarchy-editor"
    // Monospace, because what this is opened on most is a config file or a
    // commit message, and both are laid out in columns.
    defaults: ({ mono: true })
  }

  launcher.desktopId: "org.moarchy.Editor"
  launcher.genericName: "Text editor"
  launcher.comment: "One text file at a time, and an $EDITOR that waits"
  launcher.categories: "Utility;TextEditor;"
  launcher.keywords: "text;editor;notes;txt;markdown;config;"

  mark: Component { Image { source: root.appDir + "/icon.svg"; sourceSize: Qt.size(60, 60) } }

  actions: Component {
    Row {
      spacing: 2
      IconButton {
        visible: root.screen === "file" && !root.readOnly
        app: root
        glyph: KG.undo
        label: "Undo"
        opacity: edit.canUndo ? 1 : 0.35
        onClicked: if (edit.canUndo) edit.undo()
      }
      IconButton {
        visible: root.screen === "file" && !root.readOnly
        app: root
        glyph: G.save
        label: "Save"
        // The accent while there is something to save, so the key says
        // whether pressing it would do anything.
        color: root.dirty || root.docNew ? root.ui.accent : root.ui.text
        onClicked: root.save(null)
      }
      IconButton {
        visible: root.screen === "file"
        app: root
        glyph: G.more
        label: "More"
        active: root.menuOpen
        onClicked: root.menuOpen = !root.menuOpen
      }
      IconButton {
        visible: !root.compact
        app: root
        glyph: G.fileNew
        label: "New file"
        onClicked: root.request({ kind: "new" })
      }
    }
  }

  settings: Component {
    SettingsPage {
      app: root
      blurb: "One text file at a time, with undo and save where a thumb can reach them, and an $EDITOR that waits."
      SettingsSection {
        app: root
        width: parent.width
        title: "The text"
        Toggle {
          app: root
          width: parent.width
          text: "Wrap long lines"
          note: "Off, a long line runs on and the box scrolls sideways."
          checked: root.wrap
          onToggled: function (on) { root.setWrap(on) }
        }
        Toggle {
          app: root
          width: parent.width
          text: "Monospace"
          note: "Columns line up, which is what a config file and a commit message need."
          checked: root.mono
          onToggled: function (on) { root.store.set("mono", on) }
        }
      }
      AppearanceSection { app: root }
      LauncherSection { app: root }
      KeysSection {
        app: root
        keys: [
          ["Ctrl+S", "Save"],
          ["Ctrl+Shift+S", "Save as"],
          ["Ctrl+N", "A new file"],
          ["Ctrl+W", "Close the file"],
          ["Ctrl+Z  Ctrl+Shift+Z", "Undo and redo"],
          ["Esc", "Leave the text, then back"],
          [",", "Settings, from the list"]
        ]
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Being $EDITOR"
        note: "EDITOR='moarchy-editor --wait' makes this what git and the rest open, and they wait until the file is closed. The list of files and the wrap setting are kept in ~/.local/share/moarchy-editor/state.json."
      }
    }
  }

  // ------------------------------------------------------------ what is kept

  // MOARCHY_EDITOR_HOME is the harness's: it lets a screenshot of a fixture
  // read ~/Documents rather than a temporary directory's full path.
  readonly property string home: Quickshell.env("MOARCHY_EDITOR_HOME") || Quickshell.env("HOME") || ""

  // Nothing is written back until the file has been read, so a save that
  // races the first read cannot replace the list with an empty one.
  property bool stateReady: false
  property var recent: []
  property bool wrap: true
  readonly property bool mono: store.prefs.mono !== false
  // Seconds, set as the window opens, so "2 h ago" is not a binding on a clock.
  property real now: Date.now() / 1000

  // "list" | "file"
  property string screen: "list"

  // ------------------------------------------------------------ the open file

  // "" for a file with no name yet.
  property string docPath: ""
  property string docEndings: "lf"
  // Doc.problem()'s kind, when this file cannot be written back exactly.
  property string docProblem: ""
  property bool docWritable: true
  // Not on disk yet: a new file, or a path somebody named that is not there.
  property bool docNew: false
  property bool docLoading: false
  property bool dirty: false
  property int revision: 0
  property bool settingText: false

  property bool saving: false
  property string savingPath: ""
  property int savingRevision: 0
  property var afterSave: null

  // moarchy-editor --wait's marker for this file, and whether closing the file
  // should close the window with it -- which is what a caller that summoned
  // the editor for one file wants back.
  property string waitMarker: ""
  property bool leaveOnClose: false

  // What the unsaved question is standing in the way of.
  property var pending: null
  property var afterSaveAs: null
  // The path a Save As has already warned it would replace.
  property string replaceArmed: ""
  // A Save As whose path is being asked about.
  property bool saveAsProbing: false
  property bool menuOpen: false
  // Standalone and asked to quit, with the question answered.
  property bool quitAnyway: false

  readonly property bool readOnly: docProblem.length > 0
    || (docPath.length > 0 && !docWritable && !docNew)

  readonly property string docTitle: docPath.length ? Doc.basename(docPath) : "Untitled"

  readonly property string docState: {
    if (docLoading) return "Opening…"
    if (saving) return "Saving…"
    if (readOnly) return "Read only"
    if (dirty) return "Not saved"
    if (waitMarker.length) return "Go back when you are done"
    if (docNew) return docPath.length ? "New file" : "Not saved yet"
    return Doc.tilde(Doc.dirname(docPath), home)
  }

  // ------------------------------------------------------------ the host

  onSummoned: {
    var ask = Doc.parsePayload(payloadText)
    now = Date.now() / 1000
    if (ask.path.length) {
      request({ kind: "open", path: ask.path, wait: ask.wait })
      return
    }
    // Nothing to wait on is still an answer the caller is waiting for.
    touchMarker(ask.wait)
    if (ask.refused) toast("That path is not one this can open. It needs to start with /.")
  }

  // A window that has gone is a file somebody has stopped looking at, and
  // whatever is waiting on it gets the file as it is on disk. What is typed and
  // not saved stays here, and is here the next time the window is -- inside
  // the shell, which keeps this loaded. Standalone, closing is quitting, and
  // holdQuit asks first.
  onOpenedChanged: {
    if (opened) {
      if (stateReady) Qt.callLater(applyHarness)
      return
    }
    releaseWait()
    leaveOnClose = false
    menuOpen = false
    cancelDialog()
  }

  holdQuit: function () {
    if (quitAnyway || screen !== "file" || !dirty || readOnly) return false
    request({ kind: "quit" })
    return true
  }

  // Before the tabs: the menu, then the file.
  stepBack: function () {
    if (menuOpen) { menuOpen = false; return true }
    if (screen === "file") { request({ kind: "close" }); return true }
    return false
  }

  keyHandler: function (event) {
    if (!(event.modifiers & Qt.ControlModifier)) return
    if (command(event)) event.accepted = true
  }

  // Ctrl and a letter, from the window or from inside the text.
  function command(event) {
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0
    switch (event.key) {
    case Qt.Key_S: if (shift) askSaveAs(null); else save(null); return true
    case Qt.Key_N: request({ kind: "new" }); return true
    case Qt.Key_W: if (screen === "file") request({ kind: "close" }); return true
    }
    return false
  }

  // `omarchy-shell shell call org.moarchy.editor waiting <marker>` -- how
  // moarchy-editor finds out that a shell which restarted has forgotten it,
  // rather than waiting for a marker nobody is going to touch.
  function waiting(marker) {
    var m = String(marker || "")
    if (!m.length) return "no"
    if (m === waitMarker) return "yes"
    if (pending && pending.wait === m) return "yes"
    if (afterSaveAs && afterSaveAs.wait === m) return "yes"
    return "no"
  }

  function saveState() {
    if (!stateReady) return
    stateFile.save(S.serialize({ recent: recent, wrap: wrap }))
  }

  // ------------------------------------------------------------ the markers

  function touchMarker(marker) {
    if (Doc.markerOk(marker)) Quickshell.execDetached(["touch", "--", String(marker)])
  }

  function attachWait(marker) {
    var m = Doc.markerOk(marker) ? String(marker) : ""
    if (waitMarker.length && waitMarker !== m) touchMarker(waitMarker)
    waitMarker = m
    if (m.length) leaveOnClose = true
  }

  function releaseWait() {
    touchMarker(waitMarker)
    waitMarker = ""
  }

  // ------------------------------------------------------------ dropping the file

  // Opening another file, starting a new one, closing this one and quitting
  // all come through here, so edits that are not saved are asked about once
  // and in one way, whatever asked for the file to go.
  function request(action) {
    menuOpen = false
    if (action.kind === "open" && screen === "file" && action.path === docPath) {
      // The same file again keeps what is typed in it. Only who is waiting
      // for it changes.
      attachWait(action.wait)
      return
    }
    if (screen === "file" && dirty) {
      if (pending) touchMarker(pending.wait)
      pending = action
      unsaved.open()
      return
    }
    perform(action)
  }

  function perform(action) {
    pending = null
    if (!action) return
    if (action.kind === "close") { closeFile(false); return }
    if (action.kind === "quit") { quitAnyway = true; closeFile(true); dismiss(); return }
    closeFile(true)
    if (action.kind === "new") startNew()
    else if (action.kind === "open") startOpen(action.path, action.wait || "", !!action.recent)
  }

  function cancelDialog() {
    if (pending) touchMarker(pending.wait)
    if (afterSaveAs) touchMarker(afterSaveAs.wait)
    pending = null
    afterSaveAs = null
    replaceArmed = ""
    saveAsProbing = false
    if (dialog) dialog.close()
  }

  function closeFile(replacing) {
    var leave = leaveOnClose && !replacing && screen === "file"
    releaseWait()
    leaveOnClose = false
    screen = "list"
    docPath = ""
    docProblem = ""
    docEndings = "lf"
    docWritable = true
    docNew = false
    docLoading = false
    readPath = ""
    setText("")
    now = Date.now() / 1000
    resetFocus()
    if (leave) dismiss()
  }

  function startNew() {
    screen = "file"
    docNew = true
    setText("")
    Qt.callLater(focusText)
  }

  function startOpen(path, wait, fromList) {
    screen = "file"
    docPath = path
    docLoading = true
    openedFromList = fromList
    attachWait(wait)
    setText("")
    probe("open", path)
  }

  // Loading or not, and whatever it says: the undo history is the file's, so
  // a new file starts with none.
  function setText(text) {
    settingText = true
    edit.text = text
    settingText = false
    edit.cursorPosition = 0
    flick.contentY = 0
    flick.contentX = 0
    dirty = false
    revision = 0
  }

  function focusText() {
    if (screen === "file" && !readOnly) edit.forceActiveFocus()
  }

  // ------------------------------------------------------------ asking before reading

  property bool openedFromList: false
  property string readPath: ""
  property var queuedProbe: null

  function probe(job, path) {
    if (prober.running) { queuedProbe = { job: job, path: path }; return }
    prober.job = job
    prober.target = path
    prober.command = Doc.probeCommand(path)
    prober.running = true
  }

  function probed(job, path, code, out) {
    var p = code === 0 ? Doc.parseProbe(out) : null
    if (job === "open") probedOpen(path, p)
    else if (job === "saveas") probedSaveAs(path, p)
  }

  function probedOpen(path, p) {
    if (screen !== "file" || docPath !== path || !docLoading) return
    if (p && p.kind === "missing" && openedFromList) {
      recent = S.forget(recent, path)
      saveState()
      failOpen("That file is not there any more.")
      return
    }
    var trouble = Doc.probeTrouble(p)
    if (trouble.length) { failOpen(trouble); return }

    recent = S.touch(recent, path, Date.now() / 1000)
    saveState()

    if (p.kind === "missing") {
      docNew = true
      docWritable = true
      docLoading = false
      afterLoad()
      Qt.callLater(focusText)
      return
    }
    docWritable = p.writable
    readPath = path
  }

  function failOpen(message) {
    toast(message)
    closeFile(true)
  }

  function loadedText(path, text) {
    if (screen !== "file" || docPath !== path || !docLoading) return
    var held = Doc.forEditing(text)
    docEndings = held.endings
    docProblem = held.problem
    setText(held.text)
    docLoading = false
    // The reader lets go of its copy. The file is in the TextEdit now, and a
    // second copy of it in memory is nobody's.
    Qt.callLater(function () { root.readPath = "" })
    afterLoad()
  }

  function loadFailed(path, code) {
    if (screen !== "file" || docPath !== path || !docLoading) return
    readPath = ""
    failOpen(Doc.loadTrouble(code))
  }

  // ------------------------------------------------------------ writing

  function save(then) {
    menuOpen = false
    if (screen !== "file" || docLoading || saving) { drop(then); return }
    if (docProblem.length) {
      toast(Doc.problemText(docProblem))
      drop(then)
      return
    }
    if (!docPath.length) { askSaveAs(then); return }
    if (readOnly) {
      toast("You do not have permission to change this file. Save a copy somewhere else.")
      askSaveAs(then)
      return
    }
    write(docPath, then)
  }

  function write(path, then) {
    saving = true
    savingPath = path
    savingRevision = revision
    afterSave = then || null
    writer.path = path
    writer.setText(Doc.forDisk(edit.text, docEndings))
  }

  function wrote() {
    if (!saving) return
    saving = false
    var path = savingPath
    docPath = path
    docNew = false
    docWritable = true
    dirty = revision !== savingRevision
    recent = S.touch(recent, path, Date.now() / 1000)
    saveState()
    var then = afterSave
    afterSave = null
    toast("Saved")
    if (then) perform(then)
  }

  function writeFailed(code) {
    if (!saving) return
    saving = false
    drop(afterSave)
    afterSave = null
    toast(Doc.saveTrouble(code))
  }

  // An action that is not going to happen after all. Whoever was waiting on
  // it is told, rather than left to find out from a poll twenty seconds later.
  function drop(action) {
    if (action) touchMarker(action.wait)
  }

  function askSaveAs(then) {
    menuOpen = false
    if (screen !== "file") return
    if (docProblem.length) {
      toast(Doc.problemText(docProblem))
      drop(then)
      return
    }
    afterSaveAs = then || null
    // Documents for a new file, because that is where Files opens a person's
    // own things; the folder is made on save if it is not there.
    var start = docPath.length && !readOnly
      ? docPath
      : home + "/Documents/" + (docPath.length ? Doc.basename(docPath) : "Untitled.txt")
    nameField.text = Doc.tilde(start, home)
    replaceArmed = ""
    saveAs.open()
  }

  function confirmSaveAs() {
    var trouble = Doc.saveAsProblem(nameField.text, home)
    if (trouble.length) { toast(trouble); saveAs.open(); return }
    saveAsProbing = true
    probe("saveas", Doc.expand(nameField.text, home))
  }

  function probedSaveAs(path, p) {
    if (!saveAsProbing) return
    saveAsProbing = false
    // Typed on since the question was asked: that answer is about another path.
    if (Doc.expand(nameField.text, home) !== path) { saveAs.open(); return }
    var trouble = ""
    if (!p || p.kind === "") trouble = "That path cannot be saved to."
    else if (p.kind === "dir") trouble = "That is a folder. Add a file name."
    else if (p.kind === "unreadable" || p.kind === "other") trouble = "Something that is not yours to replace is already there."
    else if (p.kind === "missing" && !p.writable) trouble = "That folder is not yours to write in."
    else if (p.kind === "file" && !p.writable) trouble = "You do not have permission to change that file."
    if (trouble.length) { toast(trouble); saveAs.open(); return }

    if (p.kind === "file" && path !== docPath && replaceArmed !== path) {
      replaceArmed = path
      toast("There is already a " + Doc.basename(path) + " there. Save again to replace it.")
      saveAs.open()
      return
    }
    var then = afterSaveAs
    afterSaveAs = null
    replaceArmed = ""
    write(path, then)
  }

  function copyAll() {
    menuOpen = false
    if (!edit.length) { toast("There is nothing in this file to copy."); return }
    var at = edit.cursorPosition
    edit.selectAll()
    edit.copy()
    edit.deselect()
    edit.cursorPosition = at
    toast("Copied")
  }

  function pasteHere() {
    menuOpen = false
    if (!edit.canPaste) { toast("There is nothing to paste."); return }
    edit.paste()
    Qt.callLater(focusText)
  }

  function setWrap(on) {
    wrap = on
    menuOpen = false
    saveState()
  }

  function menuPicked(key) {
    menuOpen = false
    if (key === "redo") { if (edit.canRedo) edit.redo() }
    else if (key === "copy") copyAll()
    else if (key === "paste") pasteHere()
    else if (key === "saveas") askSaveAs(null)
    else if (key === "wrap") setWrap(!wrap)
    else if (key === "mono") store.set("mono", !mono)
    else if (key === "close") request({ kind: "close" })
  }

  // ------------------------------------------------------------ the harness

  // What dev/shots sets. Each is a screen a thumb can already reach; naming
  // them is what lets a screenshot run reach it without one.
  property bool harnessed: false
  property bool loadHarnessed: false

  function applyHarness() {
    if (harnessed || !opened) return
    harnessed = true
    if (Quickshell.env("MOARCHY_EDITOR_SETTINGS")) { setTab("settings"); return }
    var want = Quickshell.env("MOARCHY_EDITOR_OPEN") || ""
    if (want === "new") {
      request({ kind: "new" })
      afterLoad()
      return
    }
    if (want === "recent" && recent.length) want = recent[0].path
    else if (/^recent:\d+$/.test(want)) {
      var i = parseInt(want.slice(7), 10)
      want = i < recent.length ? recent[i].path : ""
    }
    if (want.charAt(0) === "/") request({ kind: "open", path: want, recent: true })
  }

  function afterLoad() {
    if (loadHarnessed) return
    loadHarnessed = true
    var typed = Quickshell.env("MOARCHY_EDITOR_TYPE") || ""
    if (typed.length) edit.insert(edit.length, typed)
    if ((Quickshell.env("MOARCHY_EDITOR_MENU") || "").length) menuOpen = true
    var which = Quickshell.env("MOARCHY_EDITOR_DIALOG") || ""
    if (which === "unsaved") request({ kind: "close" })
    else if (which === "saveas") askSaveAs(null)
  }

  // ------------------------------------------------------------ not on screen

  Process {
    id: prober
    property string job: ""
    property string target: ""
    running: false
    stdout: StdioCollector { id: probeOut; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) {
      root.probed(prober.job, prober.target, code, probeOut.text)
      var next = root.queuedProbe
      root.queuedProbe = null
      if (next) Qt.callLater(function () { root.probe(next.job, next.path) })
    }
    // qmllint enable signal-handler-parameters
  }

  FileView {
    id: reader
    path: root.readPath
    printErrors: false
    onLoaded: root.loadedText(reader.path, reader.text())
    onLoadFailed: function (error) { root.loadFailed(reader.path, error) }
  }

  // A second FileView, so that saving never reads: `preload: false` is what
  // stops pointing it at a path from loading that path first. It writes
  // atomically, through a symlink to its target, keeps the file's mode, and
  // creates missing folders.
  FileView {
    id: writer
    preload: false
    printErrors: false
    onSaved: root.wrote()
    onSaveFailed: function (error) { root.writeFailed(error) }
  }

  DataFile {
    id: stateFile
    app: "editor"
    name: "state.json"
    // Read once, as the app starts: one small file, and a second read on
    // every open would race the write an open makes.
    watchChanges: false
    onParsed: function (data) {
      if (root.stateReady) return
      var s = S.parse(data)
      root.recent = s.recent
      root.wrap = s.wrap
      root.stateReady = true
      Qt.callLater(root.applyHarness)
    }
    onQuarantined: function (to) { root.toast("The list of files was unreadable and was kept aside.") }
  }

  IpcHandler {
    target: "editor"

    function state(): string { return root.opened ? "open" : "closed" }
    function show(): string { root.open(""); return "ok" }
    // As the window manager's close would: standalone, with text not saved,
    // the window stays and asks.
    function close(): string { root.dismiss(); return root.opened ? "asked" : "closed" }
    // A path, the way a script would hand one over.
    function openFile(path: string): string {
      var p = Doc.pathFrom(path)
      if (!p.length) return "not an absolute path: " + path
      root.open(JSON.stringify({ path: p }))
      return "ok"
    }
    // moarchy-editor --wait, when this is running on its own.
    function openWait(path: string, marker: string): string {
      var p = Doc.pathFrom(path)
      if (!p.length) return "not an absolute path: " + path
      root.open(JSON.stringify({ path: p, wait: marker }))
      return "ok"
    }
    function waiting(marker: string): string { return root.waiting(marker) }
    function file(): string { return root.screen === "file" ? (root.docPath || "untitled") : "" }
    function text(): string { return edit.text }
    // For a check that types and saves without a keyboard.
    function insert(text: string): string {
      if (root.screen !== "file" || root.readOnly) return "no file to type into"
      edit.insert(edit.length, text)
      return "ok"
    }
    function save(): string {
      if (root.screen !== "file") return "no file"
      root.save(null)
      return "ok"
    }
    function dirty(): bool { return root.dirty }
  }

  // ------------------------------------------------------------ the questions

  Dialog {
    id: unsaved
    app: root
    title: "Save " + root.docTitle + "?"
    text: "What you typed since it was last saved is only in this window."
    acceptText: "Save"
    acceptGlyph: G.save
    rejectText: "Keep editing"
    onAccepted: {
      var then = root.pending
      root.pending = null
      root.save(then)
    }
    onRejected: {
      if (root.pending) root.touchMarker(root.pending.wait)
      root.pending = null
    }
    Button {
      app: root
      text: "Discard"
      tint: root.ui.bad
      onClicked: {
        var then = root.pending
        root.pending = null
        unsaved.close()
        root.perform(then)
      }
    }
  }

  Dialog {
    id: saveAs
    app: root
    title: "Save as"
    acceptText: "Save"
    onAccepted: root.confirmSaveAs()
    onRejected: {
      if (root.saveAsProbing) return
      if (root.afterSaveAs) root.touchMarker(root.afterSaveAs.wait)
      root.afterSaveAs = null
      root.replaceArmed = ""
    }
    TextField {
      id: nameField
      app: root
      width: parent.width
      placeholder: "~/Documents/Notes.txt"
      inputHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
      onAccepted: saveAs.accept()
      onTextChanged: root.replaceArmed = ""
    }
  }

  Menu {
    app: root
    open: root.menuOpen
    onDismissed: root.menuOpen = false
    onPicked: function (key) { root.menuPicked(key) }
    items: [
      { key: "redo", label: "Redo", glyph: G.redo, enabled: edit.canRedo },
      { key: "copy", label: "Copy all", glyph: G.copy },
      { key: "paste", label: "Paste", glyph: G.paste, enabled: !root.readOnly && edit.canPaste },
      { key: "saveas", label: "Save as…", glyph: G.saveAs, enabled: root.docProblem.length === 0 },
      { key: "wrap", label: "Wrap long lines", glyph: G.wrap, checked: root.wrap },
      { key: "mono", label: "Monospace", glyph: G.mono, checked: root.mono },
      { key: "close", label: "Close file", glyph: KG.close }
    ]
  }

  // ------------------------------------------------------------ the screen

  // The list: the whole screen on a phone, a column on a desktop.
  RecentList {
    id: recentList
    app: root
    visible: !root.compact || root.screen === "list"
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: root.compact ? parent.width : 320
    recent: root.recent
    home: root.home
    now: root.now
    current: root.docPath
    onPicked: function (path) { root.request({ kind: "open", path: path, recent: true }) }
    onForgot: function (path) { root.recent = S.forget(root.recent, path); root.saveState() }
  }

  // A new file, where a thumb is.
  Rectangle {
    visible: root.compact && root.screen === "list"
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: 16
    width: 56
    height: 56
    radius: root.ui.radius + 8
    color: fabMouse.pressed ? Qt.darker(root.ui.accent, 1.15) : root.ui.accent
    Accessible.role: Accessible.Button
    Accessible.name: "New file"
    Icon { app: root; anchors.centerIn: parent; text: G.fileNew; size: 24; color: root.ui.inkOnAccent }
    MouseArea { id: fabMouse; anchors.fill: parent; onClicked: root.request({ kind: "new" }) }
  }

  // The file: the whole screen on a phone, everything right of the list on a
  // desktop.
  Item {
    id: fileArea
    visible: !root.compact || root.screen === "file"
    anchors.left: root.compact ? parent.left : recentList.right
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom

    // Nothing open, on a desktop.
    EmptyState {
      visible: root.screen === "list"
      app: root
      anchors.centerIn: parent
      glyph: G.file
      title: "No file open"
      text: "Pick one from the list, or start a new one."
      actionText: "New file"
      onAction: root.request({ kind: "new" })
    }

    PageHeader {
      id: fileHead
      visible: root.compact && root.screen === "file"
      app: root
      width: parent.width
      height: visible ? implicitHeight : 0
      title: root.docTitle
      subtitle: root.docState
      IconButton {
        visible: !root.readOnly
        app: root
        glyph: KG.undo
        label: "Undo"
        opacity: edit.canUndo ? 1 : 0.35
        onClicked: if (edit.canUndo) edit.undo()
      }
      IconButton {
        visible: !root.readOnly
        app: root
        glyph: G.save
        label: "Save"
        color: root.dirty || root.docNew ? root.ui.accent : root.ui.text
        onClicked: root.save(null)
      }
      IconButton {
        app: root
        glyph: G.more
        label: "More"
        active: root.menuOpen
        onClicked: root.menuOpen = !root.menuOpen
      }
    }

    Column {
      id: fileColumn
      visible: root.screen === "file"
      anchors.top: fileHead.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: root.ui.gutter
      anchors.rightMargin: root.ui.gutter
      anchors.bottomMargin: root.ui.gutter
      spacing: 10

      // Why this file will not be written, said once and in a box, above the
      // text rather than in a toast that has gone by the time somebody
      // wonders why Save is not there.
      Rectangle {
        id: problemBox
        visible: root.docProblem.length > 0
        width: parent.width
        height: visible ? problemRow.implicitHeight + 24 : 0
        radius: root.ui.radius + 2
        color: root.alpha(root.ui.warn, 0.14)
        border.width: 1
        border.color: root.alpha(root.ui.warn, 0.5)
        Row {
          id: problemRow
          x: 12
          y: 12
          width: parent.width - 24
          spacing: 10
          Icon { app: root; text: G.warning; size: 18; color: root.ui.warn }
          Text {
            width: parent.width - 36
            text: Doc.problemText(root.docProblem)
            wrapMode: Text.Wrap
            color: root.ui.text
            font.family: root.ui.font
            font.pixelSize: root.ui.fs.sm
          }
        }
      }

      Rectangle {
        id: paper
        width: parent.width
        height: parent.height - (problemBox.visible ? problemBox.height + parent.spacing : 0)
        radius: root.ui.radius + 4
        color: root.ui.surface
        border.width: 1
        border.color: edit.activeFocus ? root.alpha(root.ui.accent, 0.6) : root.ui.divider

        Flickable {
          id: flick
          anchors.fill: parent
          anchors.margins: 1
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          contentWidth: root.wrap ? width : Math.max(width, edit.width + 28)
          contentHeight: Math.max(height, edit.height + 28)

          // Keeps the caret on screen as it moves -- and as the screen moves,
          // because the phone's keyboard coming up takes half of it.
          function ensureVisible(r) {
            var top = r.y + edit.y - 14
            var bottom = r.y + r.height + edit.y + 14
            if (flick.contentY > top) flick.contentY = Math.max(0, top)
            else if (flick.contentY + flick.height < bottom) flick.contentY = bottom - flick.height
            if (root.wrap) return
            var left = r.x + edit.x - 14
            var right = r.x + r.width + edit.x + 14
            if (flick.contentX > left) flick.contentX = Math.max(0, left)
            else if (flick.contentX + flick.width < right) flick.contentX = right - flick.width
          }

          onHeightChanged: if (edit.activeFocus) Qt.callLater(function () { flick.ensureVisible(edit.cursorRectangle) })

          TextEdit {
            id: edit
            objectName: "text"
            x: 14
            y: 14
            width: root.wrap ? flick.width - 28 : Math.max(implicitWidth, flick.width - 28)
            // At least the box, so a tap anywhere under the last line puts the
            // caret at the end rather than landing on nothing.
            height: Math.max(implicitHeight, flick.height - 28)
            textFormat: TextEdit.PlainText
            wrapMode: root.wrap ? TextEdit.Wrap : TextEdit.NoWrap
            font.family: root.mono ? "monospace" : root.ui.font
            font.pixelSize: root.compact ? root.ui.fs.sm : root.ui.fs.md
            color: root.ui.text
            selectionColor: root.alpha(root.ui.accent, 0.4)
            selectedTextColor: root.ui.text
            // On a phone a drag scrolls: one that selected instead would leave
            // a 360 px screen with no way to move through a long file. A
            // desktop has a mouse wheel, and selects.
            selectByMouse: !root.compact
            readOnly: root.readOnly || root.docLoading
            activeFocusOnPress: true
            tabStopDistance: 4 * fontMetrics.advanceWidth(" ")

            cursorDelegate: Rectangle {
              width: 2
              color: root.ui.accent
              visible: edit.activeFocus && !edit.readOnly
            }

            onTextChanged: {
              if (root.settingText) return
              root.revision += 1
              root.dirty = true
            }
            onCursorRectangleChanged: if (edit.activeFocus) flick.ensureVisible(edit.cursorRectangle)

            Keys.onPressed: function (event) {
              if (event.key === Qt.Key_Escape) { root.resetFocus(); event.accepted = true; return }
              if ((event.modifiers & Qt.ControlModifier) && root.command(event)) event.accepted = true
            }

            Text {
              visible: edit.length === 0 && !root.docLoading
              text: root.readOnly ? "This file is empty." : "Nothing here yet."
              color: root.ui.muted
              font: edit.font
            }
          }

          FontMetrics {
            id: fontMetrics
            font: edit.font
          }
        }
      }
    }
  }
}
