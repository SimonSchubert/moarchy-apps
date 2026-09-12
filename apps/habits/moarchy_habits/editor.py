"""Making a habit, and changing one.

One dialog does both, because the fields are the same and a separate "new" form
is a second place for the frequency rules to drift. On a phone Adw.Dialog
presents itself as a bottom sheet, which puts the fields above the keyboard
instead of behind it.

The frequency choices are a fixed list rather than two spin buttons. "Three
times a week" is what people mean; "3 in 7" is what the file stores, and making
the user do that translation on a touch screen buys nothing.
"""

from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, GObject, Gtk  # noqa: E402

from . import theme  # noqa: E402
from .habits import BOOLEAN, MEASURABLE, Habit  # noqa: E402

# (label, n, d). Ordered by how often people pick them, not by size.
FREQUENCIES: tuple[tuple[str, int, int], ...] = (
    ("Every day", 1, 1),
    ("6× a week", 6, 7),
    ("5× a week", 5, 7),
    ("4× a week", 4, 7),
    ("3× a week", 3, 7),
    ("2× a week", 2, 7),
    ("Once a week", 1, 7),
    ("Twice a month", 2, 30),
    ("Once a month", 1, 30),
)

KINDS = ("Yes or no", "A number")


class HabitEditor(Adw.Dialog):
    """Create or edit. Emits `saved` with the habit id once applied."""

    __gtype_name__ = "HabitsEditor"

    __gsignals__ = {
        "saved": (GObject.SignalFlags.RUN_FIRST, None, (str,)),
    }

    def __init__(self, habit: Habit, *, is_new: bool) -> None:
        super().__init__()
        self.habit = habit
        self.is_new = is_new
        self._colour = habit.colour if habit.colour in theme.COLOUR_KEYS else "green"
        self._swatches: dict[str, Gtk.Widget] = {}

        self.set_title("New habit" if is_new else "Edit habit")
        self.set_content_width(400)

        header = Adw.HeaderBar()
        cancel = Gtk.Button(label="Cancel")
        cancel.connect("clicked", lambda *_: self.close())
        header.pack_start(cancel)

        self._save = Gtk.Button(label="Add" if is_new else "Save")
        self._save.add_css_class("suggested-action")
        self._save.connect("clicked", self._on_save)
        header.pack_end(self._save)

        page = Adw.PreferencesPage()
        page.add(self._details_group())
        page.add(self._schedule_group())
        page.add(self._colour_group())

        view = Adw.ToolbarView()
        view.add_top_bar(header)
        view.set_content(page)
        self.set_child(view)

        self._sync_measurable()
        self._validate()

    # --- fields ----------------------------------------------------------

    def _details_group(self) -> Adw.PreferencesGroup:
        group = Adw.PreferencesGroup()

        self._name = Adw.EntryRow(title="Name")
        self._name.set_text(self.habit.name)
        self._name.connect("changed", lambda *_: self._validate())
        group.add(self._name)

        self._question = Adw.EntryRow(title="Question (optional)")
        self._question.set_text(self.habit.question)
        group.add(self._question)

        self._kind = Adw.ComboRow(title="Records")
        self._kind.set_model(Gtk.StringList.new(KINDS))
        self._kind.set_selected(1 if self.habit.kind == MEASURABLE else 0)
        self._kind.connect("notify::selected", lambda *_: self._sync_measurable())
        group.add(self._kind)
        return group

    def _schedule_group(self) -> Adw.PreferencesGroup:
        group = Adw.PreferencesGroup(title="Goal")

        self._target = Adw.SpinRow.new_with_range(1, 10000, 1)
        self._target.set_title("Target each day")
        self._target.set_value(self.habit.target if self.habit.target > 0 else 1)
        group.add(self._target)

        self._unit = Adw.EntryRow(title="Unit")
        self._unit.set_text(self.habit.unit)
        group.add(self._unit)

        self._frequency = Adw.ComboRow(title="How often")
        self._frequency.set_model(Gtk.StringList.new([f[0] for f in FREQUENCIES]))
        self._frequency.set_selected(self._frequency_index())
        group.add(self._frequency)
        return group

    def _colour_group(self) -> Adw.PreferencesGroup:
        group = Adw.PreferencesGroup(title="Colour")
        row = Gtk.FlowBox()
        row.set_selection_mode(Gtk.SelectionMode.NONE)
        row.set_max_children_per_line(8)
        row.set_min_children_per_line(4)
        row.set_row_spacing(6)
        row.set_column_spacing(6)
        row.set_margin_top(6)
        row.set_margin_bottom(6)
        row.set_margin_start(6)
        row.set_margin_end(6)

        for key, label in theme.HABIT_COLOURS:
            button = Gtk.Button()
            button.add_css_class("flat")
            button.set_size_request(44, 44)
            button.set_tooltip_text(label)
            button.update_property([Gtk.AccessibleProperty.LABEL], [label])
            face = Gtk.Box()
            face.set_size_request(30, 30)
            face.set_halign(Gtk.Align.CENTER)
            face.set_valign(Gtk.Align.CENTER)
            # "day" carries the size and the corner radius; without it the
            # picker drew eight sharp-cornered squares next to a grid of
            # rounded ones.
            face.add_css_class("mark")
            face.add_css_class("day")
            face.add_css_class("swatch")
            face.add_css_class(key)
            button.set_child(face)
            button.connect("clicked", self._on_colour, key)
            self._swatches[key] = face
            row.append(button)

        group.add(row)
        self._mark_colour()
        return group

    # --- behaviour -------------------------------------------------------

    def _frequency_index(self) -> int:
        for index, (_, num, den) in enumerate(FREQUENCIES):
            if num == self.habit.freq_num and den == self.habit.freq_den:
                return index
        return 0

    def _on_colour(self, _button: Gtk.Button, key: str) -> None:
        self._colour = key
        self._mark_colour()

    def _mark_colour(self) -> None:
        for key, face in self._swatches.items():
            if key == self._colour:
                face.add_css_class("selected")
            else:
                face.remove_css_class("selected")

    def _sync_measurable(self) -> None:
        measurable = self._kind.get_selected() == 1
        self._target.set_visible(measurable)
        self._unit.set_visible(measurable)

    def _validate(self) -> None:
        self._save.set_sensitive(bool(self._name.get_text().strip()))

    def _on_save(self, *_args) -> None:
        name = self._name.get_text().strip()
        if not name:
            return
        habit = self.habit
        habit.name = name
        habit.question = self._question.get_text().strip()
        measurable = self._kind.get_selected() == 1
        habit.kind = MEASURABLE if measurable else BOOLEAN
        habit.target = float(self._target.get_value()) if measurable else 1.0
        habit.unit = self._unit.get_text().strip() if measurable else ""
        habit.colour = self._colour
        _, num, den = FREQUENCIES[
            min(self._frequency.get_selected(), len(FREQUENCIES) - 1)
        ]
        habit.freq_num, habit.freq_den = num, den
        self.emit("saved", habit.id)
        self.close()
