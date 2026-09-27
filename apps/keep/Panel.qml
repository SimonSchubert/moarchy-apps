import QtQuick
import Quickshell
import "kit"
import "kit/Glyphs.js" as KG
import "Notes.js" as N
import "Glyphs.js" as G

// Keep: notes and checklists in the shape of Google Keep. A grid of cards in
// their own colours, pinned ones first, a search over all of it, and an editor
// with nothing to save.
//
//     omarchy-shell shell toggle org.moarchy.keep
//
// Below 720 px it is the phone app: two columns, "Take a note…" at the bottom
// where a thumb is, and a note opens as a page over the grid. Above it the
// grid has as many columns as fit, and a note opens in a pane beside it, so
// the grid stays where it was.
App {
  id: root

  appId: "org.moarchy.keep"
  title: "Notes"
  subtitle: {
    var n = notes.notes.length
    return n === 0 ? "" : n === 1 ? "1 note" : n + " notes"
  }
  windowWidth: 1180
  windowHeight: 800

  store: Store { name: "moarchy-keep" }

  launcher.desktopId: "org.moarchy.Keep"
  launcher.genericName: "Notes"
  launcher.comment: "Text notes and checklists, kept on the device"
  launcher.categories: "Utility;TextEditor;"
  launcher.keywords: "note;notes;list;checklist;todo;memo;keep;"

  mark: Component { Image { source: root.appDir + "/icon.svg"; sourceSize: Qt.size(60, 60) } }

  // The nine note colours' hues, where the theme names them, and a fallback
  // for each look where it does not. Brown is named by almost none.
  readonly property var noteHues: ({
    red: ui.hue("red", "#f87171", "#dc2626"),
    orange: ui.hue("orange", "#fb923c", "#ea580c"),
    yellow: ui.hue("yellow", "#facc15", "#ca8a04"),
    green: ui.hue("green", "#4ade80", "#16a34a"),
    cyan: ui.hue("cyan", "#22d3ee", "#0891b2"),
    blue: ui.hue("blue", "#60a5fa", "#2563eb"),
    magenta: ui.hue("magenta", "#c084fc", "#9333ea"),
    brown: ui.hue("brown", "#c08457", "#92400e")
  })

  // A note's fill: a wash of its hue over the window's background, not the
  // hue itself -- the theme's text on a solid yellow is unreadable in a light
  // theme, and on half the palettes people run. A light theme needs more of
  // the colour before a wash reads as deliberate.
  function noteFill(key) {
    var role = N.roleOf(key)
    if (!role) return ui.surface
    return Qt.tint(ui.bg, ui.alpha(Qt.color(noteHues[role]), ui.dark ? 0.24 : 0.30))
  }

  actions: Component {
    Row {
      spacing: 2
      IconButton {
        app: root
        glyph: root.notes.view === "list" ? G.grid : G.column
        label: root.notes.view === "list" ? "Grid" : "Single column"
        onClicked: root.toggleView()
      }
    }
  }

  settings: Component {
    SettingsPage {
      app: root
      blurb: "Notes and checklists, in the shape of Google Keep."
      AppearanceSection { app: root }
      LauncherSection { app: root }
      KeysSection {
        app: root
        keys: [
          ["n", "A new note"],
          ["l", "A new list"],
          ["/", "Search"],
          ["g", "Grid or single column"],
          [",", "Settings"],
          ["Esc", "Close the note, clear the search"]
        ]
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Where the notes are"
        note: "~/.local/share/moarchy-keep/notes.json: one file, readable by anything, and the file the GTK version of Keep wrote. Saved half a second after the last key. A file that cannot be read is moved aside, never written over."
      }
    }
  }

  // A note, over the grid, on a phone.
  page: Component {
    NoteEditor {
      app: root
      noteId: root.topPage ? root.topPage.id : ""
      fresh: root.topPage ? !!root.topPage.fresh : false
    }
  }

  // ------------------------------------------------------------ the notes

  property var notes: N.emptyStore()
  property string query: ""
  // The note open in the pane beside the grid, on a desktop.
  property string openId: ""
  property bool openFresh: false
  property bool loaded: false
  property string written: ""

  function save() {
    written = N.serialize(notes)
    file.save(written)
  }

  function saveNote(note) {
    if (!note || deleted === note.id) return
    notes = N.put(notes, N.clone(note))
    save()
  }

  // The editor closing: blank lines off a list, and a note nobody typed
  // anything into goes, the way Keep lets a note you open and back out of go.
  property string deleted: ""
  function finishNote(note) {
    if (!note || deleted === note.id) return
    var tidy = N.tidy(note)
    if (N.isEmpty(tidy)) {
      if (N.get(notes, tidy.id)) { notes = N.remove(notes, tidy.id).store; save() }
      return
    }
    notes = N.put(notes, tidy)
    save()
  }

  function newNote(kind) {
    var note = N.create(kind)
    notes = N.put(notes, note)
    deleted = ""
    openNote(note.id, true)
  }

  function openNote(id, fresh) {
    if (compact) {
      push({ kind: "note", id: id, fresh: !!fresh })
    } else {
      // Through nothing, so the editor on the last note finishes first.
      openId = ""
      openFresh = !!fresh
      openId = id
    }
  }

  function deleteNote(id) {
    deleted = id
    var gone = N.remove(notes, id)
    if (gone.index < 0) return
    if (openId === id) openId = ""
    stack = stack.filter(function (e) { return e.id !== id })
    notes = gone.store
    save()
    toast("Note deleted", "Undo", function () {
      root.deleted = ""
      root.notes = N.restore(root.notes, gone.note, gone.index)
      root.save()
    })
  }

  function setPinned(id, pinned) {
    var n = N.get(notes, id)
    if (!n) return
    n = N.clone(n)
    n.pinned = pinned
    notes = N.put(notes, n)
    save()
  }

  function setColour(id, key) {
    var n = N.get(notes, id)
    if (!n) return
    n = N.clone(n)
    n.colour = key
    notes = N.put(notes, n)
    save()
  }

  function toggleView() {
    notes = { notes: notes.notes, view: notes.view === "list" ? "grid" : "list" }
    save()
  }

  DataFile {
    id: file
    app: "keep"
    name: "notes.json"
    onParsed: function (data) {
      // JSON that is not a notes file is moved aside like a broken one: the
      // next save would otherwise destroy it.
      if (data && !N.valid(data)) {
        file.quarantine()
        root.notes = N.emptyStore()
      } else {
        var next = N.parse(data)
        // Our own save, read back: nothing changed.
        if (root.loaded && N.serialize(next) === root.written) return
        root.notes = next
      }
      if (!root.loaded) { root.loaded = true; root.afterLoad() }
    }
    onQuarantined: function (to) {
      root.toast("Unreadable notes file kept as " + to.replace(/^.*\//, ""), "OK", function () {})
    }
  }

  // ------------------------------------------------------------ the menu

  // A long press on a card: pin, colour or delete, without opening it.
  property string menuId: ""
  readonly property var menuNote: menuId ? N.get(notes, menuId) : null
  function cardMenu(id) {
    menuId = id
    menu.open()
  }

  Dialog {
    id: menu
    app: root
    title: root.menuNote ? (root.menuNote.title || "Note") : ""
    acceptText: "Done"
    rejectText: ""
    onAccepted: root.menuId = ""
    onRejected: root.menuId = ""

    Button {
      app: root
      glyph: root.menuNote && root.menuNote.pinned ? G.pinOutline : G.pin
      text: root.menuNote && root.menuNote.pinned ? "Unpin" : "Pin"
      onClicked: root.setPinned(root.menuId, !(root.menuNote && root.menuNote.pinned))
    }
    ColourGrid {
      width: parent.width
      app: root
      selected: root.menuNote ? root.menuNote.colour : "default"
      onPicked: function (key) { root.setColour(root.menuId, key) }
    }
    Button {
      app: root
      glyph: KG.remove
      text: "Delete"
      tint: root.ui.bad
      active: true
      onClicked: {
        var id = root.menuId
        menu.close()
        root.deleteNote(id)
      }
    }
  }

  // ------------------------------------------------------------ hooks

  // MOARCHY_KEEP_OPEN (an id, or part of a title), MOARCHY_KEEP_NEW (text or
  // list), MOARCHY_KEEP_MENU (part of a title), MOARCHY_KEEP_QUERY: start on a
  // screen, for the screenshots and for a phone with no finger to tap with.
  property bool hooked: false
  function find(want) {
    var n = N.get(notes, want)
    if (n) return n
    for (var i = 0; i < notes.notes.length; i++)
      if (notes.notes[i].title.toLowerCase().indexOf(want.toLowerCase()) >= 0) return notes.notes[i]
    return null
  }
  function afterLoad() {
    if (hooked || !opened) return
    hooked = true
    // The window's width is not known in the first frame; a page or a pane
    // is chosen from it.
    Qt.callLater(function () {
      var q = Quickshell.env("MOARCHY_KEEP_QUERY") || ""
      if (q) root.query = q
      var want = Quickshell.env("MOARCHY_KEEP_OPEN") || ""
      var fresh = Quickshell.env("MOARCHY_KEEP_NEW") || ""
      var menuWant = Quickshell.env("MOARCHY_KEEP_MENU") || ""
      if (want) { var n = root.find(want); if (n) root.openNote(n.id, false) }
      else if (fresh === N.TEXT || fresh === N.LIST) root.newNote(fresh)
      else if (menuWant) { var m = root.find(menuWant); if (m) root.cardMenu(m.id) }
      if (Quickshell.env("MOARCHY_KEEP_SETTINGS")) root.setTab("settings")
    })
  }
  onSummoned: if (loaded) afterLoad()

  // A pane left open on a desktop becomes a page when the window narrows.
  onCompactChanged: if (compact && openId) {
    var id = openId
    openId = ""
    push({ kind: "note", id: id, fresh: false })
  }

  stepBack: function () {
    if (openId) { openId = ""; resetFocus(); return true }
    if (query) { query = ""; return true }
    return false
  }

  onOpenedChanged: if (!opened) { openId = ""; menuId = "" }

  keyHandler: function (event) {
    if (topPage || inSettings) return
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    if (event.text === "n") { newNote(N.TEXT); event.accepted = true; return }
    if (event.text === "l") { newNote(N.LIST); event.accepted = true; return }
    if (event.text === "g") { toggleView(); event.accepted = true; return }
    if (event.text === "/") { notesView.focusSearch(); event.accepted = true }
  }

  // ------------------------------------------------------------ the screen

  NotesView {
    id: notesView
    app: root
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.right: pane.active ? pane.left : parent.right
  }

  Loader {
    id: pane
    active: !root.compact && root.openId !== ""
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.margins: 12
    width: active ? Math.min(480, parent.width * 0.45) : 0
    sourceComponent: Rectangle {
      radius: root.ui.radius + 6
      color: "transparent"
      border.width: 1
      border.color: root.ui.divider
      clip: true
      NoteEditor {
        anchors.fill: parent
        anchors.margins: 1
        radius: root.ui.radius + 5
        app: root
        noteId: root.openId
        fresh: root.openFresh
        pane: true
      }
    }
  }
}
