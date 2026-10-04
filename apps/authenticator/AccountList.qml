import QtQuick
import "kit"

// Every account, in label order: one column on a phone, as many as fit on a
// desktop, with a search box over them once there are enough to need one.
Item {
  id: root
  property var app
  // Accounts, sorted and already filtered.
  property var items: []
  // The keyboard's place, as an index into `items`.
  property int current: -1
  property bool loaded: false
  property int total: 0
  property alias query: search.text
  signal copied(string id)
  signal edited(string id)

  function focusField() { search.input.forceActiveFocus() }
  function toTop() { grid.positionViewAtBeginning() }
  function show(index) { if (index >= 0 && index < items.length) grid.positionViewAtIndex(index, GridView.Contain) }

  // Columns of at least 340 px, so a code never shares a line it is too
  // narrow for.
  readonly property int columns: Math.max(1, Math.floor((grid.width + 8) / 348))
  readonly property string currentId: current >= 0 && current < items.length ? items[current].id : ""
  readonly property bool searching: total > 5 || query !== ""

  SearchField {
    id: search
    app: root.app
    visible: root.searching
    x: root.app.ui.gutter
    y: 4
    width: Math.min(parent.width - root.app.ui.gutter * 2, 720)
    height: visible ? implicitHeight : 0
    placeholder: "Issuer or account"
    onEscaped: root.app.resetFocus()
  }

  Keyed { id: keyed; items: root.items }

  GridView {
    id: grid
    anchors.top: search.bottom
    anchors.topMargin: root.searching ? 8 : 4
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: root.app.compact ? 4 : root.app.ui.gutter - 4
    anchors.rightMargin: anchors.leftMargin
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    cellWidth: Math.floor(width / root.columns)
    cellHeight: root.app.compact ? 82 : 94
    model: keyed
    delegate: Item {
      id: cell
      required property string key
      readonly property var account: keyed.at(key)
      width: grid.cellWidth
      height: grid.cellHeight
      AccountRow {
        anchors.fill: parent
        anchors.margins: root.app.compact ? 1 : 4
        app: root.app
        account: cell.account
        current: cell.key === root.currentId
        hidden: root.app.hideCodes && root.app.revealedId !== cell.key
        onClicked: root.copied(cell.key)
        onEdit: root.edited(cell.key)
      }
    }
    footer: Item { width: 1; height: 16 + root.app.bottomInset }
  }

  EmptyState {
    anchors.centerIn: grid
    width: Math.min(parent.width - 48, 420)
    visible: root.loaded && root.items.length === 0
    app: root.app
    glyph: root.query !== "" ? root.app.glyphs.search : root.app.glyphs.shieldKey
    title: root.query !== "" ? "Nothing matches" : "No accounts yet"
    text: root.query !== "" ? "No account here has “" + root.query + "” in its issuer or name."
      : "When a site turns on two-factor sign-in it shows a QR code and a key. Add it here, and the six digits it asks for are one tap away."
    actionText: root.query !== "" ? "" : "Add an account"
    onAction: root.app.startNew()
  }
}
