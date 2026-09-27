import QtQuick
import "Api.mjs" as Api
import "Glyphs.js" as G

// The next episode of every show you are watching, most recent first, with a
// tick to mark it watched right here.
Item {
  id: root
  property var app

  property int loaded: 1
  readonly property bool signedIn: app.trakt.signedIn

  readonly property var items: {
    app.trakt.revision
    var out = []
    for (var p = 1; p <= loaded; p++) {
      var d = app.trakt.peek(Api.upNextUrl(p))
      if (!d) break
      out = out.concat(d)
    }
    return out
  }
  readonly property int pageCount: { app.trakt.revision; return app.trakt.pages(Api.upNextUrl(1)) }
  readonly property bool loading: { app.trakt.revision; return app.trakt.busy(Api.upNextUrl(loaded)) }
  readonly property string error: { app.trakt.revision; return app.trakt.error(Api.upNextUrl(1)) }

  function refresh(force) {
    if (!signedIn) return
    for (var p = 1; p <= loaded; p++) app.trakt.want(Api.upNextUrl(p), "upnext", force ? 0 : 300000, force && p === 1)
  }
  function more() {
    if (loaded >= pageCount || !app.trakt.peek(Api.upNextUrl(loaded))) return
    loaded++
    refresh(false)
  }
  onSignedInChanged: { loaded = 1; if (visible) refresh(false) }

  property alias list: cards

  CardGrid {
    id: cards
    anchors.fill: parent
    app: root.app
    items: root.signedIn ? root.items : []
    loading: root.loading
    error: root.items.length ? "" : root.error
    more: root.loaded < root.pageCount
    emptyGlyph: root.signedIn ? G.upNext : G.login
    emptyTitle: root.signedIn ? "You're all caught up" : "See what's next in every show you watch"
    emptyDetail: root.signedIn ? "Shows you are watching appear here with their next episode."
      : "Sign in with your Trakt account to track episodes, keep a watchlist and see your calendar."
    emptyAction: root.signedIn ? "" : "Sign in with Trakt"
    onEmptyTriggered: root.app.startSignIn()
    onEndReached: root.more()
    onActivated: function (e) { root.app.openMedia(e.show) }
    delegate: EpisodeCard {
      property var modelData
      property int index
      app: root.app
      entry: modelData || ({})
      onActivated: root.app.openMedia(modelData.show)
    }
  }
}
