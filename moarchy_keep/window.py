"""The grid: every note, two columns wide, newest first.

Built for 360x720 logical pixels rather than scaled down to it. That is one
decision with consequences everywhere: two columns and not four, a bottom bar
instead of a floating button in a corner your thumb cannot reach, 44px tap
targets, and Adw.NavigationView for grid -> note, which is the only navigation
model that works with one column and a back gesture instead of a window
manager.
"""

from __future__ import annotations

import os

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, GLib, Gtk  # noqa: E402

from .editor import EditorPage  # noqa: E402
from .masonry import MasonryBox  # noqa: E402
from .notes import LIST, TEXT, Note, Store  # noqa: E402
from .widgets import ColourGrid, NoteCard, icon  # noqa: E402

# How long after the last keystroke the file is rewritten. Long enough that
# typing a sentence is one write rather than forty, short enough that a note is
# on disk before you can put the phone down.
SAVE_DELAY_MS = 500


class KeepWindow(Adw.ApplicationWindow):
    def __init__(self, store: Store, **kwargs) -> None:
        super().__init__(**kwargs)
        self.store = store
        self.set_title("Notes")
        # A PinePhone's screen, and still resizable on a desktop.
        self.set_default_size(360, 720)

        self._save_source = 0
        self._popover: Gtk.Popover | None = None

        self.toasts = Adw.ToastOverlay()
        self.nav = Adw.NavigationView()
        self.toasts.set_child(self.nav)
        self.set_content(self.toasts)

        self.nav.push(self._grid_page())
        self.refresh()

        if store.rescued is not None:
            self._warn_rescued()

        # Do not let the search entry take focus at startup: the on-screen
        # keyboard raises itself whenever a text field is focused, and half the
        # grid would be behind it before anyone had looked at it.
        GLib.idle_add(self._drop_focus)

        # Debug hooks, matching the store's: start on a particular screen, so
        # the app can be driven on a machine -- or a phone -- with no way to tap
        # a card. MOARCHY_KEEP_OPEN takes a note id or part of a title.
        # MOARCHY_KEEP_NEW takes "text" or "list" and starts a new note with the
        # cursor in it, which is the only way to raise the on-screen keyboard
        # without a finger, and so the only way to photograph what it covers.
        wanted = os.environ.get("MOARCHY_KEEP_OPEN")
        fresh = os.environ.get("MOARCHY_KEEP_NEW")
        if wanted:
            target = store.get(wanted) or next(
                (n for n in store.notes if wanted.lower() in n.title.lower()), None
            )
            if target is not None:
                GLib.idle_add(self._open, target)
        elif fresh in (TEXT, LIST):
            GLib.idle_add(self._new, fresh)

    # --- the grid page ---------------------------------------------------

    def _grid_page(self) -> Adw.NavigationPage:
        header = Adw.HeaderBar()
        self.search = Gtk.SearchEntry()
        self.search.set_placeholder_text("Search your notes")
        self.search.add_css_class("search-pill")
        self.search.set_hexpand(True)
        self.search.connect("search-changed", lambda *_: self.refresh())
        header.set_title_widget(self.search)

        self.view_button = Gtk.Button()
        self.view_button.set_tooltip_text("Switch view")
        self.view_button.connect("clicked", lambda *_: self._toggle_view())
        header.pack_end(self.view_button)
        self._sync_view_button()

        self.body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.body.set_margin_top(6)
        self.body.set_margin_bottom(16)
        self.body.set_margin_start(12)
        self.body.set_margin_end(12)

        clamp = Adw.Clamp(maximum_size=900)
        clamp.set_child(self.body)
        scroller = Gtk.ScrolledWindow(vexpand=True)
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_child(clamp)

        toolbar = Adw.ToolbarView()
        toolbar.add_top_bar(header)
        toolbar.set_content(scroller)
        toolbar.add_bottom_bar(self._bottom_bar())
        return Adw.NavigationPage(child=toolbar, title="Notes")

    def _bottom_bar(self) -> Gtk.Widget:
        bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        bar.add_css_class("keep-bottom-bar")

        take = Gtk.Button(label="Take a note…")
        take.add_css_class("flat")
        take.add_css_class("take-note")
        take.set_hexpand(True)
        take.get_child().set_xalign(0)
        take.connect("clicked", lambda *_: self._new(TEXT))
        bar.append(take)

        new_list = Gtk.Button(
            icon_name=icon("checkbox-checked-symbolic", "view-list-symbolic")
        )
        new_list.add_css_class("flat")
        new_list.add_css_class("take-note")
        new_list.set_tooltip_text("New list")
        new_list.connect("clicked", lambda *_: self._new(LIST))
        bar.append(new_list)
        return bar

    # --- filling it ------------------------------------------------------

    def refresh(self) -> None:
        child = self.body.get_first_child()
        while child is not None:
            following = child.get_next_sibling()
            self.body.remove(child)
            child = following

        query = self.search.get_text()
        pinned, others = self.store.sections(query)

        if not pinned and not others:
            self.body.append(self._nothing(query))
            return

        # The headings only earn their line when there is a division to
        # explain: with nothing pinned, "OTHERS" labels the entire app.
        labelled = bool(pinned) and bool(others) and not query.strip()
        if pinned:
            self._section("PINNED" if labelled else "", pinned)
        if others:
            self._section("OTHERS" if labelled else "", others)

    def _section(self, heading: str, notes: list[Note]) -> None:
        if heading:
            label = Gtk.Label(label=heading)
            label.add_css_class("section-heading")
            label.set_xalign(0)
            label.set_margin_top(10)
            label.set_margin_bottom(2)
            self.body.append(label)

        grid = MasonryBox(minimum_column=150, spacing=10)
        grid.set_limit(1 if self.store.view == "list" else 5)
        for note in notes:
            grid.add(NoteCard(note, self._open, self._card_menu))
        self.body.append(grid)

    def _nothing(self, query: str) -> Gtk.Widget:
        if query.strip():
            return Adw.StatusPage(
                title="No matching notes",
                description=f"Nothing here matches “{query.strip()}”",
                icon_name=icon("system-search-symbolic"),
            )
        page = Adw.StatusPage(
            title="Notes you add appear here",
            description="Tap “Take a note…” to write one, or the tick box for a list.",
            icon_name=icon("document-edit-symbolic", "text-editor-symbolic"),
        )
        page.set_vexpand(True)
        return page

    # --- actions ---------------------------------------------------------

    def _new(self, kind: str) -> None:
        note = self.store.create(kind)
        self._open(note, fresh=True)

    def _open(self, note: Note, fresh: bool = False) -> bool:
        self.nav.push(
            EditorPage(note, self._note_changed, self._delete, focus_body=fresh)
        )
        return False  # so it can be used as an idle callback

    def _note_changed(self, note: Note, final: bool = False) -> None:
        """Called on every keystroke in the editor, and once when it closes.

        The grid is not rebuilt until the editor closes. It is behind the
        editor and cannot be seen, and rebuilding it would mean re-laying out
        every card in the app once per character typed.
        """
        if not final:
            self._schedule_save()
            return
        # A note nobody typed into is discarded rather than left as a blank
        # card, which is what Keep does with a note you open and back out of.
        self.store.drop_empty(note)
        self._flush()
        self.refresh()

    def _delete(self, note: Note) -> None:
        index = self.store.delete(note)
        if index < 0:
            return
        if isinstance(self.nav.get_visible_page(), EditorPage):
            self.nav.pop()
        self._flush()
        self.refresh()

        toast = Adw.Toast(title="Note deleted")
        toast.set_button_label("Undo")
        toast.connect("button-clicked", lambda *_: self._undelete(note, index))
        self.toasts.add_toast(toast)

    def _undelete(self, note: Note, index: int) -> None:
        self.store.restore(note, index)
        self._flush()
        self.refresh()

    def _card_menu(self, card: NoteCard, note: Note) -> None:
        """Long press on a card: pin, recolour, delete, without opening it."""
        if self._popover is not None:
            self._popover.unparent()

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        box.set_margin_top(4)
        box.set_margin_bottom(4)
        box.set_margin_start(4)
        box.set_margin_end(4)

        pin = Gtk.Button()
        pin.add_css_class("flat")
        pin.set_child(
            _menu_row(
                icon("view-pin-symbolic", "starred-symbolic"),
                "Unpin" if note.pinned else "Pin",
            )
        )
        pin.connect("clicked", lambda *_: self._toggle_pin(note))
        box.append(pin)

        box.append(ColourGrid(note.colour, lambda key: self._recolour(note, key)))

        delete = Gtk.Button()
        delete.add_css_class("flat")
        delete.set_child(_menu_row(icon("user-trash-symbolic"), "Delete"))
        delete.connect("clicked", lambda *_: self._menu_delete(note))
        box.append(delete)

        popover = Gtk.Popover()
        popover.set_child(box)
        popover.set_parent(card)
        popover.set_position(Gtk.PositionType.BOTTOM)
        popover.connect("closed", self._menu_closed)
        self._popover = popover
        popover.popup()

    def _menu_closed(self, popover: Gtk.Popover) -> None:
        if popover is self._popover:
            self._popover = None
        # Unparent on an idle rather than here: the popover is mid-signal, and
        # tearing it down inside its own "closed" handler crashes GTK.
        GLib.idle_add(popover.unparent)

    def _toggle_pin(self, note: Note) -> None:
        note.pinned = not note.pinned
        self._close_menu()
        self._flush()
        self.refresh()

    def _recolour(self, note: Note, key: str) -> None:
        note.colour = key
        self._close_menu()
        self._flush()
        self.refresh()

    def _menu_delete(self, note: Note) -> None:
        self._close_menu()
        self._delete(note)

    def _close_menu(self) -> None:
        if self._popover is not None:
            self._popover.popdown()

    def _toggle_view(self) -> None:
        self.store.view = "list" if self.store.view == "grid" else "grid"
        self._sync_view_button()
        self._flush()
        self.refresh()

    def _sync_view_button(self) -> None:
        grid = self.store.view == "grid"
        self.view_button.set_icon_name(
            icon("view-list-symbolic")
            if grid
            else icon("view-grid-symbolic", "view-app-grid-symbolic")
        )
        self.view_button.set_tooltip_text("Single column" if grid else "Grid")

    # --- saving ----------------------------------------------------------

    def _schedule_save(self) -> None:
        if self._save_source:
            GLib.source_remove(self._save_source)
        self._save_source = GLib.timeout_add(SAVE_DELAY_MS, self._save_now)

    def _save_now(self) -> bool:
        self._save_source = 0
        try:
            self.store.save()
        except OSError as exc:
            self.toasts.add_toast(
                Adw.Toast(title=f"Could not save: {exc.strerror or exc}")
            )
        return False  # one-shot

    def _flush(self) -> None:
        """Save immediately, cancelling any pending debounce."""
        if self._save_source:
            GLib.source_remove(self._save_source)
            self._save_source = 0
        self._save_now()

    def shutdown(self) -> None:
        self._flush()

    # --- odds and ends ---------------------------------------------------

    def _warn_rescued(self) -> None:
        toast = Adw.Toast(
            title=f"Unreadable notes file kept as {self.store.rescued.name}"
        )
        toast.set_timeout(0)
        self.toasts.add_toast(toast)

    def _drop_focus(self) -> bool:
        self.set_focus(None)
        return False


def _menu_row(icon_name: str, label: str) -> Gtk.Widget:
    row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
    row.append(Gtk.Image.new_from_icon_name(icon_name))
    text = Gtk.Label(label=label)
    text.set_xalign(0)
    text.set_hexpand(True)
    row.append(text)
    return row
