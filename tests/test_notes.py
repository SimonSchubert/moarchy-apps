"""The storage layer, tested without a display.

Everything here runs on any machine with a Python -- which is the whole reason
notes.py imports no GTK. The UI needs the GNOME stack and a display server; the
part that can lose someone's notes does not, so it is the part that gets tests.
"""

from __future__ import annotations

import json
import sys
import time
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from tempfile import TemporaryDirectory

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from moarchy_keep.notes import (
    LIST,
    TEXT,
    Item,
    Note,
    Store,
    edited_label,
)


class NoteShape(unittest.TestCase):
    def test_a_note_with_only_whitespace_is_empty(self):
        self.assertTrue(Note(title="  ", body="\n \t").is_empty)
        self.assertFalse(Note(body="x").is_empty)

    def test_a_list_of_blank_items_is_empty(self):
        note = Note(kind=LIST, items=[Item(), Item(text="  ")])
        self.assertTrue(note.is_empty)
        note.items.append(Item(text="milk"))
        self.assertFalse(note.is_empty)

    def test_converting_to_a_list_splits_lines_and_drops_blanks(self):
        note = Note(body="milk\n\n  bread \nsalt")
        note.to_list()
        self.assertEqual(note.kind, LIST)
        self.assertEqual([i.text for i in note.items], ["milk", "bread", "salt"])
        self.assertEqual(note.body, "")

    def test_converting_to_text_keeps_the_ticks(self):
        note = Note(kind=LIST, items=[Item("milk", True), Item("bread", False)])
        note.to_text()
        self.assertEqual(note.kind, TEXT)
        self.assertEqual(note.body, "✓ milk\nbread")
        self.assertEqual(note.items, [])

    def test_search_looks_in_titles_bodies_and_items(self):
        note = Note(kind=LIST, title="Shopping", items=[Item("oat milk")])
        self.assertTrue(note.matches("shop"))
        self.assertTrue(note.matches("MILK"))
        self.assertTrue(note.matches("   "))
        self.assertFalse(note.matches("bicycle"))

    def test_open_and_done_keep_their_order(self):
        note = Note(kind=LIST, items=[Item("a", True), Item("b"), Item("c", True)])
        self.assertEqual([i.text for i in note.open_items], ["b"])
        self.assertEqual([i.text for i in note.done_items], ["a", "c"])


class Serialisation(unittest.TestCase):
    def test_a_note_survives_a_round_trip(self):
        note = Note(
            kind=LIST, title="T", items=[Item("x", True)], colour="sand", pinned=True
        )
        clone = Note.from_dict(note.to_dict())
        self.assertEqual(clone.id, note.id)
        self.assertEqual(clone.title, "T")
        self.assertEqual(clone.colour, "sand")
        self.assertTrue(clone.pinned)
        self.assertEqual([(i.text, i.done) for i in clone.items], [("x", True)])

    def test_only_the_field_in_use_is_written(self):
        self.assertNotIn("items", Note(body="hi").to_dict())
        self.assertNotIn("body", Note(kind=LIST).to_dict())

    def test_junk_fields_do_not_raise(self):
        note = Note.from_dict({"kind": "hologram", "title": 7, "items": ["nope", {}]})
        self.assertEqual(note.title, "7")
        # The list held one dict, which is an item; the bare string is not.
        self.assertEqual(len(note.items), 1)

    def test_an_unknown_kind_with_no_items_reads_as_text(self):
        self.assertEqual(Note.from_dict({"kind": "hologram", "body": "x"}).kind, TEXT)

    def test_a_note_from_a_newer_version_keeps_its_items(self):
        note = Note.from_dict({"kind": "canvas", "items": [{"text": "a"}]})
        self.assertEqual(note.kind, LIST)


class StoreOnDisk(unittest.TestCase):
    def setUp(self):
        self.dir = TemporaryDirectory()
        self.path = Path(self.dir.name) / "notes.json"

    def tearDown(self):
        self.dir.cleanup()

    def test_saving_and_loading(self):
        store = Store(self.path)
        note = store.create(LIST)
        note.title = "Shopping"
        note.items = [Item("milk")]
        store.view = "list"
        store.save()

        again = Store(self.path)
        again.load()
        self.assertEqual(len(again.notes), 1)
        self.assertEqual(again.notes[0].title, "Shopping")
        self.assertEqual(again.view, "list")

    def test_loading_nothing_is_not_an_error(self):
        store = Store(self.path)
        store.load()
        self.assertEqual(store.notes, [])

    def test_a_save_leaves_no_temporary_file(self):
        store = Store(self.path)
        store.create()
        store.save()
        self.assertEqual(
            sorted(p.name for p in self.path.parent.iterdir()), ["notes.json"]
        )

    def test_a_broken_file_is_kept_and_never_overwritten(self):
        self.path.write_text("{ this is not json")
        store = Store(self.path)
        store.load()

        self.assertIsNotNone(store.rescued)
        self.assertEqual(store.notes, [])
        kept = list(self.path.parent.glob("notes.broken-*.json"))
        self.assertEqual(len(kept), 1)
        self.assertEqual(kept[0].read_text(), "{ this is not json")

        # And a save after that must not write over anything: the user's only
        # copy is the file we could not read.
        store.create()
        store.save()
        self.assertFalse(self.path.exists())

    def test_a_file_that_is_json_but_not_ours_is_rescued_too(self):
        self.path.write_text(json.dumps({"notes": "everything"}))
        store = Store(self.path)
        store.load()
        self.assertIsNotNone(store.rescued)

    def test_sections_split_pinned_from_the_rest_newest_first(self):
        store = Store(self.path)
        old = store.create()
        old.title, old.edited = "old", time.time() - 500
        new = store.create()
        new.title, new.edited = "new", time.time()
        stuck = store.create()
        stuck.title, stuck.pinned, stuck.edited = "stuck", True, time.time() - 900

        pinned, others = store.sections()
        self.assertEqual([n.title for n in pinned], ["stuck"])
        self.assertEqual([n.title for n in others], ["new", "old"])

    def test_sections_filter_on_the_query(self):
        store = Store(self.path)
        store.create().title = "Shopping"
        store.create().title = "Sourdough"
        pinned, others = store.sections("sour")
        self.assertEqual(pinned, [])
        self.assertEqual([n.title for n in others], ["Sourdough"])

    def test_delete_reports_where_it_was_so_undo_can_replace_it(self):
        store = Store(self.path)
        first, second, third = store.create(), store.create(), store.create()
        for note, title in ((first, "a"), (second, "b"), (third, "c")):
            note.title = title

        index = store.delete(second)
        self.assertEqual([n.title for n in store.notes], ["c", "a"])
        store.restore(second, index)
        self.assertEqual([n.title for n in store.notes], ["c", "b", "a"])

    def test_deleting_something_already_gone(self):
        store = Store(self.path)
        self.assertEqual(store.delete(Note()), -1)

    def test_drop_empty_only_drops_empty_ones(self):
        store = Store(self.path)
        blank = store.create()
        written = store.create()
        written.body = "something"
        self.assertTrue(store.drop_empty(blank))
        self.assertFalse(store.drop_empty(written))
        self.assertEqual(store.notes, [written])

    def test_a_new_list_starts_with_one_line_to_type_into(self):
        store = Store(self.path)
        self.assertEqual(len(store.create(LIST).items), 1)
        self.assertEqual(store.create(TEXT).items, [])


class EditedLabel(unittest.TestCase):
    def test_today_is_a_time(self):
        now = datetime(2026, 9, 6, 21, 30)
        stamp = now.replace(hour=9, minute=5)
        self.assertEqual(
            edited_label(stamp.timestamp(), now.timestamp()), "Edited 09:05"
        )

    def test_this_year_is_a_day_and_month(self):
        now = datetime(2026, 9, 6, 21, 30)
        stamp = now - timedelta(days=40)
        self.assertEqual(
            edited_label(stamp.timestamp(), now.timestamp()), "Edited 28 Jul"
        )

    def test_older_carries_the_year(self):
        now = datetime(2026, 9, 6, 21, 30)
        stamp = datetime(2024, 3, 2, 8, 0)
        self.assertEqual(
            edited_label(stamp.timestamp(), now.timestamp()), "Edited 2 Mar 2024"
        )


if __name__ == "__main__":
    unittest.main()
