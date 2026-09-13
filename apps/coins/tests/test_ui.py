"""The window, driven by calling it rather than by tapping it.

The same approach the other apps here take: build the real widgets on a real
display and call the methods the buttons call. What is different in this app is
where the numbers come from -- a network -- so the window is handed a stand-in
for it, which is the whole reason `CoinsWindow` takes a source rather than
making one. No test here opens a socket.

Two things get particular attention, because they are the two that can lose
something a person did. A star has to be on disk before the tap is over, since
the next thing that happens to a phone app is usually being killed; and a
refresh that fails has to leave the prices that were already on screen alone.

Needs a display. Skipped where there is none, so `python3 -m unittest` on a
machine without GTK still runs the arithmetic and the file formats.
"""

from __future__ import annotations

import json
import os
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
    from moarchy_coins.window import CoinsWindow

from moarchy_coins.market import Coin, MarketError  # noqa: E402
from moarchy_coins.store import Store  # noqa: E402

# Every knob the screenshot harness turns. Cleared before each test, because a
# variable left set by the harness -- or by the test before -- would open the
# window on a page the test did not ask for.
KNOBS = ("PAGE", "SEARCH", "DIR", "OFFLINE", "QUIT_AFTER", "CURRENCY", "KEY")

MARKET = [
    ("bitcoin", "Bitcoin", "BTC", 77_000.0, 4.2, 1.53e12),
    ("ethereum", "Ethereum", "ETH", 2_500.0, -3.1, 3.01e11),
    ("monero", "Monero", "XMR", 235.0, 0.0, 4.3e9),
    ("dogecoin", "Dogecoin", "DOGE", 0.176, 11.0, 2.6e10),
]


def coins(market=MARKET):
    return [
        Coin(id=i, name=n, symbol=s, rank=rank, price=p, change=c, cap=cap)
        for rank, (i, n, s, p, c, cap) in enumerate(market, start=1)
    ]


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


class Fake:
    """What `market.Live` is, without the socket."""

    currency = "usd"

    def __init__(self, answer=None, *, trouble: MarketError | None = None) -> None:
        self.answer = coins() if answer is None else answer
        self.trouble = trouble
        self.asked = 0
        self.by_name: list[list[str]] = []

    def markets(self):
        self.asked += 1
        if self.trouble is not None:
            raise self.trouble
        return list(self.answer)

    def by_ids(self, ids):
        self.by_name.append(list(ids))
        return [
            Coin(
                id=i,
                name=i.title(),
                symbol=i[:3].upper(),
                rank=400,
                price=1.0,
                change=0.0,
                cap=1.0,
            )
            for i in ids
        ]


@unittest.skipIf(REASON, REASON)
class WindowBase(unittest.TestCase):
    def setUp(self):
        for knob in KNOBS:
            os.environ.pop(f"MOARCHY_COINS_{knob}", None)
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.store = Store(self.dir)

    def cached(self, *, age: float = 0.0, market=None):
        """Put prices in the store the way a previous run would have left them."""
        self.store.replace(
            coins() if market is None else market,
            fetched=time.time() - age,
            currency="usd",
        )
        return self.store

    def open(self, source=None) -> CoinsWindow:
        window = CoinsWindow(self.store, source)
        self.addCleanup(window.destroy)
        return window

    def rows(self, page):
        return [row.coin.id for row in page._rows if row.get_visible()]

    def row(self, page, coin_id: str):
        return next(r for r in page._rows if r.get_visible() and r.coin.id == coin_id)


class TheWindow(WindowBase):
    def test_it_opens_at_the_size_of_a_phone(self):
        window = self.open()
        self.assertEqual(window.get_default_size(), (360, 720))

    def test_it_opens_on_the_market_with_two_pages(self):
        window = self.open()
        self.assertEqual(window._stack.get_visible_child_name(), "market")
        self.assertEqual(len(list(window._stack.get_pages())), 2)

    def test_cached_prices_are_on_screen_before_anything_is_fetched(self):
        """The point of the cache: a train with no signal opens on prices."""
        self.cached()
        source = Fake()
        window = self.open(source)
        self.assertEqual(self.rows(window.market_page), [c.id for c in coins()])
        self.assertIn("Updated", window._title.get_subtitle())
        # On screen without having asked anybody anything.
        self.assertEqual(source.asked, 0)

    def test_a_row_says_the_rank_the_symbol_and_the_cap(self):
        self.cached()
        window = self.open()
        row = self.row(window.market_page, "bitcoin")
        self.assertEqual(row._badge.get_label(), "1")
        self.assertEqual(row._price.get_label(), "$77,000")
        self.assertEqual(row._note.get_label(), "BTC · $1.53 T")
        self.assertEqual(row._change.get_label(), "+4.20%")
        self.assertTrue(row._change.has_css_class("up"))

    def test_a_fall_is_drawn_as_a_fall_and_a_flat_day_as_neither(self):
        self.cached()
        window = self.open()
        self.assertTrue(
            self.row(window.market_page, "ethereum")._change.has_css_class("down")
        )
        self.assertTrue(
            self.row(window.market_page, "monero")._change.has_css_class("flat")
        )

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


class TheStar(WindowBase):
    def test_a_star_is_on_disk_before_the_tap_is_over(self):
        """The next thing that happens to a phone app is being killed."""
        self.cached()
        window = self.open()
        self.row(window.market_page, "monero")._star.set_active(True)
        written = json.loads((self.dir / "favourites.json").read_text())
        self.assertEqual(written["favourites"], ["monero"])

    def test_a_starred_coin_appears_on_the_other_page(self):
        self.cached()
        window = self.open()
        self.assertEqual(self.rows(window.starred_page), [])
        self.row(window.market_page, "monero")._star.set_active(True)
        pump(lambda: self.rows(window.starred_page) == ["monero"])
        self.assertEqual(self.rows(window.starred_page), ["monero"])

    def test_unstarring_takes_it_off_again(self):
        self.cached()
        window = self.open()
        self.row(window.market_page, "monero")._star.set_active(True)
        pump(lambda: self.rows(window.starred_page) == ["monero"])
        self.row(window.starred_page, "monero")._star.set_active(False)
        pump(lambda: self.rows(window.starred_page) == [])
        self.assertEqual(self.store.favourites, [])

    def test_the_starred_page_keeps_the_order_they_were_starred_in(self):
        self.cached()
        window = self.open()
        for identifier in ("dogecoin", "bitcoin", "monero"):
            self.row(window.market_page, identifier)._star.set_active(True)
            pump(seconds=0.05)
        self.assertEqual(
            self.rows(window.starred_page), ["dogecoin", "bitcoin", "monero"]
        )

    def test_refilling_a_row_does_not_read_as_somebody_tapping_it(self):
        """`fill` puts the button into the state the store already holds."""
        self.cached()
        window = self.open()
        self.row(window.market_page, "monero")._star.set_active(True)
        pump(seconds=0.05)
        window._refill()
        pump(seconds=0.05)
        self.assertEqual(self.store.favourites, ["monero"])


class TheSearch(WindowBase):
    def test_it_filters_both_pages(self):
        self.cached()
        window = self.open()
        self.row(window.market_page, "monero")._star.set_active(True)
        pump(seconds=0.05)
        window.set_query("bit")
        self.assertEqual(self.rows(window.market_page), ["bitcoin"])
        self.assertEqual(self.rows(window.starred_page), [])

    def test_closing_the_box_puts_the_whole_list_back(self):
        """A list filtered by something nobody can see any more."""
        self.cached()
        window = self.open()
        window._search_button.set_active(True)
        window._entry.set_text("bit")
        window.set_query("bit")
        window._search_button.set_active(False)
        pump(seconds=0.05)
        self.assertEqual(window._query, "")
        self.assertEqual(len(self.rows(window.market_page)), len(coins()))

    def test_the_harness_can_open_the_box_without_filtering_anything(self):
        """MOARCHY_COINS_SEARCH= is what text-input-check.sh needs."""
        self.cached()
        os.environ["MOARCHY_COINS_SEARCH"] = ""
        window = self.open()
        self.assertTrue(window._search_button.get_active())
        self.assertEqual(len(self.rows(window.market_page)), len(coins()))


class TheFetch(WindowBase):
    def test_a_good_answer_replaces_the_prices_and_says_when(self):
        source = Fake()
        window = self.open(source)
        window._fetch(manual=True)
        pump(lambda: not window._fetching)
        self.assertEqual(self.rows(window.market_page), [c.id for c in coins()])
        self.assertEqual(window._title.get_subtitle(), "Updated just now")

    def test_a_failed_refresh_leaves_the_prices_that_were_there(self):
        """Four-minute-old prices are worth something; a blank page is not."""
        self.cached(age=300)
        window = self.open(Fake(trouble=MarketError("No answer from CoinGecko.")))
        window._fetch(manual=True)
        pump(lambda: not window._fetching)
        self.assertEqual(self.rows(window.market_page), [c.id for c in coins()])
        self.assertIn("5 min ago", window._title.get_subtitle())
        self.assertIn("Not updating", window._title.get_subtitle())

    def test_a_failure_backs_off_rather_than_asking_again_every_minute(self):
        source = Fake(trouble=MarketError("No answer from CoinGecko."))
        window = self.open(source)
        window._fetch(manual=True)
        pump(lambda: not window._fetching)
        self.assertEqual(window._failures, 1)
        self.assertFalse(window._due())

    def test_a_rate_limit_is_waited_out_for_as_long_as_it_asked(self):
        source = Fake(trouble=MarketError("rate-limited", retry_after=90.0))
        window = self.open(source)
        window._fetch(manual=True)
        pump(lambda: not window._fetching)
        self.assertGreater(window._retry_at - time.monotonic(), 80.0)

    def test_a_starred_coin_that_fell_out_of_the_list_is_asked_for_by_name(self):
        """The one case where the top hundred cannot answer for a watchlist."""
        source = Fake()
        self.store.favourites = ["some-small-coin"]
        window = self.open(source)
        window._fetch(manual=True)
        pump(lambda: not window._fetching)
        self.assertEqual(source.by_name, [["some-small-coin"]])
        self.assertEqual(self.rows(window.starred_page), ["some-small-coin"])

    def test_fresh_prices_are_not_fetched_again(self):
        """Which is also why a check run never touches the network."""
        source = Fake()
        self.cached(age=1)
        window = self.open(source)
        window.start()
        pump(seconds=0.1)
        window.stop()
        self.assertEqual(source.asked, 0)

    def test_stale_prices_are(self):
        source = Fake()
        self.cached(age=600)
        window = self.open(source)
        window.start()
        pump(lambda: source.asked > 0)
        window.stop()
        self.assertEqual(source.asked, 1)

    def test_an_answer_from_an_abandoned_request_is_dropped(self):
        source = Fake()
        window = self.open(source)
        window._fetching = True
        window._arrived(coins(), "", 0.0, -1, False)
        self.assertEqual(self.rows(window.market_page), [])


class TheCache(WindowBase):
    def test_prices_are_written_when_the_window_leaves_the_screen(self):
        """Not on every refresh: that is eighty kilobytes a minute onto flash."""
        window = self.open(Fake())
        window._fetch(manual=True)
        pump(lambda: not window._fetching)
        self.assertFalse((self.dir / "market.json").exists())
        window.stop()
        self.assertTrue((self.dir / "market.json").exists())

    def test_a_second_save_does_not_rewrite_a_file_nothing_changed_in(self):
        window = self.open(Fake())
        window._fetch(manual=True)
        pump(lambda: not window._fetching)
        window.save()
        stamp = (self.dir / "market.json").stat().st_mtime_ns
        window.save()
        self.assertEqual((self.dir / "market.json").stat().st_mtime_ns, stamp)


if __name__ == "__main__":
    unittest.main()
