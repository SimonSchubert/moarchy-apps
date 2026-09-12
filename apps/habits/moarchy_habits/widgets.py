"""The marks, and the two grids made of them.

Everything the app draws is one shape: a rounded square whose fill says how much
of a day was done. A row of four is today and the three days behind it; a block
of sixteen weeks is the history. Keeping them the same widget means the colour
ramp is defined once and a theme change repaints both.

Sizes are not arbitrary, and the arithmetic is the whole reason the row looks
the way it does. At 360px, after the list's margins and the row's own padding,
there are about 312 logical pixels to divide between a habit's name and its
days. A day needs a 44px target, because that is the smallest thing a thumb
hits reliably. Five of those leaves 92px for the name, which is not a name --
the first render of this app turned "No phone in bed" into a vertical column of
single letters. Four leaves 136px, which is a name.

The row is built by hand rather than with Adw.ActionRow for the same reason: the
weekday header above it has to line up with the marks *exactly*, and that is
only guaranteed if one file owns both paddings.
"""

from __future__ import annotations

from datetime import date, timedelta
from typing import ClassVar

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import GLib, GObject, Gtk  # noqa: E402

from . import theme  # noqa: E402
from .habits import MEASURABLE, Habit, recent_days, today  # noqa: E402

TARGET = 44  # tap target: the floor for a thumb
MARK = 30  # the drawn square inside it
HISTORY_MARK = 15  # read, not tapped
HISTORY_WEEKS = 16
STRIP_DAYS = 4  # see the module docstring -- five does not leave a name
ROW_PAD = 12  # horizontal padding, shared by the rows and their header

# Monday first: the week a calendar starts on is a locale question, and the one
# thing worse than guessing is guessing differently in the two grids.
WEEKDAYS = ("M", "T", "W", "T", "F", "S", "S")

# The tick animation's length is theme.POP_MS -- the keyframes and the timer
# that removes the class have to agree, and the stylesheet owns the number.


def step_for(habit: Habit, day: date) -> int:
    """Which rung of the ramp a day sits on, 0 (untouched) to theme.STEPS.

    A boolean habit is all or nothing. A measurable one is a proportion of its
    target, so "six of eight glasses" is visibly more than two, and reaching the
    target is the only way to the top rung.
    """
    value = habit.value(day)
    if value <= 0:
        return 0
    if habit.kind != MEASURABLE or habit.target <= 0:
        return theme.STEPS
    if value >= habit.target:
        return theme.STEPS
    share = value / habit.target
    # Anything started is at least rung 1, so a day worked on never reads empty.
    return max(1, min(theme.STEPS - 1, int(share * theme.STEPS) + 1))


class Face(Gtk.Box):
    """The drawn mark itself, with no behaviour.

    Separate from the button because the history grid is read, not tapped, and
    an insensitive Gtk.Button is dimmed by libadwaita's :disabled styling --
    which would wash out sixteen weeks of colour to make a point nobody asked
    for.

    The size comes from a CSS class, not from set_size_request: `.mark` carries
    a min-width, and a min-width in CSS beats a size request, which is why the
    first render drew the sixteen-week history at day size and ran off the side
    of the screen.
    """

    __gtype_name__ = "HabitsFace"

    def __init__(self, size_class: str = "day") -> None:
        super().__init__()
        self.set_halign(Gtk.Align.CENTER)
        self.set_valign(Gtk.Align.CENTER)
        self.add_css_class("mark")
        self.add_css_class(size_class)
        self._classes: list[str] = []

    def pop(self) -> None:
        """Acknowledge a tap.

        The whole reward loop of this app is one square changing colour, and
        without this it changed colour in complete silence -- the same frame,
        no motion, nothing to tell a thumb it had landed. The class is removed
        again afterwards so the next tick re-triggers the animation; a CSS
        animation does not replay while its class is still applied.
        """
        self.add_css_class("just-done")
        GLib.timeout_add(theme.POP_MS, self._unpop)

    def _unpop(self) -> bool:
        self.remove_css_class("just-done")
        return GLib.SOURCE_REMOVE

    def paint(
        self, colour: str, step: int, *, is_today: bool = False, is_future: bool = False
    ) -> None:
        for name in self._classes:
            self.remove_css_class(name)
        self._classes = []

        def add(name: str) -> None:
            self.add_css_class(name)
            self._classes.append(name)

        if is_future:
            add("future")
        elif step <= 0:
            add("empty")
        else:
            add(colour)
            add(f"step{step}")
        if is_today:
            add("today")


class Mark(Gtk.Button):
    """One tappable day: a 44px target around a 30px face."""

    __gtype_name__ = "HabitsMark"

    def __init__(self) -> None:
        super().__init__()
        self.add_css_class("flat")
        self.add_css_class("mark-target")
        self.set_size_request(TARGET, TARGET)
        self.set_has_frame(False)
        self._face = Face("day")
        self.set_child(self._face)

    def paint(self, *args, **kwargs) -> None:
        self._face.paint(*args, **kwargs)

    def pop(self) -> None:
        self._face.pop()


class DayStrip(Gtk.Box):
    """The days on a habit row, oldest first."""

    __gtype_name__ = "HabitsDayStrip"

    __gsignals__: ClassVar[dict] = {
        # (iso date) -- the row above decides what a tap means.
        "day-activated": (GObject.SignalFlags.RUN_FIRST, None, (str,)),
    }

    def __init__(self, count: int = STRIP_DAYS) -> None:
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        self._marks: list[Mark] = []
        self._days: list[date] = []
        for _ in range(count):
            mark = Mark()
            mark.connect("clicked", self._on_clicked)
            self.append(mark)
            self._marks.append(mark)

    def _on_clicked(self, button: Mark) -> None:
        try:
            index = self._marks.index(button)
        except ValueError:
            return
        if index < len(self._days):
            self.emit("day-activated", self._days[index].isoformat())

    def pop(self, iso: str) -> None:
        for mark, day in zip(self._marks, self._days):
            if day.isoformat() == iso:
                mark.pop()
                return

    def refresh(self, habit: Habit) -> None:
        now = today()
        self._days = recent_days(len(self._marks), now)
        for mark, day in zip(self._marks, self._days):
            mark.paint(habit.colour, step_for(habit, day), is_today=day == now)
            label = day.strftime("%A %-d %B")
            mark.set_tooltip_text(label)
            mark.update_property([Gtk.AccessibleProperty.LABEL], [label])


def strip_header(
    count: int = STRIP_DAYS, outer: int = 0
) -> tuple[Gtk.Widget, list[Gtk.Label]]:
    """Weekday letters, in cells the same width and place as the marks below.

    Built from the same ROW_PAD and the same TARGET cells as HabitRow, because
    the alternative -- guessing at Adw.ActionRow's internal padding -- put the
    letters ten pixels left of their own columns on the first render.
    """
    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
    # `outer` is whatever margin the list itself carries. The header is a
    # sibling of the list, not a child, so it has to clear both that and the
    # row's own padding -- missing the first put the letters twelve pixels left
    # of their own columns.
    box.set_margin_start(outer + ROW_PAD)
    box.set_margin_end(outer + ROW_PAD)
    box.set_margin_top(6)
    box.set_margin_bottom(2)

    spacer = Gtk.Box()
    spacer.set_hexpand(True)
    box.append(spacer)

    labels = []
    for _ in range(count):
        label = Gtk.Label()
        label.add_css_class("daylabel")
        label.set_size_request(TARGET, -1)
        box.append(label)
        labels.append(label)
    return box, labels


class HabitRow(Gtk.ListBoxRow):
    """A habit as it appears in the list: name, a line under it, four days."""

    __gtype_name__ = "HabitsHabitRow"

    __gsignals__: ClassVar[dict] = {
        "toggled": (GObject.SignalFlags.RUN_FIRST, None, (str, str)),
        "opened": (GObject.SignalFlags.RUN_FIRST, None, (str,)),
    }

    def __init__(self, habit: Habit) -> None:
        super().__init__()
        self.habit = habit
        self.set_activatable(True)

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        box.set_margin_start(ROW_PAD)
        box.set_margin_end(ROW_PAD)
        box.set_margin_top(4)
        box.set_margin_bottom(4)

        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        text.set_valign(Gtk.Align.CENTER)
        text.set_hexpand(True)
        # Ellipsize, never wrap. A name with nowhere to go must lose its tail,
        # not become a column of letters one glyph wide.
        self._name = Gtk.Label(xalign=0.0)
        self._name.set_ellipsize(3)  # Pango.EllipsizeMode.END
        self._name.set_single_line_mode(True)
        self._name.add_css_class("habit-name")
        text.append(self._name)

        self._note = Gtk.Label(xalign=0.0)
        self._note.set_ellipsize(3)
        self._note.set_single_line_mode(True)
        self._note.add_css_class("habit-note")
        text.append(self._note)
        box.append(text)

        self._strip = DayStrip()
        self._strip.set_valign(Gtk.Align.CENTER)
        self._strip.connect("day-activated", self._on_day)
        box.append(self._strip)

        self.set_child(box)
        self.refresh()

    def _on_day(self, _strip: DayStrip, iso: str) -> None:
        self.emit("toggled", self.habit.id, iso)

    def activate_row(self) -> None:
        self.emit("opened", self.habit.id)

    def pop(self, iso: str) -> None:
        self._strip.pop(iso)

    def refresh(self) -> None:
        habit = self.habit
        self._name.set_text(habit.name or "Untitled")
        streak = habit.streak()
        if streak > 1:
            note = f"{streak} day streak"
        elif habit.question:
            note = habit.question
        else:
            note = frequency_label(habit)
        self._note.set_text(note)
        self._strip.refresh(habit)


def frequency_label(habit: Habit) -> str:
    if habit.is_daily:
        return "Every day"
    if habit.freq_den == 7:
        return f"{habit.freq_num}× a week"
    if habit.freq_den in (30, 31):
        return f"{habit.freq_num}× a month"
    return f"{habit.freq_num}× in {habit.freq_den} days"


class Heatmap(Gtk.Box):
    """Sixteen weeks of history, weekdays down, weeks across.

    The shape people already know from contribution graphs, which is worth more
    than a prettier idea: nobody has to be told how to read it. Weeks run left
    to right ending with this one, so the newest mark is nearest the thumb.
    """

    __gtype_name__ = "HabitsHeatmap"

    def __init__(self, weeks: int = HISTORY_WEEKS) -> None:
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=5)
        self.weeks = weeks

        labels = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        labels.set_valign(Gtk.Align.START)
        for index, letter in enumerate(WEEKDAYS):
            label = Gtk.Label(label=letter if index % 2 == 0 else "")
            label.add_css_class("daylabel")
            # The same height as a history cell, so the letters stay level with
            # their own rows instead of drifting down the column.
            label.set_size_request(10, HISTORY_MARK)
            label.set_xalign(1.0)
            labels.append(label)
        self.append(labels)

        self._grid = Gtk.Grid(column_spacing=2, row_spacing=2)
        self._grid.add_css_class("calendar-grid")
        self._grid.set_halign(Gtk.Align.START)
        self._marks: list[tuple[Face, int]] = []
        for column in range(weeks):
            for row in range(7):
                face = Face("cell")
                self._grid.attach(face, column, row, 1, 1)
                self._marks.append((face, column * 7 + row))

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.NEVER)
        scroller.set_child(self._grid)
        scroller.set_hexpand(True)
        self.append(scroller)

    def refresh(self, habit: Habit) -> None:
        now = today()
        # Anchor on the Monday of this week, then walk back whole weeks, so the
        # rows line up with the weekday labels no matter what day it is.
        monday = now - timedelta(days=now.weekday())
        first = monday - timedelta(weeks=self.weeks - 1)
        for face, offset in self._marks:
            day = first + timedelta(days=(offset // 7) * 7 + offset % 7)
            if day > now:
                face.paint(habit.colour, 0, is_future=True)
                face.set_tooltip_text(None)
                continue
            face.paint(habit.colour, step_for(habit, day), is_today=day == now)
            face.set_tooltip_text(day.strftime("%A %-d %B %Y"))
