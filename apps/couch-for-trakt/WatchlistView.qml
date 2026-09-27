import QtQuick
import "Api.mjs" as Api
import "Glyphs.js" as G

// What you want to watch, movies or shows, most recently added first.
Item {
  id: root
  property var app

  readonly property bool signedIn: app.trakt.signedIn
  readonly property string type: app.store.prefs.watchlistType === "show" ? "show" : "movie"
  readonly property var urlOf: app.library.watchlistUrlOf(type)
  readonly property string url: Api.watchlistUrl(type, 1)
  property string sort: "added"

  readonly property var raw: { app.trakt.revision; return app.library.watchlist(type) }
  // What was just taken off shows as gone at once, not after the refetch.
  readonly property var items: {
    app.library.rev
    var r = raw.filter(function (m) { return root.app.library.inWatchlist(m) })
    if (sort === "title") r.sort(function (a, b) { return a.title.localeCompare(b.title) })
    else if (sort === "rating") r.sort(function (a, b) { return (b.rating || 0) - (a.rating || 0) })
    else if (sort === "released") r.sort(function (a, b) { return a.released < b.released ? 1 : a.released > b.released ? -1 : 0 })
    return r
  }
  readonly property bool loading: { app.trakt.revision; return app.trakt.busy(url) }
  readonly property string error: { app.trakt.revision; return app.trakt.error(url) }

  function refresh(force) { if (signedIn) app.library.wantAll(urlOf, "watchlist", force ? 0 : 600000, force) }
  onUrlChanged: if (visible) refresh(false)

  property alias list: grid

  Component {
    id: top
    Column {
      width: parent ? parent.width : 0
      spacing: 10
      bottomPadding: 12
      visible: root.signedIn
      Flickable {
        width: parent.width
        height: root.app.ui.chip
        contentWidth: chipRow.implicitWidth + grid.pad * 2
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        Row {
          id: chipRow
          x: grid.pad
          spacing: 6
          Repeater {
            model: [{ k: "movie", l: "Movies", g: G.movie }, { k: "show", l: "Shows", g: G.tv }]
            delegate: Chip {
              required property var modelData
              app: root.app
              glyph: modelData.g
              text: modelData.l
              selected: root.type === modelData.k
              onClicked: { root.app.store.set("watchlistType", modelData.k); grid.toTop() }
            }
          }
          Rectangle { width: 1; height: parent.height - 12; anchors.verticalCenter: parent.verticalCenter; color: root.app.ui.divider }
          Repeater {
            model: [{ k: "added", l: "Recently added" }, { k: "released", l: "Newest" }, { k: "rating", l: "Top rated" }, { k: "title", l: "A–Z" }]
            delegate: Chip {
              required property var modelData
              app: root.app
              hpad: 20
              text: modelData.l
              selected: root.sort === modelData.k
              onClicked: { root.sort = modelData.k; grid.toTop() }
            }
          }
        }
      }
      Text {
        x: grid.pad
        visible: root.items.length > 0
        text: root.items.length + (root.type === "show" ? (root.items.length === 1 ? " show" : " shows") : (root.items.length === 1 ? " movie" : " movies"))
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
      }
    }
  }

  PosterGrid {
    id: grid
    anchors.fill: parent
    app: root.app
    items: root.signedIn ? root.items : []
    loading: root.loading
    error: root.items.length ? "" : root.error
    topContent: top
    emptyGlyph: root.signedIn ? G.watchlist : G.login
    emptyTitle: root.signedIn ? "Your watchlist is empty" : "Keep a watchlist across all your devices"
    emptyDetail: root.signedIn ? "Tap the bookmark on any movie or show to save it for later."
      : "Sign in with Trakt to save movies and shows for later."
    emptyAction: root.signedIn ? "Discover something" : "Sign in with Trakt"
    onEmptyTriggered: root.signedIn ? root.app.setTab("discover") : root.app.startSignIn()
    subtitleFor: function (m) {
      if (m.type === "movie" && m.released && new Date(m.released) > new Date()) return "Out " + Api.date(m.released)
      return ""
    }
    onActivated: function (m) { root.app.openMedia(m) }
  }
}
