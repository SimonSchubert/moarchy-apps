import QtQuick
import "Api.mjs" as Api
import "Glyphs.js" as G

// What airs when: your shows and movies once you are signed in, and the
// season premieres and new shows everyone can see.
Item {
  id: root
  property var app

  readonly property bool signedIn: app.trakt.signedIn
  readonly property var modes: signedIn
    ? [{ k: "shows", l: "My shows" }, { k: "movies", l: "My movies" }, { k: "premieres", l: "Premieres" }, { k: "new", l: "New shows" }]
    : [{ k: "premieres", l: "Premieres" }, { k: "new", l: "New shows" }]
  readonly property string mode: {
    var m = app.store.prefs.calendar
    return modes.some(function (x) { return x.k === m }) ? m : modes[0].k
  }

  // From yesterday, so last night's episode is still there in the morning.
  readonly property string start: { app.clock; var d = new Date(); d.setDate(d.getDate() - 1); return Api.ymd(d) }
  readonly property string url: mode === "shows" ? Api.calendarUrl("my", "shows", start, 15)
    : mode === "movies" ? Api.calendarUrl("my", "movies", start, 60)
    : mode === "premieres" ? Api.calendarUrl("all", "shows/premieres", start, 21)
    : Api.calendarUrl("all", "shows/new", start, 21)

  readonly property var rows: {
    app.trakt.revision
    var r = (app.trakt.peek(url) || []).slice()
    r.sort(function (a, b) { return a.at < b.at ? -1 : a.at > b.at ? 1 : 0 })
    return r
  }
  readonly property bool loading: { app.trakt.revision; return app.trakt.busy(url) }
  readonly property string error: { app.trakt.revision; return app.trakt.error(url) }

  function refresh(force) { app.trakt.want(url, "calendar", force ? 0 : 1800000, force) }
  onUrlChanged: if (visible) refresh(false)

  property alias list: days

  Component {
    id: top
    Column {
      width: parent ? parent.width : 0
      spacing: 10
      bottomPadding: 6
      Flickable {
        width: parent.width
        height: root.app.ui.chip
        contentWidth: chipRow.implicitWidth + 28
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        Row {
          id: chipRow
          x: 14
          spacing: 6
          Repeater {
            model: root.modes
            delegate: Chip {
              required property var modelData
              app: root.app
              text: modelData.l
              selected: root.mode === modelData.k
              onClicked: { root.app.store.set("calendar", modelData.k); days.toTop() }
            }
          }
        }
      }
      // Signed out: a nudge, once, above the public calendar.
      Rectangle {
        visible: !root.signedIn
        x: 14
        width: parent.width - 28
        height: nudge.implicitHeight + 24
        radius: root.app.ui.radius + 2
        color: root.app.ui.accentSoft
        Row {
          id: nudge
          x: 12
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - 24
          spacing: 10
          Icon { anchors.verticalCenter: parent.verticalCenter; app: root.app; text: G.calendar; size: 20; color: root.app.ui.accent }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 150
            text: "Sign in to see when the shows you watch air next."
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
            wrapMode: Text.Wrap
          }
          Button {
            anchors.verticalCenter: parent.verticalCenter
            app: root.app
            text: "Sign in"
            primary: true
            onClicked: root.app.startSignIn()
          }
        }
      }
    }
  }

  DayList {
    id: days
    anchors.fill: parent
    app: root.app
    rows: root.rows
    loading: root.loading
    error: root.rows.length ? "" : root.error
    topContent: top
    dimPast: true
    emptyGlyph: G.calendar
    emptyTitle: root.mode === "shows" ? "Nothing airing in the next two weeks"
      : root.mode === "movies" ? "No releases for your movies in the next two months" : "Nothing scheduled"
    emptyDetail: root.mode === "shows" || root.mode === "movies" ? "Add shows and movies to your watchlist, or watch an episode, and their dates show up here." : ""
    leadFor: function (r) { return r.episode ? Api.time(r.at) : "" }
    noteFor: function (r) {
      if (root.app.compact) return r.media.network || ""
      var parts = []
      if (r.media.network) parts.push(r.media.network)
      var u = Api.until(r.at, root.app.clock)
      if (u) parts.push(u)
      return parts.join("  ·  ")
    }
  }
}
