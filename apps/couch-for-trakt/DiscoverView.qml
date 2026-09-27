import QtQuick
import "Api.mjs" as Api
import "Glyphs.js" as G

// What everybody is watching: trending, popular, anticipated, streaming and
// the box office, for movies or shows. The first few open as backdrops; the
// rest is a grid that loads more as it scrolls.
Item {
  id: root
  property var app

  readonly property string type: app.store.prefs.mediaType === "show" ? "show" : "movie"
  readonly property string section: {
    var s = app.store.prefs.section
    var ok = Api.SECTIONS.some(function (x) { return x.key === s && (!x.movies || root.type === "movie") })
    return ok ? s : "trending"
  }
  readonly property int perPage: 36
  property int loaded: 1

  function url(page) { return Api.discoverUrl(type, section, page, perPage) }

  readonly property var items: {
    app.trakt.revision
    var out = []
    var seen = {}
    for (var p = 1; p <= loaded; p++) {
      var d = app.trakt.peek(url(p))
      if (!d) break
      for (var i = 0; i < d.length; i++) {
        var k = d[i].type + d[i].id
        if (!seen[k]) { seen[k] = true; out.push(d[i]) }
      }
    }
    return out
  }
  readonly property int pageCount: { app.trakt.revision; return section === "boxoffice" ? 1 : app.trakt.pages(url(1)) }
  readonly property bool loading: { app.trakt.revision; return app.trakt.busy(url(loaded)) || app.trakt.busy(url(1)) }
  readonly property string error: { app.trakt.revision; return app.trakt.error(url(1)) }

  function refresh(force) {
    app.trakt.want(url(1), "list", force ? 0 : 900000, force)
    for (var p = 2; p <= loaded; p++) app.trakt.want(url(p), "list", force ? 0 : 900000, false)
  }

  function more() {
    if (loaded >= pageCount || loaded >= 10 || !app.trakt.peek(url(loaded))) return
    loaded++
    app.trakt.want(url(loaded), "list", 900000, false)
  }

  function choose(type, section) {
    if (type) app.store.set("mediaType", type)
    if (section) app.store.set("section", section)
    loaded = 1
    Qt.callLater(function () { root.refresh(false); grid.toTop() })
  }

  property alias list: grid

  Component {
    id: top
    Column {
      width: parent ? parent.width : 0
      spacing: 12
      bottomPadding: 10

      Hero {
        width: parent.width
        app: root.app
        pad: grid.pad
        maxHeight: Math.max(180, root.height * (root.app.compact ? 0.4 : 0.48))
        items: root.items.filter(function (m) { return m.fanart }).slice(0, 6)
        running: root.visible && root.app.opened && root.app.page === null
      }

      // Movies or shows, then the section: one scrolling row of chips.
      Flickable {
        width: parent.width
        height: root.app.ui.chip
        contentWidth: chips.implicitWidth + grid.pad * 2
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        Row {
          id: chips
          x: grid.pad
          spacing: 6
          Rectangle {
            width: seg.implicitWidth + 4
            height: root.app.ui.chip
            radius: height / 2
            color: root.app.ui.surface
            border.width: 1
            border.color: root.app.ui.border
            Row {
              id: seg
              anchors.centerIn: parent
              Repeater {
                model: [{ k: "movie", l: "Movies", g: G.movie }, { k: "show", l: "Shows", g: G.tv }]
                delegate: Rectangle {
                  required property var modelData
                  readonly property bool sel: root.type === modelData.k
                  width: segLabel.implicitWidth + 44
                  height: root.app.ui.chip - 4
                  radius: height / 2
                  color: sel ? root.app.ui.accent : "transparent"
                  Row {
                    id: segLabel
                    anchors.centerIn: parent
                    spacing: 4
                    Icon {
                      anchors.verticalCenter: parent.verticalCenter
                      app: root.app
                      text: modelData.g
                      size: 15
                      width: 18
                      color: sel ? root.app.onAccent : root.app.ui.text
                    }
                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.l
                      color: sel ? root.app.onAccent : root.app.ui.text
                      font.family: root.app.ui.font
                      font.pixelSize: root.app.ui.fs.sm
                      font.weight: Font.DemiBold
                    }
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.choose(modelData.k, "")
                  }
                }
              }
            }
          }
          Item { width: 4; height: 1 }
          Repeater {
            model: Api.SECTIONS.filter(function (s) { return !s.movies || root.type === "movie" })
            delegate: Chip {
              required property var modelData
              app: root.app
              hpad: 26
              text: modelData.label
              selected: root.section === modelData.key
              onClicked: root.choose("", modelData.key)
            }
          }
        }
      }

      Text {
        x: grid.pad
        width: parent.width - grid.pad * 2
        text: {
          for (var i = 0; i < Api.SECTIONS.length; i++) if (Api.SECTIONS[i].key === root.section) return Api.SECTIONS[i].note
          return ""
        }
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
        elide: Text.ElideRight
      }
    }
  }

  PosterGrid {
    id: grid
    anchors.fill: parent
    app: root.app
    items: root.items
    loading: root.loading
    error: root.items.length ? "" : root.error
    more: root.loaded < root.pageCount && root.loaded < 10
    topContent: top
    emptyGlyph: G.discover
    emptyTitle: root.app.trakt.configured ? "Nothing here right now" : "Trakt isn't set up yet"
    emptyDetail: root.app.trakt.configured ? "" : "Add a Trakt app's client ID in Settings."
    emptyAction: root.app.trakt.configured ? "" : "Open Settings"
    onEmptyTriggered: root.app.openSettings()
    badgeFor: function (m, i) {
      if (root.section === "trending" || root.section === "anticipated" || root.section === "boxoffice") return m.stat || ""
      return "#" + (i + 1)
    }
    onEndReached: root.more()
    onActivated: function (m) { root.app.openMedia(m) }
  }
}
