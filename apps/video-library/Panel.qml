import QtQuick
import Quickshell
import Quickshell.Io
import QtMultimedia
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G
import "Lbry.js" as L

// Video Library: LBRY's videos, as Odysee serves them to anybody. Its front page by
// category, search, channels, and a library of your own -- the channels you
// follow, what you saved, what you played -- in one file on this machine,
// with no account behind it. Videos play in the page (VideoSurface.qml).
//
//     omarchy-shell shell toggle org.moarchy.video-library
//
// Every question is one curl (Requests.qml) to a public endpoint (Lbry.js),
// and only while the window is open: a hidden Video Library asks nothing, decodes
// no picture and keeps no clock.
//
// A phone gets the tabs at the bottom and one card to a row; a desktop, the
// tabs in the rail and as many cards as fit. A video or a channel is a page
// over the tab either way.
App {
  id: root

  appId: "org.moarchy.video-library"
  title: "Video Library"
  subtitle: statusText()
  caption: "LBRY, through Odysee"
  windowWidth: 1280
  windowHeight: 820

  store: Store { name: "moarchy-video-library"; defaults: ({ cat: "" }) }

  launcher.desktopId: "org.moarchy.VideoLibrary"
  launcher.genericName: "Video browser"
  launcher.comment: "Videos from LBRY and Odysee: browse, search, follow channels and watch"
  launcher.categories: "AudioVideo;Video;Player;Network;"
  launcher.keywords: "odysee;lbry;video;videos;youtube;channel;stream;watch;podcast;"

  mark: Component { Image { source: root.appDir + "/icon.svg"; sourceSize: Qt.size(60, 60) } }

  ui: Tokens {
    theme: root.hostTheme
    compact: root.compact
    // Text and fills over a picture, which is dark or light at random: the
    // same in every theme, because the picture is.
    readonly property color scrimInk: "#ffffff"
    readonly property color scrimStrong: alpha("#000000", 0.72)
  }

  tabs: [
    { key: "home", label: "Home", glyph: G.home },
    { key: "search", label: "Search", glyph: KG.search },
    { key: "following", label: "Following", glyph: G.following },
    { key: "library", label: "Library", glyph: G.library }
  ]

  actions: Component {
    Row {
      spacing: 2
      IconButton {
        visible: !root.offline && root.tab !== "library" && !root.inSettings
        app: root
        glyph: KG.refresh
        label: "Refresh"
        active: requests.busy > 0
        onClicked: root.refresh()
      }
    }
  }

  settings: Component {
    SettingsPage {
      app: root
      blurb: "LBRY's videos, as Odysee serves them to anybody: its front page, search, channels, and a library of your own. Videos play in the page, with controls made for a finger."
      AppearanceSection { app: root }
      LauncherSection { app: root }
      KeysSection {
        app: root
        keys: [
          ["1 – 4", "Home, Search, Following, Library"],
          ["/", "Search"],
          ["← → ↑ ↓  Enter", "Move through a grid, open a video"],
          ["p  Space", "Play or pause"],
          ["← →", "Back or on ten seconds, while it plays"],
          ["f", "Fullscreen"],
          ["a", "Listen: the sound only"],
          ["s", "Save the video on screen"],
          ["Shift F", "Follow its channel"],
          ["r", "Refresh"],
          [",", "Settings"],
          ["Esc", "Back one step"]
        ]
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Playing"
        note: "Videos play in the page, where their picture was, and fill the window from the button in the corner. Video Library picks Odysee's own renditions by height -- 720p on a phone, whose processor decodes it comfortably, 1080p elsewhere -- and a tap on the label in the player steps through the others. The mpv button hands a video to mpv instead, with your own mpv settings." + (root.hasMpv === false ? " mpv is not installed: sudo pacman -S mpv." : "") + " Paid videos and those for a channel's members are marked, and do not play."
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Where it comes from"
        note: "The LBRY blockchain, through Odysee's public endpoints and without an account: api.na-backend.odysee.com for claims, lighthouse.odysee.tv for search, odysee.com for its front page's categories, and player.odycdn.com and thumbnails.odycdn.com for streams and pictures. Mature content is left out, as Odysee leaves it out of its own front page. Nothing is asked while the window is closed."
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Where it keeps things"
        note: "~/.local/share/moarchy-video-library: library.json, the channels you follow, what you saved and what you played; and homepage.json, Odysee's categories, asked for again once a day."
      }
    }
  }

  // A video or a channel, over the tab: { kind: "video", item } or
  // { kind: "channel", channel }.
  page: Component {
    Loader {
      sourceComponent: root.topPage && root.topPage.kind === "channel" ? channelPage : videoPage
    }
  }

  Component {
    id: videoPage
    VideoPage {
      readonly property var chFeed: ch ? (root.feeds["channel:" + ch.id] || root.emptyFeed) : root.emptyFeed
      app: root
      item: root.topPage ? root.topPage.item : null
      now: root.nowSec
      saved: item ? !!root.savedIds[item.id] : false
      followed: ch ? !!root.followIds[ch.id] : false
      playing: item !== null && root.playingItem !== null && root.playingItem.id === item.id
      related: (chFeed ? chFeed.items : []).filter(function (v) { return !item || v.id !== item.id }).slice(0, 8)
      relatedLoading: !!chFeed && chFeed.loading
      onPlay: function (audioOnly) { root.play(item, audioOnly) }
      onSaveToggled: root.toggleSave(item)
      onFollowToggled: if (ch) root.toggleFollow(ch)
      onChannelOpened: if (ch) root.openChannel(ch)
      onVideoOpened: function (v) { root.openVideo(v) }
      onTagSearched: function (tag) { root.searchFor(tag) }
      // The channel's other videos, once per channel.
      function wantRelated() { if (ch && chFeed && !chFeed.items.length && !chFeed.loading) root.load("channel:" + ch.id, 1) }
      Component.onCompleted: wantRelated()
      onChChanged: wantRelated()
    }
  }

  Component {
    id: channelPage
    ChannelPage {
      readonly property string key: channel ? "channel:" + channel.id : ""
      app: root
      channel: root.topPage ? root.topPage.channel : null
      feed: root.feeds[key] || root.emptyFeed
      now: root.nowSec
      savedIds: root.savedIds
      followed: channel ? !!root.followIds[channel.id] : false
      onFollowToggled: root.toggleFollow(channel)
      onVideoOpened: function (item) { root.openVideo(item) }
      onWantMore: root.loadMore(key)
      onRetry: root.load(key, 1)
      function wantUploads() { if (key && feed && !feed.items.length && !feed.loading) root.load(key, 1) }
      Component.onCompleted: wantUploads()
      onKeyChanged: wantUploads()
    }
  }

  // ------------------------------------------------------------ state

  // MOARCHY_VIDEO_LIBRARY_OFFLINE: never open a socket -- answers come from
  // fixture.json, when dev/demo.py left one. MOARCHY_VIDEO_LIBRARY_NOW: a frozen
  // clock, so "3 days ago" says the same in two screenshots.
  // MOARCHY_VIDEO_LIBRARY_THUMBS: a folder of pictures by claim id, in place of the
  // CDN.
  readonly property bool offline: (Quickshell.env("MOARCHY_VIDEO_LIBRARY_OFFLINE") || "") !== ""
  readonly property real pinnedNow: parseFloat(Quickshell.env("MOARCHY_VIDEO_LIBRARY_NOW") || "0") || 0
  readonly property string thumbsDir: Quickshell.env("MOARCHY_VIDEO_LIBRARY_THUMBS") || ""
  property real nowSec: pinnedNow || Date.now() / 1000

  // Odysee's categories, and the one on screen.
  property var cats: []
  property real catsFetched: 0
  property bool catsLoading: false
  property string catsError: ""
  property string cat: ""

  // Every list that is fetched a page at a time, by key: home:<category>,
  // following, channel:<id>, search:<videos|channels>:<text>.
  property var feeds: ({})
  readonly property var emptyFeed: ({ items: [], page: 0, more: false, loading: false, error: "", at: 0 })

  // The library, and lookups into it for the views.
  property var follows: []
  property var saved: []
  property var history: []
  readonly property var followIds: idSet(follows)
  readonly property var savedIds: idSet(saved)
  property bool libraryRead: false

  function idSet(list) {
    var m = {}
    for (var i = 0; i < list.length; i++) m[list[i].id] = true
    return m
  }

  function statusText() {
    if (playingItem && mediaPlaying && (!topPage || !topPage.item || topPage.item.id !== playingItem.id))
      return (playingAudio ? "Listening · " : "Playing · ") + playingItem.title
    if (offline) return "Offline"
    if (requests.busy > 0) return "Loading…"
    return ""
  }

  // A picture: from the CDN at the size it is drawn, or from the harness's
  // folder. Offline with no folder, none: the box shows its glyph.
  function art(id, src, w, h) {
    if (thumbsDir) return src ? "file://" + thumbsDir + "/" + id + ".jpg" : ""
    if (offline || !src) return ""
    return L.image(src, w, h)
  }

  function copyLink(lbryUrl) {
    if (!lbryUrl) return
    Quickshell.clipboardText = L.web(lbryUrl)
    toast("Link copied")
  }

  function openWeb(lbryUrl) { Qt.openUrlExternally(L.web(lbryUrl)) }

  // ------------------------------------------------------------ opening things

  function openVideo(item) {
    if (!item) return
    resetFocus()
    push({ kind: "video", item: item, title: item.title })
  }

  function openChannel(ch) {
    if (!ch) return
    resetFocus()
    push({ kind: "channel", channel: ch, title: ch.title })
  }

  function setCat(key) {
    if (cat === key) { homeView.grid.positionViewAtBeginning(); return }
    cat = key
    store.set("cat", key)
    var f = feeds["home:" + key]
    if (!f || !f.items.length || stale(f)) load("home:" + key, 1)
  }

  function searchFor(text) {
    stack = []
    setTab("search")
    searchView.kind = "videos"
    searchView.query = text
    searchView.run()
  }

  function findChannels() {
    setTab("search")
    searchView.kind = "channels"
    Qt.callLater(searchView.focusField)
  }

  function isLink(text) { return L.uri(text) !== "" }

  // An odysee.com link, an lbry:// URL or an @channel: resolved, then opened
  // as the page it is.
  function openLink(text, andPlay) {
    var u = L.uri(text)
    if (!u) return
    requests.run("resolve:" + u, L.rpc("resolve", { urls: [u] }), function (code, out) {
      var r = L.result(code, out)
      var claim = r.data ? r.data[u] : null
      if (r.error || !claim || claim.error) { toast(r.error || "Nothing on LBRY answers to that link"); return }
      var v = L.video(claim)
      if (v) { openVideo(v); if (andPlay) play(v, false); return }
      var c = L.channel(claim)
      if (c) { openChannel(c); return }
      toast("That link is something this app does not show")
    })
  }

  // ------------------------------------------------------------ the library

  function toggleSave(item) {
    if (!item) return
    var r = L.toggle(saved, item, L.MAX_SAVED)
    if (r.full) { toast(L.MAX_SAVED + " saved videos is as many as this app keeps"); return }
    saved = r.list
    saveLibrary()
    toast(r.on ? "Saved for later" : "Removed from Saved")
  }

  function toggleFollow(ch) {
    if (!ch) return
    var r = L.followChannel(follows, ch)
    if (r.full) { toast(L.MAX_FOLLOWS + " channels is as many as this app follows"); return }
    follows = r.list
    saveLibrary()
    // The feed was of the old list.
    dropFeed("following")
    if (tab === "following" && opened) load("following", 1)
    toast(r.on ? "Following " + ch.title : "Unfollowed " + ch.title)
  }

  function clearHistory() {
    var kept = history
    history = []
    saveLibrary()
    toast("History cleared", "Undo", function () { root.history = kept; root.saveLibrary() })
  }

  function saveLibrary() {
    if (!libraryRead) return
    libraryFile.save(L.serializeLibrary({ follows: follows, saved: saved, history: history }))
  }

  DataFile {
    id: libraryFile
    app: "video-library"
    name: "library.json"
    onParsed: function (data) {
      var lib = L.parseLibrary(data)
      root.follows = lib.follows
      root.saved = lib.saved
      root.history = lib.history
      root.libraryRead = true
    }
    onQuarantined: function (to) { root.toast("The library file was unreadable and was kept aside") }
  }

  DataFile {
    id: homepageFile
    app: "video-library"
    name: "homepage.json"
    onParsed: function (data) {
      var hp = L.parseHomepage(data)
      if (hp.categories.length && hp.fetched >= root.catsFetched) {
        root.cats = hp.categories
        root.catsFetched = hp.fetched
        root.pickCat()
      }
      root.homepageRead = true
      root.start()
    }
  }
  property bool homepageRead: false

  // Offline, the answers a real run would have had.
  DataFile {
    id: fixtureFile
    app: "video-library"
    name: "fixture.json"
    onParsed: function (data) {
      if (data && typeof data === "object") requests.fixture = data
      root.fixtureRead = true
      root.start()
    }
  }
  property bool fixtureRead: false

  // ------------------------------------------------------------ the network

  Requests { id: requests; offline: root.offline }

  function stale(f) { return !f.at || nowSec - f.at > 15 * 60 }

  function setFeed(key, patch) {
    var m = Object.assign({}, feeds)
    m[key] = Object.assign({}, feeds[key] || emptyFeed, patch)
    feeds = m
  }

  function dropFeed(key) {
    var m = Object.assign({}, feeds)
    delete m[key]
    feeds = m
  }

  function loadMore(key) {
    var f = feeds[key]
    if (f && f.more && !f.loading) load(key, f.page + 1)
  }

  // One page of one list. Page 1 replaces what is there when it arrives, not
  // before: a refresh that fails leaves the list on screen.
  function load(key, page) {
    var f = feeds[key] || emptyFeed
    if (f.loading && page > 1) return
    var token = Date.now() + Math.random()
    setFeed(key, { loading: true, error: "", token: token })
    function done(items, more, error) {
      var cur = root.feeds[key]
      if (!cur || cur.token !== token) return
      if (error) { root.setFeed(key, { loading: false, error: error }); return }
      root.setFeed(key, {
        loading: false, error: "", page: page, more: more, at: root.nowSec,
        items: page === 1 ? items : L.append(cur.items, items)
      })
    }
    function claims(reqKey, params) {
      requests.run(reqKey, L.rpc("claim_search", params), function (code, out) {
        var r = L.result(code, out)
        if (r.error) { done([], false, r.error); return }
        var raw = r.data && Array.isArray(r.data.items) ? r.data.items.length : 0
        done(L.videos(r.data), raw >= L.PAGE, "")
      })
    }
    var parts = key.split(":")
    if (parts[0] === "home") {
      var c = catNamed(parts[1])
      if (!c) { done([], false, catsError || "Odysee's categories have not arrived."); return }
      claims(key + ":" + page, L.feed(c, page, nowSec))
    } else if (parts[0] === "following") {
      if (!follows.length) { done([], false, ""); return }
      claims("following:" + page, L.uploads(follows.map(function (x) { return x.id }), page))
    } else if (parts[0] === "channel") {
      claims(key + ":" + page, L.uploads([parts[1]], page))
    } else if (parts[0] === "search") {
      var kind = parts[1]
      var q = parts.slice(2).join(":")
      requests.run("lighthouse:" + kind + ":" + q + ":" + page, L.lighthouse(q, kind, page), function (code, out) {
        var r = L.answer(code, out, "Odysee's search")
        if (r.error) { done([], false, r.error); return }
        var ids = L.hits(r.data)
        if (!ids.length) { done([], false, ""); return }
        requests.run("claims:" + kind + ":" + q + ":" + page, L.rpc("claim_search", L.claims(ids, kind)), function (code2, out2) {
          var r2 = L.result(code2, out2)
          if (r2.error) { done([], false, r2.error); return }
          var list = kind === "channels" ? L.channels(r2.data) : L.videos(r2.data)
          done(L.inOrder(list, ids), ids.length >= L.PAGE, "")
        })
      })
    }
  }

  function search(kind, text) {
    var key = "search:" + kind + ":" + text
    // Only the search on screen is kept.
    var m = {}
    for (var k in feeds) if (k.indexOf("search:") !== 0 || k === key) m[k] = feeds[k]
    feeds = m
    var f = feeds[key]
    if (!f || (!f.items.length && !f.loading) || stale(f)) load(key, 1)
  }

  function catNamed(key) {
    for (var i = 0; i < cats.length; i++) if (cats[i].key === key) return cats[i]
    return null
  }

  function pickCat() {
    var want = catNamed(harnessCat) ? harnessCat : cat || store.prefs.cat || ""
    cat = catNamed(want) ? want : (cats.length ? cats[0].key : "")
  }

  function fetchHomepage() {
    if (catsLoading) return
    catsLoading = true
    catsError = ""
    requests.run("homepage", L.homepage(), function (code, out) {
      root.catsLoading = false
      var r = L.answer(code, out, "Odysee")
      var got = r.error ? [] : L.categories(r.data, Qt.locale().name.replace("_", "-"))
      if (!got.length) {
        // A day-old list is better than none; the chain's own trending is
        // better than an error.
        if (!root.cats.length) {
          root.cats = L.FALLBACK
          root.pickCat()
          root.load("home:" + root.cat, 1)
        }
        return
      }
      root.cats = got
      root.catsFetched = root.nowSec
      homepageFile.save(L.serializeHomepage(got, root.catsFetched))
      root.pickCat()
      root.load("home:" + root.cat, 1)
    })
  }

  // The first time the window is up with the files read: the homepage if it
  // is a day old, and the tab on screen.
  property bool started: false
  function start() {
    if (started || !opened || !homepageRead || (offline && !fixtureRead)) return
    started = true
    if (!cats.length || nowSec - catsFetched > L.HOMEPAGE_TTL) fetchHomepage()
    if (cats.length) load("home:" + cat, 1)
    showTab(tab)
    harness()
  }

  onOpenedChanged: {
    // A closed window has no picture to show: pause, and pick up there.
    if (!opened) { if (mediaPlaying && !playingAudio) media.pause(); return }
    nowSec = pinnedNow || Date.now() / 1000
    start()
    // Back after a while: the list on screen is asked for again.
    if (started && !topPage) showTab(tab)
  }

  onTabSelected: function (key) { showTab(key) }

  function showTab(key) {
    if (!started) return
    if (key === "home" && cat) {
      var h = feeds["home:" + cat]
      if (!h || (!h.loading && stale(h))) load("home:" + cat, 1)
    } else if (key === "following" && follows.length) {
      var f = feeds["following"]
      if (!f || (!f.loading && stale(f))) load("following", 1)
    } else if (key === "search") {
      Qt.callLater(searchView.focusField)
    }
  }

  function refresh() {
    if (topPage && topPage.kind === "channel") { load("channel:" + topPage.channel.id, 1); return }
    if (tab === "home") { if (cats.length) load("home:" + cat, 1); else fetchHomepage() }
    else if (tab === "following") load("following", 1)
    else if (tab === "search") searchView.run()
  }

  // The clock for "3 days ago", once a minute while the window is up.
  Timer {
    interval: 60000
    repeat: true
    running: root.opened && !root.pinnedNow
    onTriggered: root.nowSec = Date.now() / 1000
  }

  // ------------------------------------------------------------ playing

  // One player for the app. A video page lends it a VideoOutput while it
  // shows the video that is playing (VideoSurface.qml); anywhere else the
  // sound carries on, and the bar under the tabs has it.
  property var playingItem: null
  property bool playingAudio: false
  property bool fullscreen: false
  // The renditions Odysee made of what is playing, tallest first, and the
  // one playing; [] when there are none and the original file plays.
  property var variants: []
  property var variant: null
  readonly property string variantLabel: variant ? variant.label : ""
  // The quality asked for: the phone's default is what its CPU decodes
  // comfortably in software.
  readonly property int wantHeight: parseInt(store.prefs.quality, 10) || (compact ? 720 : 1080)
  property real resumeAt: -1
  property bool triedOriginal: false

  readonly property bool mediaPlaying: media.playbackState === MediaPlayer.PlayingState
  readonly property bool mediaBusy: playingItem !== null && (media.mediaStatus === MediaPlayer.LoadingMedia
    || media.mediaStatus === MediaPlayer.BufferingMedia || media.mediaStatus === MediaPlayer.StalledMedia
    || (media.source.toString() === "" && playingItem !== null))
  readonly property alias media: media

  MediaPlayer {
    id: media
    audioOutput: AudioOutput { id: speaker }
    onMediaStatusChanged: {
      if (mediaStatus === MediaPlayer.LoadedMedia && root.resumeAt >= 0) {
        position = root.resumeAt
        root.resumeAt = -1
      }
      if (mediaStatus === MediaPlayer.EndOfMedia) root.setFullscreen(false)
    }
    onErrorOccurred: function (error, errorString) {
      // A rendition that will not open: once, the original file instead.
      if (root.playingItem && root.variants.length && !root.triedOriginal) {
        root.triedOriginal = true
        root.variants = []
        root.variant = null
        root.loadMedia(L.stream(root.playingItem), media.position)
        return
      }
      root.toast("This video would not play: " + errorString)
    }
  }

  function loadMedia(url, at) {
    resumeAt = at > 0 ? at : -1
    media.source = url
    media.play()
  }

  // Play, or on the video already playing, pause and resume.
  function play(item, audioOnly) {
    if (!L.playable(item)) return
    if (playingItem && playingItem.id === item.id) {
      if (playingAudio !== !!audioOnly) playingAudio = !!audioOnly
      if (!mediaPlaying) media.play()
      return
    }
    if (offline) { toast("This copy is running offline"); return }
    media.stop()
    media.source = ""
    variants = []
    variant = null
    triedOriginal = false
    playingAudio = !!audioOnly
    playingItem = item
    history = L.played(history, item, nowSec)
    saveLibrary()
    // Odysee's renditions when it made them, the file as uploaded when not.
    var id = item.id
    requests.run("hls:" + id, L.get(L.master(item)), function (code, out) {
      if (!root.playingItem || root.playingItem.id !== id) return
      var got = L.split(out)
      var list = code === 0 && got.status === 200 ? L.variants(got.body, L.master(item)) : []
      root.variants = list
      root.variant = L.pick(list, root.wantHeight)
      root.loadMedia(root.variant ? root.variant.url : L.stream(item), 0)
    })
  }

  function togglePause() {
    if (!playingItem) return
    if (mediaPlaying) media.pause()
    else media.play()
  }

  function seekBy(ms) { seekTo(media.position + ms) }
  function seekTo(ms) {
    if (!playingItem || !media.seekable) return
    media.position = Math.max(0, Math.min(media.duration > 0 ? media.duration - 500 : ms, ms))
  }

  // The next quality down, round to the top: one tap on the label.
  function nextQuality() {
    if (variants.length < 2 || !variant) return
    var i = 0
    for (var k = 0; k < variants.length; k++) if (variants[k].url === variant.url) i = k
    var next = variants[(i + 1) % variants.length]
    store.set("quality", String(next.height))
    variant = next
    loadMedia(next.url, media.position)
    toast(next.label)
  }

  function setFullscreen(on) {
    fullscreen = on && playingItem !== null && !playingAudio
    if (fullscreen) resetFocus()
  }

  function stopPlaying() {
    fullscreen = false
    media.stop()
    media.source = ""
    playingItem = null
    variants = []
    variant = null
  }


  // Back out of fullscreen before out of the page.
  pageStepBack: function () {
    if (fullscreen) { setFullscreen(false); return true }
    return false
  }

  // mpv, when somebody would rather: its own window, its own settings.
  // null until asked: whether there is an mpv to play with.
  property var hasMpv: null
  function openInMpv(item) {
    if (!L.playable(item)) return
    if (playingItem && mediaPlaying) media.pause()
    var argv = ["sh", "-c", "command -v mpv >/dev/null 2>&1 || exit 127; exec mpv \"$@\"", "mpv",
                "--referrer=" + L.REFERER, "--ytdl=no",
                // The CDN turns a request away with a 429 now and then, and
                // takes the same one a second later.
                "--stream-lavf-o=reconnect=1,reconnect_streamed=1,reconnect_on_http_error=429,reconnect_delay_max=4",
                "--force-media-title=" + item.title + (item.channel ? " — " + item.channel.title : ""),
                // mpv sizes its window to the video, which on a phone is a
                // floating window three screens wide off the left edge.
                "--force-window=immediate", compact ? "--fs" : "--autofit-larger=90%x90%",
                "--", L.stream(item)]
    if (mpv.running) mpv.running = false
    mpv.command = argv
    mpv.running = true
    history = L.played(history, item, nowSec)
    saveLibrary()
  }

  Process {
    id: mpv
    running: false
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) {
      root.hasMpv = code !== 127
      if (code === 127) root.toast("Opening in mpv needs mpv: sudo pacman -S mpv")
      else if (code === 2) root.toast("Odysee would not hand over the stream just now. Try again in a minute.")
    }
    // qmllint enable signal-handler-parameters
  }

  onQuitting: { if (mpv.running) mpv.running = false; media.stop() }

  // ------------------------------------------------------------ keys

  function shownGrid() {
    if (tab === "home") return homeView
    if (tab === "following") return followingView
    if (tab === "library") return libraryView
    if (tab === "search" && searchView.kind === "videos") return searchView
    return null
  }

  stepBack: function () {
    if (tab === "search" && searchView.query !== "") { searchView.query = ""; return true }
    return false
  }

  keyHandler: function (event) {
    if (inSettings) return
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    var t = event.text
    if (topPage) {
      var it = topPage.kind === "video" ? topPage.item : null
      if (it && (t === "p" || t === " " || t === "k")) {
        if (playingItem && playingItem.id === it.id) togglePause(); else play(it, false)
        event.accepted = true
      }
      else if (it && t === "a") { play(it, true); event.accepted = true }
      else if (it && t === "f") { if (playingItem && playingItem.id === it.id) setFullscreen(!fullscreen); event.accepted = true }
      else if (it && (event.key === Qt.Key_Left || event.key === Qt.Key_Right) && playingItem && playingItem.id === it.id) {
        seekBy(event.key === Qt.Key_Right ? 10000 : -10000)
        event.accepted = true
      }
      else if (it && t === "s") { toggleSave(it); event.accepted = true }
      else if (t === "F") {
        var ch = it ? it.channel : topPage.channel
        if (ch) toggleFollow(ch)
        event.accepted = true
      }
      return
    }
    if (t === "/") { setTab("search"); Qt.callLater(searchView.focusField); event.accepted = true; return }
    if (t === "r") { refresh(); event.accepted = true; return }
    if ((t === "p" || t === " ") && playingItem) { togglePause(); event.accepted = true; return }

    var view = shownGrid()
    if (!view) return
    var grid = view.grid
    var n = grid.count
    var k = event.key
    var step = k === Qt.Key_Right ? 1 : k === Qt.Key_Left ? -1
      : k === Qt.Key_Down ? grid.columns : k === Qt.Key_Up ? -grid.columns : 0
    if (step !== 0) {
      if (!n) return
      view.current = Math.max(0, Math.min(n - 1, (view.current < 0 ? 0 : view.current + step)))
      grid.show(view.current)
      event.accepted = true
      return
    }
    if ((k === Qt.Key_Return || k === Qt.Key_Enter) && view.current >= 0 && view.current < grid.items.length) {
      openVideo(grid.items[view.current])
      event.accepted = true
    }
  }

  // ------------------------------------------------------------ harness

  // MOARCHY_VIDEO_LIBRARY_PAGE (home, search, following, library, video, channel),
  // _CAT, _SEARCH, _KIND, _OPEN (a video id in the first list) and _SHELF:
  // straight onto the screen a screenshot is of.
  function harness() {
    var page = Quickshell.env("MOARCHY_VIDEO_LIBRARY_PAGE") || ""
    if (catNamed(harnessCat)) setCat(harnessCat)
    if (page === "search") {
      setTab("search")
      searchView.kind = Quickshell.env("MOARCHY_VIDEO_LIBRARY_KIND") || "videos"
      searchView.query = Quickshell.env("MOARCHY_VIDEO_LIBRARY_SEARCH") || ""
      searchView.run()
      resetFocus()
    } else if (page === "following" || page === "library") {
      setTab(page)
      libraryView.shelf = Quickshell.env("MOARCHY_VIDEO_LIBRARY_SHELF") || "saved"
    } else if (page === "video" || page === "channel") {
      harnessOpen = page
    }
  }
  property string harnessOpen: ""
  // Wins over the saved category whenever the categories arrive, which on a
  // run with no homepage.json is after harness() has been and gone.
  readonly property string harnessCat: Quickshell.env("MOARCHY_VIDEO_LIBRARY_CAT") || ""
  onFeedsChanged: {
    if (!harnessOpen) return
    var h = feeds["home:" + cat]
    if (!h || !h.items.length) return
    var want = Quickshell.env("MOARCHY_VIDEO_LIBRARY_OPEN") || ""
    var item = h.items[0]
    for (var i = 0; i < h.items.length; i++) if (h.items[i].id === want) item = h.items[i]
    var what = harnessOpen
    harnessOpen = ""
    if (what === "channel" && item.channel) openChannel(item.channel)
    else openVideo(item)
    // MOARCHY_VIDEO_LIBRARY_PLAY: and start it, for a picture of the player.
    if (what === "video" && Quickshell.env("MOARCHY_VIDEO_LIBRARY_PLAY")) {
      play(item, false)
      if (Quickshell.env("MOARCHY_VIDEO_LIBRARY_PLAY") === "full") Qt.callLater(function () { root.setFullscreen(true) })
    }
  }

  IpcHandler {
    target: "video-library"
    function search(text: string): string { root.searchFor(text); return "ok" }
    function open(link: string): string {
      if (!root.isLink(link)) return "not a link"
      root.openLink(link)
      return "ok"
    }
    function play(link: string): string {
      if (!root.isLink(link)) return "not a link"
      root.openLink(link, true)
      return "ok"
    }
    function pause(): string { root.togglePause(); return root.mediaPlaying ? "paused" : "playing" }
    function fullscreen(): string { root.setFullscreen(!root.fullscreen); return root.fullscreen ? "on" : "off" }
    function position(): string { return Math.round(root.media.position / 1000) + "/" + Math.round(root.media.duration / 1000) + " " + root.variantLabel }
    function stop(): string { root.stopPlaying(); return "ok" }
    function playing(): string { return root.playingItem ? root.playingItem.title : "" }
    function following(): string { return root.follows.map(function (c) { return c.name }).join(",") }
    function close(): string { root.dismiss(); return "ok" }
  }

  // A link handed to the shell's summon: { "uri": "https://odysee.com/..." }.
  onSummoned: function (payload) {
    var u = payload && typeof payload === "object" ? String(payload.uri || payload.url || "") : ""
    if (!u && isLink(payloadText)) u = payloadText
    if (u && isLink(u)) Qt.callLater(function () { root.openLink(u) })
  }

  // ------------------------------------------------------------ views

  Item {
    anchors.fill: parent

    Item {
      id: views
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: nowPlaying.visible ? nowPlaying.top : parent.bottom

      HomeView { id: homeView; anchors.fill: parent; app: root; visible: root.tab === "home" }
      SearchView { id: searchView; anchors.fill: parent; app: root; visible: root.tab === "search" }
      FollowingView { id: followingView; anchors.fill: parent; app: root; visible: root.tab === "following" }
      LibraryView { id: libraryView; anchors.fill: parent; app: root; visible: root.tab === "library" }
    }

    // What is playing, under every tab but its own page: tap it for the
    // page, pause or stop it here.
    Rectangle {
      id: nowPlaying
      visible: root.playingItem !== null && !(root.topPage && root.topPage.item && root.topPage.item.id === root.playingItem.id)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: root.compact ? 8 : root.ui.gutter
      anchors.rightMargin: anchors.leftMargin
      anchors.bottomMargin: 8
      height: 60
      radius: root.ui.radius
      color: root.ui.surfaceHigh
      border.width: 1
      border.color: root.ui.accent

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.playingItem) root.openVideo(root.playingItem)
      }
      Thumb {
        id: npPic
        x: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 78
        height: 44
        app: root
        glyph: root.playingAudio ? G.audio : G.video
        glyphSize: 16
        source: root.playingItem ? root.art(root.playingItem.id, root.playingItem.thumb, 156, 88) : ""
      }
      Column {
        anchors.left: npPic.right
        anchors.leftMargin: 12
        anchors.right: npPause.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text {
          text: (root.playingAudio ? "LISTENING" : root.mediaPlaying ? "PLAYING" : "PAUSED") + "  " + L.clock(root.media.position) + " / " + L.clock(root.media.duration)
          color: root.ui.accent
          font.family: root.ui.font
          font.pixelSize: root.ui.fs.xs
          font.weight: Font.Bold
          font.letterSpacing: root.ui.tracking
        }
        Text {
          width: parent.width
          text: root.playingItem ? root.playingItem.title : ""
          color: root.ui.text
          font.family: root.ui.font
          font.pixelSize: root.ui.fs.md
          font.weight: Font.Bold
          elide: Text.ElideRight
        }
      }
      IconButton {
        id: npPause
        anchors.right: npStop.left
        anchors.verticalCenter: parent.verticalCenter
        app: root
        glyph: root.mediaPlaying ? KG.pause : KG.play
        label: root.mediaPlaying ? "Pause" : "Play"
        onClicked: root.togglePause()
      }
      IconButton {
        id: npStop
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        app: root
        glyph: KG.close
        label: "Stop"
        onClicked: root.stopPlaying()
      }
    }
  }
}
