import QtQuick
import "Api.mjs" as Api
import "Glyphs.js" as G

// Where to start: genres as tiles, what is popular where you are, what is
// trending everywhere, and under it the most loved stations in the
// directory, loading more as it scrolls.
Item {
  id: root
  property var app

  readonly property string country: app.country
  readonly property int maxPages: 8
  property int loaded: 1

  function lovedPath(page) { return Api.stationsPath({}, "votes", page) }
  readonly property string localPath: country ? Api.stationsPath({ country: country }, "clickcount", 0) : ""
  readonly property string trendingPath: Api.stationsPath({}, "clicktrend", 0)

  readonly property var items: {
    app.api.revision
    var out = []
    var seen = {}
    for (var p = 0; p < loaded; p++) {
      var d = app.api.peek(lovedPath(p))
      if (!d) break
      for (var i = 0; i < d.length; i++) if (!seen[d[i].id]) { seen[d[i].id] = true; out.push(d[i]) }
    }
    return out
  }
  readonly property var local: { app.api.revision; return localPath ? (app.api.peek(localPath) || []).slice(0, 20) : [] }
  readonly property var trending: { app.api.revision; return (app.api.peek(trendingPath) || []).slice(0, 20) }
  readonly property var stats: { app.api.revision; return app.api.peek(Api.statsPath()) }
  readonly property bool lastFull: { app.api.revision; var d = app.api.peek(lovedPath(loaded - 1)); return !!d && d.length >= Api.PAGE }
  readonly property bool loading: { app.api.revision; return app.api.busy(lovedPath(loaded - 1)) || app.api.busy(lovedPath(0)) }
  readonly property string error: { app.api.revision; return app.api.error(lovedPath(0)) }

  function refresh(force) {
    var ttl = force ? 0 : 1800000
    app.api.want(lovedPath(0), "stations", ttl, force)
    if (localPath) app.api.want(localPath, "stations", ttl, false)
    app.api.want(trendingPath, "stations", force ? 0 : 900000, false)
    app.api.want(Api.statsPath(), "stats", force ? 0 : 3600000, false)
    for (var p = 1; p < loaded; p++) app.api.want(lovedPath(p), "stations", ttl, false)
  }
  onLocalPathChanged: if (localPath) app.api.want(localPath, "stations", 1800000, false)

  function more() {
    if (!lastFull || loaded >= maxPages) return
    loaded++
    app.api.want(lovedPath(loaded - 1), "stations", 1800000, false)
  }

  // Anything that is popular somewhere: here, trending, or loved.
  function surprise() {
    var pool = local.concat(trending).concat(items.slice(0, 40))
    if (!pool.length) return
    var cur = app.player.station ? app.player.station.id : ""
    var pick = pool[Math.floor(Math.random() * pool.length)]
    if (pick.id === cur && pool.length > 1) pick = pool[(pool.indexOf(pick) + 1) % pool.length]
    app.play(pick)
  }

  property alias list: stations

  Component {
    id: top
    Column {
      width: parent ? parent.width : 0
      spacing: root.app.compact ? 22 : 28
      topPadding: root.app.compact ? 4 : 8
      bottomPadding: 6

      // Hello, and how much there is to hear.
      Item {
        width: parent.width
        height: hello.implicitHeight
        Column {
          id: hello
          x: stations.pad + 10
          width: parent.width - x * 2 - surpriseBtn.width - 12
          spacing: 4
          Text {
            width: parent.width
            text: Api.greeting(new Date(root.app.clock))
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xxl
            font.weight: Font.Bold
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: root.stats && root.stats.stations
              ? Api.group(root.stats.stations) + " stations from " + root.stats.countries + " countries, live"
              : "Radio stations from all over the world, live"
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
            wrapMode: Text.Wrap
          }
        }
        Button {
          id: surpriseBtn
          anchors.right: parent.right
          anchors.rightMargin: stations.pad + 10
          anchors.verticalCenter: parent.verticalCenter
          app: root.app
          glyph: G.shuffle
          text: root.app.compact ? "" : "Surprise me"
          primary: true
          enabled: root.local.length + root.trending.length + root.items.length > 0
          onClicked: root.surprise()
        }
      }

      // Genres: one row that scrolls sideways.
      Column {
        width: parent.width
        spacing: 12
        SectionTitle {
          width: parent.width
          app: root.app
          pad: stations.pad + 10
          title: "Genres"
          action: "All genres"
          onTriggered: { root.app.store.set("browse", "tags"); root.app.setTab("browse") }
        }
        ListView {
          width: parent.width
          height: root.app.compact ? 76 : 88
          orientation: ListView.Horizontal
          spacing: 10
          leftMargin: stations.pad + 10
          rightMargin: stations.pad + 10
          // The window opens narrow and then takes its size; a margin that
          // grows after the row is laid out leaves it scrolled into it.
          onLeftMarginChanged: contentX = -leftMargin
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: Api.GENRES
          delegate: GenreTile {
            required property var modelData
            app: root.app
            label: modelData.label
            hue: modelData.hue
            glyph: G.genre[modelData.tag] || G.note
            onClicked: root.app.openList({ facet: "tag", value: modelData.tag, label: modelData.label })
          }
        }
      }

      Shelf {
        width: parent.width
        app: root.app
        pad: stations.pad + 10
        visible: root.country !== "" && (root.local.length > 0 || root.app.api.busy(root.localPath))
        title: "Popular in " + root.app.countryName
        note: "What people there listen to most"
        items: root.local
        loading: { root.app.api.revision; return root.localPath !== "" && root.app.api.busy(root.localPath) }
        onSeeAll: root.app.openList({ facet: "country", value: root.country, label: root.app.countryName })
      }

      Shelf {
        width: parent.width
        app: root.app
        pad: stations.pad + 10
        title: "Trending now"
        note: "Tuned in to more and more, right now"
        items: root.trending
        loading: { root.app.api.revision; return root.app.api.busy(root.trendingPath) }
        onSeeAll: root.app.openList({ facet: "all", value: "", label: "Trending now", order: "clicktrend" })
      }

      SectionTitle {
        width: parent.width
        app: root.app
        pad: stations.pad + 10
        title: "Most loved"
        note: "The stations with the most votes, worldwide"
      }
    }
  }

  StationList {
    id: stations
    anchors.fill: parent
    app: root.app
    items: root.items
    loading: root.loading
    error: root.items.length ? "" : root.error
    more: root.lastFull && root.loaded < root.maxPages
    topContent: top
    emptyGlyph: G.radio
    emptyTitle: "No stations yet"
    onEndReached: root.more()
    onActivated: function (s) { root.app.activate(s) }
  }
}
