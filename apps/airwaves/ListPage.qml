import QtQuick
import "Api.mjs" as Api
import "Glyphs.js" as G

// Every station of a genre, a country or a language -- or of the whole
// directory -- in the order the chips pick, loading more as it scrolls. A
// page over the current tab, with its own way back.
Item {
  id: root
  property var app
  // { facet: "tag" | "country" | "language" | "all", value, label, order }
  property var spec: ({})

  readonly property int maxPages: 12
  property int loaded: 1
  property string order: spec.order || app.store.prefs.order || "clickcount"

  readonly property var filter: {
    var f = {}
    if (spec.facet === "tag") f.tag = spec.value
    else if (spec.facet === "country") f.country = spec.value
    else if (spec.facet === "language") f.language = spec.value
    return f
  }

  function path(page) { return Api.stationsPath(filter, order, page) }

  readonly property var items: {
    app.api.revision
    var out = []
    var seen = {}
    for (var p = 0; p < loaded; p++) {
      var d = app.api.peek(path(p))
      if (!d) break
      for (var i = 0; i < d.length; i++) if (!seen[d[i].id]) { seen[d[i].id] = true; out.push(d[i]) }
    }
    return out
  }
  readonly property bool lastFull: { app.api.revision; var d = app.api.peek(path(loaded - 1)); return !!d && d.length >= Api.PAGE }
  readonly property bool loading: { app.api.revision; return app.api.busy(path(loaded - 1)) || app.api.busy(path(0)) }
  readonly property string error: { app.api.revision; return app.api.error(path(0)) }

  // How many stations there are, from the list the facet came from.
  readonly property int total: {
    app.api.revision
    var src = spec.facet === "tag" ? Api.tagsPath() : spec.facet === "country" ? Api.countriesPath()
      : spec.facet === "language" ? Api.languagesPath() : ""
    var list = src ? app.api.peek(src) || [] : []
    for (var i = 0; i < list.length; i++) if (list[i].key === spec.value) return list[i].count
    return 0
  }

  function refresh(force) {
    app.api.want(path(0), "stations", force ? 0 : 1800000, true)
    for (var p = 1; p < loaded; p++) app.api.want(path(p), "stations", force ? 0 : 1800000, false)
  }

  function more() {
    if (!lastFull || loaded >= maxPages) return
    loaded++
    app.api.want(path(loaded - 1), "stations", 1800000, false)
  }

  function choose(o) {
    order = o
    if (!spec.order) app.store.set("order", o)
    loaded = 1
    restart.restart()
  }

  Component.onCompleted: refresh(false)
  // The Loader keeps this page when one list replaces another. (And empties
  // it on the way out, which is not a list to load.)
  onSpecChanged: {
    if (!spec || !spec.facet) return
    order = spec.order || app.store.prefs.order || "clickcount"
    loaded = 1
    restart.restart()
  }
  // A Timer rather than Qt.callLater: it goes with the page, and a call
  // queued by a page that has closed has nothing left to call.
  Timer {
    id: restart
    interval: 0
    onTriggered: { root.refresh(false); stations.toTop() }
  }

  property alias list: stations

  Rectangle { anchors.fill: parent; color: root.app.ui.bg }

  Item {
    id: header
    width: parent.width
    height: root.app.compact ? 56 : 64
    IconButton {
      id: backBtn
      x: 4
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      glyph: G.back
      label: "Back"
      onClicked: root.app.back()
    }
    Column {
      anchors.left: backBtn.right
      anchors.leftMargin: 4
      anchors.right: parent.right
      anchors.rightMargin: 16
      anchors.verticalCenter: parent.verticalCenter
      Text {
        width: parent.width
        text: root.spec.facet === "tag" ? root.spec.label.charAt(0).toUpperCase() + root.spec.label.slice(1) : root.spec.label || ""
        color: root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: root.app.compact ? 20 : 22
        font.weight: Font.Bold
        elide: Text.ElideRight
      }
      Text {
        visible: text !== ""
        width: parent.width
        text: root.total ? Api.group(root.total) + " stations" + (root.spec.facet === "tag" ? " tagged " + root.spec.value : "")
          : root.spec.facet === "all" ? "From the whole directory" : ""
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
        elide: Text.ElideRight
      }
    }
  }

  Flickable {
    id: chipRow
    anchors.top: header.bottom
    width: parent.width
    height: root.app.ui.chip
    contentWidth: chips.implicitWidth + 32
    flickableDirection: Flickable.HorizontalFlick
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    Row {
      id: chips
      x: 16
      spacing: 6
      Repeater {
        model: Api.ORDERS
        delegate: Chip {
          required property var modelData
          app: root.app
          text: modelData.label
          selected: root.order === modelData.key
          onClicked: root.choose(modelData.key)
        }
      }
    }
  }

  StationList {
    id: stations
    anchors.top: chipRow.bottom
    anchors.topMargin: 10
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    app: root.app
    items: root.items
    loading: root.loading
    error: root.items.length ? "" : root.error
    more: root.lastFull && root.loaded < root.maxPages
    emptyGlyph: G.radio
    emptyTitle: "No working stations here"
    emptyDetail: "The directory has none that passed its last check."
    onEndReached: root.more()
    onActivated: function (s) { root.app.activate(s) }
  }
}
