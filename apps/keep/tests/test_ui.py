"""The window, driven by calling it rather than by tapping it.

scripts/interact.sh taps real coordinates, which is the honest test but a
blunt one: every assertion costs a pixel position that changes when the layout
does. These tests build the real widgets on a real display and call the same
methods the buttons call, which is how the paths that are awkward to tap --
deleting a note and undoing it, switching the view, the long-press menu -- get
covered at all.

Needs a display. Skipped where there is none, so `python3 -m unittest` on a
machine without GTK still runs the storage tests rather than erroring.
"""

from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

REASON = ""
try:
    import gi

    gi.require_version("Gtk", "4.0")
    gi.require_version("Adw", "1")
    from gi.repository import Adw, Gtk

    if not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        REASON = "no display"
    elif not Gtk.init_check():
        REASON = "GTK could not open the display"
except (ImportError, ValueError) as exc:  # pragma: no cover - depends on host
    REASON = f"no GTK: {exc}"

if not REASON:
    Adw.init()
    from moarchy_keep.editor import EditorPage
    from moarchy_keep.masonry import MasonryBox
    from moarchy_keep.widgets import NoteCard
    from moarchy_keep.window import KeepWindow

from moarchy_keep.notes import LIST, TEXT, Item, Store  # noqa: E402


@unittest.skipIf(REASON, REASON)
class WindowActions(unittest.TestCase):
    def setUp(self):
        self.dir = TemporaryDirectory()
        self.store = Store(Path(self.dir.name) / "notes.json")
        self.window = KeepWindow(self.store)

    def tearDown(self):
        self.window.destroy()
        self.dir.cleanup()

    def test_the_grid_holds_a_card_for_every_note(self):
        for title in ("one", "two", "three"):
            self.store.create().title = title
        self.window.refresh()
        self.assertEqual(len(self._cards()), 3)

    def test_pinned_notes_are_in_their_own_section(self):
        self.store.create().title = "ordinary"
        pinned = self.store.create()
        pinned.title, pinned.pinned = "stuck", True
        self.window.refresh()
        headings = [
            child.get_label()
            for child in self._children(self.window.body)
            if isinstance(child, Gtk.Label)
        ]
        self.assertEqual(headings, ["PINNED", "OTHERS"])

    def test_search_narrows_the_grid(self):
        self.store.create().title = "Shopping"
        self.store.create().title = "Sourdough"
        self.window.search.set_text("shop")
        # Gtk.SearchEntry holds "search-changed" back for ~150ms so that a
        # word typed on a phone is one rebuild of the grid rather than four.
        # That the signal arrives is scripts/interact.sh's business; this is
        # about what the grid does with it.
        self.window.refresh()
        self.assertEqual([c.note.title for c in self._cards()], ["Shopping"])

    def test_deleting_a_note_can_be_undone_back_into_place(self):
        first, second, third = (self.store.create() for _ in range(3))
        for note, title in ((first, "a"), (second, "b"), (third, "c")):
            note.title = title
        self.window.refresh()

        self.window._delete(second)
        self.assertEqual([n.title for n in self.store.notes], ["c", "a"])
        self.assertEqual(len(self._cards()), 2)
        # And it is on disk, not just in the list: delete flushes rather than
        # waiting for the debounce, because the toast that offers undo does not.
        self.assertNotIn('"title": "b"', self.store.path.read_text())

        self.window._undelete(second, 1)
        self.assertEqual([n.title for n in self.store.notes], ["c", "b", "a"])
        self.assertEqual(len(self._cards()), 3)
        self.assertIn('"title": "b"', self.store.path.read_text())

    def test_the_view_toggle_switches_to_one_column_and_is_remembered(self):
        self.store.create().title = "one"
        self.window.refresh()
        grid = self._grids()[0]
        self.assertGreater(grid.masonry.columns_for(360), 1)

        self.window._toggle_view()
        self.assertEqual(self.store.view, "list")
        self.assertEqual(self._grids()[0].masonry.columns_for(360), 1)

        again = Store(self.store.path)
        again.load()
        self.assertEqual(again.view, "list")

    def test_pinning_from_the_card_menu_moves_the_note_and_saves(self):
        note = self.store.create()
        note.title = "one"
        self.window.refresh()
        self.window._toggle_pin(note)
        self.assertTrue(note.pinned)
        self.assertIn('"pinned": true', self.store.path.read_text())

    def test_recolouring_from_the_card_menu_restyles_the_card(self):
        note = self.store.create()
        note.title = "one"
        self.window.refresh()
        self.window._recolour(note, "mint")
        self.assertTrue(self._cards()[0].has_css_class("note-mint"))

    def test_the_long_press_menu_opens_and_can_be_closed(self):
        self.store.create().title = "one"
        self.window.refresh()
        card = self._cards()[0]
        self.window._card_menu(card, card.note)
        self.assertIsNotNone(self.window._popover)
        self.window._close_menu()

    def test_an_empty_note_is_dropped_when_its_editor_closes(self):
        note = self.store.create()
        self.window._note_changed(note, final=True)
        self.assertEqual(self.store.notes, [])

    # --- helpers ---------------------------------------------------------

    @staticmethod
    def _children(widget):
        child, out = widget.get_first_child(), []
        while child is not None:
            out.append(child)
            child = child.get_next_sibling()
        return out

    def _grids(self):
        return [
            c for c in self._children(self.window.body) if isinstance(c, MasonryBox)
        ]

    def _cards(self):
        return [card for grid in self._grids() for card in self._children(grid)]


@unittest.skipIf(REASON, REASON)
class Editor(unittest.TestCase):
    def setUp(self):
        self.dir = TemporaryDirectory()
        self.store = Store(Path(self.dir.name) / "notes.json")
        self.changes = []

    def tearDown(self):
        self.dir.cleanup()

    def _page(self, note):
        return EditorPage(
            note, lambda n, final=False: self.changes.append(final), lambda n: None
        )

    def test_typing_a_title_reaches_the_note(self):
        note = self.store.create(TEXT)
        page = self._page(note)
        page.title.set_text("Shopping")
        self.assertEqual(note.title, "Shopping")
        self.assertTrue(self.changes)

    def test_typing_a_body_reaches_the_note(self):
        note = self.store.create(TEXT)
        page = self._page(note)
        page.buffer.set_text("two loaves")
        self.assertEqual(note.body, "two loaves")

    def test_adding_and_removing_list_items(self):
        note = self.store.create(LIST)
        page = self._page(note)
        page._add_item(after=note.items[0])
        self.assertEqual(len(note.items), 2)
        page._remove_item(note.items[1])
        self.assertEqual(len(note.items), 1)

    def test_a_list_always_keeps_one_line_to_type_into(self):
        note = self.store.create(LIST)
        page = self._page(note)
        page._remove_item(note.items[0])
        self.assertEqual(len(note.items), 1)

    def test_converting_between_a_list_and_text_rebuilds_the_page(self):
        note = self.store.create(TEXT)
        note.body = "milk\nbread"
        page = self._page(note)
        page._convert(None)
        self.assertEqual([i.text for i in note.items], ["milk", "bread"])
        page._convert(None)
        self.assertEqual(note.body, "milk\nbread")

    def test_ticking_an_item_moves_it_below_the_heading(self):
        note = self.store.create(LIST)
        note.items = [Item("milk"), Item("bread")]
        page = self._page(note)
        page._item_toggled(Gtk.CheckButton(active=True), note.items[0])
        self.assertTrue(note.items[0].done)
        self.assertEqual([i.text for i in note.open_items], ["bread"])

    def test_closing_drops_the_blank_lines_a_list_was_typed_with(self):
        note = self.store.create(LIST)
        note.items = [Item("milk"), Item(""), Item("  ")]
        page = self._page(note)
        page._closed()
        self.assertEqual([i.text for i in note.items], ["milk"])
        self.assertIn(True, self.changes)

    def test_the_colour_is_applied_to_the_page(self):
        note = self.store.create(TEXT)
        page = self._page(note)
        page._recolour("sand")
        self.assertEqual(note.colour, "sand")
        self.assertTrue(page.toolbar.has_css_class("note-sand"))
        self.assertFalse(page.toolbar.has_css_class("note-default"))


@unittest.skipIf(REASON, REASON)
class MasonryLayout(unittest.TestCase):
    def test_columns_follow_the_width(self):
        box = MasonryBox(minimum_column=150, spacing=10)
        self.assertEqual(box.masonry.columns_for(336), 2)  # a phone, less margins
        self.assertEqual(box.masonry.columns_for(150), 1)
        self.assertEqual(box.masonry.columns_for(0), 1)
        box.set_limit(1)
        self.assertEqual(box.masonry.columns_for(900), 1)

    def test_a_card_goes_into_the_shortest_column(self):
        box = MasonryBox(minimum_column=150, spacing=10)
        store = Store("/nonexistent")
        tall = store.create(TEXT)
        tall.body = "\n".join(f"line {i}" for i in range(30))
        short = store.create(TEXT)
        short.title = "short"
        second_short = store.create(TEXT)
        second_short.title = "also short"
        for note in (tall, short, second_short):
            box.add(NoteCard(note, lambda *_: None, lambda *_: None))

        placements, height = box.masonry._place(box, 340)
        xs = [x for _, x, _, _, _ in placements]
        # First card left, second right, and the third goes back to the right
        # because the tall one is still the taller column.
        self.assertEqual(xs[0], 0)
        self.assertGreater(xs[1], 0)
        self.assertEqual(xs[2], xs[1])
        self.assertGreater(height, 0)


if __name__ == "__main__":
    unittest.main()
