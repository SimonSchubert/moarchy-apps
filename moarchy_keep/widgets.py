"""The two pieces both screens need: the card, and the colour picker."""

from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Gdk, GLib, Gtk, Pango  # noqa: E402

from . import theme  # noqa: E402
from .notes import CARD_ITEMS, Item, Note  # noqa: E402


def icon(*candidates: str) -> str:
    """First of these icon names the live theme actually has.

    Naming an icon that is not installed does not fall back to nothing -- GTK
    renders "image-missing", a broken-image glyph that reads as a bug. The
    phone's icon theme is not the desktop's, so the chain is checked rather
    than assumed.
    """
    display = Gdk.Display.get_default()
    if display is None:
        return candidates[-1] if candidates else "dialog-information-symbolic"
    icons = Gtk.IconTheme.get_for_display(display)
    for name in candidates:
        if icons.has_icon(name):
            return name
    return "dialog-information-symbolic"


def checkbox_glyph(done: bool) -> Gtk.Widget:
    """A checkbox for a *card*, where it is a picture rather than a control.

    Drawn as a CSS box with a tick inside rather than as an insensitive
    Gtk.CheckButton: a greyed-out checkbox says "you may not tick this", which
    is wrong -- tapping the card opens the note, where every box is live.
    """
    box = Gtk.Box()
    box.add_css_class("card-check")
    box.set_valign(Gtk.Align.CENTER)
    if done:
        box.add_css_class("checked")
        tick = Gtk.Image.new_from_icon_name(
            icon("object-select-symbolic", "emblem-ok-symbolic")
        )
        tick.set_pixel_size(10)
        box.append(tick)
    return box


def _label(text: str, css: str, lines: int) -> Gtk.Label:
    label = Gtk.Label(label=text)
    label.add_css_class(css)
    label.set_xalign(0)
    label.set_wrap(True)
    label.set_wrap_mode(Pango.WrapMode.WORD_CHAR)
    label.set_ellipsize(Pango.EllipsizeMode.END)
    label.set_lines(lines)
    label.set_halign(Gtk.Align.FILL)
    return label


class NoteCard(Gtk.Button):
    """One note in the grid.

    A Gtk.Button rather than a box with a click handler, because a button is
    already the thing that is focusable, activatable from the keyboard, and
    announced as "press to activate" -- reimplementing that on a box gets the
    look right and loses all of it.
    """

    def __init__(self, note: Note, on_open, on_menu) -> None:
        super().__init__()
        self.note = note
        self.add_css_class("note-card")
        self.add_css_class(f"note-{note.colour}")
        self.set_can_shrink(True)
        self.connect("clicked", lambda *_: on_open(note))

        # Long press is the only way to reach a per-note action on a
        # touchscreen; the same popover opens with a right click on a desktop.
        press = Gtk.GestureLongPress()
        press.set_touch_only(False)
        press.connect("pressed", lambda *_: on_menu(self, note))
        self.add_controller(press)
        right = Gtk.GestureClick(button=Gdk.BUTTON_SECONDARY)
        right.connect("pressed", lambda *_: on_menu(self, note))
        self.add_controller(right)

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        body.set_margin_top(12)
        body.set_margin_bottom(12)
        body.set_margin_start(12)
        body.set_margin_end(12)
        self.set_child(body)

        if note.title.strip():
            body.append(_label(note.title.strip(), "note-title", 3))

        if note.is_list:
            self._fill_list(body, note)
        elif note.body.strip():
            body.append(_label(note.body.strip(), "note-body", 12))

        if note.is_empty:
            body.append(_label("Empty note", "note-empty-line", 1))

        self.set_tooltip_text(note.title.strip() or None)

    def _fill_list(self, body: Gtk.Box, note: Note) -> None:
        # Open items first, then ticked ones -- the same order as the editor,
        # so a card and the note it opens read the same way.
        ordered = note.open_items + note.done_items
        for item in ordered[:CARD_ITEMS]:
            if not item.text.strip():
                continue
            body.append(self._item_row(item))
        remaining = len([i for i in ordered if i.text.strip()]) - CARD_ITEMS
        if remaining > 0:
            more = Gtk.Label(label=f"+ {remaining} more")
            more.add_css_class("note-more")
            more.set_xalign(0)
            body.append(more)

    @staticmethod
    def _item_row(item: Item) -> Gtk.Widget:
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.append(checkbox_glyph(item.done))
        text = _label(item.text.strip(), "note-item", 2)
        text.set_hexpand(True)
        if item.done:
            # Markup rather than a Pango attribute list, because the label is
            # also ellipsized and wrapped; attributes and ellipsis interact
            # badly, markup does not.
            text.set_markup(f"<s>{GLib.markup_escape_text(item.text.strip())}</s>")
            text.add_css_class("note-done")
        row.append(text)
        return row


class ColourGrid(Gtk.Box):
    """The nine note colours, 3x3, as 44px circles.

    Not a Gtk.ColorDialogButton and not a submenu: picking a colour is the one
    decoration this app has, it is one tap deep in Keep, and a grid of circles
    is legible without a single word of label.
    """

    def __init__(self, selected: str, on_pick) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.on_pick = on_pick
        self.buttons: dict[str, Gtk.ToggleButton] = {}

        grid = Gtk.Grid(row_spacing=8, column_spacing=8)
        grid.set_margin_top(10)
        grid.set_margin_bottom(10)
        grid.set_margin_start(10)
        grid.set_margin_end(10)
        self.append(grid)

        for index, (key, label, _) in enumerate(theme.NOTE_COLOURS):
            button = Gtk.ToggleButton()
            button.add_css_class("swatch")
            button.add_css_class(f"swatch-{key}")
            button.set_tooltip_text(label)
            button.set_active(key == selected)
            if key == "default":
                # The uncoloured swatch is a colour you cannot see, so it needs
                # a mark of its own or it reads as a missing button.
                mark = Gtk.Image.new_from_icon_name(
                    icon("action-unavailable-symbolic", "edit-clear-symbolic")
                )
                mark.set_pixel_size(14)
                button.set_child(mark)
            button.connect("toggled", self._picked, key)
            self.buttons[key] = button
            grid.attach(button, index % 3, index // 3, 1, 1)

    def _picked(self, button: Gtk.ToggleButton, key: str) -> None:
        if not button.get_active():
            # Untoggling the current colour would leave the note with none
            # selected and no way back to it, so the active one stays active.
            if not any(b.get_active() for b in self.buttons.values()):
                button.set_active(True)
            return
        for other_key, other in self.buttons.items():
            if other_key != key and other.get_active():
                other.set_active(False)
        self.on_pick(key)
