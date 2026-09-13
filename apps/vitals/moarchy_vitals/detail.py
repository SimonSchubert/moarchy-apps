"""One task, and the two ways to stop it.

Pushed onto the navigation view rather than shown in a sheet, so the bottom
switcher goes away with the rest of the window chrome: a page about one process
is not a fourth tab, and on a phone a detail is the whole screen either way.

Both pages refresh from the same Sample as everything else, so the figures on
one of them keep moving while it is open -- which is the point of opening it.
A process that ends while it is on screen says so rather than vanishing under
the thumb that is reading it.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gtk  # noqa: E402

from . import theme  # noqa: E402
from .sysinfo import (  # noqa: E402
    AppGroup,
    Process,
    Sample,
    human_bytes,
    human_seconds,
    task_percent,
)
from .widgets import MARGIN, MAX_ROWS, TaskList  # noqa: E402

if TYPE_CHECKING:  # pragma: no cover - the window imports these, not the other way
    from .window import VitalsWindow


class DetailPage(Adw.NavigationPage):
    """What the window expects of a pushed page."""

    def set_palette(self, palette: theme.Palette) -> None:
        """Nothing on a detail page is drawn with cairo."""

    def refresh(self, sample: Sample | None) -> None:  # pragma: no cover - interface
        raise NotImplementedError


class ProcessPage(DetailPage):
    """One process, live, and the two ways to stop it."""

    __gtype_name__ = "VitalsProcess"

    def __init__(self, window: VitalsWindow, pid: int) -> None:
        super().__init__()
        self.window = window
        self.pid = pid
        self.process: Process | None = None
        self.set_title("Process")

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        body.set_margin_start(MARGIN + 2)
        body.set_margin_end(MARGIN + 2)
        body.set_margin_top(16)
        body.set_margin_bottom(24)

        self._name = Gtk.Label(xalign=0.0)
        self._name.add_css_class("figure-small")
        self._name.set_ellipsize(3)
        body.append(self._name)

        self._command = Gtk.Label(xalign=0.0)
        self._command.add_css_class("command")
        self._command.set_wrap(True)
        self._command.set_selectable(True)
        # Six lines is enough to recognise a command and short enough that the
        # facts below it are still on screen. A browser's command line is longer
        # than this screen is tall.
        self._command.set_lines(6)
        self._command.set_ellipsize(3)
        body.append(self._command)

        self._facts = Gtk.ListBox()
        self._facts.set_selection_mode(Gtk.SelectionMode.NONE)
        self._facts.add_css_class("boxed-list")
        self._rows: dict[str, Gtk.Label] = {}
        for key, title in (
            ("cpu", "Processor"),
            ("memory", "Memory"),
            ("state", "State"),
            ("threads", "Threads"),
            ("time", "Processor time"),
            ("pid", "Process"),
            ("user", "User"),
            ("app", "Part of"),
        ):
            row = Adw.ActionRow(title=title)
            value = Gtk.Label()
            value.add_css_class("dim-label")
            value.add_css_class("value")
            value.set_ellipsize(3)
            row.add_suffix(value)
            self._facts.append(row)
            self._rows[key] = value
        body.append(self._facts)

        self._buttons = end_buttons(self._on_end, self._on_force)
        body.append(self._buttons)

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_vexpand(True)
        scroller.set_child(body)

        view = Adw.ToolbarView()
        view.add_top_bar(Adw.HeaderBar())
        view.set_content(scroller)
        self.set_child(view)

    def refresh(self, sample: Sample | None) -> None:
        if sample is None:
            return
        match = next((p for p in sample.processes if p.pid == self.pid), None)
        if match is None:
            # Gone. The page stays -- popping it under a thumb that is reading
            # it would be worse -- but it says so and stops offering to end it.
            self.set_title(self.process.name if self.process else "Process")
            self._rows["state"].set_text("no longer running")
            self._buttons.set_sensitive(False)
            return
        self.process = match
        self.set_title(match.name)
        self._name.set_text(match.name)
        self._command.set_text(match.cmdline or "kernel thread")
        self._rows["cpu"].set_text(task_percent(match.cpu))
        self._rows["memory"].set_text(human_bytes(match.rss))
        self._rows["state"].set_text(match.state)
        self._rows["threads"].set_text(str(match.threads))
        self._rows["time"].set_text(human_seconds(match.seconds))
        self._rows["pid"].set_text(f"{match.pid} · parent {match.ppid}")
        self._rows["user"].set_text(match.user)
        self._rows["app"].set_text(match.app_name)
        self._buttons.set_sensitive(True)

    def _on_end(self, *_args) -> None:
        if self.process is not None:
            self.window.confirm_end(self.process.name, (self.pid,), force=False)

    def _on_force(self, *_args) -> None:
        if self.process is not None:
            self.window.confirm_end(self.process.name, (self.pid,), force=True)


class AppPage(DetailPage):
    """One app: what it is costing in total, and every process in it."""

    __gtype_name__ = "VitalsApp"

    def __init__(self, window: VitalsWindow, key: str) -> None:
        super().__init__()
        self.window = window
        self.key = key
        self.group: AppGroup | None = None
        self.set_title("App")

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        body.set_margin_start(MARGIN + 2)
        body.set_margin_end(MARGIN + 2)
        body.set_margin_top(16)
        body.set_margin_bottom(24)

        self._name = Gtk.Label(xalign=0.0)
        self._name.add_css_class("figure-small")
        self._name.set_ellipsize(3)
        body.append(self._name)

        self._summary = Gtk.Label(xalign=0.0)
        self._summary.add_css_class("note")
        body.append(self._summary)

        heading = Gtk.Label(label="PROCESSES", xalign=0.0)
        heading.add_css_class("section-heading")
        body.append(heading)

        self._list = TaskList()
        self._list.connect("picked", self._on_picked)
        body.append(self._list)

        self._buttons = end_buttons(self._on_end, self._on_force)
        body.append(self._buttons)

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_vexpand(True)
        scroller.set_child(body)

        view = Adw.ToolbarView()
        view.add_top_bar(Adw.HeaderBar())
        view.set_content(scroller)
        self.set_child(view)

    def refresh(self, sample: Sample | None) -> None:
        if sample is None:
            return
        group = next((g for g in sample.apps if g.key == self.key), None)
        if group is None:
            self.set_title(self.group.name if self.group else "App")
            self._summary.set_text("no longer running")
            self._buttons.set_sensitive(False)
            self._list.set_items([])
            return
        self.group = group
        self.set_title(group.name)
        self._name.set_text(group.name)
        self._summary.set_text(
            f"{task_percent(group.cpu)} processor · {human_bytes(group.rss)} · "
            f"{group.count} process{'es' if group.count != 1 else ''} · {group.user}"
        )
        members = [p for p in sample.processes if p.app_key == self.key]
        members.sort(key=lambda p: (-p.cpu, -p.rss))
        self._list.set_items(members[:MAX_ROWS])
        self._buttons.set_sensitive(True)

    def _on_picked(self, _list: TaskList, item) -> None:
        if isinstance(item, Process):
            self.window.open_process(item.pid)

    def _on_end(self, *_args) -> None:
        if self.group is not None:
            self.window.confirm_end(self.group.name, self.group.pids, force=False)

    def _on_force(self, *_args) -> None:
        if self.group is not None:
            self.window.confirm_end(self.group.name, self.group.pids, force=True)


def end_buttons(on_end, on_force) -> Gtk.Box:
    """The two ways to stop something, in the order to try them.

    Full width and 48px tall, which is the phone's tap target with room to
    spare: these are the two buttons in the app that do something irreversible,
    and a near miss on either is somebody's unsaved work.
    """
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
    end = Gtk.Button(label="End task")
    end.add_css_class("pill")
    end.set_size_request(-1, 48)
    end.connect("clicked", on_end)
    box.append(end)

    force = Gtk.Button(label="Force stop")
    force.add_css_class("pill")
    force.add_css_class("destructive-action")
    force.set_size_request(-1, 48)
    force.connect("clicked", on_force)
    box.append(force)
    return box
