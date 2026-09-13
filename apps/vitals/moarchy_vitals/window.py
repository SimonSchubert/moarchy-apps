"""The window: three pages behind a bar a thumb can reach, and one reading.

btop draws four boxes at once because it is on a screen that fits four boxes.
360 logical pixels does not, and the two usual answers are both wrong: shrinking
the four until they fit gives four unreadable boxes, and scrolling one long
column means the processor graph is off-screen while you look at the task list.

So the app is a page each of the three questions somebody opens a task manager
to ask -- what is the machine doing, what is doing it, and what is on the
network -- with the switcher at the *bottom*, where a thumb is. That is the one
structural difference from every desktop system monitor, and it is the whole
reason this app exists rather than being a link to gnome-system-monitor.

One sampler, one timer, one reading per tick, handed to whichever page is
showing. The pages keep no state of their own beyond their widgets: everything
they draw comes from the Sample and the histories the window owns, so a page
that has been off-screen for a minute is correct the moment it is shown.

The timer stops when the window is not on screen. A monitor that keeps reading
/proc every two seconds after the phone is in a pocket is a battery bug wearing
a feature's clothes -- and on a phone the app is not closed, it is hidden, so
this is the normal case rather than an edge one.
"""

from __future__ import annotations

import os

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gio, GLib, Gtk  # noqa: E402
from moarchy_ui.icons import icon  # noqa: E402

from . import theme  # noqa: E402
from .detail import AppPage, DetailPage, ProcessPage  # noqa: E402
from .pages import NetworkPage, OverviewPage, Page, TasksPage  # noqa: E402
from .sysinfo import (  # noqa: E402
    History,
    Reel,
    Sample,
    Sampler,
    human_percent,
)
from .widgets import SAMPLES  # noqa: E402

# Two seconds. btop's default is close to this and for the same reason: a
# processor reading is a difference between two samples, so a shorter interval
# measures a shorter span and reports more noise as load. It is also twice the
# work per minute on a phone, and a graph of the last two minutes at this rate
# is exactly the sixty samples the graph holds.
TICK_MS = 2000

# Frames of a fixture reel left for the app itself to walk through. Priming
# fills the graphs so a screenshot has a past; leaving a few means the app is
# still visibly moving when it is photographed.
PRIME_TAIL = 6


class VitalsWindow(Adw.ApplicationWindow):
    __gtype_name__ = "VitalsWindow"

    def __init__(self, sampler: Sampler, **kwargs) -> None:
        super().__init__(**kwargs)
        self.sampler = sampler
        self.sample: Sample | None = None
        self._source = 0
        self._detail: Adw.NavigationPage | None = None
        self._palette = theme.fallback(dark=True)

        self.set_title("Vitals")
        self.set_default_size(360, 720)

        # One history per series the app draws. The per-interface ones are made
        # on demand: which interfaces exist is not known until the first sample,
        # and on a phone it changes when the modem or the Wi-Fi comes up.
        self.history: dict[str, History] = {
            key: History(SAMPLES) for key in ("cpu", "memory", "swap", "rx", "tx")
        }

        self.overview = OverviewPage(self)
        self.tasks = TasksPage(self)
        self.network = NetworkPage(self)

        self._stack = Adw.ViewStack()
        self._stack.add_titled_with_icon(
            self.overview,
            "overview",
            "System",
            icon(
                "speedometer-symbolic",
                "utilities-system-monitor-symbolic",
                "go-home-symbolic",
            ),
        )
        self._stack.add_titled_with_icon(
            self.tasks,
            "tasks",
            "Tasks",
            icon(
                "view-list-symbolic",
                "view-list-bullet-symbolic",
                "format-justify-fill-symbolic",
            ),
        )
        self._stack.add_titled_with_icon(
            self.network,
            "network",
            "Network",
            icon(
                "network-transmit-receive-symbolic",
                "network-wireless-symbolic",
                "network-workgroup-symbolic",
            ),
        )
        self._stack.connect("notify::visible-child-name", self._on_page_changed)

        self._toasts = Adw.ToastOverlay()
        self._toasts.set_child(self._stack)

        view = Adw.ToolbarView()
        view.add_top_bar(self._header())
        view.set_content(self._toasts)

        switcher = Adw.ViewSwitcherBar()
        switcher.set_stack(self._stack)
        switcher.set_reveal(True)
        switcher.add_css_class("tabbar")
        view.add_bottom_bar(switcher)

        self._nav = Adw.NavigationView()
        self._nav.add(Adw.NavigationPage.new(view, "Vitals"))
        self._nav.connect("popped", self._on_popped)
        self.set_content(self._nav)

        # Sampling follows the window being on screen, not being focused. A
        # phone's compositor does not hand focus out the way a desktop does, and
        # the headless X server the checks run on has no window manager to hand
        # it out at all -- an app that sampled only while focused would sit
        # frozen in every screenshot.
        self.connect("map", lambda *_: self.start())
        self.connect("unmap", lambda *_: self.stop())

        self._prime()
        self._requested()

    # --- chrome ----------------------------------------------------------

    def _header(self) -> Adw.HeaderBar:
        header = Adw.HeaderBar()
        # The processor and memory figures live in the title, so they are on
        # screen on every page: the task list is the page you are on when you
        # want to know whether killing that process helped.
        self._title = Adw.WindowTitle(title="Vitals", subtitle="")
        header.set_title_widget(self._title)

        self._search_button = Gtk.ToggleButton(
            icon_name=icon("system-search-symbolic", "edit-find-symbolic")
        )
        self._search_button.set_tooltip_text("Search tasks")
        self._search_button.update_property(
            [Gtk.AccessibleProperty.LABEL], ["Search tasks"]
        )
        self._search_button.connect("toggled", self._on_search_toggled)
        self._search_button.set_visible(False)
        header.pack_start(self._search_button)

        menu = Gtk.MenuButton(
            icon_name=icon("open-menu-symbolic", "view-more-symbolic")
        )
        menu.set_tooltip_text("Menu")
        model = Gio.Menu()
        model.append("About Vitals", "app.about")
        menu.set_menu_model(model)
        header.pack_end(menu)
        return header

    def set_palette(self, palette: theme.Palette) -> None:
        """Hand the drawn half its colours.

        Everything that is a widget follows the stylesheet and needs nothing
        from here. Graphs and core bars are cairo, and cairo cannot read a CSS
        class -- the same arrangement Reversi and Solitaire have with their
        boards.
        """
        self._palette = palette
        for page in (self.overview, self.tasks, self.network):
            page.set_palette(palette)
        if isinstance(self._detail, DetailPage):
            self._detail.set_palette(palette)

    # --- the clock -------------------------------------------------------

    def start(self) -> None:
        if self._source:
            return
        self._tick()
        self._source = GLib.timeout_add(TICK_MS, self._on_tick)

    def stop(self) -> None:
        if self._source:
            GLib.source_remove(self._source)
            self._source = 0

    def _on_tick(self) -> bool:
        self._tick()
        return GLib.SOURCE_CONTINUE

    def _tick(self, *, draw: bool = True, processes: bool = False) -> None:
        # The process walk is a few hundred file reads; the overview needs none
        # of them. Asking for them only when something is showing them is the
        # difference between an app you can leave open and one you cannot.
        # `processes` is for the caller that wants the list before anything is
        # showing it -- opening straight onto a task, for the harness.
        wants = (
            processes
            or self._stack.get_visible_child_name() == "tasks"
            or self._detail is not None
        )
        sample = self.sampler.sample(processes=wants)
        self.sample = sample

        self.history["cpu"].push(sample.cpu.total)
        self.history["memory"].push(sample.memory.fraction)
        self.history["swap"].push(sample.memory.swap_fraction)
        self.history["rx"].push(sample.net_rx)
        self.history["tx"].push(sample.net_tx)
        for interface in sample.interfaces:
            for key, value in (("rx", interface.rx_rate), ("tx", interface.tx_rate)):
                name = f"{interface.name}:{key}"
                if name not in self.history:
                    self.history[name] = History(SAMPLES)
                self.history[name].push(value)

        if draw:
            self._refresh()

    def _refresh(self) -> None:
        sample = self.sample
        if sample is None:
            return
        self._title.set_subtitle(
            f"CPU {human_percent(sample.cpu.total)} · "
            f"RAM {human_percent(sample.memory.fraction)}"
        )
        page = self._stack.get_visible_child()
        if isinstance(page, Page):
            page.refresh(sample)
        if isinstance(self._detail, DetailPage):
            self._detail.refresh(sample)

    def _prime(self) -> None:
        """Fill the graphs from a fixture reel before the window is shown.

        Only ever a fixture: a real machine has no past in /proc to read, so on
        a phone the graphs fill up over the first two minutes and this does
        nothing. See `sysinfo.Reel` for why a screenshot needs it.
        """
        root = self.sampler.root
        if not isinstance(root, Reel):
            return
        while root.remaining > PRIME_TAIL:
            self._tick(draw=False)
        self._refresh()

    def _on_page_changed(self, *_args) -> None:
        name = self._stack.get_visible_child_name()
        self._search_button.set_visible(name == "tasks")
        # Read now rather than in two seconds. The page that has just appeared
        # may need something the last tick did not collect -- the task list is
        # the whole reason the walk of /proc is optional -- and a page that
        # showed a two-second-old reading for two seconds would be showing one
        # from before it was opened.
        self._tick()

    def _on_search_toggled(self, button: Gtk.ToggleButton) -> None:
        self.tasks.set_search(button.get_active())

    # --- the detail pages ------------------------------------------------

    def open_process(self, pid: int) -> None:
        self._push(ProcessPage(self, pid))

    def open_app(self, key: str) -> None:
        self._push(AppPage(self, key))

    def _push(self, page: DetailPage) -> None:
        self._detail = page
        page.set_palette(self._palette)
        self._nav.push(page)
        if self.sample is None or not self.sample.processes:
            # Opened from a page that was not reading processes. Sample now
            # rather than showing a row of dashes for two seconds.
            self._tick()
        else:
            page.refresh(self.sample)

    def _on_popped(self, _nav: Adw.NavigationView, page: Adw.NavigationPage) -> None:
        if page is self._detail:
            self._detail = self._nav.get_visible_page()
            if not isinstance(self._detail, DetailPage):
                self._detail = None

    def toast(self, text: str) -> None:
        toast = Adw.Toast.new(text)
        toast.set_timeout(3)
        self._toasts.add_toast(toast)

    # --- ending something ------------------------------------------------

    def confirm_end(self, name: str, pids: tuple[int, ...], *, force: bool) -> None:
        """Ask before signalling, differently for the two signals.

        TERM and KILL are not two strengths of the same button. One asks a
        process to stop and lets it save what it was doing; the other takes it
        away mid-write. The wording says which, because "Force stop" on its own
        reads as "the one that works".
        """
        if not pids:
            return
        count = len(pids)
        many = (
            f" and its {count - 1} helper process{'es' if count > 2 else ''}"
            if count > 1
            else ""
        )
        if force:
            title = f"Force stop {name}?"
            body = (
                f"{name}{many} will be stopped at once and cannot save anything. "
                "Use this when asking it to stop has not worked."
            )
        else:
            title = f"End {name}?"
            body = (
                f"{name}{many} will be asked to stop. Anything unsaved in it is lost."
            )

        dialog = Adw.AlertDialog.new(title, body)
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("end", "Force stop" if force else "End")
        dialog.set_response_appearance("end", Adw.ResponseAppearance.DESTRUCTIVE)
        dialog.set_default_response("cancel")
        dialog.set_close_response("cancel")
        dialog.connect("response", self._on_confirm, name, pids, force)
        dialog.present(self)

    def _on_confirm(
        self,
        _dialog: Adw.AlertDialog,
        response: str,
        name: str,
        pids: tuple[int, ...],
        force: bool,
    ) -> None:
        if response != "end":
            return
        self.end(name, pids, force=force)

    def end(self, name: str, pids: tuple[int, ...], *, force: bool) -> None:
        sent = 0
        refused = gone = False
        for pid in pids:
            try:
                self.sampler.end(pid, force=force)
                sent += 1
            except ProcessLookupError:
                gone = True
            except PermissionError:
                refused = True
            except OSError as exc:
                self.toast(f"Could not end {name}: {exc.strerror or exc}")
                return
        if sent:
            self.toast(f"Force stopped {name}" if force else f"Asked {name} to stop")
            if self._detail is not None:
                self._nav.pop()
        elif refused:
            # The usual reason, and worth saying plainly rather than as an
            # error: a phone task manager runs as the user, and the user does
            # not own the processes that keep the phone up.
            self.toast(f"{name} belongs to another user")
        elif gone:
            self.toast(f"{name} had already stopped")
        # Whatever happened, the list is now out of date.
        if self._source:
            self._tick()

    # --- starting on a particular screen ---------------------------------

    def _requested(self) -> None:
        """Open where an environment variable says, for the harness.

        A headless X server has no pointer worth clicking with, and a run that
        opens straight into the screen it should photograph needs none. The same
        mechanism every app in this repo uses.
        """
        sort = os.environ.get("MOARCHY_VITALS_SORT")
        if sort:
            self.tasks.set_sort(sort)
        mode = os.environ.get("MOARCHY_VITALS_TASKS")
        if mode:
            self.tasks.set_mode(mode)
        page = os.environ.get("MOARCHY_VITALS_PAGE")
        if page and self._stack.get_child_by_name(page) is not None:
            self._stack.set_visible_child_name(page)
        text = os.environ.get("MOARCHY_VITALS_SEARCH")
        if text is not None:
            self._search_button.set_active(True)
            self.tasks.set_query(text)
        pick = os.environ.get("MOARCHY_VITALS_PICK")
        if pick:
            self._pick(pick)

    def _pick(self, wanted: str) -> None:
        if self.sample is None or not self.sample.processes:
            self._tick(processes=True)
        if self.sample is None:
            return
        if wanted.isdigit():
            self.open_process(int(wanted))
            return
        for group in self.sample.apps:
            if group.name.lower() == wanted.lower():
                self.open_app(group.key)
                return
        for proc in self.sample.processes:
            if proc.name.lower() == wanted.lower():
                self.open_process(proc.pid)
                return
