import QtQuick
import "kit"
import "Countries.js" as C

// The world as a wall of flags: a search, the regions, an order, and the
// grid. Two columns on a phone and as many as fit on a desktop.
Item {
  id: root
  property var app
  property var items: []
  property var regions: []
  property string region: "all"
  property string sort: "name"
  property string selectedCode: ""
  property int current: -1
  property string emptyGlyph: ""
  property string emptyTitle: ""
  property string emptyText: ""
  property bool busy: false
  // False before the first fetch: no regions to pick and nothing to sort.
  property bool hasWorld: true
  property alias query: search.text
  signal opened(string code)
  signal regionPicked(string region)
  signal sortPicked(string sort)

  function focusField() { search.input.forceActiveFocus() }
  function toTop() { grid.positionViewAtBeginning() }
  function show(index) { if (index >= 0) grid.positionViewAtIndex(index, GridView.Contain) }
  readonly property int columns: grid.columns

  readonly property int side: app.compact ? 12 : app.ui.gutter

  SearchField {
    id: search
    app: root.app
    x: root.side
    y: 4
    width: parent.width - root.side * 2
    placeholder: "Country, capital or code"
    onEscaped: root.app.resetFocus()
  }

  // The regions, in a strip that scrolls sideways when a phone is too narrow
  // for six of them.
  Flickable {
    id: strip
    anchors.top: search.bottom
    anchors.topMargin: 10
    x: root.side
    width: parent.width - root.side * 2
    height: root.hasWorld ? root.app.ui.chip : 0
    visible: root.hasWorld
    contentWidth: chips.implicitWidth
    contentHeight: height
    flickableDirection: Flickable.HorizontalFlick
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    Row {
      id: chips
      spacing: 6
      Chip {
        app: root.app
        text: "All"
        selected: root.region === "all"
        onClicked: root.regionPicked("all")
      }
      Repeater {
        model: root.regions
        delegate: Chip {
          required property string modelData
          app: root.app
          text: modelData
          selected: root.region === modelData
          onClicked: root.regionPicked(modelData)
        }
      }
    }
  }

  Item {
    id: bar
    anchors.top: strip.bottom
    anchors.topMargin: 8
    x: root.side
    width: parent.width - root.side * 2
    height: root.hasWorld ? 32 : 0
    visible: root.hasWorld
    SectionTitle {
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      text: root.region === "all" ? "World" : root.region
      note: root.items.length === 1 ? "1 country" : root.items.length + " countries"
    }
    Row {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: 4
      Repeater {
        model: [{ k: "name", l: "A–Z" }, { k: "population", l: "People" }, { k: "area", l: "Area" }]
        delegate: Chip {
          required property var modelData
          app: root.app
          hpad: 14
          implicitHeight: 28
          text: modelData.l
          selected: root.sort === modelData.k
          onClicked: root.sortPicked(modelData.k)
        }
      }
    }
  }

  Keyed { id: keyed; items: root.items }

  GridView {
    id: grid
    anchors.top: bar.bottom
    anchors.topMargin: 8
    anchors.bottom: parent.bottom
    x: root.side - gap / 2
    width: parent.width - root.side * 2 + gap
    readonly property int gap: root.app.compact ? 10 : 14
    readonly property int columns: Math.max(2, Math.floor(width / (root.app.compact ? 160 : 172)))
    cellWidth: Math.floor(width / columns)
    cellHeight: Math.round((cellWidth - gap - (root.app.compact ? 20 : 24)) * 0.62) + (root.app.compact ? 20 : 24) + 50 + gap
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    cacheBuffer: 400
    model: keyed
    delegate: Item {
      id: cell
      required property string key
      required property int index
      width: grid.cellWidth
      height: grid.cellHeight
      CountryCard {
        x: grid.gap / 2
        y: grid.gap / 2
        width: cell.width - grid.gap
        height: cell.height - grid.gap
        app: root.app
        // Keyed answers {} for a row on its way out; that is no country.
        country: keyed.at(cell.key).code ? keyed.at(cell.key) : null
        sort: root.sort
        selected: cell.key === root.selectedCode
        current: cell.index === root.current
        onOpened: root.opened(cell.key)
      }
    }
    footer: Item { width: 1; height: 12 }
  }

  EmptyState {
    anchors.centerIn: grid
    visible: root.items.length === 0
    app: root.app
    busy: root.busy
    glyph: root.emptyGlyph
    title: root.emptyTitle
    text: root.emptyText
  }
}
