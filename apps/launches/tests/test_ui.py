"""The window, driven by calling it rather than by tapping it.

The same approach the other apps here take: build the real widgets on a real
display and call the methods the buttons call. What is different in this app
is where the numbers come from -- a network -- so the window is handed a
stand-in for it. No test here opens a socket.

Two things get particular attention, because they are the two that can lose
something a person did. A star has to be on disk before the tap is over, since
the next thing that happens to a phone app is usually being killed; and a
refresh that fails has to leave the launches that were already on screen alone.

Needs a display. Skipped where there is none, so `python3 -m unittest` on a
machine without GTK still runs the arithmetic and the file formats.
"""

from __future__ import annotations

import json
import os
import sys
import time
import unittest
from datetime import datetime, timezone
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
    from moarchy_launches.window import LaunchesWindow

from moarchy_launches.launches import (  # noqa: E402
    STATUS_GO,
    STATUS_SUCCESS,
    Launch,
    LaunchError,
)
from moarchy_launches.store import Store  # noqa: E402

KNOBS = ("PAGE", "SEARCH", "DIR", "OFFLINE", "QUIT_AFTER", "KEY", "NOW", "OPEN")

NOW = datetime(2026, 9, 14, 18, 0, 0, tzinfo=timezone.utc)


def item(
    identifier="vega-sentinel",
    name="Sentinel-3C & FLEX",
    vehicle="Vega-C",
    agency="Arianespace",
    status_id=STATUS_GO,
    status="Go",
    net=None,
    **extra,
) -> Launch:
    return Launch(
        id=identifier,
        name=name,
        vehicle=vehicle,
        agency=agency,
        status_id=status_id,
        status=status,
        net=net or datetime(2026, 9, 15, 1, 21, 7, tzinfo=timezone.utc),
        precision=extra.get("precision", "SEC"),
        window_start=extra.get("window_start"),
        window_end=extra.get("window_end"),
        pad=extra.get("pad", "Ensemble de Lancement Vega"),
        location=extra.get("location", "Guiana Space Centre, French Guiana"),
        orbit=extra.get("orbit", "SSO"),
        mission_type=extra.get("mission_type", "Earth Science"),
        probability=extra.get("probability", 75),
        weather=extra.get("weather", ""),
        hold=extra.get("hold", ""),
        description=extra.get("description", "Copernicus satellites."),
    )


MARKET = [
    item(),
    item(
        "falcon-o3b",
        "O3b mPower 11-13",
        "Falcon 9 Block 5",
        "SpaceX",
        STATUS_SUCCESS,
        "Success",
        datetime(2026, 9, 13, 18, 49, 0, tzinfo=timezone.utc),
        pad="Space Launch Complex 40",
        location="Cape Canaveral SFS, FL, USA",
        description="Communications satellites.",
    ),
    item(
        "electron-capella",
        "Capella 17",
        "Electron",
        "Rocket Lab",
        net=datetime(2026, 9, 16, 18, 0, 0, tzinfo=timezone.utc),
        location="Mahia Peninsula, New Zealand",
    ),
]


def pump(until=None, seconds: float = 4.0) -> bool:
    context = GLib.MainContext.default()
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        while context.pending():
            context.iteration(False)
        if until is None or until():
            return True
        time.sleep(0.01)
    return until is None or until()


class Fake:
    """What `launches.Live` is, without the socket."""

    def __init__(self, answer=None, *, trouble: LaunchError | None = None) -> None:
        self.answer = list(MARKET) if answer is None else answer
        self.trouble = trouble
        self.asked = 0

    def upcoming(self):
        self.asked += 1
        if self.trouble is not None:
            raise self.trouble
        return list(self.answer)


@unittest.skipIf(REASON, REASON)
class WindowBase(unittest.TestCase):
    def setUp(self):
        for knob in KNOBS:
            os.environ.pop(f"MOARCHY_LAUNCHES_{knob}", None)
        os.environ["MOARCHY_LAUNCHES_NOW"] = "2026-09-14T18:00:00Z"
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.store = Store(self.dir)

    def cached(self, *, age: float = 0.0, market=None):
        self.store.replace(
            list(MARKET) if market is None else market,
            fetched=time.time() - age,
        )
        return self.store

    def open(self, source=None) -> LaunchesWindow:
        window = LaunchesWindow(self.store, source)
        self.addCleanup(window.destroy)
        return window

    def rows(self, page):
        return [row.launch.id for row in page._rows if row.get_visible() and row.launch]

    def row(self, page, launch_id: str):
        return next(
            r
            for r in page._rows
            if r.get_visible() and r.launch and r.launch.id == launch_id
        )


class TheWindow(WindowBase):
    def test_it_opens_at_the_size_of_a_phone(self):
        window = self.open()
        self.assertEqual(window.get_default_size(), (360, 720))

    def test_it_opens_on_upcoming_with_two_pages(self):
        window = self.open()
        self.assertEqual(window._stack.get_visible_child_name(), "upcoming")
        self.assertEqual(len(list(window._stack.get_pages())), 2)

    def test_cached_launches_are_on_screen_before_anything_is_fetched(self):
        self.cached()
        source = Fake()
        window = self.open(source)
        self.assertEqual(self.rows(window.upcoming_page), [c.id for c in MARKET])
        self.assertIn("Updated", window._title.get_subtitle())
        self.assertEqual(source.asked, 0)

    def test_a_row_says_the_status_the_vehicle_and_the_countdown(self):
        self.cached()
        window = self.open()
        row = self.row(window.upcoming_page, "vega-sentinel")
        self.assertEqual(row._badge.get_label(), "GO")
        self.assertEqual(row._name.get_label(), "Sentinel-3C & FLEX")
        self.assertIn("Vega-C", row._note.get_label())
        self.assertTrue(row._when.get_label().startswith("T-"))

    def test_the_clock_runs_only_while_the_window_is_on_screen(self):
        window = self.open()
        self.assertEqual(window._source_id, 0)
        window.start()
        self.assertNotEqual(window._source_id, 0)
        window.stop()
        self.assertEqual(window._source_id, 0)

    def test_starting_twice_does_not_leave_two_timers(self):
        window = self.open()
        window.start()
        first = window._source_id
        window.start()
        self.assertEqual(window._source_id, first)
        window.stop()

    def test_an_offline_run_never_asks_for_a_refresh_it_cannot_do(self):
        self.cached()
        window = self.open(source=None)
        self.assertFalse(window._refresh_button.get_visible())
        window.start()
        self.assertIn("Offline", window._title.get_subtitle())
        window.stop()

    def test_the_only_entry_is_the_search_bar(self):
        window = self.open()
        found = []

        def walk(widget):
            if isinstance(widget, Gtk.Entry) and widget is not window._entry:
                found.append(widget)
            child = (
                widget.get_first_child() if hasattr(widget, "get_first_child") else None
            )
            while child is not None:
                walk(child)
                child = child.get_next_sibling()

        walk(window)
        self.assertEqual(found, [])


class TheStar(WindowBase):
    def test_a_star_is_on_disk_before_the_tap_is_over(self):
        self.cached()
        window = self.open()
        self.row(window.upcoming_page, "vega-sentinel")._star.set_active(True)
        written = json.loads((self.dir / "favourites.json").read_text())
        self.assertEqual(written["favourites"], ["vega-sentinel"])

    def test_a_starred_launch_appears_on_the_other_page(self):
        self.cached()
        window = self.open()
        self.assertEqual(self.rows(window.starred_page), [])
        self.row(window.upcoming_page, "vega-sentinel")._star.set_active(True)
        pump(lambda: self.rows(window.starred_page) == ["vega-sentinel"])
        self.assertEqual(self.rows(window.starred_page), ["vega-sentinel"])

    def test_unstarring_takes_it_off_again(self):
        self.cached()
        window = self.open()
        self.row(window.upcoming_page, "vega-sentinel")._star.set_active(True)
        pump(lambda: self.rows(window.starred_page) == ["vega-sentinel"])
        self.row(window.starred_page, "vega-sentinel")._star.set_active(False)
        pump(lambda: self.rows(window.starred_page) == [])
        self.assertEqual(self.store.favourites, [])

    def test_the_starred_page_keeps_the_order_they_were_starred_in(self):
        self.cached()
        window = self.open()
        for identifier in ("electron-capella", "falcon-o3b", "vega-sentinel"):
            self.row(window.upcoming_page, identifier)._star.set_active(True)
            pump(seconds=0.05)
        self.assertEqual(
            self.rows(window.starred_page),
            ["electron-capella", "falcon-o3b", "vega-sentinel"],
        )


class TheSearch(WindowBase):
    def test_it_filters_both_pages(self):
        self.cached()
        window = self.open()
        self.row(window.upcoming_page, "vega-sentinel")._star.set_active(True)
        pump(seconds=0.05)
        window.set_query("falcon")
        self.assertEqual(self.rows(window.upcoming_page), ["falcon-o3b"])
        self.assertEqual(self.rows(window.starred_page), [])

    def test_closing_the_box_puts_the_whole_list_back(self):
        self.cached()
        window = self.open()
        window._search_button.set_active(True)
        window._entry.set_text("falcon")
        window.set_query("falcon")
        window._search_button.set_active(False)
        pump(seconds=0.05)
        self.assertEqual(window._query, "")
        self.assertEqual(len(self.rows(window.upcoming_page)), len(MARKET))

    def test_the_harness_can_open_the_box_without_filtering_anything(self):
        self.cached()
        os.environ["MOARCHY_LAUNCHES_SEARCH"] = ""
        window = self.open()
        self.assertTrue(window._search_button.get_active())
        self.assertEqual(len(self.rows(window.upcoming_page)), len(MARKET))


class TheFetch(WindowBase):
    def test_a_good_answer_replaces_the_list_and_says_when(self):
        source = Fake()
        window = self.open(source)
        window._fetch(manual=True)
        pump(lambda: not window._fetching)
        self.assertEqual(self.rows(window.upcoming_page), [c.id for c in MARKET])
        self.assertEqual(window._title.get_subtitle(), "Updated just now")

    def test_a_failed_refresh_leaves_the_launches_that_were_there(self):
        self.cached(age=300)
        window = self.open(Fake(trouble=LaunchError("No answer from Launch Library.")))
        window._fetch(manual=True)
        pump(lambda: not window._fetching)
        self.assertEqual(self.rows(window.upcoming_page), [c.id for c in MARKET])
        self.assertIn("5 min ago", window._title.get_subtitle())
        self.assertIn("Not updating", window._title.get_subtitle())

    def test_a_failure_backs_off_rather_than_asking_again_every_minute(self):
        source = Fake(trouble=LaunchError("No answer from Launch Library."))
        window = self.open(source)
        window._fetch(manual=True)
        pump(lambda: not window._fetching)
        self.assertEqual(window._failures, 1)
        self.assertFalse(window._due())

    def test_a_rate_limit_is_waited_out_for_as_long_as_it_asked(self):
        source = Fake(trouble=LaunchError("rate-limited", retry_after=90.0))
        window = self.open(source)
        window._fetch(manual=True)
        pump(lambda: not window._fetching)
        self.assertGreater(window._retry_at - time.monotonic(), 80.0)

    def test_fresh_launches_are_not_fetched_again(self):
        source = Fake()
        self.cached(age=1)
        window = self.open(source)
        window.start()
        pump(seconds=0.1)
        window.stop()
        self.assertEqual(source.asked, 0)

    def test_stale_launches_are(self):
        source = Fake()
        self.cached(age=20 * 60)
        window = self.open(source)
        window.start()
        pump(lambda: source.asked > 0)
        window.stop()
        self.assertEqual(source.asked, 1)

    def test_an_answer_from_an_abandoned_request_is_dropped(self):
        source = Fake()
        window = self.open(source)
        window._fetching = True
        window._arrived(list(MARKET), "", 0.0, -1, False)
        self.assertEqual(self.rows(window.upcoming_page), [])


class TheCache(WindowBase):
    def test_launches_are_written_when_the_window_leaves_the_screen(self):
        window = self.open(Fake())
        window._fetch(manual=True)
        pump(lambda: not window._fetching)
        self.assertFalse((self.dir / "upcoming.json").exists())
        window.stop()
        self.assertTrue((self.dir / "upcoming.json").exists())

    def test_a_second_save_does_not_rewrite_a_file_nothing_changed_in(self):
        window = self.open(Fake())
        window._fetch(manual=True)
        pump(lambda: not window._fetching)
        window.save()
        stamp = (self.dir / "upcoming.json").stat().st_mtime_ns
        window.save()
        self.assertEqual((self.dir / "upcoming.json").stat().st_mtime_ns, stamp)


class TheDetail(WindowBase):
    def test_the_harness_can_open_a_launch(self):
        self.cached()
        os.environ["MOARCHY_LAUNCHES_PAGE"] = "detail"
        os.environ["MOARCHY_LAUNCHES_OPEN"] = "vega-sentinel"
        window = self.open()
        pump(lambda: window._open_id == "vega-sentinel")
        self.assertEqual(window._open_id, "vega-sentinel")
        self.assertIsNotNone(window._detail_view)
        self.assertEqual(window._detail_view.launch.id, "vega-sentinel")
        self.assertIn("Copernicus", window._detail_view._body.get_label())

    def test_popping_detail_clears_it(self):
        self.cached()
        window = self.open()
        window._open_launch("vega-sentinel")
        self.assertEqual(window._open_id, "vega-sentinel")
        window._nav.pop()
        pump(lambda: window._open_id == "")
        self.assertEqual(window._open_id, "")
        self.assertIsNone(window._detail_view)


if __name__ == "__main__":
    unittest.main()
