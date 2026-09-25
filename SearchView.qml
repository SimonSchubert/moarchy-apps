import QtQuick
import "Api.mjs" as Api
import "Glyphs.js" as G

// Any movie or show on Trakt, by title.
Item {
  id: root
  property var app
  property string query: ""
  property string filter: "movie,show"

  readonly property string trimmed: query.trim()
  property string asked: ""
  readonly property string url: asked.length >= 2 ? Api.searchUrl(asked, filter) : ""
  readonly property var results: { app.trakt.revision; return url ? (app.trakt.peek(url) || []) : [] }
  readonly property bool loading: { app.trakt.revision; return !!trimmed && (debounce.running || app.trakt.busy(url)) }
  readonly property string error: { app.trakt.revision; return url ? app.trakt.error(url) : "" }

  // Nothing typed: what is trending, from lists already on hand.
  readonly property var suggestions: {
    app.trakt.revision
    var a = app.trakt.peek(Api.discoverUrl("movie", "trending", 1, 36)) || []
    var b = app.trakt.peek(Api.discoverUrl("show", "trending", 1, 36)) || []
    var out = []
    for (var i = 0; i < 9; i++) { if (a[i]) out.push(a[i]); if (b[i]) out.push(b[i]) }
    return out
  }

  function refresh(force) {
    if (url) app.trakt.want(url, "search", 3600000, true)
    else if (!suggestions.length) {
      app.trakt.want(Api.discoverUrl("movie", "trending", 1, 36), "list", 900000, false)
      app.trakt.want(Api.discoverUrl("show", "trending", 1, 36), "list", 900000, false)
    }
  }
  function focusField() { field.forceActiveFocus() }

  onQueryChanged: debounce.restart()
  onUrlChanged: refresh(false)
  Timer { id: debounce; interval: 380; onTriggered: root.asked = root.trimmed }

  Column {
    id: bar
    width: parent.width
    topPadding: 4
    spacing: 10

    Rectangle {
      x: grid.pad
      width: Math.min(parent.width - grid.pad * 2, 720)
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
          else { field.focus = false; event.accepted = false }
        }
        Keys.onReturnPressed: { debounce.stop(); root.asked = root.trimmed; if (root.results.length) root.app.openMedia(root.results[0]) }
        Keys.onDownPressed: { root.app.resetFocus(); grid.move(0, 0) }

        Text {
          anchors.fill: parent
          verticalAlignment: Text.AlignVCenter
          visible: !field.text
          text: "Movies and shows"
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
      x: grid.pad
      spacing: 6
      Repeater {
        model: [{ k: "movie,show", l: "All" }, { k: "movie", l: "Movies", g: G.movie }, { k: "show", l: "Shows", g: G.tv }]
        delegate: Chip {
          required property var modelData
          app: root.app
          glyph: modelData.g || ""
          text: modelData.l
          selected: root.filter === modelData.k
          onClicked: root.filter = modelData.k
        }
      }
    }

    Text {
      x: grid.pad
      text: root.url ? (root.loading && !root.results.length ? "Searching…" : root.results.length + " results")
        : root.suggestions.length ? "Trending now" : ""
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
      font.weight: Font.DemiBold
    }
  }

  PosterGrid {
    id: grid
    anchors.top: bar.bottom
    anchors.topMargin: 10
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    app: root.app
    items: root.url ? root.results : root.suggestions
    loading: root.loading
    error: root.error
    emptyGlyph: G.search
    emptyTitle: root.url ? "Nothing matches “" + root.asked + "”" : "Type a title"
    emptyDetail: root.url ? "Try fewer words, or the original title." : ""
    subtitleFor: function (m) { return (m.type === "show" ? "Show" : "Movie") + (m.year ? " · " + m.year : "") }
    onActivated: function (m) { root.app.openMedia(m) }
  }

  property alias list: grid
}
