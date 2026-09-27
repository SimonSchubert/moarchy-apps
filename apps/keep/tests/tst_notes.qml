// The notes and their file, against the GTK version's notes.py (0.1.1): the
// cases test_notes.py had, so a file one of them wrote reads the same in the
// other. The part that can lose somebody's notes is the part with the tests.
import QtQuick
import QtTest
import "../Notes.js" as N

TestCase {
  name: "KeepNotes"

  function note(fields) { return N.noteFrom(fields || {}) }
  function list(items, fields) {
    var f = fields || {}
    f.kind = "list"
    f.items = items
    return N.noteFrom(f)
  }
  function roundTrip(store) { return N.parse(JSON.parse(N.serialize(store))) }

  // --- shape

  function test_a_note_with_only_whitespace_is_empty() {
    verify(N.isEmpty(note({ title: "  ", body: "\n \t" })))
    verify(!N.isEmpty(note({ body: "x" })))
  }

  function test_a_list_of_blank_items_is_empty() {
    verify(N.isEmpty(list([{ text: "" }, { text: "  " }])))
    verify(!N.isEmpty(list([{ text: "" }, { text: "milk" }])))
  }

  function test_converting_to_a_list_splits_lines_and_drops_blanks() {
    var n = N.toList(note({ body: "milk\n\n  bread \nsalt" }))
    compare(n.kind, "list")
    compare(n.items.map(function (i) { return i.text }), ["milk", "bread", "salt"])
    compare(n.body, "")
  }

  function test_converting_to_text_keeps_the_ticks() {
    var n = N.toText(list([{ text: "milk", done: true }, { text: "bread" }]))
    compare(n.kind, "text")
    compare(n.body, "✓ milk\nbread")
    compare(n.items, [])
  }

  function test_a_tick_comes_back_as_a_tick() {
    var n = N.toList(N.toText(list([{ text: "milk", done: true }, { text: "bread" }])))
    compare(n.items, [{ text: "milk", done: true }, { text: "bread", done: false }])
  }

  function test_search_looks_in_titles_bodies_and_items() {
    var n = list([{ text: "oat milk" }], { title: "Shopping" })
    verify(N.matches(n, "shop"))
    verify(N.matches(n, "MILK"))
    verify(N.matches(n, "   "))
    verify(!N.matches(n, "bicycle"))
  }

  function test_open_and_done_keep_their_order() {
    var n = list([{ text: "a", done: true }, { text: "b" }, { text: "c", done: true }])
    compare(N.openItems(n).map(function (i) { return i.text }), ["b"])
    compare(N.doneItems(n).map(function (i) { return i.text }), ["a", "c"])
  }

  // --- the file

  function test_a_note_survives_a_round_trip() {
    var n = list([{ text: "x", done: true }], { title: "T", colour: "sand", pinned: true })
    var back = roundTrip({ notes: [n], view: "grid" }).notes[0]
    compare(back.id, n.id)
    compare(back.title, "T")
    compare(back.colour, "sand")
    verify(back.pinned)
    compare(back.items, [{ text: "x", done: true }])
  }

  function test_only_the_field_in_use_is_written() {
    verify(!("items" in N.noteTo(note({ body: "hi" }))))
    verify(!("body" in N.noteTo(list([]))))
  }

  function test_junk_fields_do_not_raise() {
    var n = note({ kind: "hologram", title: 7, items: ["nope", {}] })
    compare(n.title, "7")
    // The list held one object, which is an item; the bare string is not.
    compare(n.items.length, 1)
  }

  function test_an_unknown_kind_with_no_items_reads_as_text() {
    compare(note({ kind: "hologram", body: "x" }).kind, "text")
  }

  function test_a_note_from_a_newer_version_keeps_its_items() {
    compare(note({ kind: "canvas", items: [{ text: "a" }] }).kind, "list")
  }

  function test_saving_and_loading() {
    var n = N.create("list")
    n.title = "Shopping"
    n.items = [{ text: "milk", done: false }]
    var back = roundTrip({ notes: [n], view: "list" })
    compare(back.notes.length, 1)
    compare(back.notes[0].title, "Shopping")
    compare(back.view, "list")
  }

  function test_the_file_is_the_shape_notes_py_wrote() {
    var raw = JSON.parse(N.serialize({ notes: [note({ id: "abc", body: "hi", created: 1, edited: 2 })], view: "grid" }))
    compare(raw.schema, 1)
    compare(raw.view, "grid")
    compare(raw.notes[0], { id: "abc", kind: "text", title: "", colour: "default", pinned: false, created: 1, edited: 2, body: "hi" })
  }

  function test_loading_nothing_is_not_an_error() {
    compare(N.parse(null).notes, [])
  }

  function test_a_file_that_is_json_but_not_ours_is_not_ours() {
    verify(!N.valid({ notes: "everything" }))
    verify(!N.valid({}))
    verify(N.valid({ notes: [] }))
  }

  // --- the collection

  function test_sections_split_pinned_from_the_rest_newest_first() {
    var t = N.now()
    var store = { notes: [
      note({ title: "old", edited: t - 500 }),
      note({ title: "new", edited: t }),
      note({ title: "stuck", pinned: true, edited: t - 900 })
    ], view: "grid" }
    var s = N.sections(store, "")
    compare(s.pinned.map(function (n) { return n.title }), ["stuck"])
    compare(s.others.map(function (n) { return n.title }), ["new", "old"])
  }

  function test_sections_filter_on_the_query() {
    var store = { notes: [note({ title: "Shopping" }), note({ title: "Sourdough" })], view: "grid" }
    var s = N.sections(store, "sour")
    compare(s.pinned, [])
    compare(s.others.map(function (n) { return n.title }), ["Sourdough"])
  }

  function test_delete_reports_where_it_was_so_undo_can_replace_it() {
    var a = note({ title: "a" }), b = note({ title: "b" }), c = note({ title: "c" })
    var store = N.put(N.put(N.put(N.emptyStore(), a), b), c)
    compare(store.notes.map(function (n) { return n.title }), ["c", "b", "a"])
    var gone = N.remove(store, b.id)
    compare(gone.index, 1)
    compare(gone.store.notes.map(function (n) { return n.title }), ["c", "a"])
    compare(N.restore(gone.store, gone.note, gone.index).notes.map(function (n) { return n.title }), ["c", "b", "a"])
  }

  function test_deleting_something_already_gone() {
    compare(N.remove(N.emptyStore(), "nothing").index, -1)
  }

  function test_putting_a_note_back_replaces_it_in_place() {
    var a = note({ title: "a" }), b = note({ title: "b" })
    var store = N.put(N.put(N.emptyStore(), a), b)
    var edited = N.clone(a)
    edited.title = "A"
    compare(N.put(store, edited).notes.map(function (n) { return n.title }), ["b", "A"])
  }

  function test_a_new_list_starts_with_one_line_to_type_into() {
    compare(N.create("list").items.length, 1)
    compare(N.create("text").items, [])
  }

  function test_trailing_blank_items_go_when_a_list_is_closed() {
    compare(N.tidy(list([{ text: "milk" }, { text: " " }, { text: "" }])).items, [{ text: "milk", done: false }])
  }

  function test_a_card_shows_open_items_first_and_counts_the_rest() {
    var items = []
    for (var i = 0; i < 10; i++) items.push({ text: "i" + i, done: i < 2 })
    var p = N.preview(list(items))
    compare(p.items.length, 7)
    compare(p.items[0].text, "i2")
    compare(p.more, 3)
  }

  function test_columns_keep_the_order_and_fill_the_shortest() {
    var notes = [note({ title: "a", body: "1\n2\n3\n4\n5\n6" }), note({ title: "b" }), note({ title: "c" })]
    var cols = N.columns(notes, 2)
    compare(cols[0].map(function (n) { return n.title }), ["a"])
    compare(cols[1].map(function (n) { return n.title }), ["b", "c"])
  }

  // --- the stamp

  function test_today_is_a_time() {
    var now = new Date(2026, 8, 6, 21, 30).getTime() / 1000
    compare(N.editedLabel(new Date(2026, 8, 6, 9, 5).getTime() / 1000, now), "Edited 09:05")
  }

  function test_this_year_is_a_day_and_month() {
    var now = new Date(2026, 8, 6, 21, 30).getTime() / 1000
    compare(N.editedLabel(now - 40 * 86400, now), "Edited 28 Jul")
  }

  function test_older_carries_the_year() {
    var now = new Date(2026, 8, 6, 21, 30).getTime() / 1000
    compare(N.editedLabel(new Date(2024, 2, 2, 8, 0).getTime() / 1000, now), "Edited 2 Mar 2024")
  }
}
