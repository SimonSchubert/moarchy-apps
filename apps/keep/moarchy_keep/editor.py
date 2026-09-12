"""The open note.

Keep's editor is not a form. There is no Save, no field boxes and no separators:
the note fills the screen in its own colour, the title is bigger than the body,
and everything you type is already saved. That is worth copying exactly, because
on a phone every frame of chrome is a line of note you cannot see.

The widgets are the source of truth only while they have focus. Typing writes
straight through to the Note, and the window debounces the write to disk -- so
the app can be killed at any moment and lose, at most, the last half second.
"""

from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gdk, GLib, Gtk, Pango  # noqa: E402

from .notes import Item, Note, edited_label  # noqa: E402
from .widgets import ColourGrid, icon  # noqa: E402


def _struck() -> Pango.AttrList | None:
    """A strikethrough attribute list, or None where Pango will not give us one.

    GTK CSS has no text-decoration, so a ticked item can only be struck through
    with a Pango attribute -- and the constructors for those have not always
    been introspectable. Losing the line is cosmetic; a traceback while typing
    is not, so this degrades to the dim colour the CSS class already applies.
    """
    try:
        attrs = Pango.AttrList()
        attrs.insert(Pango.attr_strikethrough_new(True))
        return attrs
    except (AttributeError, TypeError):  # pragma: no cover - Pango version
        return None


class EditorPage(Adw.NavigationPage):
    def __init__(
        self, note: Note, on_change, on_delete, focus_body: bool = False
    ) -> None:
        super().__init__(title="Note")
        self.note = note
        self.on_change = on_change
        self.on_delete = on_delete
        self._colour_class = f"note-{note.colour}"

        self.toolbar = Adw.ToolbarView()
        # Flat, both ends. A raised toolbar paints its own background, which on
        # a coral note leaves a grey strip along the top and another under the
        # "Edited" line -- the two places the note's colour has to run to the
        # edge of the screen or the page reads as a widget inside a window.
        self.toolbar.set_top_bar_style(Adw.ToolbarStyle.FLAT)
        self.toolbar.set_bottom_bar_style(Adw.ToolbarStyle.FLAT)
        self.toolbar.add_css_class("note-page")
        self.toolbar.add_css_class(self._colour_class)
        self.set_child(self.toolbar)
        self.toolbar.add_top_bar(self._header())

        self.content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.content.set_margin_top(8)
        self.content.set_margin_bottom(24)
        self.content.set_margin_start(16)
        self.content.set_margin_end(16)

        self.title = Gtk.Text(text=note.title)
        self.title.set_placeholder_text("Title")
        self.title.add_css_class("editor-title")
        self.title.connect("changed", self._title_changed)
        # Enter in the title moves to the note, the way Tab would on a keyboard
        # nobody here has.
        self.title.connect("activate", lambda *_: self._focus_first_body())
        self.content.append(self.title)

        self.area = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        # item -> its entry. Holding the Python wrapper here is what keeps it
        # alive: attributes set on a wrapper reached back through
        # get_first_child() are lost when that wrapper is collected.
        self.entries: dict[int, Gtk.Text] = {}
        self.content.append(self.area)

        clamp = Adw.Clamp(maximum_size=700)
        clamp.set_child(self.content)
        scroller = Gtk.ScrolledWindow(vexpand=True)
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_child(clamp)
        self.toolbar.set_content(scroller)
        self.toolbar.add_bottom_bar(self._meta_bar(note))

        self._build_area()
        self.connect("hidden", lambda *_: self._closed())

        if focus_body:
            # A new note exists because someone tapped "Take a note", so the
            # keyboard should already be up when the page settles. Idle, not
            # now: focus set during construction is lost to the navigation
            # animation that follows it.
            GLib.idle_add(self._focus_first_body)

    def _meta_bar(self, note: Note) -> Gtk.Widget:
        """ "Edited 19:59", where Keep puts it: a bar of its own at the bottom.

        Not at the end of the note's text. A note is as tall as what is in it,
        so a stamp underneath sits wherever the text happens to stop -- halfway
        up the screen on a short note, and off the bottom of a long one.
        """
        self.meta = Gtk.Label(label=edited_label(note.edited))
        self.meta.add_css_class("editor-meta")
        self.meta.set_xalign(0)
        bar = Gtk.Box()
        bar.add_css_class("meta-bar")
        bar.set_margin_top(8)
        bar.set_margin_bottom(8)
        bar.set_margin_start(18)
        bar.set_margin_end(18)
        bar.append(self.meta)
        return bar

    # --- chrome ----------------------------------------------------------

    def _header(self) -> Adw.HeaderBar:
        header = Adw.HeaderBar()
        # No title. The note's own title is the first thing under the bar, in
        # the note's own type -- repeating it in the chrome spends a quarter of
        # a 360px bar saying it twice.
        header.set_title_widget(Gtk.Label())

        self.pin = Gtk.ToggleButton()
        self.pin.set_icon_name(icon("view-pin-symbolic", "starred-symbolic"))
        self.pin.set_tooltip_text("Pin note")
        self.pin.set_active(self.note.pinned)
        self.pin.connect("toggled", self._pin_toggled)
        header.pack_end(self.pin)

        colour = Gtk.MenuButton()
        colour.set_icon_name(
            icon(
                "color-select-symbolic",
                "preferences-color-symbolic",
                "applications-graphics-symbolic",
            )
        )
        colour.set_tooltip_text("Colour")
        popover = Gtk.Popover()
        popover.set_child(ColourGrid(self.note.colour, self._recolour))
        colour.set_popover(popover)
        header.pack_end(colour)

        menu = Gtk.MenuButton()
        menu.set_icon_name(icon("view-more-symbolic", "open-menu-symbolic"))
        menu.set_tooltip_text("More")
        self.menu_popover = Gtk.Popover()
        menu.set_popover(self.menu_popover)
        self._fill_menu()
        header.pack_end(menu)

        return header

    def _fill_menu(self) -> None:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        box.set_margin_top(4)
        box.set_margin_bottom(4)
        box.set_margin_start(4)
        box.set_margin_end(4)

        convert = Gtk.Button()
        convert.add_css_class("flat")
        convert.set_child(
            self._menu_row(
                icon("checkbox-checked-symbolic", "object-select-symbolic"),
                "Hide tick boxes" if self.note.is_list else "Tick boxes",
            )
        )
        convert.connect("clicked", self._convert)
        box.append(convert)

        delete = Gtk.Button()
        delete.add_css_class("flat")
        delete.set_child(self._menu_row(icon("user-trash-symbolic"), "Delete note"))
        delete.connect("clicked", lambda *_: self._delete())
        box.append(delete)

        self.menu_popover.set_child(box)

    @staticmethod
    def _menu_row(icon_name: str, label: str) -> Gtk.Widget:
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        row.append(Gtk.Image.new_from_icon_name(icon_name))
        text = Gtk.Label(label=label)
        text.set_xalign(0)
        text.set_hexpand(True)
        row.append(text)
        return row

    # --- the note's body -------------------------------------------------

    def _build_area(self) -> None:
        self.entries.clear()
        child = self.area.get_first_child()
        while child is not None:
            following = child.get_next_sibling()
            self.area.remove(child)
            child = following

        if self.note.is_list:
            self._build_list()
        else:
            self._build_text()

    def _build_text(self) -> None:
        self.buffer = Gtk.TextBuffer()
        self.buffer.set_text(self.note.body)
        view = Gtk.TextView(buffer=self.buffer)
        view.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        view.add_css_class("editor-body")
        view.set_vexpand(True)
        # 200px, so that tapping anywhere in the empty space below a one-line
        # note puts the cursor in the note rather than doing nothing.
        view.set_size_request(-1, 200)
        view.set_top_margin(2)
        self.buffer.connect("changed", self._body_changed)

        placeholder = Gtk.Label(label="Note")
        placeholder.add_css_class("editor-placeholder")
        placeholder.set_xalign(0)
        placeholder.set_yalign(0)
        placeholder.set_visible(not self.note.body)
        placeholder.set_can_target(False)
        self.placeholder = placeholder

        overlay = Gtk.Overlay()
        overlay.set_child(view)
        overlay.add_overlay(placeholder)
        self.area.append(overlay)
        self.text_view = view

    def _build_list(self) -> None:
        self.text_view = None
        open_items = self.note.open_items
        done_items = self.note.done_items

        for item in open_items:
            self.area.append(self._item_row(item))

        add = Gtk.Button()
        add.add_css_class("flat")
        add.add_css_class("add-item")
        add.set_child(self._menu_row(icon("list-add-symbolic"), "List item"))
        add.connect("clicked", lambda *_: self._add_item())
        self.area.append(add)

        if done_items:
            heading = Gtk.Button()
            heading.add_css_class("flat")
            heading.add_css_class("checked-heading")
            self._checked_open = getattr(self, "_checked_open", True)
            heading.set_child(
                self._menu_row(
                    icon(
                        "pan-down-symbolic"
                        if self._checked_open
                        else "pan-end-symbolic"
                    ),
                    f"{len(done_items)} ticked item"
                    + ("s" if len(done_items) != 1 else ""),
                )
            )
            heading.connect("clicked", lambda *_: self._toggle_checked())
            heading.set_margin_top(8)
            self.area.append(heading)

            if self._checked_open:
                for item in done_items:
                    self.area.append(self._item_row(item))

    def _item_row(self, item: Item) -> Gtk.Widget:
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        row.add_css_class("editor-item-row")

        check = Gtk.CheckButton(active=item.done)
        check.set_valign(Gtk.Align.CENTER)
        check.connect("toggled", self._item_toggled, item)
        row.append(check)

        entry = Gtk.Text(text=item.text)
        entry.add_css_class("editor-item")
        entry.set_hexpand(True)
        entry.set_valign(Gtk.Align.CENTER)
        if item.done:
            entry.set_attributes(_struck())
            entry.add_css_class("note-done")
        entry.connect("changed", self._item_changed, item)
        entry.connect("activate", self._item_activated, item)

        keys = Gtk.EventControllerKey()
        keys.connect("key-pressed", self._item_key, item, entry)
        entry.add_controller(keys)
        row.append(entry)

        remove = Gtk.Button(icon_name=icon("window-close-symbolic"))
        remove.add_css_class("flat")
        remove.set_valign(Gtk.Align.CENTER)
        remove.set_tooltip_text("Remove item")
        remove.connect("clicked", lambda *_: self._remove_item(item))
        row.append(remove)

        self.entries[id(item)] = entry
        return row

    # --- edits -----------------------------------------------------------

    def _title_changed(self, entry: Gtk.Text) -> None:
        self.note.title = entry.get_text()
        self._changed()

    def _body_changed(self, buffer: Gtk.TextBuffer) -> None:
        start, end = buffer.get_bounds()
        self.note.body = buffer.get_text(start, end, False)
        self.placeholder.set_visible(not self.note.body)
        self._changed()

    def _item_changed(self, entry: Gtk.Text, item: Item) -> None:
        item.text = entry.get_text()
        self._changed()

    def _item_toggled(self, check: Gtk.CheckButton, item: Item) -> None:
        if item.done == check.get_active():
            return
        item.done = check.get_active()
        # A ticked item leaves the list it was in and joins the ticked group at
        # the bottom, which is a structural change: rebuild rather than restyle.
        self._changed()
        self._build_area()

    def _item_activated(self, entry: Gtk.Text, item: Item) -> None:
        self._add_item(after=item)

    def _item_key(
        self, _controller, keyval, _code, _state, item: Item, entry: Gtk.Text
    ) -> bool:
        """Backspace at the very start of an empty item removes it.

        The one editing gesture worth having beyond typing: a list gets long by
        accident, and reaching for a small delete button for every stray line is
        the slow way out.
        """
        if keyval != Gdk.KEY_BackSpace or entry.get_text():
            return False
        if len(self.note.items) <= 1:
            return False
        self._remove_item(item, focus_previous=True)
        return True

    def _add_item(self, after: Item | None = None) -> None:
        fresh = Item()
        if after is not None and after in self.note.items:
            self.note.items.insert(self.note.items.index(after) + 1, fresh)
        else:
            self.note.items.append(fresh)
        self._changed()
        self._build_area()
        self._focus_item(fresh)

    def _remove_item(self, item: Item, focus_previous: bool = False) -> None:
        if item not in self.note.items:
            return
        index = self.note.items.index(item)
        self.note.items.remove(item)
        if not self.note.items:
            self.note.items.append(Item())
        self._changed()
        self._build_area()
        if focus_previous:
            neighbour = self.note.items[max(0, index - 1)]
            self._focus_item(neighbour, at_end=True)

    def _toggle_checked(self) -> None:
        self._checked_open = not getattr(self, "_checked_open", True)
        self._build_area()

    def _convert(self, _button) -> None:
        self.menu_popover.popdown()
        if self.note.is_list:
            self.note.to_text()
        else:
            self.note.to_list()
            if not self.note.items:
                self.note.items.append(Item())
        self._changed()
        self._build_area()
        self._fill_menu()

    def _pin_toggled(self, button: Gtk.ToggleButton) -> None:
        self.note.pinned = button.get_active()
        button.set_tooltip_text("Unpin note" if self.note.pinned else "Pin note")
        self._changed(touch=False)

    def _recolour(self, key: str) -> None:
        if key == self.note.colour:
            return
        self.note.colour = key
        self.toolbar.remove_css_class(self._colour_class)
        self._colour_class = f"note-{key}"
        self.toolbar.add_css_class(self._colour_class)
        self._changed(touch=False)

    def _delete(self) -> None:
        self.menu_popover.popdown()
        self.on_delete(self.note)

    def _changed(self, touch: bool = True) -> None:
        if touch:
            self.note.touch()
            self.meta.set_label(edited_label(self.note.edited))
        self.on_change(self.note)

    def _closed(self) -> None:
        # Trailing blank items are how a list is typed, not something anyone
        # meant to keep; they would otherwise show up as gaps on the card.
        if self.note.is_list:
            self.note.items = [i for i in self.note.items if i.text.strip()]
        self.on_change(self.note, final=True)

    # --- focus -----------------------------------------------------------

    def _focus_first_body(self) -> bool:
        if self.note.is_list and self.note.items:
            self._focus_item(self.note.items[0], at_end=True)
        elif self.text_view is not None:
            self.text_view.grab_focus()
        return False

    def _focus_item(self, item: Item, at_end: bool = False) -> None:
        entry = self.entries.get(id(item))
        if entry is None:
            return
        entry.grab_focus()
        if at_end:
            entry.set_position(-1)
