// Somebody else's JSON, our own file, and every figure on screen.
//
// Nothing here touches the network: the answers are what curl would have
// printed -- a body, a newline, a status -- so the failures worth testing,
// a 429 or a body that is not JSON, can be had on demand.
import QtQuick
import QtTest
import "../OpenLibrary.js" as OL

TestCase {
  name: "Books"

  readonly property var dune: ({
    key: "/works/OL893414W", title: "Dune", author_name: ["Frank Herbert"], author_key: ["OL79034A"],
    cover_i: 11481354, first_publish_year: 1965, edition_count: 155, number_of_pages_median: 608,
    ratings_average: 4.3049326, ratings_count: 446, want_to_read_count: 3426, already_read_count: 727
  })

  function said(body, status) { return JSON.stringify(body) + "\n" + (status || 200) }

  // --- reading answers

  function test_book() {
    var b = OL.book(dune)
    compare(b.id, "OL893414W")
    compare(b.title, "Dune")
    compare(b.authors, [{ id: "OL79034A", name: "Frank Herbert" }])
    compare(b.cover, 11481354)
    compare(b.year, 1965)
    compare(b.pages, 608)
    compare(b.editions, 155)
    compare(OL.rating(b.rating), "4.3")
  }

  function test_trending_uses_cover_id_and_no_ratings() {
    var b = OL.book({ key: "/works/OL17930368W", title: "Atomic Habits", author_name: ["James Clear"], author_key: ["OL7422948A"], cover_id: 12539702 })
    compare(b.cover, 12539702)
    compare(b.rating, 0)
    compare(b.year, 0)
  }

  function test_not_books() {
    compare(OL.book(null), null)
    compare(OL.book({ key: "/books/OL27918581M", title: "An edition" }), null)
    compare(OL.book({ key: "/authors/OL79034A", name: "Frank Herbert" }), null)
    var untitled = OL.book({ key: "/works/OL1W" })
    compare(untitled.title, "Untitled")
    compare(untitled.authors, [])
  }

  function test_books_once_each_from_docs_or_works() {
    var twice = OL.books({ docs: [dune, dune, { key: "/works/OL893461W", title: "Dune Messiah" }] })
    compare(twice.length, 2)
    compare(OL.books({ works: [dune] }).length, 1)
    compare(OL.books({}).length, 0)
    compare(OL.books(null).length, 0)
  }

  function test_authors_from_search() {
    var a = OL.authors({ docs: [{ key: "OL26320A", name: "J.R.R. Tolkien", birth_date: "3 January 1892", death_date: "2 September 1973", top_work: "The Hobbit", work_count: 346 }, { key: "nonsense" }] })
    compare(a.length, 1)
    compare(a[0].id, "OL26320A")
    compare(OL.lifespan(a[0]), "1892 – 1973")
    compare(OL.lifespan({ born: "1947" }), "born 1947")
    compare(OL.lifespan({}), "")
    compare(OL.initials("Ursula K. Le Guin"), "UG")
    compare(OL.initials("Homer"), "H")
    compare(OL.initials(""), "?")
  }

  function test_answer() {
    compare(OL.answer(0, said({ docs: [] })).error, "")
    verify(OL.answer(0, said({}, 429)).error.indexOf("rate-limiting") > 0)
    verify(OL.answer(0, said({}, 503)).error.indexOf("trouble") > 0)
    verify(OL.answer(0, said({}, 404)).error.indexOf("no such page") > 0)
    verify(OL.answer(0, "<html>oops</html>\n200").error.indexOf("not JSON") > 0)
    verify(OL.answer(28, "").error.indexOf("too long") > 0)
    verify(OL.answer(6, "").error.indexOf("No answer") === 0)
    verify(OL.answer(0, "null\n200").error.indexOf("empty") > 0)
  }

  function test_work_detail() {
    var d = OL.workDetail({
      title: "Dune", covers: [11481354, -1, 12375564],
      authors: [{ author: { key: "/authors/OL79034A" } }, { author: { key: "/authors/OL79034A" } }],
      description: { type: "/type/text", value: "Set on **Arrakis**.\r\n\r\nSee [the film](https://x.y).\r\n\r\n----------\r\n\r\nAlso contained in: [Dune Chronicles](https://openlibrary.org/works/OL1W)" },
      subjects: ["Science fiction", "Fiction", "nyt:mass-market-monthly=2021-11-07", "Science-fiction", "Dune (Imaginary place)", "Ecology", "award:hugo_award=1966"],
      first_publish_date: "1965",
      excerpts: [{ excerpt: "A beginning is the time for taking the most delicate care." }]
    })
    compare(d.cover, 11481354)
    compare(d.authorIds, ["OL79034A"])
    compare(d.description, "Set on Arrakis.\n\nSee the film.")
    compare(d.subjects, ["Science fiction", "Ecology"])
    compare(d.published, "1965")
    compare(d.excerpt, "A beginning is the time for taking the most delicate care.")
  }

  function test_ratings_and_shelves() {
    var r = OL.ratingsDetail({ summary: { average: 4.3, count: 446 }, counts: { "1": 6, "2": 15, "3": 46, "4": 149, "5": 230 } })
    compare(r.counts, [6, 15, 46, 149, 230])
    compare(r.count, 446)
    compare(OL.ratingsDetail({}).counts, [0, 0, 0, 0, 0])
    var s = OL.shelvesDetail({ counts: { want_to_read: 3426, currently_reading: 257, already_read: 727 } })
    compare(s.want, 3426)
    compare(s.reading, 257)
  }

  function test_author_detail() {
    var a = OL.authorDetail({ key: "/authors/OL79034A", name: "Frank Herbert", bio: "American author.", photos: [-1, 14852808],
      links: [{ url: "https://dunenovels.com" }, { url: "https://en.wikipedia.org/wiki/Frank_Herbert" }], birth_date: "8 October 1920" })
    compare(a.id, "OL79034A")
    compare(a.photo, 14852808)
    compare(a.wikipedia, "https://en.wikipedia.org/wiki/Frank_Herbert")
    compare(OL.lifespan(a), "born 1920")
  }

  // --- where things are

  function test_urls() {
    compare(OL.coverUrl(11481354, "L"), "https://covers.openlibrary.org/b/id/11481354-L.jpg")
    compare(OL.coverUrl(0), "")
    compare(OL.photoUrl(7), "https://covers.openlibrary.org/a/id/7-M.jpg")
    compare(OL.authorPhotoUrl("OL79034A", "S"), "https://covers.openlibrary.org/a/olid/OL79034A-S.jpg?default=false")
    var argv = OL.search("the hobbit", 2)
    compare(argv[0], "curl")
    var url = argv[argv.length - 1]
    verify(url.indexOf("q=the%20hobbit") > 0)
    verify(url.indexOf("page=2") > 0)
    verify(OL.subject("science_fiction", 1)[argv.length - 1].indexOf("subject_key%3Ascience_fiction") > 0)
    verify(argv.indexOf("User-Agent: " + OL.AGENT) > 0)
  }

  function test_links() {
    compare(OL.link("https://openlibrary.org/works/OL893414W/Dune"), { kind: "work", id: "OL893414W" })
    compare(OL.link("ol893414w"), { kind: "work", id: "OL893414W" })
    compare(OL.link("openlibrary.org/authors/OL79034A/Frank_Herbert"), { kind: "author", id: "OL79034A" })
    compare(OL.link("978-0-441-01359-3"), { kind: "isbn", id: "9780441013593" })
    compare(OL.link("044101359x"), { kind: "isbn", id: "044101359X" })
    compare(OL.link("dune"), null)
    compare(OL.link("1965"), null)
  }

  function test_subject_keys() {
    compare(OL.subjectKey("Science fiction"), "science_fiction")
    compare(OL.subjectKey("  Mystery & detective stories "), "mystery_detective_stories")
    compare(OL.subjectLabel("science_fiction"), "Science fiction")
    compare(OL.subjectLabel("space_opera"), "Space opera")
  }

  // --- saying it

  function test_figures() {
    compare(OL.count(999), "999")
    compare(OL.count(3426), "3.4k")
    compare(OL.count(12500), "13k")
    compare(OL.count(2500000), "2.5M")
    compare(OL.grouped(1234567), "1,234,567")
    compare(OL.plural(1, "page"), "1 page")
    compare(OL.plural(608, "page"), "608 pages")
    compare(OL.facts(OL.book(dune), null), ["1965", "608 pages", "155 editions"])
    compare(OL.byline(OL.book(dune)), "Frank Herbert · 1965")
    compare(OL.names({ authors: [{ name: "A" }, { name: "B" }, { name: "C" }] }), "A, B and others")
  }

  // --- the reading list

  function test_shelving() {
    var b = OL.book(dune)
    var r = OL.shelve([], b, "want", 1000)
    verify(r.on)
    compare(r.list.length, 1)
    compare(r.list[0].shelf, "want")
    compare(r.list[0].added, 1000)

    r = OL.shelve(r.list, b, "reading", 2000)
    compare(r.list.length, 1)
    compare(r.list[0].shelf, "reading")
    compare(r.list[0].started, 2000)
    compare(r.list[0].added, 1000)

    var list = OL.setPage(r.list, b.id, 700)
    compare(list[0].page, 608)
    list = OL.setPage(list, b.id, -3)
    compare(list[0].page, 0)
    list = OL.setPage(list, b.id, 152)
    compare(OL.progress(list[0]), 0.25)
    compare(OL.progressText(list[0]), "Page 152 of 608  ·  25%")

    r = OL.shelve(list, b, "read", 3000)
    compare(r.list[0].finished, 3000)
    compare(r.list[0].page, 608)
    list = OL.setStars(r.list, b.id, 4)
    compare(list[0].stars, 4)
    list = OL.setStars(list, b.id, 4)
    compare(list[0].stars, 0)

    // The shelf it is on, tapped again, takes it off.
    r = OL.shelve(list, b, "read", 4000)
    verify(!r.on)
    compare(r.list.length, 0)
  }

  function test_shelves_in_order() {
    var list = []
    list = OL.shelve(list, { id: "OL1W", title: "One" }, "read", 100).list
    list = OL.shelve(list, { id: "OL2W", title: "Two" }, "read", 300).list
    list = OL.shelve(list, { id: "OL3W", title: "Three" }, "want", 200).list
    compare(OL.onShelf(list, "read").map(function (e) { return e.id }), ["OL2W", "OL1W"])
    compare(OL.counts(list), { want: 1, reading: 0, read: 2 })
  }

  function test_year() {
    var jan2026 = Date.UTC(2026, 0, 15) / 1000
    var dec2025 = Date.UTC(2025, 11, 15) / 1000
    var list = [
      { id: "OL1W", shelf: "read", finished: jan2026, pages: 300 },
      { id: "OL2W", shelf: "read", finished: dec2025, pages: 200 },
      { id: "OL3W", shelf: "reading", pages: 100 }
    ]
    compare(OL.yearStats(list, Date.UTC(2026, 8, 28) / 1000), { year: 2026, books: 1, pages: 300 })
  }

  function test_library_file() {
    var list = OL.shelve([], OL.book(dune), "reading", 1000).list
    var back = OL.parseLibrary(JSON.parse(OL.serializeLibrary(list)))
    compare(back.length, 1)
    compare(back[0].title, "Dune")
    compare(back[0].authors[0].name, "Frank Herbert")
    compare(back[0].shelf, "reading")

    // A bad book is dropped, not the file.
    var mixed = OL.parseLibrary({ books: [null, { id: "nope", shelf: "read" }, { id: "OL1W", shelf: "lost" },
      { id: "OL2W", shelf: "want", title: "Kept", stars: 9, authors: [null, { name: "X" }] }, { id: "OL2W", shelf: "read" }] })
    compare(mixed.length, 1)
    compare(mixed[0].title, "Kept")
    compare(mixed[0].stars, 5)
    compare(mixed[0].authors, [{ id: "", name: "X" }])
    compare(OL.parseLibrary(null), [])
  }

  function test_discover_file() {
    var feeds = {
      trending: { items: [OL.book(dune)], at: 50, total: 0 },
      "subject:fantasy": { items: [], at: 50 },
      "search:books:dune": { items: [OL.book(dune)], at: 50 }
    }
    var back = OL.parseShelves(JSON.parse(OL.serializeShelves(feeds)))
    compare(Object.keys(back), ["trending"])
    compare(back.trending.items[0].id, "OL893414W")
    compare(OL.parseShelves({ feeds: { x: { items: [{ id: "bad" }] } } }), {})
  }

  function test_plain() {
    compare(OL.plain("A [link][1] and _this_.\n\n[1]: https://x"), "A link and this.")
    compare(OL.plain({ value: "<b>Bold</b> text" }), "Bold text")
    compare(OL.plain(null), "")
  }
}
