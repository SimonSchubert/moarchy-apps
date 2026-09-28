import QtQuick
import Quickshell
import Quickshell.Io
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G
import "OpenLibrary.js" as OL

// Books: Open Library's catalogue -- what its readers are opening this week,
// the most-read books in fifteen subjects, search by title, author, subject or
// ISBN, a page for every book and author -- and a reading list of your own:
// what you want to read, what you are reading and how far, and what you have
// read, with your stars and the year's count against a goal.
//
//     omarchy-shell shell toggle org.moarchy.books
//
// Every question is one curl (Requests.qml) to a public endpoint
// (OpenLibrary.js), at most four at once, and only while the window is open:
// a hidden Books asks nothing and keeps no clock. The reading list is one
// file on this machine, with no account behind it.
//
// A phone gets the tabs at the bottom and three covers to a row; a desktop,
// the tabs in the rail and as many as fit. A book, an author or a whole shelf
// is a page over the tab either way.
App {
  id: root

  appId: "org.moarchy.books"
  title: "Books"
  subtitle: statusText()
  caption: "From Open Library"
  windowWidth: 1280
  windowHeight: 840

  store: Store { name: "moarchy-books"; defaults: ({ goal: 12 }) }

  launcher.desktopId: "org.moarchy.Books"
  launcher.genericName: "Reading list"
  launcher.comment: "Discover books on Open Library and keep track of what you read"
  launcher.categories: "Education;Literature;"
  launcher.keywords: "books;reading;library;open library;isbn;author;novel;goodreads;want to read;"

  mark: Component { Image { source: root.appDir + "/icon.svg"; sourceSize: Qt.size(60, 60) } }

  ui: Tokens {
    theme: root.hostTheme
    compact: root.compact
    // The cloth a book with no cover picture is bound in: the theme's own
    // hues, taken most of the way to dark so a title in cream reads on any
    // of them.
    function bind(name, darkFallback, lightFallback) {
      return Qt.tint(hue(name, darkFallback, lightFallback), alpha("#16130f", 0.55))
    }
    readonly property var cloth: [
      bind("red", "#f87171", "#b91c1c"), bind("blue", "#60a5fa", "#1d4ed8"),
      bind("green", "#4ade80", "#15803d"), bind("magenta", "#e879f9", "#a21caf"),
      bind("yellow", "#facc15", "#a16207"), bind("cyan", "#22d3ee", "#0e7490")
    ]
    readonly property color clothInk: "#f3ede2"
    // Over a cover, which is dark or light at random: the same in every
    // theme, because the picture is.
    readonly property color scrimStrong: alpha("#000000", 0.55)
    readonly property color inkOnGood: dark ? "#10140f" : "#ffffff"
  }

  tabs: [
    { key: "discover", label: "Discover", glyph: G.discover },
    { key: "search", label: "Search", glyph: KG.search },
    { key: "library", label: "My books", glyph: G.library }
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
      blurb: "Open Library's catalogue and a reading list of your own: what to read next, what you are reading and how far, and what you read, with your stars. No account; the list stays on this machine."
      SettingsSection {
        app: root
        width: parent.width
        title: "Reading goal"
        note: "How many books you mean to finish this year. My books counts the ones you mark Read against it. Zero hides it."
        Row {
          spacing: 8
          IconButton { anchors.verticalCenter: parent.verticalCenter; app: root; glyph: KG.minus; label: "Fewer"; onClicked: root.setGoal(root.goal - 1) }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 110
            horizontalAlignment: Text.AlignHCenter
            text: root.goal > 0 ? root.goal + (root.goal === 1 ? " book" : " books") : "No goal"
            color: root.ui.text
            font.family: root.ui.font
            font.pixelSize: root.ui.fs.lg
            font.weight: Font.Bold
          }
          IconButton { anchors.verticalCenter: parent.verticalCenter; app: root; glyph: KG.plus; label: "More"; onClicked: root.setGoal(root.goal + 1) }
        }
      }
      AppearanceSection { app: root }
      LauncherSection { app: root }
      KeysSection {
        app: root
        keys: [
          ["1 – 3", "Discover, Search, My books"],
          ["/", "Search"],
          ["← → ↑ ↓  Enter", "Move through a grid, open a book"],
          ["w", "Want to read, on a book"],
          ["c", "Currently reading, on a book"],
          ["d", "Done: read, on a book"],
          ["+  -", "Ten pages on or back, on a book you are reading"],
          ["o", "Open on openlibrary.org"],
          ["r", "Refresh"],
          [",", "Settings"],
          ["Esc", "Back one step"]
        ]
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Where it comes from"
        note: "Open Library, the Internet Archive's open catalogue of every book, without an account: openlibrary.org for search, trending, subjects, books, authors and ratings, and covers.openlibrary.org for covers and photos. Each request says it is Books. Nothing is asked while the window is closed."
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Where it keeps things"
        note: "~/.local/share/moarchy-books: library.json, your three shelves, the page you are on and your stars; and discover.json, the shelves on Discover as last seen, so they open with no signal."
      }
    }
  }

  // A book, an author or a shelf, over the tab: { kind: "book", book },
  // { kind: "author", author } or { kind: "shelf", key, label }.
  page: Component {
    Loader {
      sourceComponent: !root.topPage ? null
        : root.topPage.kind === "author" ? authorPage
        : root.topPage.kind === "shelf" ? shelfPage : bookPage
    }
  }

  Component {
    id: bookPage
    BookPage {
      readonly property var work: book ? root.works[book.id] || null : null
      readonly property var firstAuthor: authors.length && OL.isAuthor(authors[0].id) ? authors[0] : null
      readonly property string moreKey: firstAuthor ? "by:" + firstAuthor.id : ""
      app: root
      book: root.topPage ? root.topPage.book : null
      detail: work ? work.detail : null
      ratings: work ? work.ratings : null
      counts: work ? work.counts : null
      entry: book ? root.shelved[book.id] || null : null
      more: moreKey ? root.feeds[moreKey] || null : null
      loading: !work || work.loading
      error: work ? work.error : ""
      onAuthorOpened: function (a) { root.openAuthor(a) }
      onSubjectOpened: function (name) { root.openSubject(name) }
      onBookOpened: function (b) { root.openBook(b) }
      onRetry: if (book) root.loadWork(book.id, true)
      onMoreKeyChanged: if (moreKey) root.want(moreKey)
      Component.onCompleted: if (moreKey) root.want(moreKey)
    }
  }

  Component {
    id: authorPage
    AuthorPage {
      readonly property string key: author ? "by:" + author.id : ""
      readonly property var info: author ? root.authorInfo[author.id] || null : null
      app: root
      author: root.topPage ? root.topPage.author : null
      detail: info ? info.detail : null
      error: info ? info.error : ""
      feed: key ? root.feeds[key] || null : null
      onBookOpened: function (b) { root.openBook(b) }
      onWantMore: root.loadMore(key)
      onRetry: { root.load(key, 1); if (author) root.loadAuthor(author.id, true) }
    }
  }

  Component {
    id: shelfPage
    ShelfPage {
      app: root
      key: root.topPage ? root.topPage.key : ""
      label: root.topPage ? root.topPage.label : ""
      feed: key ? root.feeds[key] || null : null
      onBookOpened: function (b) { root.openBook(b) }
      onWantMore: root.loadMore(key)
      onRetry: root.load(key, 1)
    }
  }

  // ------------------------------------------------------------ state

  // MOARCHY_BOOKS_OFFLINE: never open a socket -- answers come from
  // fixture.json, when dev/demo.py left one. MOARCHY_BOOKS_NOW: a frozen
  // clock, so "this year" is the same year in every screenshot.
  // MOARCHY_BOOKS_COVERS: a folder of pictures by number, in place of the CDN.
  readonly property bool offline: (Quickshell.env("MOARCHY_BOOKS_OFFLINE") || "") !== ""
  readonly property real pinnedNow: parseFloat(Quickshell.env("MOARCHY_BOOKS_NOW") || "0") || 0
  readonly property string coversDir: Quickshell.env("MOARCHY_BOOKS_COVERS") || ""
  property real nowSec: pinnedNow || Date.now() / 1000

  // Every list fetched a page at a time, by key: trending, subject:<key>,
  // by:<author id>, search:<books|authors>:<text>.
  property var feeds: ({})
  readonly property var emptyFeed: ({ items: [], page: 0, more: false, loading: false, error: "", at: 0, total: 0 })

  // A work's page, by id: { loading, error, detail, ratings, counts, at }.
  property var works: ({})
  // An author's page, by id: { loading, error, detail }.
  property var authorInfo: ({})

  // The reading list, and lookups into it for the views.
  property var books: []
  property bool libraryRead: false
  readonly property var shelved: {
    var m = {}
    for (var i = 0; i < books.length; i++) m[books[i].id] = books[i]
    return m
  }
  readonly property var readingNow: OL.onShelf(books, "reading")
  readonly property int goal: Math.max(0, parseInt(store.prefs.goal, 10) || 0)

  function statusText() {
    if (offline) return "Offline"
    if (requests.busy > 0) return "Loading…"
    return ""
  }

  function countText(n, word) { return OL.plural(n, word) }

  // A cover: from the CDN, or from the harness's folder. Offline with no
  // folder, none: the book is drawn in its cloth.
  function coverSource(id, size) {
    if (!(id > 0)) return ""
    if (coversDir) return "file://" + coversDir + "/" + id + "-" + size + ".jpg"
    if (offline) return ""
    return OL.coverUrl(id, size)
  }

  function authorPhotoSource(authorId, photoId, size) {
    if (coversDir) return photoId > 0 ? "file://" + coversDir + "/a" + photoId + ".jpg" : ""
    if (offline) return ""
    return photoId > 0 ? OL.photoUrl(photoId, size) : OL.authorPhotoUrl(authorId, size)
  }

  // Who wrote it: the list's names when it had them, else the work's author
  // ids with the names their own pages gave.
  function authorsOf(book, detail) {
    if (book && book.authors && book.authors.length) return book.authors
    var ids = detail ? detail.authorIds : []
    var out = []
    for (var i = 0; i < ids.length; i++) {
      var info = authorInfo[ids[i]]
      if (info && info.detail) out.push({ id: ids[i], name: info.detail.name })
    }
    return out
  }

  function copyLink(url) {
    if (!url) return
    Quickshell.clipboardText = url
    toast("Link copied")
  }

  function setGoal(n) { store.set("goal", Math.max(0, Math.min(365, n))) }

  // ------------------------------------------------------------ opening things

  function openBook(b) {
    if (!b || !OL.isWork(b.id)) return
    resetFocus()
    push({ kind: "book", book: b, title: b.title || "Book" })
    loadWork(b.id, false)
  }

  function openAuthor(a) {
    if (!a || !OL.isAuthor(a.id)) return
    resetFocus()
    push({ kind: "author", author: a, title: a.name || "Author" })
    loadAuthor(a.id, false)
    want("by:" + a.id)
  }

  function openShelf(key, label) {
    resetFocus()
    push({ kind: "shelf", key: key, label: label, title: label })
    want(key)
  }

  function openSubject(name) {
    var k = OL.subjectKey(name)
    if (k) openShelf("subject:" + k, name)
  }

  function searchFor(text) {
    stack = []
    setTab("search")
    searchView.kind = "books"
    searchView.query = text
    searchView.run()
  }

  // An openlibrary.org link, an OLID or an ISBN: opened as what it names.
  function openLink(text) {
    var l = OL.link(text)
    if (!l) return false
    if (l.kind === "work") { openBook({ id: l.id, title: "", authors: [], cover: 0 }); return true }
    if (l.kind === "author") { openAuthor({ id: l.id, name: "" }); return true }
    requests.run("isbn:" + l.id, OL.search(l.id, 1), function (code, out) {
      var r = OL.answer(code, out)
      var found = r.error ? [] : OL.books(r.data)
      if (found.length) root.openBook(found[0])
      else root.toast(r.error || "No book in Open Library has ISBN " + l.id)
    })
    return true
  }

  // ------------------------------------------------------------ the reading list

  function shelve(book, shelf) {
    if (!book || !libraryRead) return
    var before = books
    var r = OL.shelve(books, book, shelf, nowSec)
    if (r.full) { toast(OL.MAX_BOOKS + " books is as many as this list keeps"); return }
    books = r.list
    saveLibrary()
    var said = !r.on ? "Taken off your shelves"
      : shelf === "want" ? "On Want to read"
      : shelf === "reading" ? "Reading — it waits at the top of Discover"
      : "Read. Give it your stars."
    toast(said, "Undo", function () { root.books = before; root.saveLibrary() })
  }

  function setPage(id, page) {
    var e = shelved[id]
    if (!e) return
    books = OL.setPage(books, id, page)
    saveLibrary()
    var now = shelved[id]
    if (now && now.pages > 0 && now.page >= now.pages && e.page < e.pages)
      toast("The last page. Finished it?", "Mark read", function () { root.shelve(now, "read") })
  }

  function setStars(id, stars) {
    books = OL.setStars(books, id, stars)
    saveLibrary()
  }

  function saveLibrary() {
    if (!libraryRead) return
    libraryFile.save(OL.serializeLibrary(books))
  }

  DataFile {
    id: libraryFile
    app: "books"
    name: "library.json"
    onParsed: function (data) {
      root.books = OL.parseLibrary(data)
      root.libraryRead = true
      root.start()
    }
    onQuarantined: function (to) { root.toast("The reading list was unreadable and was kept aside") }
  }

  // Discover's shelves as last seen.
  DataFile {
    id: shelvesFile
    app: "books"
    name: "discover.json"
    onParsed: function (data) {
      var saved = OL.parseShelves(data)
      var m = Object.assign({}, root.feeds)
      for (var k in saved)
        if (!m[k] || !m[k].items.length)
          m[k] = Object.assign({}, root.emptyFeed, { items: saved[k].items, at: saved[k].at, total: saved[k].total, page: 1, more: true })
      root.feeds = m
      root.shelvesRead = true
      root.start()
    }
  }
  property bool shelvesRead: false
  Timer {
    id: shelvesSave
    interval: 1500
    onTriggered: if (!root.offline) shelvesFile.save(OL.serializeShelves(root.feeds))
  }

  // Offline, the answers a real run would have had.
  DataFile {
    id: fixtureFile
    app: "books"
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

  function isShelf(key) { return key === "trending" || key.indexOf("subject:") === 0 }
  function stale(key, f) { return !f.at || nowSec - f.at > (isShelf(key) ? OL.SHELF_TTL : 15 * 60) }

  function setFeed(key, patch) {
    var m = Object.assign({}, feeds)
    m[key] = Object.assign({}, feeds[key] || emptyFeed, patch)
    feeds = m
  }

  // A list on screen that has nothing, or something old: asked for.
  function want(key) {
    if (!started || !key) return
    var f = feeds[key]
    if (!f || (!f.loading && !f.error && (!f.items.length || stale(key, f)))) load(key, 1)
  }

  function loadMore(key) {
    var f = feeds[key]
    if (f && f.more && !f.loading) load(key, f.page + 1)
  }

  // One page of one list. Page 1 replaces what is there when it arrives, not
  // before: a refresh that fails leaves the books on screen.
  function load(key, page) {
    if (!key) return
    var f = feeds[key] || emptyFeed
    if (f.loading && page > 1) return
    var token = Date.now() + Math.random()
    setFeed(key, { loading: true, error: "", token: token })
    var parts = key.split(":")
    var kind = parts[0]
    var argv = kind === "trending" ? OL.trending(page)
      : kind === "subject" ? OL.subject(parts[1], page)
      : kind === "by" ? OL.byAuthor(parts[1], page)
      : kind === "search" && parts[1] === "authors" ? OL.authorSearch(parts.slice(2).join(":"), page)
      : kind === "search" ? OL.search(parts.slice(2).join(":"), page)
      : null
    if (!argv) return
    requests.run(key + ":" + page, argv, function (code, out) {
      var cur = root.feeds[key]
      if (!cur || cur.token !== token) return
      var r = OL.answer(code, out)
      if (r.error) { root.setFeed(key, { loading: false, error: r.error }); return }
      var got = key.indexOf("search:authors:") === 0 ? OL.authors(r.data) : OL.books(r.data)
      var raw = r.data.docs ? r.data.docs.length : r.data.works ? r.data.works.length : 0
      var total = OL.total(r.data)
      root.setFeed(key, {
        loading: false, error: "", page: page, at: root.nowSec, total: total,
        more: raw >= OL.PAGE && (total === 0 || page * OL.PAGE < total),
        items: page === 1 ? got : OL.append(cur.items, got)
      })
      if (page === 1 && root.isShelf(key)) shelvesSave.restart()
    })
  }

  function search(kind, text) {
    var key = "search:" + kind + ":" + text
    // Only the search on screen is kept.
    var m = {}
    for (var k in feeds) if (k.indexOf("search:") !== 0 || k === key) m[k] = feeds[k]
    feeds = m
    var f = feeds[key]
    if (!f || (!f.items.length && !f.loading) || stale(key, f)) load(key, 1)
  }

  function setWork(id, patch) {
    var m = Object.assign({}, works)
    m[id] = Object.assign({ loading: false, error: "", detail: null, ratings: null, counts: null, at: 0 }, works[id] || {}, patch)
    works = m
  }

  // A book's page: the work, its ratings, and how many have it on a shelf --
  // three small answers, each drawn as it lands.
  function loadWork(id, force) {
    var w = works[id]
    if (w && (w.loading || (!force && w.detail && nowSec - w.at < 3600))) return
    setWork(id, { loading: true, error: "" })
    var left = 3
    function landed() { if (--left === 0) root.setWork(id, { loading: false, at: root.nowSec }) }
    requests.run("work:" + id, OL.work(id), function (code, out) {
      var r = OL.answer(code, out)
      if (r.error) root.setWork(id, { error: r.error })
      else {
        var d = OL.workDetail(r.data)
        root.setWork(id, { detail: d })
        // A book opened from a link came with no names.
        for (var i = 0; i < d.authorIds.length && i < 3; i++) root.loadAuthor(d.authorIds[i], false)
      }
      landed()
    })
    requests.run("ratings:" + id, OL.ratings(id), function (code, out) {
      var r = OL.answer(code, out)
      if (!r.error) root.setWork(id, { ratings: OL.ratingsDetail(r.data) })
      landed()
    })
    requests.run("shelves:" + id, OL.bookshelves(id), function (code, out) {
      var r = OL.answer(code, out)
      if (!r.error) root.setWork(id, { counts: OL.shelvesDetail(r.data) })
      landed()
    })
  }

  function loadAuthor(id, force) {
    var a = authorInfo[id]
    if (a && (a.loading || (a.detail && !force))) return
    var m = Object.assign({}, authorInfo)
    m[id] = { loading: true, error: "", detail: a ? a.detail : null }
    authorInfo = m
    requests.run("author:" + id, OL.author(id), function (code, out) {
      var r = OL.answer(code, out)
      var n = Object.assign({}, root.authorInfo)
      n[id] = { loading: false, error: r.error, detail: r.error ? (a ? a.detail : null) : OL.authorDetail(r.data) }
      root.authorInfo = n
    })
  }

  // The first time the window is up with the files read.
  property bool started: false
  function start() {
    if (started || !opened || !libraryRead || !shelvesRead || (offline && !fixtureRead)) return
    started = true
    harness()
  }

  onOpenedChanged: {
    if (!opened) return
    nowSec = pinnedNow || Date.now() / 1000
    start()
  }

  onTabSelected: function (key) {
    if (key === "search") Qt.callLater(searchView.focusField)
  }

  function refresh() {
    if (topPage) {
      if (topPage.kind === "book") loadWork(topPage.book.id, true)
      else if (topPage.kind === "author") { load("by:" + topPage.author.id, 1); loadAuthor(topPage.author.id, true) }
      else if (topPage.kind === "shelf") load(topPage.key, 1)
      return
    }
    if (tab === "discover") {
      for (var k in feeds) if (isShelf(k)) load(k, 1)
    } else if (tab === "search") searchView.run()
  }

  // The clock for "this year", once an hour while the window is up.
  Timer {
    interval: 3600 * 1000
    repeat: true
    running: root.opened && !root.pinnedNow
    onTriggered: root.nowSec = Date.now() / 1000
  }

  // ------------------------------------------------------------ keys

  function shownGrid() {
    if (tab === "library") return libraryView
    if (tab === "search" && searchView.kind === "books" && searchView.term !== "") return searchView
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
      var b = topPage.kind === "book" ? topPage.book : null
      if (b && (t === "w" || t === "c" || t === "d")) {
        shelve(b, t === "w" ? "want" : t === "c" ? "reading" : "read")
        event.accepted = true
      } else if (b && (t === "+" || t === "-") && shelved[b.id] && shelved[b.id].shelf === "reading") {
        setPage(b.id, (shelved[b.id].page || 0) + (t === "+" ? 10 : -10))
        event.accepted = true
      } else if (t === "o") {
        if (b) Qt.openUrlExternally(OL.workWeb(b.id))
        else if (topPage.kind === "author") Qt.openUrlExternally(OL.authorWeb(topPage.author.id))
        event.accepted = true
      } else if (t === "r") { refresh(); event.accepted = true }
      return
    }
    if (t === "/") { setTab("search"); Qt.callLater(searchView.focusField); event.accepted = true; return }
    if (t === "r") { refresh(); event.accepted = true; return }

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
      openBook(grid.items[view.current])
      event.accepted = true
    }
  }

  // ------------------------------------------------------------ harness

  // MOARCHY_BOOKS_PAGE (discover, search, library, book, author, shelf),
  // _OPEN (a work id, an author id or a shelf key), _SEARCH, _KIND and
  // _SHELF: straight onto the screen a screenshot is of.
  function harness() {
    var page = Quickshell.env("MOARCHY_BOOKS_PAGE") || ""
    var open = Quickshell.env("MOARCHY_BOOKS_OPEN") || ""
    if (page === "search") {
      setTab("search")
      searchView.kind = Quickshell.env("MOARCHY_BOOKS_KIND") || "books"
      searchView.query = Quickshell.env("MOARCHY_BOOKS_SEARCH") || ""
      searchView.run()
      resetFocus()
    } else if (page === "library") {
      setTab("library")
      libraryView.shelf = Quickshell.env("MOARCHY_BOOKS_SHELF") || "reading"
    } else if (page === "shelf" && open) {
      openShelf(open, open === "trending" ? "Trending" : OL.subjectLabel(open.replace(/^subject:/, "")))
    } else if (page === "author" && OL.isAuthor(open)) {
      openAuthor({ id: open, name: "" })
    } else if (page === "book" && OL.isWork(open)) {
      harnessBook = open
      harnessFind()
      harnessGiveUp.start()
    }
  }
  property string harnessBook: ""
  // The book as a list had it, so the page opens as it would from a tap.
  function harnessFind() {
    if (!harnessBook) return
    var found = shelved[harnessBook] || null
    for (var k in feeds) {
      if (found) break
      var items = feeds[k].items || []
      for (var i = 0; i < items.length; i++) if (items[i].id === harnessBook) { found = items[i]; break }
    }
    if (!found) return
    harnessBook = ""
    openBook(found)
  }
  onFeedsChanged: harnessFind()
  Timer {
    id: harnessGiveUp
    interval: 1500
    onTriggered: if (root.harnessBook) {
      var id = root.harnessBook
      root.harnessBook = ""
      root.openBook({ id: id, title: "", authors: [], cover: 0 })
    }
  }

  IpcHandler {
    target: "books"
    function search(text: string): string { root.searchFor(text); return "ok" }
    function open(link: string): string { return root.openLink(link) ? "ok" : "not a book, an author or an ISBN" }
    function reading(): string {
      return root.readingNow.map(function (e) { return e.title + " (" + OL.progressText(e) + ")" }).join("\n")
    }
    function shelf(name: string): string {
      return OL.onShelf(root.books, name).map(function (e) { return e.title }).join("\n")
    }
    function close(): string { root.dismiss(); return "ok" }
  }

  // A link or an ISBN handed to the shell's summon -- { "uri": "..." }, or
  // bare, as xdg-open hands one over -- opens what it names; { "query": "..." }
  // searches.
  onSummoned: function (payload) {
    var p = payload && typeof payload === "object" ? payload : ({})
    var u = String(p.uri || p.url || p.isbn || "")
    if (!u && payloadText.trim().charAt(0) !== "{") u = payloadText.trim()
    var q = String(p.query || "")
    if (u && OL.link(u)) Qt.callLater(function () { root.openLink(u) })
    else if (q) Qt.callLater(function () { root.searchFor(q) })
  }

  // ------------------------------------------------------------ views

  DiscoverView { id: discoverView; anchors.fill: parent; app: root; visible: root.tab === "discover" }
  SearchView { id: searchView; anchors.fill: parent; app: root; visible: root.tab === "search" }
  LibraryView { id: libraryView; anchors.fill: parent; app: root; visible: root.tab === "library" }
}
