import QtQuick
import QtQuick.Effects
import "Api.mjs" as Api
import "Glyphs.js" as G

// A movie or a show: the backdrop and poster, what it is, your watchlist,
// watched mark and rating, the story, who is in it, and -- for a show -- its
// seasons and episodes with your progress through them.
//
// Painted at once from the card that opened it (`seed`), then filled in as
// the full record arrives, so a tap never shows an empty page while Trakt
// thinks.
Item {
  id: root
  property var app
  property var seed: null

  readonly property string type: seed && seed.type === "show" ? "show" : "movie"
  readonly property int id: seed ? Api.tid(seed.id) : 0
  readonly property bool isShow: type === "show"

  readonly property string summaryUrl: Api.summaryUrl(type, id)
  readonly property string peopleUrl: Api.peopleUrl(type, id)
  readonly property string relatedUrl: Api.relatedUrl(type, id)
  readonly property string seasonsUrl: isShow ? Api.seasonsUrl(id) : ""
  readonly property string progressUrl: isShow && app.trakt.signedIn ? Api.progressUrl(id) : ""

  readonly property var full: { app.trakt.revision; return app.trakt.peek(summaryUrl) }
  readonly property var item: full || seed || ({ type: type, id: id, title: "" })
  readonly property var people: { app.trakt.revision; return app.trakt.peek(peopleUrl) || ({ cast: [], crew: [] }) }
  readonly property var related: { app.trakt.revision; return app.trakt.peek(relatedUrl) || [] }
  readonly property var seasons: { app.trakt.revision; return seasonsUrl ? (app.trakt.peek(seasonsUrl) || []) : [] }
  readonly property var progress: { app.trakt.revision; return progressUrl ? app.trakt.peek(progressUrl) : null }
  readonly property bool loading: { app.trakt.revision; return !full && app.trakt.busy(summaryUrl) }
  readonly property string error: { app.trakt.revision; return full ? "" : app.trakt.error(summaryUrl) }

  // The season on show: where your next episode is, else the first real one.
  property int chosenSeason: -1
  readonly property int season: {
    if (chosenSeason >= 0) return chosenSeason
    if (progress && progress.next) return progress.next.season
    for (var i = 0; i < seasons.length; i++) if (seasons[i].number > 0) return seasons[i].number
    return seasons.length ? seasons[0].number : 1
  }
  readonly property string seasonUrl: isShow && seasons.length ? Api.seasonUrl(id, season) : ""
  readonly property var episodes: { app.trakt.revision; return seasonUrl ? (app.trakt.peek(seasonUrl) || []) : [] }
  readonly property bool episodesLoading: { app.trakt.revision; return !!seasonUrl && app.trakt.busy(seasonUrl) }
  property bool allEpisodes: false

  readonly property bool listed: { app.library.rev; return app.library.inWatchlist(item) }
  readonly property int plays: { app.library.rev; return app.library.plays(item) }
  readonly property int myRating: { app.library.rev; return app.library.rating(item) }

  readonly property bool wide: width >= 820
  readonly property int pad: app.compact ? 16 : 32

  function refresh(force) {
    if (!id) return
    var g = app.trakt
    g.want(summaryUrl, "summary-" + type, force ? 0 : 3600000, true)
    g.want(peopleUrl, "people", force ? 0 : 86400000, false)
    g.want(relatedUrl, "list", force ? 0 : 86400000, false)
    if (isShow) {
      g.want(seasonsUrl, "seasons", force ? 0 : 3600000, true)
      if (progressUrl) g.want(progressUrl, "progress", force ? 0 : 120000, true)
      if (seasonUrl) g.want(seasonUrl, "season", force ? 0 : 3600000, true)
    }
  }
  onSeasonUrlChanged: if (seasonUrl) app.trakt.want(seasonUrl, "season", 3600000, true)
  onSeedChanged: {
    chosenSeason = -1
    allEpisodes = false
    confirmUnwatch = false
    flick.contentY = 0
    Qt.callLater(refresh, false)
  }
  Component.onCompleted: refresh(false)
  Component.onDestruction: if (app && app.trakt) app.trakt.forget([summaryUrl, peopleUrl, relatedUrl, seasonsUrl, seasonUrl])

  function scroll(dy) {
    flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + dy))
  }

  function openLink(url) { if (/^https:\/\//i.test(url)) Qt.openUrlExternally(url) }

  property bool confirmUnwatch: false
  Timer { id: confirmTimer; interval: 3000; onTriggered: root.confirmUnwatch = false }

  Rectangle { anchors.fill: parent; color: root.app.ui.bg; radius: 0
  }

  // ---------------------------------------------------------------- body
  Flickable {
    id: flick
    anchors.fill: parent
    contentWidth: width
    contentHeight: body.height + 40
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick

    Item {
      id: body
      width: flick.width
      height: content.y + content.height

      // Backdrop, fading into the page.
      Item {
        id: backdrop
        width: parent.width
        height: Math.round(root.app.compact ? width * 0.62 : Math.min(460, Math.max(300, width * 0.38)))
        clip: true
        Poster {
          anchors.fill: parent
          app: root.app
          source: root.item.fanart || ""
          title: ""
          tint: root.item.tint || ""
          glyph: root.isShow ? G.tv : G.movie
          radius: 0
          showTitle: false
        }
        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            // Dark behind the buttons at the top; the page colour well before
            // the foot, where the title sits on the picture -- a bright yellow
            // backdrop must not wash it out.
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.45) }
            GradientStop { position: 0.25; color: Qt.rgba(0, 0, 0, 0) }
            GradientStop { position: 0.5; color: root.app.alpha(root.app.ui.bg, 0.35) }
            GradientStop { position: 0.72; color: root.app.alpha(root.app.ui.bg, 0.82) }
            GradientStop { position: 0.88; color: root.app.alpha(root.app.ui.bg, 0.97) }
            GradientStop { position: 1.0; color: root.app.ui.bg }
          }
        }
      }

      // Poster, overlapping the backdrop's foot.
      Item {
        id: posterBox
        x: root.pad
        width: root.app.compact ? 112 : (root.wide ? 220 : 170)
        height: Math.round(width * 1.5)
        y: backdrop.height - Math.round(height * (root.app.compact ? 0.62 : 0.66))

        Rectangle {
          anchors.fill: parent
          anchors.margins: -1
          radius: root.app.ui.radius + 3
          color: root.app.alpha("#000000", 0.25)
        }
        Poster {
          id: bigPoster
          anchors.fill: parent
          app: root.app
          source: root.full && root.full.posterLarge ? root.full.posterLarge : root.item.poster || ""
          title: root.item.title || ""
          tint: root.item.tint || ""
          glyph: root.isShow ? G.tv : G.movie
          radius: 0
          layer.enabled: true
          layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: posterMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
          }
        }
        Item {
          id: posterMask
          anchors.fill: parent
          layer.enabled: true
          visible: false
          Rectangle { anchors.fill: parent; radius: root.app.ui.radius + 2; color: "black" }
        }
      }

      // Title and figures, beside the poster.
      Column {
        id: titleBlock
        anchors.left: posterBox.right
        anchors.leftMargin: root.app.compact ? 14 : 28
        anchors.right: parent.right
        anchors.rightMargin: root.pad
        y: backdrop.height - (root.app.compact ? 30 : 96)
        spacing: root.app.compact ? 4 : 8

        Text {
          width: parent.width
          text: root.item.title || (root.loading ? "Loading…" : "")
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xxl
          font.weight: Font.Bold
          wrapMode: Text.Wrap
          maximumLineCount: 3
          elide: Text.ElideRight
          lineHeight: 1.05
        }
        Text {
          width: parent.width
          visible: text !== ""
          text: Api.metaLine(root.item)
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
          wrapMode: Text.Wrap
        }
        Text {
          width: parent.width
          visible: text !== ""
          text: (root.item.genres || []).join("  ·  ")
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
          wrapMode: Text.Wrap
        }
        Row {
          spacing: 6
          visible: Api.percent(root.item.rating) !== ""
          topPadding: 2
          Icon { anchors.verticalCenter: parent.verticalCenter; app: root.app; text: G.heart; size: 17; width: 20; color: root.app.ui.heart }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Api.percent(root.item.rating)
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.lg
            font.weight: Font.Bold
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !isNaN(root.item.votes)
            text: Api.compact(root.item.votes) + " votes"
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xs
          }
        }
      }

      // Everything below the header.
      Column {
        id: content
        x: root.pad
        width: parent.width - root.pad * 2
        y: Math.max(posterBox.y + posterBox.height, titleBlock.y + titleBlock.height) + (root.app.compact ? 16 : 24)
        spacing: root.app.compact ? 20 : 26

        Text {
          visible: root.error !== ""
          width: parent.width
          text: root.error
          color: root.app.ui.heart
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
        }

        // What you can do with it.
        Flow {
          width: parent.width
          spacing: 8
          Button {
            app: root.app
            glyph: root.listed ? G.bookmarked : G.watchlist
            text: root.listed ? "On watchlist" : "Watchlist"
            active: root.listed
            onClicked: root.app.library.toggleWatchlist(root.item)
          }
          Button {
            visible: !root.isShow
            app: root.app
            glyph: root.plays > 0 ? G.checkCircle : G.check
            tint: root.app.ui.good
            active: root.plays > 0
            text: root.confirmUnwatch ? "Tap again to unwatch" : root.plays > 1 ? "Watched " + root.plays + "×" : root.plays === 1 ? "Watched" : "Mark watched"
            onClicked: {
              if (root.plays === 0) { root.app.library.markWatched(root.item); return }
              if (!root.confirmUnwatch) { root.confirmUnwatch = true; confirmTimer.restart(); return }
              root.confirmUnwatch = false
              root.app.library.unwatch(root.item)
            }
          }
          Button {
            visible: !!(root.full && root.full.trailer)
            app: root.app
            glyph: G.youtube
            text: "Trailer"
            onClicked: root.openLink(root.full.trailer)
          }
          Button {
            app: root.app
            glyph: G.open
            text: root.app.compact ? "" : "Trakt"
            onClicked: root.openLink(Api.siteUrl(root.item))
          }
        }

        // Your rating.
        Column {
          visible: root.app.trakt.signedIn
          width: parent.width
          spacing: 4
          Text {
            text: "Your rating"
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xs
            font.weight: Font.DemiBold
          }
          RatingBar {
            width: parent.width
            app: root.app
            value: root.myRating
            onRated: function (v) { root.app.library.rate(root.item, v) }
          }
        }

        // The story.
        Column {
          width: Math.min(parent.width, 820)
          spacing: 8
          visible: overview.text !== "" || tagline.text !== ""
          Text {
            id: tagline
            visible: text !== ""
            width: parent.width
            text: root.full ? root.full.tagline || "" : ""
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.md
            font.italic: true
            wrapMode: Text.Wrap
          }
          Text {
            id: overview
            property bool more: false
            width: parent.width
            text: root.item.overview || ""
            color: root.app.alpha(root.app.ui.text, 0.85)
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.md
            wrapMode: Text.Wrap
            lineHeight: 1.25
            maximumLineCount: more || !root.app.compact ? 100 : 5
            elide: Text.ElideRight
            MouseArea { anchors.fill: parent; enabled: overview.truncated || overview.more; onClicked: overview.more = !overview.more }
          }
          Text {
            visible: overview.truncated
            text: "More"
            color: root.app.ui.accent
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
            font.weight: Font.DemiBold
            MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: overview.more = true }
          }
          Text {
            visible: text !== ""
            width: parent.width
            text: root.people.crew.map(function (c) { return c.job + " " + c.names.join(", ") }).join("\n")
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
            wrapMode: Text.Wrap
          }
        }

        // ------------------------------------------------ show: progress
        Rectangle {
          visible: root.isShow && root.progress !== null && root.progress.aired > 0
          width: parent.width
          height: prog.implicitHeight + 28
          radius: root.app.ui.radius + 2
          color: root.app.ui.surface
          Column {
            id: prog
            x: 14
            y: 14
            width: parent.width - 28
            spacing: 10
            Row {
              width: parent.width
              spacing: 8
              Text {
                text: root.progress ? (root.progress.completed === root.progress.aired ? "All caught up" : "Your progress") : ""
                color: root.app.ui.text
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.md
                font.weight: Font.DemiBold
              }
              Text {
                anchors.baseline: parent.children[0].baseline
                text: root.progress ? root.progress.completed + " of " + root.progress.aired + " episodes" : ""
                color: root.app.ui.muted
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.sm
              }
            }
            Rectangle {
              width: parent.width
              height: 6
              radius: 3
              color: root.app.ui.divider
              Rectangle {
                width: root.progress && root.progress.aired > 0 ? parent.width * Math.min(1, root.progress.completed / root.progress.aired) : 0
                height: parent.height
                radius: 3
                color: root.app.ui.accent
                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
              }
            }
            Item {
              visible: !!(root.progress && root.progress.next)
              width: parent.width
              height: 40
              Text {
                anchors.left: parent.left
                anchors.right: nextBtn.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: root.progress && root.progress.next ? "Next: " + Api.epCode(root.progress.next)
                  + (root.progress.next.title && !root.app.store.prefs.hideSpoilers ? "  ·  " + root.progress.next.title : "") : ""
                color: root.app.ui.text
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.sm
                elide: Text.ElideRight
              }
              Button {
                id: nextBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                app: root.app
                glyph: G.check
                text: "Watched"
                tint: root.app.ui.good
                primary: true
                onClicked: root.app.library.setEpisodes(root.item, [root.progress.next], true)
              }
            }
          }
        }

        // ------------------------------------------------ show: seasons
        Column {
          visible: root.isShow && root.seasons.length > 0
          width: parent.width
          spacing: 12

          Text {
            text: "Episodes"
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.lg
            font.weight: Font.Bold
          }
          Flickable {
            width: parent.width
            height: root.app.ui.chip
            contentWidth: seasonRow.implicitWidth
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            Row {
              id: seasonRow
              spacing: 6
              Repeater {
                model: root.seasons
                delegate: Chip {
                  required property var modelData
                  app: root.app
                  hpad: 22
                  text: modelData.number === 0 ? "Specials" : (root.app.compact ? "S" + modelData.number : "Season " + modelData.number)
                  selected: root.season === modelData.number
                  onClicked: { root.chosenSeason = modelData.number; root.allEpisodes = false }
                }
              }
            }
          }
          Item {
            width: parent.width
            height: 40
            visible: root.episodes.length > 0
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.episodes.length + " episodes" + (function () {
                var s = root.seasons.filter(function (x) { return x.number === root.season })[0]
                return s && s.firstAired ? "  ·  " + new Date(s.firstAired).getFullYear() : ""
              })()
              color: root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.sm
            }
            Button {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              visible: root.app.trakt.signedIn
              app: root.app
              readonly property var airedEps: root.episodes.filter(function (e) { return e.aired && new Date(e.aired).getTime() <= root.app.clock })
              readonly property bool allDone: { root.app.library.rev; return airedEps.length > 0 && airedEps.every(function (e) { return root.app.library.episodeWatched(root.item.id, root.progress, e) }) }
              glyph: allDone ? G.checkCircle : G.check
              text: allDone ? "Season watched" : "Mark season watched"
              tint: root.app.ui.good
              active: allDone
              enabled: airedEps.length > 0
              onClicked: root.app.library.setEpisodes(root.item, airedEps, !allDone)
            }
          }
          Placeholder {
            visible: root.episodes.length === 0
            width: parent.width
            app: root.app
            busy: root.episodesLoading
            title: root.episodesLoading ? "" : "No episodes listed yet"
            topPadding: 8
          }
          Column {
            width: parent.width
            Repeater {
              model: root.allEpisodes ? root.episodes : root.episodes.slice(0, 40)
              delegate: EpisodeRow {
                required property var modelData
                width: parent.width
                app: root.app
                show: root.item
                ep: modelData
                progress: root.progress
                canMark: root.app.trakt.signedIn
              }
            }
          }
          Button {
            visible: !root.allEpisodes && root.episodes.length > 40
            app: root.app
            text: "Show all " + root.episodes.length + " episodes"
            onClicked: root.allEpisodes = true
          }
        }

        // ------------------------------------------------ facts
        Grid {
          id: facts
          width: parent.width
          columns: root.app.compact ? 3 : (root.wide ? 5 : 4)
          spacing: 8
          readonly property real cell: (width - spacing * (columns - 1)) / columns
          Repeater {
            model: {
              var m = root.item, f = []
              if (m.released) f.push({ k: root.isShow ? "Premiered" : "Released", v: Api.date(m.released) })
              if (Api.runtime(m.runtime)) f.push({ k: "Runtime", v: Api.runtime(m.runtime) })
              if (Api.status(m.status)) f.push({ k: "Status", v: Api.status(m.status) })
              if (m.network) f.push({ k: "Network", v: m.network })
              if (root.full && root.full.airs) f.push({ k: "Airs", v: root.full.airs })
              if (root.full && root.full.country) f.push({ k: "Country", v: root.full.country })
              if (root.full && root.full.language) f.push({ k: "Language", v: root.full.language.toUpperCase() })
              if (root.full && !isNaN(root.full.airedEpisodes)) f.push({ k: "Episodes", v: String(root.full.airedEpisodes) })
              if (root.full && root.full.certification) f.push({ k: "Rated", v: root.full.certification })
              return f
            }
            delegate: Rectangle {
              required property var modelData
              width: facts.cell
              height: 56
              radius: root.app.ui.radius
              color: root.app.ui.surface
              Column {
                id: factCol
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                  text: modelData.k
                  color: root.app.ui.muted
                  font.family: root.app.ui.font
                  font.pixelSize: root.app.ui.fs.xs
                }
                Text {
                  width: facts.cell - 20
                  text: modelData.v
                  color: root.app.ui.text
                  font.family: root.app.ui.font
                  font.pixelSize: root.app.ui.fs.sm
                  font.weight: Font.DemiBold
                  elide: Text.ElideRight
                  fontSizeMode: Text.HorizontalFit
                  minimumPixelSize: 10
                }
              }
            }
          }
        }

        // ------------------------------------------------ cast
        Shelf {
          x: -root.pad
          width: parent.width + root.pad * 2
          pad: root.pad
          app: root.app
          title: "Cast"
          model: root.people.cast
          rowHeight: root.app.compact ? 150 : 164
          delegate: Item {
            required property var modelData
            width: root.app.compact ? 84 : 100
            height: root.app.compact ? 150 : 164
            Avatar {
              anchors.horizontalCenter: parent.horizontalCenter
              app: root.app
              size: root.app.compact ? 76 : 88
              source: modelData.headshot || ""
              name: modelData.name
              ground: root.app.ui.bg
            }
            Column {
              y: (root.app.compact ? 76 : 88) + 8
              width: parent.width
              spacing: 1
              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: modelData.name
                color: root.app.ui.text
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.xs
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: modelData.role
                color: root.app.ui.muted
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.xs
                elide: Text.ElideRight
              }
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: if (modelData.slug) root.openLink(Api.SITE + "/people/" + modelData.slug)
            }
          }
        }

        // ------------------------------------------------ related
        Shelf {
          x: -root.pad
          width: parent.width + root.pad * 2
          pad: root.pad
          app: root.app
          title: "More like this"
          model: root.related
          rowHeight: Math.round((root.app.compact ? 108 : 140) * 1.5) + 52
          delegate: PosterCard {
            required property var modelData
            width: root.app.compact ? 108 : 140
            app: root.app
            item: modelData
            onActivated: root.app.openMedia(modelData)
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- top bar
  // Floats over the backdrop; turns solid, with the title, once the header
  // has scrolled away.
  Item {
    id: topBar
    width: parent.width
    height: root.app.compact ? 56 : 64
    z: 2
    readonly property real solid: Math.max(0, Math.min(1, (flick.contentY - backdrop.height + 140) / 60))

    Rectangle {
      anchors.fill: parent
      color: root.app.ui.bg
      opacity: topBar.solid
      Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.app.ui.divider }
    }

    // Round, dark discs behind the buttons while they sit on a picture.
    component Disc: Rectangle {
      property real solid: 0
      anchors.centerIn: parent
      width: 38
      height: 38
      radius: 19
      color: Qt.rgba(0, 0, 0, 0.4 * (1 - solid))
    }

    Item {
      id: backBtn
      x: root.app.compact ? 6 : 14
      anchors.verticalCenter: parent.verticalCenter
      width: 44
      height: 44
      Disc { solid: topBar.solid }
      IconButton {
        anchors.centerIn: parent
        app: root.app
        glyph: G.back
        label: "Back"
        color: topBar.solid > 0.5 ? root.app.ui.text : "white"
        onClicked: if (!root.app.back()) root.app.dismiss()
      }
    }
    Text {
      anchors.left: backBtn.right
      anchors.leftMargin: 8
      anchors.right: bookmark.left
      anchors.rightMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      opacity: topBar.solid
      text: root.item.title || ""
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.lg
      font.weight: Font.Bold
      elide: Text.ElideRight
    }
    Item {
      id: bookmark
      anchors.right: parent.right
      anchors.rightMargin: root.app.compact ? 6 : 14
      anchors.verticalCenter: parent.verticalCenter
      width: 44
      height: 44
      Disc { solid: topBar.solid }
      IconButton {
        anchors.centerIn: parent
        app: root.app
        glyph: root.listed ? G.bookmarked : G.watchlist
        label: root.listed ? "Remove from watchlist" : "Add to watchlist"
        color: root.listed ? root.app.ui.accent : topBar.solid > 0.5 ? root.app.ui.text : "white"
        onClicked: root.app.library.toggleWatchlist(root.item)
      }
    }
  }
}
