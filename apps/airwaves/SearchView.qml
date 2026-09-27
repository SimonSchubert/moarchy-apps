import QtQuick
import "Api.mjs" as Api
import "Glyphs.js" as G

// Any station in the directory, by its name or by a genre it is tagged with.
Item {
  id: root
  property var app
  property string query: ""
  property string by: "name"

  readonly property string trimmed: query.trim()
  property string asked: ""
  readonly property int maxPages: 5
  property int loaded: 1

  function path(page) {
    if (asked.length < 2) return ""
    return Api.stationsPath(by === "tag" ? { tagLike: asked.toLowerCase() } : { name: asked }, "clickcount", page)
  }
  readonly property string first: path(0)

  readonly property var results: {
    app.api.revision
    if (!first) return []
    var out = []
    var seen = {}
    for (var p = 0; p < loaded; p++) {
      var d = app.api.peek(path(p))
      if (!d) break
      for (var i = 0; i < d.length; i++) if (!seen[d[i].id]) { seen[d[i].id] = true; out.push(d[i]) }
    }
    return out
  }
  readonly property bool lastFull: { app.api.revision; var d = first ? app.api.peek(path(loaded - 1)) : null; return !!d && d.length >= Api.PAGE }
  readonly property bool loading: { app.api.revision; return !!trimmed && (debounce.running || app.api.busy(first) || app.api.busy(path(loaded - 1))) }
  readonly property string error: { app.api.revision; return first ? app.api.error(first) : "" }

  function refresh(force) {
    if (first) app.api.want(first, "stations", force ? 0 : 3600000, true)
    app.api.want(Api.tagsPath(), "tags", 86400000, false)
  }
  function focusField() { field.forceActiveFocus() }

  property alias list: stations
  function more() {
    if (!lastFull || loaded >= maxPages) return
    loaded++
    app.api.want(path(loaded - 1), "stations", 3600000, false)
  }

  onQueryChanged: debounce.restart()
  onFirstChanged: { loaded = 1; refresh(false) }
  Timer { id: debounce; interval: 380; onTriggered: root.asked = root.trimmed }

  // Nothing typed yet: the biggest genres, one tap away.
  readonly property var popularTags: { app.api.revision; return (app.api.peek(Api.tagsPath()) || []).slice(0, 36) }

  Column {
    id: bar
    width: parent.width
    topPadding: 4
    spacing: 10

    Rectangle {
      x: stations.pad + 4
      width: Math.min(parent.width - x * 2, 720)
      height: 46
      radius: 23
      color: root.app.ui.surface
      border.width: 1
      border.color: field.activeFocus ? root.app.ui.accent : root.app.ui.border

      Icon {
        id: lens
        app: root.app
        x: 10
        anchors.verticalCenter: parent.verticalCenter
        text: G.search
        color: root.app.ui.muted
      }
      TextInput {
        id: field
        anchors.left: lens.right
        anchors.leftMargin: 4
        anchors.right: clearBtn.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        verticalAlignment: TextInput.AlignVCenter
        text: root.query
        onTextEdited: root.query = text
        color: root.app.ui.text
        selectionColor: root.app.ui.accent
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.md
        clip: true
        inputMethodHints: Qt.ImhNoPredictiveText
        Keys.onEscapePressed: function (event) {
          if (root.query) { root.query = ""; event.accepted = true }
          else { root.app.resetFocus(); event.accepted = false }
        }
        Keys.onReturnPressed: { debounce.stop(); root.asked = root.trimmed; if (root.results.length) root.app.activate(root.results[0]) }
        Keys.onDownPressed: { root.app.resetFocus(); stations.move(0, 0) }

        Text {
          anchors.fill: parent
          verticalAlignment: Text.AlignVCenter
          visible: !field.text
          text: root.by === "tag" ? "A genre, like jazz or lo-fi" : "A station's name"
          color: root.app.ui.muted
          font: field.font
        }
      }
      IconButton {
        id: clearBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: root.query !== ""
        width: visible ? implicitWidth : 10
        app: root.app
        glyph: G.close
        label: "Clear search"
        size: 16
        onClicked: { root.query = ""; root.asked = ""; field.forceActiveFocus() }
      }
    }

    Row {
      x: stations.pad + 4
      spacing: 6
      Repeater {
        model: [{ k: "name", l: "Stations", g: G.radio }, { k: "tag", l: "Genre", g: G.tag }]
        delegate: Chip {
          required property var modelData
          app: root.app
          glyph: modelData.g
          text: modelData.l
          selected: root.by === modelData.k
          onClicked: root.by = modelData.k
        }
      }
    }

    Text {
      x: stations.pad + 6
      visible: text !== ""
      text: root.first ? (root.loading && !root.results.length ? "Searching…"
        : root.results.length + (root.lastFull ? "+" : "") + (root.results.length === 1 ? " station" : " stations")) : ""
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
      font.weight: Font.DemiBold
    }
  }

  // Before anything is typed.
  Flickable {
    anchors.top: bar.bottom
    anchors.topMargin: 16
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    visible: !root.first
    contentHeight: tagCol.implicitHeight + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    Column {
      id: tagCol
      x: stations.pad + 4
      width: Math.min(parent.width - x * 2, 900)
      spacing: 12
      Text {
        text: "Popular genres"
        color: root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.lg
        font.weight: Font.Bold
      }
      Flow {
        width: parent.width
        spacing: 8
        Repeater {
          model: root.popularTags
          delegate: Chip {
            required property var modelData
            app: root.app
            text: modelData.name
            hpad: 22
            tint: Qt.hsla(modelData.hue / 360, 0.6, root.app.ui.dark ? 0.62 : 0.42, 1)
            onClicked: root.app.openList({ facet: "tag", value: modelData.key, label: modelData.name })
          }
        }
      }
    }
  }

  StationList {
    id: stations
    anchors.top: bar.bottom
    anchors.topMargin: 10
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    visible: root.first !== ""
    app: root.app
    items: root.results
    loading: root.loading
    error: root.error
    more: root.lastFull && root.loaded < root.maxPages
    emptyGlyph: G.search
    emptyTitle: "Nothing matches “" + root.asked + "”"
    emptyDetail: root.by === "name" ? "Try part of the name, or search by genre instead." : "Try a broader genre, like rock or news."
    onEndReached: root.more()
    onActivated: function (s) { root.app.activate(s) }
  }
}
