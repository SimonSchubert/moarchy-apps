"""The clear button a text field on a phone has to have.

On a desktop an unwanted value in a field is Ctrl+A and a keystroke. On this
phone it is one backspace per character on an on-screen keyboard that is already
covering half the window, and the field that hurts most is the one that came
pre-filled: opening a habit to rename it starts you with eleven characters to
delete before you can type the first one of yours.

`Gtk.SearchEntry` carries this control already, which is why Keep's and Vitals'
search fields did not need anything doing to them and are not touched. What has
no such thing is `Adw.EntryRow` -- libadwaita gives it an apply button and a
whole prefix/suffix mechanism and no clear -- so this is the missing half, in
one place so that every app's version of it behaves the same way.

Four decisions, all of which are about a thumb rather than about GTK:

  * It appears only while there is something to clear. Drawn always, it is a
    control that does nothing for as long as the row is empty, sitting exactly
    where the row's own text ends.
  * 44x44, which is `moarchy_habits.widgets.TARGET` and `docs/style.md` E1 in
    the shell: the floor for a thumb, and well over the 34 a flat icon button
    is by default.
  * It cannot take focus. A `Gtk.Button` that does takes it from the entry, the
    text-input hint goes with it, and the on-screen keyboard retracts -- so
    clearing a field to retype it would put the keyboard away every time.
  * The icon name goes through `icons.icon()`, because naming one the device's
    theme does not have never fails: GTK draws "image-missing" and logs
    nothing (see `icons.py`).
"""

from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gtk  # noqa: E402

from .icons import icon  # noqa: E402

# The floor for a thumb, in logical pixels. The same 44 the shell's style
# contract names and the apps' own `TARGET` already is; written here rather
# than imported from an app, because this module is the one every app has.
TARGET = 44


def clearable(row: Adw.EntryRow, *, tooltip: str = "Clear") -> Gtk.Button:
    """Give an `Adw.EntryRow` a trailing clear button, and return it.

    Idempotent in the only sense that matters: calling it twice on one row adds
    two buttons, so call it once, at the point the row is built.
    """
    button = Gtk.Button(icon_name=icon("edit-clear-symbolic", "window-close-symbolic"))
    button.add_css_class("flat")
    button.set_valign(Gtk.Align.CENTER)
    button.set_size_request(TARGET, TARGET)
    button.set_tooltip_text(tooltip)
    # See the header: focus here is the keyboard going away mid-edit.
    button.set_can_focus(False)
    button.set_focus_on_click(False)
    button.set_visible(bool(row.get_text()))

    def sync(*_args: object) -> None:
        button.set_visible(bool(row.get_text()))

    def cleared(*_args: object) -> None:
        row.set_text("")
        # Back to the field, so the keyboard that is already up stays up and
        # the next character typed goes where the user is looking.
        row.grab_focus()

    row.connect("changed", sync)
    button.connect("clicked", cleared)
    row.add_suffix(button)
    return button
