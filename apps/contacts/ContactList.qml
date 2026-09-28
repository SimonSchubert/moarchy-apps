import QtQuick
import "kit"
import "Contacts.js" as Contacts

// The book: a search box, then every contact that matches, filed under the
// letter of its name. The letters are rows in the same list rather than
// boxes around it, so the keyboard and the scroll position are one list.
Item {
  id: root
  property var app
  // Contacts, sorted and already filtered.
  property var items: []
  property string selectedId: ""
  // The keyboard's place, as an index into `items`.
  property int current: -1
  property bool loaded: false
  property int total: 0
  property alias query: search.text
  signal opened(string id)

  function focusField() { search.input.forceActiveFocus() }
  function toTop() { list.positionViewAtBeginning() }
  function show(index) {
    if (index < 0 || index >= items.length) return
    var at = rowOf[items[index].id]
    if (at !== undefined) list.positionViewAtIndex(at, ListView.Contain)
  }

  // Letters and people in one flat list: { key, letter } or { key, id }.
  readonly property var rows: {
    var out = []
    var groups = Contacts.sections(items)
    for (var i = 0; i < groups.length; i++) {
      out.push({ key: "letter:" + groups[i].letter, letter: groups[i].letter })
      for (var j = 0; j < groups[i].contacts.length; j++) {
        var c = groups[i].contacts[j]
        out.push({ key: c.id, id: c.id, contact: c })
      }
    }
    return out
  }
  readonly property var rowOf: {
    var out = ({})
    for (var i = 0; i < rows.length; i++) if (rows[i].id) out[rows[i].id] = i
    return out
  }
  readonly property string currentId: current >= 0 && current < items.length ? items[current].id : ""

  SearchField {
    id: search
    app: root.app
    x: root.app.ui.gutter
    y: 4
    width: parent.width - root.app.ui.gutter * 2
    placeholder: "Name, number, email or note"
    onEscaped: root.app.resetFocus()
  }

  Keyed { id: keyed; items: root.rows }

  ListView {
    id: list
    anchors.top: search.bottom
    anchors.topMargin: 8
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: root.app.compact ? 4 : root.app.ui.gutter - 8
    anchors.rightMargin: anchors.leftMargin
    clip: true
    spacing: 2
    boundsBehavior: Flickable.StopAtBounds
    model: keyed
    delegate: Loader {
      id: slot
      required property string key
      readonly property var row: keyed.at(key)
      width: list.width
      sourceComponent: row.letter ? letterRow : contactRow

      Component {
        id: letterRow
        Text {
          topPadding: 12
          bottomPadding: 4
          leftPadding: 12
          text: slot.row.letter || ""
          color: root.app.ui.accent
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
          font.weight: Font.Bold
        }
      }
      Component {
        id: contactRow
        ContactRow {
          app: root.app
          contact: slot.row.contact || null
          selected: slot.key === root.selectedId
          current: slot.key === root.currentId
          onClicked: root.opened(slot.key)
        }
      }
    }
    footer: Item { width: 1; height: 16 + root.app.bottomInset }
  }

  EmptyState {
    anchors.centerIn: list
    visible: root.loaded && root.items.length === 0
    app: root.app
    glyph: root.query !== "" ? root.app.glyphs.search : root.app.glyphs.people
    title: root.query !== "" ? "Nothing matches" : "No contacts yet"
    text: root.query !== "" ? "Nobody here has “" + root.query + "” in their name, number, email or note."
      : "Add somebody with the plus, and they are kept in one file on this computer."
  }
}
