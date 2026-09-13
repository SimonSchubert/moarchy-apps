"""The three pages, and what the window expects of one.

btop draws four boxes at once because it is on a screen that fits four boxes.
360 logical pixels does not, so the app is a page each of the three questions
somebody opens a task manager to ask: what is the machine doing, what is doing
it, and what is on the network.

None of them keeps state of its own beyond its widgets. Everything they draw
comes from the Sample and the histories the window owns, so a page that has been
off-screen for a minute is correct the moment it is shown -- which is what makes
the tick able to skip the expensive half while nothing is looking at it.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gtk  # noqa: E402
from moarchy_ui.icons import icon  # noqa: E402

from . import theme  # noqa: E402
from .sysinfo import (  # noqa: E402
    AppGroup,
    Process,
    Sample,
    human_bytes,
    human_percent,
    human_rate,
    human_seconds,
)
from .widgets import (  # noqa: E402
    APP_ICON,
    MARGIN,
    MAX_ROWS,
    NET_H,
    SPARK_H,
    Cores,
    Facts,
    Graph,
    Meter,
    TaskList,
    figure,
    panel,
    rate_pair,
    rate_text,
)

if TYPE_CHECKING:  # pragma: no cover - the window imports these, not the other way
    from .window import VitalsWindow

# How the task list may be ordered. Three, because a phone has room for three
# and because every question anybody brings to a task list is one of them:
# what is busy, what is big, and where is the one I am looking for.
SORTS = (
    ("cpu", "Processor"),
    ("memory", "Memory"),
    ("name", "Name"),
)


class Page:
    """What the window expects of a page: colours in, a reading in.

    A plain mixin rather than a GObject base. Two GObject classes cannot be
    inherited from at once, and every page already has one -- a scrolled window
    or a box -- so what is shared is Python's and not GTK's.
    """

    def set_palette(
        self, palette: theme.Palette
    ) -> None:  # pragma: no cover - interface
        raise NotImplementedError

    def refresh(self, sample: Sample) -> None:  # pragma: no cover - interface
        raise NotImplementedError


class OverviewPage(Gtk.ScrolledWindow, Page):
    """btop's four boxes, stacked and scrolled.

    Order is by how often the answer is here: the processor, then memory, then
    the battery, then storage, then a network summary. The network panel is a
    summary rather than the whole page because it has a page.
    """

    __gtype_name__ = "VitalsOverview"

    def __init__(self, window: VitalsWindow) -> None:
        super().__init__()
        self.window = window
        self.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.set_vexpand(True)

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        body.set_margin_start(MARGIN)
        body.set_margin_end(MARGIN)
        body.set_margin_top(10)
        body.set_margin_bottom(18)

        body.append(self._cpu_panel())
        body.append(self._memory_panel())
        self._battery_panel_widget = self._battery_panel()
        body.append(self._battery_panel_widget)
        body.append(self._storage_panel())
        body.append(self._network_panel())
        self.set_child(body)

    # --- panels ----------------------------------------------------------

    def _cpu_panel(self) -> Gtk.Widget:
        outer, inner = panel("PROCESSOR")

        top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        box, self._cpu_figure, _ = figure(unit="%")
        top.append(box)
        self._cpu_state = Gtk.Label(xalign=0.0)
        self._cpu_state.add_css_class("note")
        self._cpu_state.set_valign(Gtk.Align.CENTER)
        self._cpu_state.set_hexpand(True)
        self._cpu_state.set_ellipsize(3)
        top.append(self._cpu_state)
        inner.append(top)

        self._cpu_graph = Graph(("cpu",))
        inner.append(self._cpu_graph)

        self._cores = Cores()
        inner.append(self._cores)

        self._cpu_facts = Facts()
        for key, title in (
            ("load", "Load"),
            ("tasks", "Tasks"),
            ("temp", "Heat"),
            ("uptime", "Up"),
        ):
            self._cpu_facts.add(key, title)
        inner.append(self._cpu_facts)
        return outer

    def _memory_panel(self) -> Gtk.Widget:
        outer, inner = panel("MEMORY")
        self._memory_meter = Meter("Used", "memory")
        inner.append(self._memory_meter)
        # Shorter than the processor's. Memory sits in the middle of its scale
        # and stays there, so a tall graph of it is a tall block of colour: what
        # is worth seeing is the shape, and forty pixels carries a shape.
        self._memory_graph = Graph(("memory",), height=SPARK_H, fill=theme.GHOST)
        inner.append(self._memory_graph)
        self._swap_meter = Meter("Swap", "swap", thin=True)
        inner.append(self._swap_meter)
        self._memory_facts = Facts()
        for key, title in (("cache", "Cached"), ("free", "Available")):
            self._memory_facts.add(key, title)
        inner.append(self._memory_facts)
        return outer

    def _battery_panel(self) -> Gtk.Widget:
        outer, inner = panel("BATTERY")
        self._battery_meter = Meter("Charge", "battery")
        inner.append(self._battery_meter)
        return outer

    def _storage_panel(self) -> Gtk.Widget:
        outer, inner = panel("STORAGE")
        self._disk_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self._disk_meters: dict[str, Meter] = {}
        inner.append(self._disk_box)
        self._io = Facts(columns=1)
        self._io.add("io", "Disk")
        inner.append(self._io)
        return outer

    def _network_panel(self) -> Gtk.Widget:
        outer, inner = panel("NETWORK")
        box, self._net_down, self._net_up = rate_pair("—", "—")
        inner.append(box)
        self._net_graph = Graph(("rx", "tx"), height=NET_H, mirror=True, scale=None)
        inner.append(self._net_graph)
        self._net_note = Gtk.Label(xalign=0.0)
        self._net_note.add_css_class("note")
        self._net_note.set_ellipsize(3)
        inner.append(self._net_note)
        return outer

    # --- filling them in -------------------------------------------------

    def set_palette(self, palette: theme.Palette) -> None:
        for widget in (
            self._cpu_graph,
            self._memory_graph,
            self._net_graph,
            self._cores,
        ):
            widget.set_palette(palette)

    def refresh(self, sample: Sample) -> None:
        history = self.window.history
        cpu = sample.cpu

        self._cpu_figure.set_text(f"{round(cpu.total * 100)}")
        running = cpu.running
        busiest = f"{running} running" if running else "idle"
        if cpu.frequency:
            busiest += f" · {cpu.frequency / 1000:.1f} GHz"
        self._cpu_state.set_text(busiest)
        self._cpu_graph.refresh(history["cpu"].as_tuple())
        self._cores.refresh(cpu.cores)

        one, five, fifteen = cpu.load
        self._cpu_facts.set("load", f"{one:.2f} {five:.2f} {fifteen:.2f}")
        self._cpu_facts.set("tasks", str(cpu.tasks))
        if cpu.temperature is None:
            self._cpu_facts.set("temp", "—")
        else:
            classes = theme.temperature_class(cpu.temperature)
            self._cpu_facts.set(
                "temp",
                f"{cpu.temperature:.0f} °C",
                classes=(classes,) if classes else (),
            )
        self._cpu_facts.set("uptime", human_seconds(cpu.uptime))

        memory = sample.memory
        self._memory_meter.refresh(
            memory.fraction,
            f"{human_bytes(memory.used)} of {human_bytes(memory.total)}",
        )
        self._memory_graph.refresh(history["memory"].as_tuple())
        self._swap_meter.set_visible(memory.swap_total > 0)
        if memory.swap_total:
            self._swap_meter.refresh(
                memory.swap_fraction,
                f"{human_bytes(memory.swap_used)} of {human_bytes(memory.swap_total)}",
            )
        self._memory_facts.set("cache", human_bytes(memory.cached))
        self._memory_facts.set("free", human_bytes(memory.available))

        battery = sample.battery
        self._battery_panel_widget.set_visible(battery is not None)
        if battery is not None:
            note = battery.status.lower()
            if battery.watts:
                note += f" · {battery.watts:.1f} W"
            self._battery_meter.refresh(
                battery.percent / 100.0, f"{battery.percent}% {note}"
            )

        self._refresh_disks(sample)

        self._net_down.set_text(rate_text(sample.net_rx))
        self._net_up.set_text(rate_text(sample.net_tx))
        self._net_graph.refresh(history["rx"].as_tuple(), history["tx"].as_tuple())
        live = [i.name for i in sample.interfaces if i.up and i.name != "lo"]
        peak = self._net_graph.scale
        self._net_note.set_text(
            (", ".join(live) if live else "no interface up")
            + f" · scale {human_rate(peak)}"
        )

    def _refresh_disks(self, sample: Sample) -> None:
        for disk in sample.disks:
            meter = self._disk_meters.get(disk.mount)
            if meter is None:
                meter = Meter(disk.mount, "disk", thin=True, literal=True)
                self._disk_meters[disk.mount] = meter
                self._disk_box.append(meter)
            meter.set_visible(True)
            meter.refresh(
                disk.fraction,
                f"{human_bytes(disk.free)} free of {human_bytes(disk.total)}",
            )
        mounted = {disk.mount for disk in sample.disks}
        for mount, meter in self._disk_meters.items():
            if mount not in mounted:
                # An SD card can be pulled out. The meter is kept rather than
                # destroyed, because it will be back when the card is.
                meter.set_visible(False)
        self._io.set(
            "io",
            f"↓ {rate_text(sample.io.read_rate)}   ↑ {rate_text(sample.io.write_rate)}",
        )


class TasksPage(Gtk.Box, Page):
    """What is running: grouped into apps, or every process.

    Apps first, because "which app is eating the battery" is the question, and a
    list of two hundred processes answers it with a puzzle -- twenty of the rows
    are one browser. Every process is one tap away for when the answer really is
    a particular pid.
    """

    __gtype_name__ = "VitalsTasks"

    def __init__(self, window: VitalsWindow) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.window = window
        self.mode = "apps"
        self.sort = "cpu"
        self.query = ""

        self.append(self._controls())

        self._search = Gtk.SearchBar()
        self._entry = Gtk.SearchEntry()
        self._entry.set_placeholder_text("Name of an app or process")
        self._entry.connect("search-changed", self._on_query)
        self._search.set_child(self._entry)
        self._search.connect_entry(self._entry)
        self._search.set_key_capture_widget(window)
        self.append(self._search)

        self._list = TaskList()
        self._list.set_margin_start(MARGIN)
        self._list.set_margin_end(MARGIN)
        self._list.set_margin_bottom(6)
        self._list.connect("picked", self._on_picked)

        self._count = Gtk.Label(xalign=0.5)
        self._count.add_css_class("note")
        self._count.set_margin_top(6)
        self._count.set_margin_bottom(12)

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        body.append(self._list)
        body.append(self._count)

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_vexpand(True)
        scroller.set_child(body)

        self._empty = Adw.StatusPage()
        self._empty.set_icon_name(icon("system-search-symbolic", "edit-find-symbolic"))
        self._empty.set_title("Nothing matches")
        self._empty.set_description("No app or process here has that in its name.")

        self._stack = Gtk.Stack()
        self._stack.add_named(scroller, "list")
        self._stack.add_named(self._empty, "empty")
        self._stack.set_vexpand(True)
        self.append(self._stack)

    def _controls(self) -> Gtk.Widget:
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.set_margin_start(MARGIN)
        row.set_margin_end(MARGIN)
        row.set_margin_top(8)
        row.set_margin_bottom(4)

        # Two linked toggles rather than Adw.ToggleGroup: that widget is newer
        # than the libadwaita on the phone image, and a segmented control is two
        # buttons and a CSS class in every version.
        toggles = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        toggles.add_css_class("linked")
        self._apps_toggle = Gtk.ToggleButton(label="Apps", active=True)
        self._all_toggle = Gtk.ToggleButton(label="All")
        self._all_toggle.set_group(self._apps_toggle)
        for button in (self._apps_toggle, self._all_toggle):
            button.set_size_request(-1, 40)
            toggles.append(button)
        self._apps_toggle.connect("toggled", self._on_mode)
        row.append(toggles)

        spacer = Gtk.Box()
        spacer.set_hexpand(True)
        row.append(spacer)

        self._sort = Gtk.DropDown.new_from_strings([title for _, title in SORTS])
        self._sort.set_tooltip_text("Sort by")
        self._sort.update_property([Gtk.AccessibleProperty.LABEL], ["Sort by"])
        self._sort.connect("notify::selected", self._on_sort)
        row.append(self._sort)
        return row

    # --- what is showing -------------------------------------------------

    def set_mode(self, mode: str) -> None:
        if mode not in ("apps", "all"):
            return
        self.mode = mode
        self._apps_toggle.set_active(mode == "apps")
        self._all_toggle.set_active(mode == "all")

    def set_sort(self, key: str) -> None:
        for index, (name, _) in enumerate(SORTS):
            if name == key:
                self.sort = key
                self._sort.set_selected(index)
                return

    def set_search(self, on: bool) -> None:
        self._search.set_search_mode(on)
        if on:
            self._entry.grab_focus()
        else:
            self._entry.set_text("")

    def set_query(self, text: str) -> None:
        self._search.set_search_mode(True)
        self._entry.set_text(text)

    def _on_mode(self, button: Gtk.ToggleButton) -> None:
        self.mode = "apps" if button.get_active() else "all"
        self._redraw()

    def _on_sort(self, *_args) -> None:
        index = self._sort.get_selected()
        if 0 <= index < len(SORTS):
            self.sort = SORTS[index][0]
        self._redraw()

    def _on_query(self, entry: Gtk.SearchEntry) -> None:
        self.query = entry.get_text().strip().lower()
        self._redraw()

    def _on_picked(self, _list: TaskList, item) -> None:
        if isinstance(item, AppGroup):
            self.window.open_app(item.key)
        else:
            self.window.open_process(item.pid)

    def _redraw(self) -> None:
        if self.window.sample is not None:
            self.refresh(self.window.sample)

    # --- the list --------------------------------------------------------

    def set_palette(self, palette: theme.Palette) -> None:
        """Nothing here is drawn: every row is a widget and follows the CSS."""

    def refresh(self, sample: Sample) -> None:
        items = list(sample.apps) if self.mode == "apps" else list(sample.processes)
        if self.query:
            items = [item for item in items if self.query in item.name.lower()]
        items.sort(key=self._key)
        total = len(items)
        self._list.set_items(items[:MAX_ROWS])
        self._stack.set_visible_child_name("empty" if not items else "list")

        one, many = ("app", "apps") if self.mode == "apps" else ("process", "processes")
        if total > MAX_ROWS:
            self._count.set_text(f"{MAX_ROWS} of {total} {many}, busiest first")
        else:
            self._count.set_text(f"{total} {one if total == 1 else many}")

    def _key(self, item: Process | AppGroup):
        if self.sort == "memory":
            return (-item.rss, -item.cpu, item.name.lower())
        if self.sort == "name":
            return (item.name.lower(), -item.cpu)
        return (-item.cpu, -item.rss, item.name.lower())


class NetworkPage(Gtk.ScrolledWindow, Page):
    """One panel per interface: a graph of both directions, and the totals.

    Both directions on one graph, mirrored about the middle, because upload and
    download are the same unit in opposite directions and a phone has room for
    one graph per interface, not two. Loopback is on the list and last: it is
    real traffic, and it is never the answer to "what is using my data".
    """

    __gtype_name__ = "VitalsNetwork"

    def __init__(self, window: VitalsWindow) -> None:
        super().__init__()
        self.window = window
        self.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.set_vexpand(True)

        self._body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self._body.set_margin_start(MARGIN)
        self._body.set_margin_end(MARGIN)
        self._body.set_margin_top(10)
        self._body.set_margin_bottom(18)
        self._panels: dict[str, dict] = {}
        self._palette = theme.fallback(dark=True)

        self._empty = Adw.StatusPage()
        self._empty.set_icon_name(APP_ICON)
        self._empty.set_title("No interfaces")
        self._empty.set_description("Nothing in /proc/net/dev to show.")

        self._stack = Gtk.Stack()
        self._stack.add_named(self._body, "list")
        self._stack.add_named(self._empty, "empty")
        self.set_child(self._stack)

    def set_palette(self, palette: theme.Palette) -> None:
        self._palette = palette
        for widgets in self._panels.values():
            widgets["graph"].set_palette(palette)

    def refresh(self, sample: Sample) -> None:
        self._stack.set_visible_child_name("list" if sample.interfaces else "empty")
        for interface in sample.interfaces:
            widgets = self._panels.get(interface.name)
            if widgets is None:
                widgets = self._build(interface.name)
            widgets["panel"].set_visible(True)

            state = interface.state
            if interface.wireless and interface.quality is not None:
                state += f" · signal {human_percent(interface.quality)}"
                if interface.signal is not None:
                    state += f" ({interface.signal} dBm)"
            widgets["state"].set_text(state)

            # An interface that is down and has never carried a byte gets its
            # name and nothing else. The phone has three of these and the modem
            # is usually one of them: a full panel of dashes, an empty graph and
            # two zeroes is most of a screen saying "no".
            quiet = not interface.up and interface.rx + interface.tx == 0
            for key in ("rates", "graph", "totals"):
                widgets[key].set_visible(not quiet)
            if quiet:
                continue

            widgets["down"].set_text(rate_text(interface.rx_rate))
            widgets["up"].set_text(rate_text(interface.tx_rate))
            history = self.window.history
            widgets["graph"].refresh(
                history[f"{interface.name}:rx"].as_tuple()
                if f"{interface.name}:rx" in history
                else (),
                history[f"{interface.name}:tx"].as_tuple()
                if f"{interface.name}:tx" in history
                else (),
            )
            widgets["totals"].set(
                "since",
                f"↓ {human_bytes(interface.rx)}   ↑ {human_bytes(interface.tx)}",
            )
            widgets["totals"].set("scale", human_rate(widgets["graph"].scale))

        present = {interface.name for interface in sample.interfaces}
        for name, widgets in self._panels.items():
            if name not in present:
                widgets["panel"].set_visible(False)

    def _build(self, name: str) -> dict:
        # The interface's own name, not upper-cased: wlan0 in capitals is
        # WLANO, and the zero reads as a letter.
        outer, inner = panel(name)
        state = Gtk.Label(xalign=0.0)
        state.add_css_class("note")
        state.set_ellipsize(3)
        inner.append(state)

        rates, down, up = rate_pair("—", "—")
        inner.append(rates)

        graph = Graph(("rx", "tx"), height=NET_H, mirror=True, scale=None)
        graph.set_palette(self._palette)
        inner.append(graph)

        totals = Facts(columns=1)
        totals.add("since", "Since boot")
        totals.add("scale", "Graph scale")
        inner.append(totals)

        self._body.append(outer)
        widgets = {
            "panel": outer,
            "state": state,
            "rates": rates,
            "down": down,
            "up": up,
            "graph": graph,
            "totals": totals,
        }
        self._panels[name] = widgets
        return widgets
