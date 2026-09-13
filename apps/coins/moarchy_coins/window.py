"""The window: a hundred coins, the few somebody starred, and one clock.

Two pages behind a switcher at the *bottom*, where a thumb is -- the same
arrangement Vitals has, for the same reason. The market is the list everybody
means by "top coins"; the starred page is the one the app is actually for, and
it is a tab rather than a section pinned above the market because a watchlist
you have to scroll past a hundred rows to reach is not a watchlist.

**The network is on a thread and nothing waits for it.** A fetch is twelve
seconds at worst on a phone's radio, which is twelve seconds of a frozen window
if it happens on the main loop. So it happens the way every other slow thing in
this repo does -- a daemon thread, a generation counter, and one
`GLib.idle_add` back -- and the window carries on drawing whatever it last had.

**The clock stops when the window leaves the screen.** An app that keeps pulling
prices every minute after the phone is in a pocket is a battery bug and a data
bill wearing a feature's clothes, and on a phone the app is not closed, it is
hidden, so this is the ordinary case. That is also the moment the cached prices
are written to disk: see `store.py` for why not on every refresh.

**Failure is a sentence, not an empty list.** A refresh that fails leaves the
last prices on screen with their age beside them, because prices from four
minutes ago are worth something and a blank page is worth nothing. The only
screen that says nothing is the one that has never had anything to say.
"""

from __future__ import annotations

import os
import threading
import time

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gio, GLib, GObject, Gtk  # noqa: E402
from moarchy_ui.icons import icon  # noqa: E402

from . import market  # noqa: E402
from .pages import CoinList  # noqa: E402
from .store import MAX_FAVOURITES  # noqa: E402
from .widgets import STAR_OFF, STAR_ON  # noqa: E402

# The app's own icon, which this package installs -- so it cannot be missing
# whatever the phone's icon theme is. Used for the empty states, where a missing
# icon would be a grey warning triangle in the middle of the screen.
APP_ICON = "org.moarchy.Coins"

# How often the window wakes up, and how old prices have to be before it asks
# for new ones. Two numbers rather than one: the tick also re-writes "4 min ago"
# in the header, which has to age by itself whether or not anything is fetched.
#
# A minute is the interval a coin tracker is worth having at. Under that is a
# request a minute against a keyless rate limit shared with everybody behind the
# same carrier NAT, for a number that has not moved enough to see.
TICK_MS = 30_000
REFRESH_S = 60.0

# How long to wait after a failure, by how many have happened in a row. A phone
# that has gone through a tunnel is back in a minute; a phone with no data plan
# left is not, and asking it every minute for an hour is the difference between
# a flat battery at six and at nine.
BACKOFF_S = (60.0, 150.0, 300.0, 600.0)


class CoinsWindow(Adw.ApplicationWindow):
    __gtype_name__ = "CoinsWindow"

    def __init__(self, store, source, **kwargs) -> None:
        super().__init__(**kwargs)
        self.store = store
        # None is an app that has been told not to use the network at all --
        # `MOARCHY_COINS_OFFLINE`, which is what the screenshots run under. The
        # window never asks which it has beyond hiding the refresh button.
        self.source = source
        self.currency = getattr(source, "currency", "") or store.currency

        self._query = ""
        self._fetching = False
        self._generation = 0
        self._failures = 0
        self._retry_at = 0.0  # monotonic; 0 is "no reason to wait"
        self._trouble = ""
        self._source_id = 0
        # Prices in memory that are not on disk yet. See `stop`.
        self._dirty = False

        self.set_title("Coins")
        self.set_default_size(360, 720)

        # Named for the page rather than for the list, because `market` in this
        # file is the module that talks to CoinGecko.
        self.market_page = CoinList(self._on_star)
        self.starred_page = CoinList(self._on_star)

        self._stack = Adw.ViewStack()
        self._stack.add_titled_with_icon(
            self.market_page,
            "market",
            "Market",
            icon(
                "view-list-symbolic",
                "view-list-bullet-symbolic",
                "format-justify-fill-symbolic",
            ),
        )
        self._stack.add_titled_with_icon(
            self.starred_page, "favourites", "Starred", icon(*STAR_ON)
        )

        self._toasts = Adw.ToastOverlay()
        self._toasts.set_child(self._stack)

        view = Adw.ToolbarView()
        view.add_top_bar(self._header())
        view.add_top_bar(self._search())
        view.set_content(self._toasts)

        switcher = Adw.ViewSwitcherBar()
        switcher.set_stack(self._stack)
        switcher.set_reveal(True)
        switcher.add_css_class("tabbar")
        view.add_bottom_bar(switcher)
        self.set_content(view)

        # The clock follows the window being on screen, not being focused. A
        # phone's compositor does not hand focus out the way a desktop does, and
        # the headless X server the checks run on has no window manager to hand
        # it out at all.
        self.connect("map", lambda *_: self.start())
        self.connect("unmap", lambda *_: self.stop())

        self._refill()
        self._requested()

    # --- chrome ----------------------------------------------------------

    def _header(self) -> Adw.HeaderBar:
        header = Adw.HeaderBar()
        # How old the prices are lives in the title, on both pages, because it
        # is the one thing that decides whether the number under it means
        # anything. A tracker that does not say when it last spoke to anybody is
        # indistinguishable from one that is lying.
        self._title = Adw.WindowTitle(title="Coins", subtitle="")
        header.set_title_widget(self._title)

        self._search_button = Gtk.ToggleButton(
            icon_name=icon("system-search-symbolic", "edit-find-symbolic")
        )
        self._search_button.set_tooltip_text("Search coins")
        self._search_button.update_property(
            [Gtk.AccessibleProperty.LABEL], ["Search coins"]
        )
        header.pack_start(self._search_button)

        menu = Gtk.MenuButton(
            icon_name=icon("open-menu-symbolic", "view-more-symbolic")
        )
        menu.set_tooltip_text("Menu")
        model = Gio.Menu()
        model.append("About Coins", "app.about")
        menu.set_menu_model(model)
        header.pack_end(menu)

        self._refresh_button = Gtk.Button(
            icon_name=icon("view-refresh-symbolic", "emblem-synchronizing-symbolic")
        )
        self._refresh_button.set_tooltip_text("Refresh prices")
        self._refresh_button.update_property(
            [Gtk.AccessibleProperty.LABEL], ["Refresh prices"]
        )
        self._refresh_button.connect("clicked", lambda *_: self._fetch(manual=True))
        # Nothing to refresh with: an offline run has no source to ask, and a
        # button that cannot do its one job is worse than no button.
        self._refresh_button.set_visible(self.source is not None)
        header.pack_end(self._refresh_button)
        return header

    def _search(self) -> Gtk.SearchBar:
        self._entry = Gtk.SearchEntry()
        self._entry.set_placeholder_text("Name or symbol")
        self._entry.set_hexpand(True)
        self._entry.connect("search-changed", self._on_query)

        bar = Gtk.SearchBar()
        bar.set_child(self._entry)
        bar.connect_entry(self._entry)
        # Two-way, so that the button shows the bar and Escape un-presses the
        # button. Binding them beats two handlers that each try not to trigger
        # the other.
        self._search_button.bind_property(
            "active",
            bar,
            "search-mode-enabled",
            GObject.BindingFlags.BIDIRECTIONAL | GObject.BindingFlags.SYNC_CREATE,
        )
        bar.connect("notify::search-mode-enabled", self._on_search_mode)
        self._bar = bar
        return bar

    # --- what is on the pages --------------------------------------------

    def _refill(self, *_args) -> bool:
        """Put the store on screen, filtered by whatever is in the search box.

        Returns SOURCE_REMOVE so this can be handed to `GLib.idle_add` as it is:
        a star toggled inside a button's own signal handler refills from the
        idle loop rather than rebuilding the row that is mid-emission.
        """
        currency = self.store.currency
        favourites = self.store.favourites
        coins = [c for c in self.store.coins if c.matches(self._query)]
        starred = [c for c in self.store.starred() if c.matches(self._query)]

        if self._query:
            self.market_page.set_blank(
                "No match", f"Nothing here is called “{self._query}”.", APP_ICON
            )
        elif self._trouble:
            self.market_page.set_blank("No prices yet", self._trouble, APP_ICON)
        elif self.source is None:
            self.market_page.set_blank(
                "No prices yet",
                "This copy is running offline, and has nothing saved to show.",
                APP_ICON,
            )
        else:
            self.market_page.set_blank(
                "No prices yet", "Fetching the market…", APP_ICON
            )
        self.market_page.fill(coins, currency, favourites)

        if self._query:
            self.starred_page.set_blank(
                "No match", f"Nothing starred is called “{self._query}”.", APP_ICON
            )
        elif favourites:
            # Starred, but not in what was last fetched. It lasts until the next
            # refresh asks for those coins by name.
            self.starred_page.set_blank(
                "No prices for these yet",
                "The coins you starred are not in the last answer. Refresh.",
                icon(*STAR_ON),
            )
        else:
            self.starred_page.set_blank(
                "Nothing starred",
                "Tap the star beside a coin and it stays on this page.",
                icon(*STAR_OFF),
            )
        self.starred_page.fill(starred, currency, favourites)

        self._retitle()
        return GLib.SOURCE_REMOVE

    def _retitle(self) -> None:
        self._title.set_subtitle(self._freshness())

    def _freshness(self) -> str:
        if self._fetching:
            return "Updating…"
        if not self.store.coins:
            return "No prices yet"
        age = market.freshness(self.store.age())
        if self.source is None:
            return f"Offline · {age}"
        if self._failures:
            # The prices below are real, and this says how real. "Not updating"
            # rather than the error itself: the sentence was already said in a
            # toast, and none of them fits in a subtitle.
            return f"Not updating · {age}"
        return f"Updated {age}"

    # --- the star --------------------------------------------------------

    def _on_star(self, coin_id: str, wanted: bool) -> None:
        if wanted == self.store.is_favourite(coin_id):
            return
        got = self.store.toggle(coin_id)
        if got != wanted:
            self.toast(f"{MAX_FAVOURITES} starred coins is as many as this app keeps.")
        try:
            self.store.save_favourites()
        except OSError as exc:
            # The star is in memory and will be gone when the app is. Say so
            # now, rather than letting it disappear silently overnight.
            self.toast(f"Could not save: {exc.strerror or exc}")
        # Out of the button's own signal handler: the refill refills the row
        # that emitted it, including the button that is mid-click.
        GLib.idle_add(self._refill)

    # --- the clock -------------------------------------------------------

    def start(self) -> None:
        if self._source_id:
            return
        self._source_id = GLib.timeout_add(TICK_MS, self._on_tick)
        self._tick()

    def stop(self) -> None:
        if self._source_id:
            GLib.source_remove(self._source_id)
            self._source_id = 0
        self.save()

    def save(self) -> None:
        """Write the cached prices, if they are not already written.

        Called when the window leaves the screen and again when the application
        shuts down, which between them are every way this app ends that is not
        the kernel taking it away mid-frame -- and a cache lost to that is one
        refresh, which is what the cache is for in the first place.
        """
        if not self._dirty:
            return
        try:
            self.store.save_market()
            self._dirty = False
        except OSError:
            # Nowhere to write is not worth a toast on the way out of the
            # screen: nothing a person did has been lost, and the next launch
            # simply fetches.
            pass

    def _on_tick(self) -> bool:
        self._tick()
        return GLib.SOURCE_CONTINUE

    def _tick(self) -> None:
        self._retitle()
        if self._due():
            self._fetch()

    def _due(self) -> bool:
        if self.source is None or self._fetching:
            return False
        if self._retry_at and time.monotonic() < self._retry_at:
            return False
        return self.store.age() >= REFRESH_S

    # --- the network -----------------------------------------------------

    def _fetch(self, *, manual: bool = False) -> None:
        if self.source is None or self._fetching:
            return
        self._fetching = True
        self._generation += 1
        # Which starred coins the last answer did not cover, read here rather
        # than on the thread: the store belongs to the main loop.
        wanted = tuple(self.store.missing())
        self._retitle()
        threading.Thread(
            target=self._work,
            args=(wanted, self._generation, manual),
            # Daemon, so that quitting never waits for a request. The answer to
            # an abandoned one is worth nothing, and the headless checks run the
            # app with a time limit.
            daemon=True,
        ).start()

    def _work(self, wanted: tuple[str, ...], generation: int, manual: bool) -> None:
        coins: list[market.Coin] = []
        trouble = ""
        retry = 0.0
        try:
            coins = list(self.source.markets())
            have = {coin.id for coin in coins}
            missing = [i for i in wanted if i not in have]
            if missing:
                try:
                    coins.extend(self.source.by_ids(missing))
                except market.MarketError:
                    # A starred coin that has fallen out of the top hundred is
                    # not worth failing the whole refresh over: the hundred rows
                    # arrived, and one page of the app is short one price.
                    pass
        except market.MarketError as exc:
            trouble, retry = str(exc), exc.retry_after
        except Exception as exc:  # noqa: BLE001
            # A fetch that dies must not leave the window saying "Updating…"
            # forever. This thread is the only thing that will ever clear it.
            trouble = f"Could not read the market: {exc}"
        GLib.idle_add(self._arrived, coins, trouble, retry, generation, manual)

    def _arrived(
        self,
        coins: list[market.Coin],
        trouble: str,
        retry: float,
        generation: int,
        manual: bool,
    ) -> bool:
        if generation != self._generation:
            return GLib.SOURCE_REMOVE  # a newer request has already answered
        self._fetching = False
        if trouble:
            self._failures += 1
            # Whatever the answer asked for, and otherwise the backoff. A 429
            # always carries one -- `market` fills in CoinGecko's own limit when
            # the header does not -- so a rate limit is waited out rather than
            # counted as one more failure in a row.
            wait = retry or BACKOFF_S[min(self._failures - 1, len(BACKOFF_S) - 1)]
            self._retry_at = time.monotonic() + wait
            self._trouble = trouble
            # Only when somebody is waiting for an answer: a tap on refresh, or
            # a first launch with nothing on screen. A phone that loses signal
            # in a pocket must not queue up an hour of toasts.
            if manual or not self.store.coins:
                self.toast(trouble)
        else:
            self._failures = 0
            self._retry_at = 0.0
            self._trouble = ""
            self.store.replace(coins, fetched=time.time(), currency=self.currency)
            self._dirty = True
        self._refill()
        return GLib.SOURCE_REMOVE

    # --- odds and ends ---------------------------------------------------

    def toast(self, text: str) -> None:
        toast = Adw.Toast.new(text)
        toast.set_timeout(3)
        self._toasts.add_toast(toast)

    def _on_query(self, entry: Gtk.SearchEntry) -> None:
        self.set_query(entry.get_text())

    def set_query(self, text: str) -> None:
        if text == self._query:
            return
        self._query = text
        self._refill()
        # A different list, rather than the same list with new prices in it.
        self.market_page.top()
        self.starred_page.top()

    def _on_search_mode(self, bar: Gtk.SearchBar, *_args) -> None:
        if not bar.get_search_mode():
            # Closing the box clears it. Leaving a query behind means a list
            # filtered by something the person can no longer see.
            self._entry.set_text("")
            self.set_query("")
            return
        # Into the box, from the idle loop rather than from here. Opening the
        # search bar is what raises the phone's keyboard -- moarchy-keyboard
        # comes up when the focused client enables text input, and nothing is
        # focused yet at the moment this signal arrives, least of all when the
        # harness opens the box before the window has been mapped at all.
        GLib.idle_add(self._focus_entry)

    def _focus_entry(self) -> bool:
        self._entry.grab_focus()
        return GLib.SOURCE_REMOVE

    def _requested(self) -> None:
        """Open where an environment variable says, for the harness.

        A headless X server has no pointer worth clicking with, and a run that
        opens straight into the screen it should photograph needs none. The same
        mechanism every app in this repo uses.
        """
        page = os.environ.get("MOARCHY_COINS_PAGE")
        if page and self._stack.get_child_by_name(page) is not None:
            self._stack.set_visible_child_name(page)
        text = os.environ.get("MOARCHY_COINS_SEARCH")
        if text is not None:
            # Empty is meaningful: it opens the box without filtering anything,
            # which is what scripts/text-input-check.sh needs to find out
            # whether this app raises the phone's keyboard.
            self._search_button.set_active(True)
            self._entry.set_text(text)
            self.set_query(text)
