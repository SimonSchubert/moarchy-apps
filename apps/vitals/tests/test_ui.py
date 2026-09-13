"""The window, driven by calling it rather than by tapping it.

The same approach the other apps here take: build the real widgets on a real
display and call the methods the buttons call. What is different in this app is
what the widgets are looking at -- a directory of files instead of a phone -- so
these tests can assert on the *numbers on screen*, which is usually the part a
UI test has to give up on.

Two things get particular attention, because they are the two that can do
damage. Ending a task must ask first and must send the signal the button says it
sends; and a fixture must never signal anything at all, which is what makes the
demo data safe to run in a container whose pid 1 is the thing being developed in.

Needs a display. Skipped where there is none, so `python3 -m unittest` on a
machine without GTK still runs the arithmetic and the file formats.
"""

from __future__ import annotations

import os
import signal
import sys
import time
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent), str(HERE.parent.parent.parent / "shared")]

REASON = ""
try:
    import gi

    gi.require_version("Gtk", "4.0")
    gi.require_version("Adw", "1")
    from gi.repository import Adw, GLib, Gtk

    if not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        REASON = "no display"
    elif not Gtk.init_check():
        REASON = "GTK could not open the display"
except (ImportError, ValueError) as exc:  # pragma: no cover - depends on the host
    REASON = f"no GTK: {exc}"

if not REASON:
    Adw.init()
    settings = Gtk.Settings.get_default()
    if settings is not None:
        settings.props.gtk_enable_animations = False
    # Inside the guard: every one of these imports gi, so on a machine with no
    # GTK the import itself is the failure rather than the skip.
    from moarchy_vitals.detail import AppPage, ProcessPage
    from moarchy_vitals.widgets import Cores, Graph, nice_ceiling
    from moarchy_vitals.window import VitalsWindow

from fixtures import put, write_machine, write_reel  # noqa: E402
from moarchy_vitals import theme  # noqa: E402
from moarchy_vitals.sysinfo import Reel, Sampler, Sysroot  # noqa: E402

# Every knob the screenshot harness turns. Cleared before each test, because a
# variable left set by the harness -- or by the test before -- would open the
# window on a page the test did not ask for.
KNOBS = ("PAGE", "TASKS", "SORT", "SEARCH", "PICK", "DIR", "QUIT_AFTER")


def pump(until=None, seconds: float = 4.0) -> bool:
    """Run the main loop until something has happened, or give up."""
    context = GLib.MainContext.default()
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        while context.pending():
            context.iteration(False)
        if until is None or until():
            return True
        time.sleep(0.01)
    return until is None or until()


@unittest.skipIf(REASON, REASON)
class TheGraphArithmetic(unittest.TestCase):
    """Where a graph scales to is a function rather than a widget.

    Skipped without GTK all the same: it lives in widgets.py, which imports gi
    at the top like every other module that draws.
    """

    def test_a_graph_scales_to_a_round_number_above_its_peak(self):
        # One, two or five times a power of ten: a scale that moves with the
        # peak is a graph that is always full and never comparable.
        self.assertEqual(nice_ceiling(0.4), 0.5)
        self.assertEqual(nice_ceiling(1.1), 2.0)
        self.assertEqual(nice_ceiling(3.0), 5.0)
        self.assertEqual(nice_ceiling(6.0), 10.0)
        self.assertEqual(nice_ceiling(1_300_000), 2_000_000)

    def test_an_empty_graph_still_has_a_scale(self):
        self.assertEqual(nice_ceiling(0), 1.0)


@unittest.skipIf(REASON, REASON)
class WindowBase(unittest.TestCase):
    frames = 12

    def setUp(self):
        for knob in KNOBS:
            os.environ.pop(f"MOARCHY_VITALS_{knob}", None)
        self.dir = TemporaryDirectory()
        self.root = Path(self.dir.name)
        write_reel(self.root, frames=self.frames)
        self.reel = Reel(self.root)

    def tearDown(self):
        pump(seconds=0.05)
        self.dir.cleanup()

    def open(self) -> VitalsWindow:
        self.window = VitalsWindow(Sampler(self.reel))
        self.addCleanup(self.window.destroy)
        return self.window

    def tasks(self, window: VitalsWindow):
        window._stack.set_visible_child_name("tasks")
        pump(seconds=0.05)
        return window.tasks

    def rows(self, window: VitalsWindow) -> list:
        return [row.payload for row in window.tasks._list._pool if row.get_visible()]


class TheWindow(WindowBase):
    def test_it_opens_at_the_size_of_a_phone(self):
        window = self.open()
        self.assertEqual(window.get_default_size(), (360, 720))

    def test_it_opens_on_the_overview_with_three_pages(self):
        window = self.open()
        self.assertEqual(window._stack.get_visible_child_name(), "overview")
        names = [page.get_name() for page in window._stack.get_pages()]
        self.assertEqual(len(names), 3)

    def test_a_reel_fills_the_graphs_before_anything_is_drawn(self):
        # Without this a screenshot two seconds after launch is one sample: a
        # flat line against the left edge, which says nothing about the app.
        window = self.open()
        self.assertGreater(len(window.history["cpu"].as_tuple()), 1)
        self.assertEqual(self.reel.remaining, 6)

    def test_the_headline_figures_are_in_the_title_on_every_page(self):
        window = self.open()
        self.assertIn("CPU", window._title.get_subtitle())
        self.assertIn("RAM", window._title.get_subtitle())

    def test_the_clock_runs_only_while_the_window_is_on_screen(self):
        window = self.open()
        self.assertEqual(window._source, 0)
        window.start()
        self.assertNotEqual(window._source, 0)
        window.stop()
        self.assertEqual(window._source, 0)

    def test_starting_twice_does_not_leave_two_timers(self):
        window = self.open()
        window.start()
        first = window._source
        window.start()
        self.assertEqual(window._source, first)
        window.stop()

    def test_a_theme_change_repaints_without_rebuilding_anything(self):
        window = self.open()
        self.tasks(window)
        rows = self.rows(window)
        window.set_palette(theme.fallback(dark=False))
        pump(seconds=0.05)
        self.assertEqual(self.rows(window), rows)

    def test_the_search_button_is_only_on_the_page_that_has_a_list(self):
        window = self.open()
        self.assertFalse(window._search_button.get_visible())
        self.tasks(window)
        self.assertTrue(window._search_button.get_visible())


class TheOverview(WindowBase):
    def test_it_shows_the_memory_the_fixture_has(self):
        window = self.open()
        # 1,000,000 kB total with 400,000 kB available: 600,000 kB used.
        self.assertIn("614 MB", window.overview._memory_meter._value.get_text())
        self.assertIn("1.0 GB", window.overview._memory_meter._value.get_text())

    def test_it_shows_one_bar_per_core(self):
        window = self.open()
        labels = window.overview._cores._labels
        self.assertEqual(len([1 for _ in iter_children(labels)]), 2)

    def test_the_load_average_and_the_uptime_are_on_it(self):
        window = self.open()
        facts = window.overview._cpu_facts
        self.assertEqual(facts._values["load"].get_text(), "0.50 0.40 0.30")
        self.assertTrue(facts._values["uptime"].get_text())

    def test_heat_is_coloured_rather_than_only_printed(self):
        window = self.open()
        value = window.overview._cpu_facts._values["temp"]
        # The fixture's 47,500 millidegrees, which is warm for a desk and
        # unremarkable for a phone.
        self.assertEqual(value.get_text(), "48 °C")
        self.assertFalse(value.has_css_class("hot"))
        self.assertFalse(value.has_css_class("warm"))

    def test_every_mounted_filesystem_gets_a_bar(self):
        window = self.open()
        self.assertEqual(set(window.overview._disk_meters), {"/", "/media/SD card"})

    def test_a_machine_with_no_battery_has_no_battery_panel(self):
        bare = Path(self.dir.name) / "bare"
        write_machine(bare, battery=None)
        window = VitalsWindow(Sampler(Sysroot(bare)))
        self.addCleanup(window.destroy)
        window._tick()
        self.assertFalse(window.overview._battery_panel_widget.get_visible())

    def test_a_machine_with_one_shows_its_charge(self):
        window = self.open()
        self.assertIn("80%", window.overview._battery_meter._value.get_text())


class TheTaskList(WindowBase):
    def test_apps_group_the_processes_that_belong_to_one(self):
        window = self.open()
        self.tasks(window)
        names = [item.name for item in self.rows(window)]
        self.assertIn("firefox", names)
        firefox = next(item for item in self.rows(window) if item.name == "firefox")
        self.assertEqual(firefox.count, 2)

    def test_every_process_is_one_tap_away(self):
        window = self.open()
        page = self.tasks(window)
        page.set_mode("all")
        pump(seconds=0.05)
        names = {item.name for item in self.rows(window)}
        self.assertEqual(names, {"systemd", "firefox", "Isolated Web Co"})

    def test_the_list_says_how_many_there_are(self):
        window = self.open()
        page = self.tasks(window)
        page.set_mode("all")
        pump(seconds=0.05)
        self.assertEqual(page._count.get_text(), "3 processes")

    def test_searching_narrows_it(self):
        window = self.open()
        page = self.tasks(window)
        page.set_mode("all")
        page.set_query("web")
        # GtkSearchEntry holds its signal back for a moment, which is what stops
        # a phone filtering two hundred processes on every keystroke.
        pump(lambda: page.query == "web")
        self.assertEqual([item.name for item in self.rows(window)], ["Isolated Web Co"])

    def test_a_search_that_matches_nothing_says_so(self):
        window = self.open()
        page = self.tasks(window)
        page.set_query("nothing here")
        pump(lambda: page._stack.get_visible_child_name() == "empty")
        self.assertEqual(page._stack.get_visible_child_name(), "empty")

    def test_sorting_by_memory_puts_the_biggest_first(self):
        window = self.open()
        page = self.tasks(window)
        page.set_mode("all")
        page.set_sort("memory")
        pump(seconds=0.05)
        self.assertEqual(self.rows(window)[0].name, "firefox")

    def test_sorting_by_name_is_alphabetical(self):
        window = self.open()
        page = self.tasks(window)
        page.set_mode("all")
        page.set_sort("name")
        pump(seconds=0.05)
        names = [item.name for item in self.rows(window)]
        self.assertEqual(names, sorted(names, key=str.lower))

    def test_the_rows_are_reused_rather_than_rebuilt(self):
        # A list that rebuilt its rows every two seconds would throw away the
        # row under a thumb mid-scroll.
        window = self.open()
        page = self.tasks(window)
        page.set_mode("all")
        pump(seconds=0.05)
        before = list(page._list._pool)
        window._tick()
        self.assertEqual(list(page._list._pool), before)

    def test_the_overview_does_not_pay_for_the_task_list(self):
        # Walking /proc is a few hundred file reads, and the overview needs
        # none of them.
        window = self.open()
        self.assertEqual(window.sample.processes, ())
        self.tasks(window)
        self.assertTrue(window.sample.processes)


class TheNetworkPage(WindowBase):
    def test_an_interface_that_is_up_gets_a_graph(self):
        window = self.open()
        window._stack.set_visible_child_name("network")
        pump(seconds=0.05)
        widgets = window.network._panels["wlan0"]
        self.assertTrue(widgets["graph"].get_visible())
        self.assertTrue(widgets["totals"].get_visible())

    def test_an_interface_that_is_down_and_silent_gets_its_name_only(self):
        # The phone's modem. A full panel of dashes, an empty graph and two
        # zeroes is most of a screen saying "no".
        quiet = Path(self.dir.name) / "quiet"
        write_machine(quiet, net={"wwan0": (0, 0)}, wireless=False)
        put(quiet, "sys/class/net/wwan0/operstate", "down\n")
        window = VitalsWindow(Sampler(Sysroot(quiet)))
        self.addCleanup(window.destroy)
        window._stack.set_visible_child_name("network")
        window._tick()
        pump(seconds=0.05)
        widgets = window.network._panels["wwan0"]
        self.assertTrue(widgets["panel"].get_visible())
        self.assertFalse(widgets["graph"].get_visible())
        self.assertFalse(widgets["rates"].get_visible())
        self.assertEqual(widgets["state"].get_text(), "down")


class OneTask(WindowBase):
    def open_firefox(self) -> ProcessPage:
        window = self.open()
        self.tasks(window)
        window.open_process(420)
        pump(seconds=0.05)
        return window._detail

    def test_tapping_a_process_opens_what_it_is(self):
        page = self.open_firefox()
        self.assertIsInstance(page, ProcessPage)
        self.assertEqual(page.get_title(), "firefox")
        self.assertIn("420", page._rows["pid"].get_text())
        self.assertEqual(page._rows["user"].get_text(), "simon")
        self.assertIn("firefox", page._command.get_text())

    def test_it_says_which_app_the_process_belongs_to(self):
        page = self.open_firefox()
        self.assertEqual(page._rows["app"].get_text(), "firefox")

    def test_tapping_an_app_opens_the_processes_in_it(self):
        window = self.open()
        self.tasks(window)
        window.open_app("unit:firefox")
        pump(seconds=0.05)
        page = window._detail
        self.assertIsInstance(page, AppPage)
        self.assertEqual([item.pid for item in self.app_rows(page)], [420, 421])

    def test_a_process_that_has_gone_says_so_rather_than_vanishing(self):
        window = self.open()
        self.tasks(window)
        window.open_process(999_999)
        pump(seconds=0.05)
        page = window._detail
        self.assertEqual(page._rows["state"].get_text(), "no longer running")
        self.assertFalse(page._buttons.get_sensitive())

    def app_rows(self, page: AppPage) -> list:
        return [row.payload for row in page._list._pool if row.get_visible()]


class EndingATask(WindowBase):
    def test_the_button_asks_before_it_signals_anything(self):
        window = self.open()
        self.tasks(window)
        window.open_process(420)
        pump(seconds=0.05)
        window._detail._on_end()
        pump(seconds=0.1)
        self.assertEqual(self.reel.signalled, [])

    def test_ending_sends_term_and_forcing_sends_kill(self):
        window = self.open()
        self.tasks(window)
        window.end("firefox", (420,), force=False)
        window.end("firefox", (420,), force=True)
        self.assertEqual(
            self.reel.signalled, [(420, signal.SIGTERM), (420, signal.SIGKILL)]
        )

    def test_answering_the_question_is_what_signals(self):
        window = self.open()
        self.tasks(window)
        window._on_confirm(None, "end", "firefox", (420,), False)
        self.assertEqual(self.reel.signalled, [(420, signal.SIGTERM)])

    def test_saying_no_signals_nothing(self):
        window = self.open()
        self.tasks(window)
        window._on_confirm(None, "cancel", "firefox", (420,), False)
        self.assertEqual(self.reel.signalled, [])

    def test_ending_an_app_ends_every_process_in_it(self):
        window = self.open()
        self.tasks(window)
        window.open_app("unit:firefox")
        pump(seconds=0.05)
        window.end("firefox", window._detail.group.pids, force=False)
        self.assertEqual(
            self.reel.signalled, [(420, signal.SIGTERM), (421, signal.SIGTERM)]
        )


class StartingSomewhereElse(WindowBase):
    """The environment variables the screenshot harness drives the app with."""

    def test_it_can_open_on_the_task_list(self):
        os.environ["MOARCHY_VITALS_PAGE"] = "tasks"
        window = self.open()
        self.assertEqual(window._stack.get_visible_child_name(), "tasks")

    def test_it_can_open_showing_every_process(self):
        os.environ["MOARCHY_VITALS_PAGE"] = "tasks"
        os.environ["MOARCHY_VITALS_TASKS"] = "all"
        window = self.open()
        pump(seconds=0.05)
        self.assertEqual(len(self.rows(window)), 3)

    def test_it_can_open_on_one_process(self):
        os.environ["MOARCHY_VITALS_PICK"] = "421"
        window = self.open()
        pump(seconds=0.05)
        self.assertIsInstance(window._detail, ProcessPage)
        self.assertEqual(window._detail.pid, 421)

    def test_it_can_open_on_one_app_by_name(self):
        os.environ["MOARCHY_VITALS_PICK"] = "firefox"
        window = self.open()
        pump(seconds=0.05)
        self.assertIsInstance(window._detail, AppPage)

    def test_it_can_open_with_the_search_showing(self):
        # Which is also the probe scripts/text-input-check.sh uses: this is the
        # only text field in the app, so it is the one that has to raise the
        # phone's keyboard.
        os.environ["MOARCHY_VITALS_PAGE"] = "tasks"
        os.environ["MOARCHY_VITALS_SEARCH"] = ""
        window = self.open()
        self.assertTrue(window.tasks._search.get_search_mode())

    def test_a_page_that_does_not_exist_is_ignored(self):
        os.environ["MOARCHY_VITALS_PAGE"] = "nonsense"
        window = self.open()
        self.assertEqual(window._stack.get_visible_child_name(), "overview")


@unittest.skipIf(REASON, REASON)
class TheDrawnHalf(unittest.TestCase):
    """The graphs and the core bars actually draw.

    A draw function that raises is not a crash: GTK catches it, logs one line
    and leaves an empty rectangle on screen. So these call it with a real cairo
    context and look at what came out, which is the only way the failure is
    visible from a test.
    """

    def surface(self, width: int, height: int):
        import cairo

        surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, width, height)
        return surface, cairo.Context(surface)

    def painted(self, surface) -> bool:
        surface.flush()
        return any(surface.get_data())

    def test_a_graph_with_history_draws_something(self):
        graph = Graph(("cpu",))
        graph.set_palette(theme.fallback(dark=True))
        graph.refresh(tuple(0.1 * n for n in range(10)))
        surface, cr = self.surface(300, 62)
        graph._draw(graph, cr, 300, 62)
        self.assertTrue(self.painted(surface))

    def test_an_empty_graph_draws_its_baseline_and_no_more(self):
        graph = Graph(("cpu",))
        graph.set_palette(theme.fallback(dark=True))
        graph.refresh(())
        surface, cr = self.surface(300, 62)
        graph._draw(graph, cr, 300, 62)
        self.assertTrue(self.painted(surface))

    def test_a_mirrored_graph_takes_two_series(self):
        graph = Graph(("rx", "tx"), mirror=True, scale=None)
        graph.set_palette(theme.fallback(dark=True))
        graph.refresh((1000.0, 2000.0, 1500.0), (100.0, 200.0, 150.0))
        self.assertEqual(graph.scale, 2000.0)
        surface, cr = self.surface(300, 56)
        graph._draw(graph, cr, 300, 56)
        self.assertTrue(self.painted(surface))

    def test_the_core_bars_draw_one_bar_per_core(self):
        cores = Cores()
        cores.set_palette(theme.fallback(dark=True))
        cores.refresh((0.1, 0.5, 0.9, 1.0))
        surface, cr = self.surface(300, 42)
        cores._draw(cores, cr, 300, 42)
        self.assertTrue(self.painted(surface))
        self.assertEqual(len([1 for _ in iter_children(cores._labels)]), 4)

    def test_no_cores_is_not_a_crash(self):
        cores = Cores()
        surface, cr = self.surface(300, 42)
        cores._draw(cores, cr, 300, 42)
        self.assertFalse(self.painted(surface))


def iter_children(widget):
    child = widget.get_first_child()
    while child is not None:
        yield child
        child = child.get_next_sibling()


if __name__ == "__main__":
    unittest.main()
