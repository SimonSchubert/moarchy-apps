"""The window: a list of habits, and a page for one of them.

Adw.NavigationView rather than a split view. A split view earns its keep on a
tablet and costs a frame of animation on a Mali-400; this app is a list and a
detail, and on 360px a detail is the whole screen either way.

Rows are rebuilt rather than diffed when the list changes shape, and refreshed
in place when only a value changed. The distinction matters: ticking a day must
not rebuild five widgets and lose the button the thumb is still on.
"""

from __future__ import annotations

import os
from datetime import date

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gio, GLib, Gtk  # noqa: E402

from . import theme  # noqa: E402
from .editor import HabitEditor  # noqa: E402
from .habits import MEASURABLE, Habit, Store, recent_days, today  # noqa: E402
from .widgets import (  # noqa: E402
    STRIP_DAYS,
    WEEKDAYS,
    HabitRow,
    Heatmap,
    frequency_label,
    strip_header,
)

# A tick writes the file, but not once per tap: a thumb going down a column of
# five days would otherwise fsync five times.
SAVE_DEBOUNCE_MS = 700

# The boxed list's inset from the window edge. The weekday header is a sibling
# of the list rather than a child, so it needs this too.
LIST_MARGIN = 12


class HabitsWindow(Adw.ApplicationWindow):
    __gtype_name__ = "HabitsWindow"

    def __init__(self, store: Store, **kwargs) -> None:
        super().__init__(**kwargs)
        self.store = store
        self._save_source = 0
        self._rows: dict[str, HabitRow] = {}
        self._detail: HabitDetail | None = None
        self._complete = False

        self.set_title("Habits")
        self.set_default_size(360, 720)

        self._nav = Adw.NavigationView()
        self._nav.add(self._list_page())
        self.set_content(self._nav)

        self.connect("close-request", self._on_close)
        self.rebuild()
        self._open_requested()

    # --- the list page ---------------------------------------------------

    def _list_page(self) -> Adw.NavigationPage:
        header = Adw.HeaderBar()
        # The day's progress lives in the title, where it is seen without going
        # looking. A streak and a strength score both sit on the detail page,
        # which meant the list -- the screen people actually open -- said
        # nothing at all about how today was going.
        self._title = Adw.WindowTitle(title="Habits", subtitle="")
        header.set_title_widget(self._title)
        add = Gtk.Button(icon_name="list-add-symbolic")
        add.set_tooltip_text("New habit")
        add.update_property([Gtk.AccessibleProperty.LABEL], ["New habit"])
        add.connect("clicked", lambda *_: self.new_habit())
        header.pack_start(add)

        menu = Gtk.MenuButton(icon_name="open-menu-symbolic")
        menu.set_tooltip_text("Menu")
        model = Gio.Menu()
        model.append("About Habits", "app.about")
        menu.set_menu_model(model)
        header.pack_end(menu)

        self._list = Gtk.ListBox()
        self._list.set_selection_mode(Gtk.SelectionMode.NONE)
        self._list.connect("row-activated", self._on_row_activated)
        self._list.add_css_class("boxed-list")
        self._list.set_margin_start(LIST_MARGIN)
        self._list.set_margin_end(LIST_MARGIN)
        self._list.set_margin_bottom(18)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        content.append(self._day_header())
        content.append(self._list)

        self._scroller = Gtk.ScrolledWindow()
        self._scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self._scroller.set_vexpand(True)
        self._scroller.set_child(content)

        self._empty = Adw.StatusPage()
        self._empty.set_icon_name("view-list-bullet-symbolic")
        self._empty.set_title("No habits yet")
        self._empty.set_description(
            "Add something you want to do regularly. Tap a day to mark it done."
        )
        start = Gtk.Button(label="Add a habit")
        start.add_css_class("suggested-action")
        start.add_css_class("pill")
        start.set_halign(Gtk.Align.CENTER)
        start.connect("clicked", lambda *_: self.new_habit())
        self._empty.set_child(start)

        self._stack = Gtk.Stack()
        self._stack.add_named(self._scroller, "list")
        self._stack.add_named(self._empty, "empty")

        self._toasts = Adw.ToastOverlay()
        self._toasts.set_child(self._stack)

        view = Adw.ToolbarView()
        view.add_top_bar(header)
        view.set_content(self._toasts)
        return Adw.NavigationPage.new(view, "Habits")

    def _day_header(self) -> Gtk.Widget:
        box, self._day_labels = strip_header(outer=LIST_MARGIN)
        self._refresh_day_header()
        return box

    def _refresh_day_header(self) -> None:
        for label, day in zip(self._day_labels, recent_days(STRIP_DAYS, today())):
            label.set_text(WEEKDAYS[day.weekday()])

    def _on_row_activated(self, _list: Gtk.ListBox, row: Gtk.ListBoxRow) -> None:
        if isinstance(row, HabitRow):
            row.activate_row()

    # --- building --------------------------------------------------------

    def rebuild(self) -> None:
        """Reflect a change in *which* habits exist."""
        self._list.remove_all()
        self._rows.clear()
        habits = self.store.active()
        for habit in habits:
            row = HabitRow(habit)
            row.connect("toggled", self._on_toggled)
            row.connect("opened", self._on_opened)
            self._list.append(row)
            self._rows[habit.id] = row
        self._refresh_day_header()
        self._refresh_progress()
        self._stack.set_visible_child_name("list" if habits else "empty")

    def refresh(self) -> None:
        """Reflect a change in what the habits *contain*."""
        for row in self._rows.values():
            row.refresh()
        if self._detail is not None:
            self._detail.refresh()
        self._refresh_progress()

    def _refresh_progress(self) -> None:
        kept, total = self.store.today_progress()
        if not total:
            self._title.set_subtitle("")
        elif kept == total:
            self._title.set_subtitle("All done today")
        else:
            self._title.set_subtitle(f"{kept} of {total} today")
        self._complete = bool(total) and kept == total

    # --- actions ---------------------------------------------------------

    def _on_toggled(self, row: HabitRow, habit_id: str, iso: str) -> None:
        habit = self.store.get(habit_id)
        if habit is None:
            return
        try:
            day = date.fromisoformat(iso)
        except ValueError:
            return
        was_streak = habit.streak()
        was_complete = self._complete
        if habit.kind == MEASURABLE and habit.target > 0:
            # Tapping a measurable habit adds one -- a glass of water, a page.
            # Once the target is reached the next tap clears the day, so a
            # mistake is one tap from gone rather than a trip to the detail.
            value = habit.value(day)
            habit.set_value(day, 0 if value >= habit.target else value + 1)
        else:
            habit.toggle(day)

        self.refresh()
        self.queue_save()

        if not habit.kept(day):
            # Unticking is not a thing to celebrate, and a halo on the way down
            # would read as a reward for undoing the work.
            return
        row.pop(iso)
        self._celebrate(habit, was_streak, was_complete)

    def _celebrate(self, habit: Habit, was_streak: int, was_complete: bool) -> None:
        """Say something, but only when there is something to say.

        Two things earn a toast: crossing a milestone, and finishing the day.
        Everything else gets the halo and nothing more -- a tracker that
        congratulates every tap is a tracker people mute.
        """
        milestone = habit.milestone_crossed(was_streak, habit.streak())
        if milestone is not None:
            best = habit.best_streak()
            note = " Longest yet." if milestone >= best else ""
            self._toast(f"{milestone} days of {habit.name}.{note}")
            return
        if self._complete and not was_complete:
            _, total = self.store.today_progress()
            self._toast(f"That is all {total} today.")

    def _toast(self, text: str) -> None:
        toast = Adw.Toast.new(text)
        toast.set_timeout(3)
        self._toasts.add_toast(toast)

    def _on_opened(self, _row: HabitRow, habit_id: str) -> None:
        habit = self.store.get(habit_id)
        if habit is None:
            return
        self._detail = HabitDetail(self, habit)
        self._nav.push(self._detail)

    def new_habit(self) -> None:
        habit = Habit()
        editor = HabitEditor(habit, is_new=True)
        editor.connect("saved", self._on_new_saved, habit)
        editor.present(self)

    def _on_new_saved(self, _editor: HabitEditor, _habit_id: str, habit: Habit) -> None:
        self.store.habits.append(habit)
        self.rebuild()
        self.queue_save()
        self._toasts.add_toast(Adw.Toast.new(f"Added {habit.name}"))

    def edit_habit(self, habit: Habit) -> None:
        editor = HabitEditor(habit, is_new=False)
        editor.connect("saved", lambda *_: self._after_edit())
        editor.present(self)

    def _after_edit(self) -> None:
        self.rebuild()
        self.refresh()
        self.queue_save()

    def delete_habit(self, habit: Habit) -> None:
        index = self.store.delete(habit)
        if index < 0:
            return
        if self._nav.get_visible_page() is self._detail:
            self._nav.pop()
        self._detail = None
        self.rebuild()
        self.queue_save()

        toast = Adw.Toast.new(f"Deleted {habit.name}")
        toast.set_button_label("Undo")
        toast.connect("button-clicked", self._on_undo, habit, index)
        self._toasts.add_toast(toast)

    def _on_undo(self, _toast: Adw.Toast, habit: Habit, index: int) -> None:
        self.store.restore(habit, index)
        self.rebuild()
        self.queue_save()

    def _open_requested(self) -> None:
        """Start on a particular page, for the screenshot harness.

        A headless X server has no pointer worth clicking with, and a run that
        opens straight into the page it should photograph needs none. Same
        mechanism Keep uses, and for the same reason.
        """
        wanted = os.environ.get("MOARCHY_HABITS_OPEN")
        if wanted:
            match = next(
                (h for h in self.store.active() if h.name.lower() == wanted.lower()),
                None,
            )
            if match is not None:
                self._on_opened(None, match.id)
        if os.environ.get("MOARCHY_HABITS_NEW"):
            self.new_habit()

    # --- saving ----------------------------------------------------------

    def queue_save(self) -> None:
        if self._save_source:
            GLib.source_remove(self._save_source)
        self._save_source = GLib.timeout_add(SAVE_DEBOUNCE_MS, self._flush)

    def _flush(self) -> bool:
        self._save_source = 0
        self.save_now()
        return GLib.SOURCE_REMOVE

    def save_now(self) -> None:
        try:
            self.store.save()
        except OSError as exc:
            self._toasts.add_toast(
                Adw.Toast.new(f"Could not save: {exc.strerror or exc}")
            )

    def _on_close(self, *_args) -> bool:
        if self._save_source:
            GLib.source_remove(self._save_source)
            self._save_source = 0
        self.save_now()
        return False


class HabitDetail(Adw.NavigationPage):
    """One habit: what it is, how it is going, and its history."""

    __gtype_name__ = "HabitsDetail"

    def __init__(self, window: HabitsWindow, habit: Habit) -> None:
        super().__init__()
        self.window = window
        self.habit = habit
        self.set_title(habit.name or "Habit")

        header = Adw.HeaderBar()
        edit = Gtk.Button(icon_name="document-edit-symbolic")
        edit.set_tooltip_text("Edit")
        edit.update_property([Gtk.AccessibleProperty.LABEL], ["Edit habit"])
        edit.connect("clicked", lambda *_: self.window.edit_habit(self.habit))
        header.pack_end(edit)

        delete = Gtk.Button(icon_name="user-trash-symbolic")
        delete.set_tooltip_text("Delete")
        delete.update_property([Gtk.AccessibleProperty.LABEL], ["Delete habit"])
        delete.add_css_class("destructive-action")
        delete.add_css_class("flat")
        delete.connect("clicked", lambda *_: self._confirm_delete())
        header.pack_end(delete)

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        body.set_margin_top(18)
        body.set_margin_bottom(24)
        body.set_margin_start(16)
        body.set_margin_end(16)

        self._streak = Gtk.Label()
        self._streak.add_css_class("streak-figure")
        self._streak.set_halign(Gtk.Align.CENTER)
        body.append(self._streak)

        self._streak_label = Gtk.Label()
        self._streak_label.add_css_class("stat-label")
        self._streak_label.set_halign(Gtk.Align.CENTER)
        body.append(self._streak_label)

        self._bar = Gtk.ProgressBar()
        self._bar.add_css_class("habitbar")
        self._bar.set_margin_top(4)
        body.append(self._bar)

        self._score_label = Gtk.Label()
        self._score_label.add_css_class("stat-label")
        self._score_label.set_halign(Gtk.Align.CENTER)
        body.append(self._score_label)

        stats = Gtk.ListBox()
        stats.set_selection_mode(Gtk.SelectionMode.NONE)
        stats.add_css_class("boxed-list")
        self._rows = {}
        self._stat_rows = {}
        for key, title in (
            ("frequency", "How often"),
            ("next", "Next milestone"),
            ("best", "Best streak"),
            ("kept", "Days kept"),
            ("total", "Total"),
        ):
            row = Adw.ActionRow(title=title)
            value = Gtk.Label()
            value.add_css_class("dim-label")
            row.add_suffix(value)
            stats.append(row)
            self._rows[key] = value
            self._stat_rows[key] = row
        body.append(stats)

        history = Gtk.Label(label="HISTORY", xalign=0.0)
        history.add_css_class("section-heading")
        history.set_margin_top(6)
        body.append(history)

        self._heatmap = Heatmap()
        body.append(self._heatmap)

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_vexpand(True)
        scroller.set_child(body)

        view = Adw.ToolbarView()
        view.add_top_bar(header)
        view.set_content(scroller)
        self.set_child(view)

        self.refresh()

    def refresh(self) -> None:
        habit = self.habit
        self.set_title(habit.name or "Habit")

        streak = habit.streak()
        self._streak.set_text(str(streak))
        for key in theme.COLOUR_KEYS:
            self._streak.remove_css_class(f"hue-{key}")
            self._bar.remove_css_class(key)
        self._streak.add_css_class(f"hue-{habit.colour}")
        self._bar.add_css_class(habit.colour)
        self._streak_label.set_text("DAY STREAK" if streak != 1 else "DAY")

        score = habit.score()
        self._bar.set_fraction(score)
        self._score_label.set_text(f"{round(score * 100)}% strength")

        self._rows["frequency"].set_text(frequency_label(habit))

        # Something to aim at. A streak with no next number is just a number;
        # "4 days to 30" is the same fact with somewhere to go. Hidden once the
        # last milestone is behind you, rather than inventing bigger ones --
        # past a year the habit is not a project any more.
        upcoming = habit.next_milestone()
        self._stat_rows["next"].set_visible(upcoming is not None)
        if upcoming is not None:
            target, togo = upcoming
            self._rows["next"].set_text(
                f"{target} days — {togo} to go" if togo else f"{target} days"
            )

        self._rows["best"].set_text(f"{habit.best_streak()} days")
        self._rows["kept"].set_text(f"{habit.kept_days()} days")
        # For a yes-or-no habit the total *is* the number of days kept, so the
        # row would repeat the one above it. Measurable habits have something
        # of their own to say: 431 glasses.
        measurable = habit.kind == MEASURABLE
        self._stat_rows["total"].set_visible(measurable)
        if measurable:
            unit = f" {habit.unit}" if habit.unit else ""
            self._rows["total"].set_text(f"{habit.total():g}{unit}")

        self._heatmap.refresh(habit)

    def _confirm_delete(self) -> None:
        dialog = Adw.AlertDialog.new(
            f"Delete {self.habit.name}?",
            "Its history will be removed. This cannot be undone once the toast goes.",
        )
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("delete", "Delete")
        dialog.set_response_appearance("delete", Adw.ResponseAppearance.DESTRUCTIVE)
        dialog.set_default_response("cancel")
        dialog.set_close_response("cancel")
        dialog.connect("response", self._on_delete_response)
        dialog.present(self.window)

    def _on_delete_response(self, _dialog: Adw.AlertDialog, response: str) -> None:
        if response == "delete":
            self.window.delete_habit(self.habit)
