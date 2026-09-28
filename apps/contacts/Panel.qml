import QtQuick
import Quickshell
import Quickshell.Io
import "kit"
import "kit/Glyphs.js" as KG
import "Contacts.js" as Contacts
import "Store.js" as S

// Contacts: a name, a number, an email and a note, in one file, with no
// accounts behind it.
//
//     omarchy-shell shell toggle org.moarchy.contacts
//
// The book is ~/.local/share/moarchy-contacts/contacts.json (Store.js), the
// same file the shell plugin wrote and Mail reads the To: suggestions from,
// so it is kept in exactly that shape.
//
// A phone gets the list, and a person as a page over it; a desktop gets the
// list with the person in a pane beside it. Either way the person is a form:
// an address book is opened for eleven seconds to find a number, and there
// is nothing to read on a contact that is not one of its four fields.
App {
  id: root

  appId: "org.moarchy.contacts"
  title: "Contacts"
  subtitle: !loaded || !contacts.length ? ""
    : list.query !== "" ? shown.length + " of " + contacts.length
    : contacts.length + (contacts.length === 1 ? " person" : " people")
  windowWidth: 1080
  windowHeight: 760

  store: Store { name: "moarchy-contacts" }

  launcher.desktopId: "org.moarchy.Contacts"
  launcher.genericName: "Contacts"
  launcher.comment: "A name, a number, an email, and a note — one file, no accounts"
  launcher.categories: "Office;ContactManagement;"
  launcher.keywords: "contacts;address;phone;email;people;book;"

  mark: Component { Image { source: root.appDir + "/icon.svg"; sourceSize: Qt.size(60, 60) } }

  ui: Tokens {
    theme: root.hostTheme
    compact: root.compact
    // A person's disc takes one of the theme's hues, by name.
    readonly property var people: [
      accent,
      hue("green", "#4ade80", "#16a34a"),
      hue("magenta", "#c084fc", "#9333ea"),
      hue("orange", "#fb923c", "#ea580c"),
      hue("cyan", "#22d3ee", "#0891b2"),
      hue("yellow", "#facc15", "#ca8a04"),
      hue("red", "#f87171", "#dc2626")
    ]
    function personHue(key) { return people[Contacts.hueIndex(key, people.length)] }
  }

  readonly property var glyphs: ({
    search: KG.search,
    people: String.fromCodePoint(0xF0849),   // md-account_group
    person: String.fromCodePoint(0xF0013),   // md-account_outline
    plus: KG.plus,
    remove: KG.remove,
    check: KG.check,
    close: KG.close
  })

  actions: Component {
    Row {
      spacing: 2
      IconButton {
        app: root
        glyph: KG.plus
        label: "A new contact"
        onClicked: root.startNew()
      }
    }
  }

  settings: Component {
    SettingsPage {
      app: root
      blurb: "A name, a number, an email and a note, in one file, with no accounts behind it."
      AppearanceSection { app: root }
      LauncherSection { app: root }
      KeysSection {
        app: root
        keys: [
          ["/", "Search"],
          ["↑ ↓  Enter", "Move through the list, open a contact"],
          ["n", "A new contact"],
          ["e", "Edit the contact in the pane"],
          ["Enter", "Save, in a field"],
          ["Delete", "Delete the contact, after asking"],
          [",", "Settings"],
          ["Esc", "Back one step"]
        ]
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Where it keeps them"
        note: "~/.local/share/moarchy-contacts/contacts.json, in name order, legible to a person with a text editor and to jq. Mail reads it for addresses. Nothing syncs and nothing leaves this computer."
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "What it does not do"
        note: "No sync, no CardDAV, no vCard import, no photos, no groups. Nobody is dialled from here: it is a book, not a phone."
      }
    }
  }

  // A person, over the list, on a phone.
  page: Component { ContactEditor { app: root; paged: true } }

  // ------------------------------------------------------------ the book

  property var contacts: []
  // Rows in the file this app cannot draw, written back as they were found.
  property var strays: []
  property bool loaded: false

  readonly property var shown: Contacts.filtered(contacts, list.query)

  // The person being edited, a copy, or null.
  property var draft: null
  property bool draftIsNew: false

  // The pane, on a desktop wide enough for the list and a person.
  readonly property bool split: contentArea.width >= 780
  // The keyboard's place in the shown list.
  property int current: -1

  function save() { file.save(S.serialize(contacts, strays) + "\n") }

  function openEditor(c, isNew) {
    draft = Contacts.copy(c)
    draftIsNew = !!isNew
    if (!split && !topPage) push({ kind: "contact" })
  }

  function open_(id) {
    var c = Contacts.find(contacts, id)
    if (!c) return
    resetFocus()
    var i = indexIn(shown, id)
    if (i >= 0) current = i
    openEditor(c, false)
  }

  function startNew() {
    resetFocus()
    current = -1
    openEditor(Contacts.blank(Date.now()), true)
  }

  function closeEditor() {
    draft = null
    draftIsNew = false
    if (topPage) pop()
    resetFocus()
  }

  function commit(fields) {
    if (Contacts.isEmpty(fields)) {
      toast("A contact needs something on it")
      return
    }
    var c = Contacts.normalise(fields, Date.now())
    contacts = Contacts.withContact(contacts, c)
    save()
    var wasNew = draftIsNew
    // A desktop keeps the person in the pane, saved; a phone goes back to
    // the book, where they now are.
    if (split) {
      draft = Contacts.copy(c)
      draftIsNew = false
      var i = indexIn(shown, c.id)
      if (i >= 0) { current = i; list.show(i) }
    } else {
      closeEditor()
    }
    resetFocus()
    toast(wasNew ? "Added" : "Saved")
  }

  function askDelete(id) {
    var c = Contacts.find(contacts, id)
    if (c) confirmDelete.open(c)
  }

  function remove(id) {
    var c = Contacts.find(contacts, id)
    if (!c) return
    contacts = Contacts.without(contacts, id)
    save()
    if (draft && draft.id === id) closeEditor()
    current = Math.min(current, shown.length - 1)
    toast("Deleted " + (c.name || c.phone || c.email || "a contact"), "Undo", function () {
      root.contacts = Contacts.withContact(root.contacts, c)
      root.save()
    })
  }

  function indexIn(items, id) {
    for (var i = 0; i < items.length; i++) if (items[i].id === id) return i
    return -1
  }

  Dialog {
    id: confirmDelete
    app: root
    readonly property var who: subject || ({ name: "" })
    title: "Delete " + (who.name || who.phone || who.email || "this contact") + "?"
    text: "They go from the book, and from Mail's suggestions."
    acceptText: "Delete"
    acceptGlyph: KG.remove
    destructive: true
    onAccepted: root.remove(who.id)
  }

  // A window that narrows with a person in the pane shows them as a page,
  // and one that widens with a page up shows them in the pane.
  onSplitChanged: {
    if (!draft) return
    if (!split && !topPage) push({ kind: "contact" })
    else if (split && topPage) stack = []
  }

  // Before closing: the search, then the pane.
  stepBack: function () {
    if (list.query !== "") { list.query = ""; return true }
    if (draft && split) { closeEditor(); return true }
    return false
  }
  // A page popped by Back leaves no draft behind it.
  onStackChanged: if (!stack.length && !split && draft) { draft = null; draftIsNew = false }

  keyHandler: function (event) {
    if (topPage || inSettings) return
    var k = event.key
    var n = shown.length
    if (k === Qt.Key_Down || k === Qt.Key_Up) {
      if (!n) return
      current = Math.max(0, Math.min(n - 1, current + (k === Qt.Key_Down ? 1 : -1)))
      list.show(current)
      if (split && draft && !draftIsNew) open_(shown[current].id)
      event.accepted = true
      return
    }
    if ((k === Qt.Key_Return || k === Qt.Key_Enter) && current >= 0 && current < n) {
      open_(shown[current].id)
      event.accepted = true
      return
    }
    if (k === Qt.Key_Delete) {
      var id = draft && !draftIsNew ? draft.id : (current >= 0 && current < n ? shown[current].id : "")
      if (id) askDelete(id)
      event.accepted = true
      return
    }
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    if (event.text === "/") { Qt.callLater(list.focusField); event.accepted = true; return }
    if (event.text === "n") { startNew(); event.accepted = true; return }
    if (event.text === "e") {
      if (!draft && current >= 0 && current < n) open_(shown[current].id)
      if (draft && split) Qt.callLater(function () { var e = pane.item as ContactEditor; if (e) e.focusName() })
      event.accepted = true
    }
  }

  // ------------------------------------------------------------ the file

  DataFile {
    id: file
    app: "contacts"
    name: "contacts.json"
    onParsed: function (data) {
      var state = S.parse(data)
      root.contacts = state.contacts
      root.strays = state.strays
      root.loaded = true
      root.harness()
    }
    onQuarantined: function (to) { root.toast("The contacts file was unreadable and was kept aside") }
  }

  onOpenedChanged: if (!opened) { draft = null; draftIsNew = false; current = -1 }

  // MOARCHY_CONTACTS_PAGE=editor or _NEW: a new contact. _EDIT=<name or id>:
  // that person. _SEARCH: a query. For the screenshots.
  property bool harnessed: false
  function harness() {
    if (harnessed) return
    harnessed = true
    var search = Quickshell.env("MOARCHY_CONTACTS_SEARCH") || ""
    if (search) list.query = search
    var want = Quickshell.env("MOARCHY_CONTACTS_EDIT") || ""
    var fresh = (Quickshell.env("MOARCHY_CONTACTS_PAGE") || "") === "editor" || (Quickshell.env("MOARCHY_CONTACTS_NEW") || "") !== ""
    // The width is not known in the first frame.
    Qt.callLater(function () {
      if (fresh) { root.startNew(); return }
      for (var i = 0; want && i < root.contacts.length; i++)
        if (root.contacts[i].name === want || root.contacts[i].id === want) { root.open_(root.contacts[i].id); return }
    })
  }

  IpcHandler {
    target: "contacts"
    function add(json: string): string {
      var raw
      try { raw = JSON.parse(String(json || "")) } catch (e) { return "not JSON: " + e }
      var c = Contacts.normalise(raw, Date.now())
      if (c === null) return "a contact needs a name, phone, email or note"
      root.contacts = Contacts.withContact(root.contacts, c)
      root.save()
      return c.id
    }
    function remove(id: string): string {
      if (!Contacts.find(root.contacts, id)) return "no such contact: " + id
      root.contacts = Contacts.without(root.contacts, String(id))
      root.save()
      return "ok"
    }
    function count(): int { return root.contacts.length }
    function close(): string { root.dismiss(); return "ok" }
  }

  // ------------------------------------------------------------ views

  Item {
    anchors.fill: parent

    ContactList {
      id: list
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: root.split ? Math.min(440, Math.max(340, parent.width * 0.42)) : parent.width
      app: root
      items: root.shown
      loaded: root.loaded
      total: root.contacts.length
      selectedId: root.split && root.draft ? root.draft.id : ""
      current: root.current
      onQueryChanged: { root.current = -1; toTop() }
      onOpened: function (id) { root.open_(id) }
    }

    // The pane: a person, or what to do to see one.
    Rectangle {
      visible: root.split
      anchors.left: list.right
      anchors.leftMargin: 8
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.rightMargin: root.ui.gutter
      anchors.bottomMargin: root.ui.gutter
      radius: root.ui.radius
      color: root.ui.surface
      border.width: 1
      border.color: root.ui.line

      Loader {
        id: pane
        anchors.fill: parent
        active: root.split && root.draft !== null
        sourceComponent: ContactEditor { app: root; paged: false }
      }
      EmptyState {
        anchors.centerIn: parent
        visible: !pane.active
        app: root
        glyph: root.glyphs.person
        title: root.contacts.length ? "Nobody picked" : "An empty book"
        text: root.contacts.length ? "Pick somebody on the left, or press n for somebody new."
          : "Press n, or the plus, for the first person in it."
      }
    }
  }
}
