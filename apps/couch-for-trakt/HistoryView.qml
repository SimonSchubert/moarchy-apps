import QtQuick
import "Api.mjs" as Api
import "Glyphs.js" as G

// Everything you marked watched, newest first.
Item {
  id: root
  property var app

  property int loaded: 1
  readonly property bool signedIn: app.trakt.signedIn

  readonly property var rows: {
    app.trakt.revision
    var out = []
    for (var p = 1; p <= loaded; p++) {
      var d = app.trakt.peek(Api.historyUrl(p))
      if (!d) break
      out = out.concat(d)
    }
    return out
  }
  readonly property int pageCount: { app.trakt.revision; return app.trakt.pages(Api.historyUrl(1)) }
  readonly property bool loading: { app.trakt.revision; return app.trakt.busy(Api.historyUrl(loaded)) }
  readonly property string error: { app.trakt.revision; return app.trakt.error(Api.historyUrl(1)) }

  function refresh(force) {
    if (!signedIn) return
    for (var p = 1; p <= loaded; p++) app.trakt.want(Api.historyUrl(p), "history", force ? 0 : 300000, force && p === 1)
  }
  function more() {
    if (loaded >= pageCount || loaded >= 25 || !app.trakt.peek(Api.historyUrl(loaded))) return
    loaded++
    refresh(false)
  }
  onSignedInChanged: loaded = 1

  property alias list: days

  DayList {
    id: days
    anchors.fill: parent
    app: root.app
    rows: root.signedIn ? root.rows : []
    loading: root.loading
    error: root.rows.length ? "" : root.error
    more: root.loaded < root.pageCount && root.loaded < 25
    emptyGlyph: root.signedIn ? G.history : G.login
    emptyTitle: root.signedIn ? "Nothing watched yet" : "Your watch history lives on Trakt"
    emptyDetail: root.signedIn ? "Movies and episodes you mark watched appear here." : "Sign in to see everything you've watched."
    emptyAction: root.signedIn ? "" : "Sign in with Trakt"
    onEmptyTriggered: root.app.startSignIn()
    onEndReached: root.more()
    leadFor: function (r) { return Api.time(r.at) }
    noteFor: function (r) { return root.app.compact ? "" : Api.ago(r.at, root.app.clock) }
  }
}
