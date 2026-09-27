import QtQuick
import "Glyphs.js" as G

// The stations you starred, kept on this computer: they open offline, and
// the directory is not told.
Item {
  id: root
  property var app
  property string sort: "added"

  readonly property var items: {
    var f = app.store.favorites.slice()
    if (sort === "name") f.sort(function (a, b) { return a.name.localeCompare(b.name) })
    else if (sort === "country") f.sort(function (a, b) { return (a.country || "~").localeCompare(b.country || "~") || a.name.localeCompare(b.name) })
    return f
  }

  function refresh(force) {}

  property alias list: stations

  Component {
    id: top
    Row {
      x: stations.pad + 10
      spacing: 6
      bottomPadding: 10
      visible: root.items.length > 1
      height: visible ? implicitHeight : 0
      Repeater {
        model: [{ k: "added", l: "Recently added" }, { k: "name", l: "A–Z" }, { k: "country", l: "Country" }]
        delegate: Chip {
          required property var modelData
          app: root.app
          text: modelData.l
          selected: root.sort === modelData.k
          onClicked: root.sort = modelData.k
        }
      }
    }
  }

  StationList {
    id: stations
    anchors.fill: parent
    app: root.app
    items: root.items
    topContent: top
    emptyGlyph: G.starOutline
    emptyTitle: "No favourites yet"
    emptyDetail: "Tap the star beside any station to keep it here."
    emptyAction: "Discover stations"
    onEmptyTriggered: root.app.setTab("discover")
    onActivated: function (s) { root.app.activate(s) }
  }
}
