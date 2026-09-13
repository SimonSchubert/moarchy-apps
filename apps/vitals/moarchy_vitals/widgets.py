"""The things a reading is drawn as.

Four shapes carry the whole app: a graph of the last two minutes, a row of bars
for the cores, a meter for anything with a maximum, and a task row. Every screen
is made of those four and some labels.

What is cairo and what is a widget is decided per shape rather than by
preference. A graph is sixty values and two paths, which is one drawn shape; the
same thing as sixty widgets would be sixty style lookups twice a second on a
phone with no GL. A meter is libadwaita's own progress bar, because it already
has the height, the radius and the animation, and recolouring its trough is four
lines of CSS against reimplementing all three. Text is always a label -- cairo
can draw text, and then it is text that does not scale with the phone's font
size, does not get read out by a screen reader and does not ellipsize.

The sizes are the phone. 360 logical pixels wide, minus 12 of window margin
either side and 14 of panel padding either side, leaves 308 for anything inside
a panel -- which is where the graph width, the core bar arithmetic and the task
row's two columns all come from.
"""

from __future__ import annotations

import math
from typing import ClassVar

import gi

gi.require_version("Gtk", "4.0")

from gi.repository import GObject, Gtk  # noqa: E402

from . import theme  # noqa: E402
from .sysinfo import (  # noqa: E402
    AppGroup,
    Process,
    human_bytes,
    human_percent,
    human_rate,
    task_percent,
)

# Inside a panel, at 360px. Everything laid out by hand uses this rather than a
# guess: the panel's padding is in the stylesheet and this is the number it
# leaves.
PANEL_WIDTH = 308

# How many samples a graph holds. At one sample every two seconds this is two
# minutes of history, and at 308px of panel it is a little under five pixels a
# sample -- wide enough that a single busy tick is a visible spike rather than a
# hairline.
SAMPLES = 60

GRAPH_H = 62
NET_H = 56
SPARK_H = 40

# The core row is short on purpose. A bar is mostly empty on an idle phone, and
# a tall empty track reads as a grey box rather than as a meter at nine per cent.
CORES_H = 26

# A core bar. Wide enough to read across a room, narrow enough that four of them
# are a row of meters rather than four grey slabs -- which is what 308px divided
# four ways looked like. Eight fit at this width too; more than that and the
# drawing shrinks them to fit rather than running off the panel.
CORE_BAR = 34
CORE_GAP = 4

# The tap target floor, as everywhere else in this repo: the smallest thing a
# thumb hits reliably.
TARGET = 44

# The window's own margin, and the gap between panels. 12 either side is what
# the boxed lists in the other apps here use, so a panel in this app lines up
# with a row in Keep.
MARGIN = 12

# How many rows a task list will draw. A phone has two hundred processes and no
# screen for them; the point of a task list is the top of it, and the search box
# is how anybody finds one further down. The number is a compromise about
# scrolling rather than about widgets -- the rows are pooled, so a hundred would
# cost little to build and be no more use.
MAX_ROWS = 50

# The app's own icon, which this package installs -- so it cannot be missing
# wherever the app is, whatever the icon theme. Used for the empty states, where
# a missing icon would be a grey warning triangle in the middle of the screen.
APP_ICON = "org.moarchy.Vitals"


def rgb(colour: str) -> tuple[float, float, float]:
    """A theme colour as cairo wants it."""
    text = colour.lstrip("#")
    if len(text) == 3:
        text = "".join(c * 2 for c in text)
    try:
        return tuple(int(text[i : i + 2], 16) / 255.0 for i in (0, 2, 4))  # type: ignore[return-value]
    except ValueError:  # pragma: no cover - a malformed theme is caught upstream
        return (0.5, 0.5, 0.5)


def nice_ceiling(value: float) -> float:
    """The next round number up from `value`: 1, 2 or 5 times a power of ten.

    A graph that scales to exactly its own peak has no scale at all -- every
    graph is full, and a quiet interface looks as busy as a download. Rounding
    up to a round number means the axis holds still while the traffic moves, and
    two interfaces drawn at the same scale can be compared.
    """
    if value <= 0:
        return 1.0
    power = 10 ** math.floor(math.log10(value))
    for step in (1.0, 2.0, 5.0, 10.0):
        if value <= step * power:
            return step * power
    return 10 * power  # pragma: no cover - unreachable, the loop ends at 10


class Graph(Gtk.DrawingArea):
    """The last `SAMPLES` readings of one or two series, as a filled area.

    Newest at the right, which is the direction every graph of time on a screen
    runs, and a half-full history draws as a half-full graph rather than being
    stretched to fit -- a phone that has been open for twenty seconds should
    look like it, not like two minutes of flat line.

    `mirror` splits the box: the first series fills downwards from the middle
    and the second upwards from the bottom, both against the same scale. That is
    for traffic, where the two numbers are the same unit in opposite directions
    and drawing them on top of each other hides whichever is smaller.
    """

    __gtype_name__ = "VitalsGraph"

    def __init__(
        self,
        keys: tuple[str, ...],
        *,
        height: int = GRAPH_H,
        mirror: bool = False,
        scale: float | None = 1.0,
        fill: float = theme.FILL,
    ) -> None:
        super().__init__()
        self.keys = keys
        self.mirror = mirror
        # How much of the hue goes under the line. A series that lives in the
        # middle of its scale -- memory, which is never near either end -- is a
        # block of colour at the full amount and a shape at theme.GHOST.
        self.fill = fill
        self.fixed_scale = scale
        self.scale = scale or 1.0
        self._series: tuple[tuple[float, ...], ...] = ((),) * len(keys)
        self._palette = theme.fallback(dark=True)
        self.set_content_height(height)
        self.set_hexpand(True)
        self.set_draw_func(self._draw)

    def set_palette(self, palette: theme.Palette) -> None:
        self._palette = palette
        self.queue_draw()

    def refresh(self, *series: tuple[float, ...]) -> None:
        self._series = series
        if self.fixed_scale is None:
            peak = max((max(s) for s in series if s), default=0.0)
            self.scale = nice_ceiling(peak)
        self.queue_draw()

    def _draw(self, _area: Gtk.DrawingArea, cr, width: int, height: int) -> None:
        p = self._palette
        track = rgb(theme.mix(p.foreground, p.background, theme.TRACK))

        cr.set_line_width(1.0)
        cr.set_source_rgb(*track)
        if self.mirror:
            # The line the two directions are measured from, rather than a box:
            # a frame around a graph this small is mostly frame.
            cr.move_to(0, height / 2)
            cr.line_to(width, height / 2)
        else:
            cr.move_to(0, height - 0.5)
            cr.line_to(width, height - 0.5)
        cr.stroke()

        for index, (key, values) in enumerate(zip(self.keys, self._series)):
            if not values:
                continue
            if self.mirror:
                base = height / 2
                span = height / 2
                # Down above the line, up below it: the convention every
                # traffic graph uses, and the one the arrows beside the figures
                # have already promised.
                down = index == 1
            else:
                base = height
                span = height
                down = False
            self._draw_series(cr, width, values, key, base, span, down)

    def _draw_series(
        self,
        cr,
        width: int,
        values: tuple[float, ...],
        key: str,
        base: float,
        span: float,
        down: bool,
    ) -> None:
        colour = theme.series(self._palette, key)
        step = width / max(1, SAMPLES - 1)
        # Right-aligned: the newest sample sits on the right edge whatever the
        # history holds.
        start = width - (len(values) - 1) * step

        def point(index: int, value: float) -> tuple[float, float]:
            share = min(1.0, value / self.scale) if self.scale else 0.0
            offset = share * (span - 1)
            return start + index * step, base + offset if down else base - offset

        # The fill and the line are one path traced twice: the fill closes it
        # back along the baseline, the line does not. Solid colours both, mixed
        # against the background rather than drawn with an alpha -- there is no
        # GL on this hardware, and a translucent fill is blended every frame.
        if self.fill > 0:
            cr.save()
            cr.move_to(*point(0, values[0]))
            for index, value in enumerate(values[1:], start=1):
                cr.line_to(*point(index, value))
            end_x, _ = point(len(values) - 1, values[-1])
            cr.line_to(end_x, base)
            cr.line_to(start, base)
            cr.close_path()
            cr.set_source_rgb(
                *rgb(theme.mix(colour, self._palette.background, self.fill))
            )
            cr.fill()
            cr.restore()

        cr.set_line_width(1.5)
        cr.set_source_rgb(*rgb(colour))
        cr.move_to(*point(0, values[0]))
        for index, value in enumerate(values[1:], start=1):
            cr.line_to(*point(index, value))
        cr.stroke()


class Cores(Gtk.Box):
    """One bar per processor core, and its load under it.

    A phone has four of these, or eight, and which of them is pegged is a real
    question on a big.LITTLE SoC -- a browser tab on a little core reads as 25%
    of the machine and feels like the phone has stopped. The bars are drawn and
    the numbers are labels, because a number drawn with cairo ignores the
    phone's font size and cannot be read out.
    """

    __gtype_name__ = "VitalsCores"

    def __init__(self) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        self._loads: tuple[float, ...] = ()
        self._palette = theme.fallback(dark=True)

        self._area = Gtk.DrawingArea()
        self._area.set_content_height(CORES_H)
        self._area.set_halign(Gtk.Align.CENTER)
        self._area.set_draw_func(self._draw)
        self.append(self._area)

        # Centred and sized to the bars rather than stretched across the panel,
        # so each number sits under the bar it belongs to.
        self._labels = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=CORE_GAP)
        self._labels.set_halign(Gtk.Align.CENTER)
        self.append(self._labels)

    def set_palette(self, palette: theme.Palette) -> None:
        self._palette = palette
        self._area.queue_draw()

    def refresh(self, loads: tuple[float, ...]) -> None:
        if len(loads) != len(self._loads):
            # The count only changes when a core is brought online or taken
            # away, which on a phone happens on the first sample and then never.
            while (child := self._labels.get_first_child()) is not None:
                self._labels.remove(child)
            for _ in loads:
                label = Gtk.Label()
                label.add_css_class("corelabel")
                label.set_size_request(CORE_BAR, -1)
                self._labels.append(label)
            count = len(loads)
            self._area.set_content_width(
                min(PANEL_WIDTH, count * CORE_BAR + (count - 1) * CORE_GAP)
            )
        self._loads = loads
        label = self._labels.get_first_child()
        for load in loads:
            if label is None:
                break
            label.set_text(human_percent(load))
            label = label.get_next_sibling()
        self._area.queue_draw()

    def _draw(self, _area: Gtk.DrawingArea, cr, width: int, height: int) -> None:
        if not self._loads:
            return
        p = self._palette
        count = len(self._loads)
        gap = CORE_GAP if count <= 8 else 2
        bar = max(2.0, (width - gap * (count - 1)) / count)
        track = rgb(theme.mix(p.foreground, p.background, theme.TRACK))
        for index, load in enumerate(self._loads):
            x = index * (bar + gap)
            cr.set_source_rgb(*track)
            _round_rect(cr, x, 0, bar, height, min(3.0, bar / 2))
            cr.fill()
            # Never less than a visible line of colour. At five per cent of a
            # 26px bar the fill is one pixel, which on the device read as four
            # empty boxes with numbers underneath them.
            filled = max(3.0, load * height)
            cr.set_source_rgb(*rgb(theme.heat(p, load)))
            _round_rect(cr, x, height - filled, bar, filled, min(3.0, bar / 2))
            cr.fill()


def _round_rect(
    cr, x: float, y: float, width: float, height: float, radius: float
) -> None:
    radius = min(radius, width / 2, height / 2)
    cr.new_sub_path()
    cr.arc(x + width - radius, y + radius, radius, -math.pi / 2, 0)
    cr.arc(x + width - radius, y + height - radius, radius, 0, math.pi / 2)
    cr.arc(x + radius, y + height - radius, radius, math.pi / 2, math.pi)
    cr.arc(x + radius, y + radius, radius, math.pi, 1.5 * math.pi)
    cr.close_path()


class Meter(Gtk.Box):
    """Anything with a maximum: a name, a figure, and a bar under both.

    libadwaita's progress bar, recoloured through its trough. Reimplementing it
    would mean reimplementing its height, its radius and the animation it does
    when the value changes, all of which are already right.
    """

    __gtype_name__ = "VitalsMeter"

    def __init__(
        self, name: str, key: str, *, thin: bool = False, literal: bool = False
    ) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)

        self._name = Gtk.Label(label=name, xalign=0.0)
        self._name.add_css_class("label")
        # A meter's name is normally a word this app chose -- USED, SWAP -- and
        # is upper-cased to sit with the panel headings. A mount point is not:
        # /boot upper-cased is /BOOT, which is a path that does not exist.
        if literal:
            self._name.add_css_class("literal")
        self._name.set_hexpand(True)
        self._name.set_ellipsize(3)  # Pango.EllipsizeMode.END
        top.append(self._name)

        self._value = Gtk.Label(xalign=1.0)
        self._value.add_css_class("note")
        top.append(self._value)
        self.append(top)

        self._bar = Gtk.ProgressBar()
        self._bar.add_css_class("meter")
        self._bar.add_css_class(key)
        if thin:
            self._bar.add_css_class("thin")
        self.append(self._bar)

    def set_name(self, text: str) -> None:
        self._name.set_text(text)

    def refresh(self, fraction: float, text: str) -> None:
        self._bar.set_fraction(max(0.0, min(1.0, fraction)))
        self._value.set_text(text)
        # The bar is the only thing on screen saying this, so it says it out
        # loud as well: a progress bar with no accessible value is a rectangle.
        self._bar.update_property(
            [Gtk.AccessibleProperty.LABEL], [f"{self._name.get_text()}: {text}"]
        )


class Facts(Gtk.Grid):
    """A short list of label-and-value pairs, in two columns.

    Not a boxed list: these sit inside a panel that already has a background and
    a heading, and a list inside a panel is two backgrounds and two radii for
    four facts. The values are right-aligned in a column of their own so that
    four rows of digits line up.

    `columns` is how many label-and-value pairs share a row. Two for four short
    facts under a graph; one where a value is wide enough to need the width.
    """

    __gtype_name__ = "VitalsFacts"

    def __init__(self, *, columns: int = 2) -> None:
        super().__init__(column_spacing=18, row_spacing=2)
        self.columns = columns
        self._values: dict[str, Gtk.Label] = {}
        self._rows: dict[str, tuple[Gtk.Widget, Gtk.Widget]] = {}
        self._count = 0

    def add(self, key: str, title: str) -> None:
        label = Gtk.Label(label=title, xalign=0.0)
        label.add_css_class("note")
        value = Gtk.Label(xalign=1.0)
        value.add_css_class("value")
        value.set_ellipsize(3)

        row, column = divmod(self._count, max(1, self.columns))
        # A label and its value are attached as a pair of adjacent columns, so
        # `columns=2` is two pairs across rather than four columns of text.
        self.attach(label, column * 2, row, 1, 1)
        self.attach(value, column * 2 + 1, row, 1, 1)
        value.set_hexpand(True)
        self._values[key] = value
        self._rows[key] = (label, value)
        self._count += 1

    def set(self, key: str, text: str, *, classes: tuple[str, ...] = ()) -> None:
        value = self._values.get(key)
        if value is None:
            return
        value.set_text(text)
        for name in ("warm", "hot"):
            value.remove_css_class(name)
        for name in classes:
            value.add_css_class(name)


class TaskRow(Gtk.ListBoxRow):
    """One process, or one app: what it is called, and what it is costing.

    Two columns, and the right one is fixed. The figures are the reason anybody
    opened this page, so they get a column of their own that does not move when
    a name beside it is long -- and the name ellipsizes into whatever is left
    rather than wrapping, because a task list where one row is three lines tall
    is a task list you cannot scan.
    """

    __gtype_name__ = "VitalsTaskRow"

    FIGURES = 76

    def __init__(self) -> None:
        super().__init__()
        self.payload: Process | AppGroup | None = None
        self.set_activatable(True)

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        box.add_css_class("task-row")

        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        text.set_hexpand(True)
        text.set_valign(Gtk.Align.CENTER)
        self._name = Gtk.Label(xalign=0.0)
        self._name.add_css_class("task-name")
        self._name.set_ellipsize(3)
        self._name.set_single_line_mode(True)
        text.append(self._name)
        self._note = Gtk.Label(xalign=0.0)
        self._note.add_css_class("task-note")
        self._note.set_ellipsize(3)
        self._note.set_single_line_mode(True)
        text.append(self._note)
        box.append(text)

        figures = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        figures.set_size_request(self.FIGURES, -1)
        figures.set_valign(Gtk.Align.CENTER)
        self._cpu = Gtk.Label(xalign=1.0)
        self._cpu.add_css_class("task-figure")
        figures.append(self._cpu)
        self._rss = Gtk.Label(xalign=1.0)
        self._rss.add_css_class("task-sub")
        figures.append(self._rss)
        box.append(figures)

        self.set_child(box)

    def refresh(self, item: Process | AppGroup) -> None:
        self.payload = item
        self._name.set_text(item.name or "?")
        if isinstance(item, AppGroup):
            count = item.count
            self._note.set_text(
                f"{item.user} · {count} process{'es' if count != 1 else ''}"
            )
        else:
            self._note.set_text(f"{item.user} · pid {item.pid} · {item.state.lower()}")
        self._cpu.set_text(task_percent(item.cpu))
        self._rss.set_text(human_bytes(item.rss))
        # One string for a screen reader, because four labels in two columns are
        # read as four unrelated fragments.
        self.update_property(
            [Gtk.AccessibleProperty.LABEL],
            [
                f"{item.name}, {task_percent(item.cpu)} processor, {human_bytes(item.rss)}"
            ],
        )


class TaskList(Gtk.ListBox):
    """The rows, reused rather than rebuilt.

    A task list refreshes twice a second and has two hundred candidates. Both
    halves of that are why the rows are a pool: rebuilding them every tick would
    throw away the row under the thumb mid-scroll, and building two hundred of
    them would cost more than reading /proc did. So `set_items` refreshes as
    many rows as there are items, hides the rest, and adds more only when a
    longer list than has ever been shown arrives.
    """

    __gtype_name__ = "VitalsTaskList"

    __gsignals__: ClassVar[dict] = {
        # The Process or the AppGroup itself, rather than a pid: the page above
        # has to know which of the two it was handed to know where to go.
        "picked": (GObject.SignalFlags.RUN_FIRST, None, (object,)),
    }

    def __init__(self) -> None:
        super().__init__()
        self.set_selection_mode(Gtk.SelectionMode.NONE)
        self.add_css_class("boxed-list")
        self._pool: list[TaskRow] = []
        self.connect("row-activated", self._on_activated)

    def _on_activated(self, _list: Gtk.ListBox, row: Gtk.ListBoxRow) -> None:
        if isinstance(row, TaskRow) and row.payload is not None:
            self.emit("picked", row.payload)

    def set_items(self, items: list[Process] | list[AppGroup]) -> None:
        for index, item in enumerate(items):
            if index >= len(self._pool):
                row = TaskRow()
                self._pool.append(row)
                self.append(row)
            row = self._pool[index]
            row.refresh(item)
            row.set_visible(True)
        for row in self._pool[len(items) :]:
            row.set_visible(False)
            row.payload = None


def panel(heading: str | None = None, *, flat: bool = False) -> tuple[Gtk.Box, Gtk.Box]:
    """A titled panel, and the box to put things in.

    Returned as a pair rather than as a widget with an `add`, because every
    caller wants the inner box and none of them want to remember which of the
    two to append to.
    """
    outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    outer.add_css_class("panel-flat" if flat else "panel")
    if heading is not None:
        label = Gtk.Label(label=heading, xalign=0.0)
        label.add_css_class("section-heading")
        outer.append(label)
    inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
    outer.append(inner)
    return outer, inner


def figure(*, unit: str = "") -> tuple[Gtk.Box, Gtk.Label, Gtk.Label]:
    """A big number with a small unit beside it, aligned on the baseline."""
    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
    box.set_valign(Gtk.Align.BASELINE)
    number = Gtk.Label()
    number.add_css_class("figure")
    number.set_valign(Gtk.Align.BASELINE)
    box.append(number)
    tail = Gtk.Label(label=unit)
    tail.add_css_class("figure-unit")
    tail.set_valign(Gtk.Align.BASELINE)
    box.append(tail)
    return box, number, tail


def rate_pair(down: str, up: str) -> tuple[Gtk.Box, Gtk.Label, Gtk.Label]:
    """Down and up, side by side, each in its own colour.

    The arrows are the label. "Received" and "Transmitted" spelled out would not
    fit twice across a phone, and everyone already reads a down arrow next to a
    number as a download.
    """
    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
    labels = []
    for glyph, key in (("↓", "rx"), ("↑", "tx")):
        pair = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=3)
        arrow = Gtk.Label(label=glyph)
        arrow.add_css_class(f"ink-{key}")
        arrow.add_css_class("figure-small")
        pair.append(arrow)
        value = Gtk.Label()
        value.add_css_class("figure-small")
        pair.append(value)
        labels.append(value)
        box.append(pair)
    labels[0].set_text(down)
    labels[1].set_text(up)
    return box, labels[0], labels[1]


def rate_text(value: float) -> str:
    """A throughput, with a quiet link drawn as a dash rather than as 0 B/s."""
    return human_rate(value) if value >= 1 else "—"
