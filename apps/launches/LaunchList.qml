import QtQuick
import "kit"

// One tab: a search box, then a list of launches or the reason there are
// none. Both tabs are this with a different list handed to it -- upcoming in
// NET order, starred in the order somebody tapped a star -- and a different
// sentence for empty, which is the part that has to be right: a starred page
// that said "no launches" would be reporting a network problem the app does
// not have.
Item {
  id: root
  property var app
  property var items: []
  property var favourites: []
  property string selectedId: ""
  property int current: -1
  property real now: 0
  property string emptyGlyph: ""
  property string emptyTitle: ""
  property string emptyText: ""
  property bool busy: false
  property alias query: search.text
  signal opened(string id)
  signal starToggled(string id)

  function focusField() { search.input.forceActiveFocus() }
  function toTop() { list.positionViewAtBeginning() }
  function show(index) { if (index >= 0) list.positionViewAtIndex(index, ListView.Contain) }

  SearchField {
    id: search
    app: root.app
    x: root.app.ui.gutter
    y: 4
    width: parent.width - root.app.ui.gutter * 2
    placeholder: "Mission, vehicle, pad"
    onEscaped: root.app.resetFocus()
  }

  Keyed { id: keyed; items: root.items }

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
    delegate: LaunchRow {
      required property string key
      required property int index
      width: list.width
      app: root.app
      // Keyed answers {} for a row that is on its way out; that is no launch.
      item: keyed.at(key).id ? keyed.at(key) : null
      now: root.now
      starred: root.favourites.indexOf(key) >= 0
      selected: key === root.selectedId
      current: index === root.current
      onOpened: root.opened(key)
      onStarToggled: root.starToggled(key)
    }
    footer: Item { width: 1; height: 12 }
  }

  EmptyState {
    anchors.centerIn: list
    visible: root.items.length === 0
    app: root.app
    busy: root.busy
    glyph: root.emptyGlyph
    title: root.emptyTitle
    text: root.emptyText
  }
}
