"""The window: twenty launches, the few somebody starred, and one clock.

Two pages behind a switcher at the *bottom*, where a thumb is -- the same
arrangement Coins has, for the same reason. Upcoming is the list everybody
means by "next launch"; the starred page is the one the app is actually for,
and it is a tab rather than a section pinned above the list because a
watchlist you have to scroll past twenty rows to reach is not a watchlist.

**The network is on a thread and nothing waits for it.** A fetch is twelve
seconds at worst on a phone's radio, which is twelve seconds of a frozen
window if it happens on the main loop. So it happens the way every other
slow thing in this repo does -- a daemon thread, a generation counter, and
one `GLib.idle_add` back -- and the window carries on drawing whatever it
last had.

**The clock stops when the window leaves the screen.** An app that keeps
pulling the pad every two minutes after the phone is in a pocket is a
battery bug and a data bill wearing a feature's clothes, and on a phone
the app is not closed, it is hidden, so this is the ordinary case. That is
also the moment the cached launches are written to disk.

**Failure is a sentence, not an empty list.** A refresh that fails leaves
the last launches on screen with their age beside them, because a NET from
four minutes ago is worth something and a blank page is worth nothing. The
only screen that says nothing is the one that has never had anything to say.
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

from . import launches  # noqa: E402
from .pages import DetailView, LaunchList  # noqa: E402
from .store import MAX_FAVOURITES  # noqa: E402
from .widgets import STAR_OFF, STAR_ON  # noqa: E402

APP_ICON = "org.moarchy.Launches"

# The countdown ticks once a second while the window is on screen. Fetching
# is a different clock, and lives in `launches.refresh_after`.
TICK_MS = 1_000

BACKOFF_S = (60.0, 150.0, 300.0, 600.0)


class LaunchesWindow(Adw.ApplicationWindow):
    __gtype_name__ = "LaunchesWindow"

    def __init__(self, store, source, **kwargs) -> None:
        super().__init__(**kwargs)
        self.store = store
        self.source = source

        self._query = ""
        self._fetching = False
        self._generation = 0
        self._failures = 0
        self._retry_at = 0.0
        self._trouble = ""
        self._source_id = 0
        self._dirty = False
        self._open_id = ""
        self._detail_view: DetailView | None = None

        self.set_title("Launches")
        self.set_default_size(360, 720)

        self.upcoming_page = LaunchList(self._on_star, self._open_launch)
        self.starred_page = LaunchList(self._on_star, self._open_launch)

        self._stack = Adw.ViewStack()
        self._stack.add_titled_with_icon(
            self.upcoming_page,
            "upcoming",
            "Upcoming",
            icon(
                "view-list-symbolic",
                "view-list-bullet-symbolic",
                "format-justify-fill-symbolic",
            ),
        )
        self._stack.add_titled_with_icon(
            self.starred_page, "favourites", "Starred", icon(*STAR_ON)
        )

        home = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        home.set_hexpand(True)
        home.set_vexpand(True)
        home.append(self._stack)
        switcher = Adw.ViewSwitcherBar()
        switcher.set_stack(self._stack)
        switcher.set_reveal(True)
        switcher.add_css_class("tabbar")
        home.append(switcher)

        view = Adw.ToolbarView()
        view.add_top_bar(self._header())
        view.add_top_bar(self._search())
        view.set_content(home)

        self._home = Adw.NavigationPage(title="Launches", tag="home")
        self._home.set_child(view)
        self._nav = Adw.NavigationView()
        self._nav.add(self._home)
        self._nav.connect("popped", self._on_popped)

        self._toasts = Adw.ToastOverlay()
        self._toasts.set_child(self._nav)
        self.set_content(self._toasts)

        self.connect("map", lambda *_: self.start())
        self.connect("unmap", lambda *_: self.stop())

        self._refill()
        self._requested()

    # --- chrome ----------------------------------------------------------

    def _header(self) -> Adw.HeaderBar:
        header = Adw.HeaderBar()
        self._title = Adw.WindowTitle(title="Launches", subtitle="")
        header.set_title_widget(self._title)

        self._search_button = Gtk.ToggleButton(
            icon_name=icon("system-search-symbolic", "edit-find-symbolic")
        )
        self._search_button.set_tooltip_text("Search launches")
        self._search_button.update_property(
            [Gtk.AccessibleProperty.LABEL], ["Search launches"]
        )
        header.pack_start(self._search_button)

        menu = Gtk.MenuButton(
            icon_name=icon("open-menu-symbolic", "view-more-symbolic")
        )
        menu.set_tooltip_text("Menu")
        model = Gio.Menu()
        model.append("About Launches", "app.about")
        menu.set_menu_model(model)
        header.pack_end(menu)

        self._refresh_button = Gtk.Button(
            icon_name=icon("view-refresh-symbolic", "emblem-synchronizing-symbolic")
        )
        self._refresh_button.set_tooltip_text("Refresh launches")
        self._refresh_button.update_property(
            [Gtk.AccessibleProperty.LABEL], ["Refresh launches"]
        )
        self._refresh_button.connect("clicked", lambda *_: self._fetch(manual=True))
        self._refresh_button.set_visible(self.source is not None)
        header.pack_end(self._refresh_button)
        return header

    def _search(self) -> Gtk.SearchBar:
        self._entry = Gtk.SearchEntry()
        self._entry.set_placeholder_text("Mission, vehicle, pad")
        self._entry.set_hexpand(True)
        self._entry.connect("search-changed", self._on_query)

        bar = Gtk.SearchBar()
        bar.set_child(self._entry)
        bar.connect_entry(self._entry)
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
        favourites = self.store.favourites
        items = [item for item in self.store.launches if item.matches(self._query)]
        starred = [item for item in self.store.starred() if item.matches(self._query)]

        if self._query:
            self.upcoming_page.set_blank(
                "No match", f"Nothing here is called “{self._query}”.", APP_ICON
            )
        elif self._trouble:
            self.upcoming_page.set_blank("No launches yet", self._trouble, APP_ICON)
        elif self.source is None:
            self.upcoming_page.set_blank(
                "No launches yet",
                "This copy is running offline, and has nothing saved to show.",
                APP_ICON,
            )
        else:
            self.upcoming_page.set_blank(
                "No launches yet", "Fetching launches…", APP_ICON
            )
        self.upcoming_page.fill(items, favourites)

        if self._query:
            self.starred_page.set_blank(
                "No match", f"Nothing starred is called “{self._query}”.", APP_ICON
            )
        elif favourites:
            self.starred_page.set_blank(
                "The launches you starred are no longer in the last answer.",
                "They have flown, or they have slipped off the next twenty.",
                icon(*STAR_ON),
            )
        else:
            self.starred_page.set_blank(
                "Nothing starred",
                "Tap the star beside a launch and it stays on this page until it flies.",
                icon(*STAR_OFF),
            )
        self.starred_page.fill(starred, favourites)

        if self._detail_view is not None and self._open_id:
            current = self.store.get(self._open_id)
            if current is not None:
                self._detail_view.fill(current)

        self._retitle()
        return GLib.SOURCE_REMOVE

    def _retitle(self) -> None:
        self._title.set_subtitle(self._freshness())

    def _freshness(self) -> str:
        if self._fetching:
            return "Updating…"
        if not self.store.launches:
            return "No launches yet"
        age = launches.freshness(self.store.age())
        if self.source is None:
            return f"Offline · {age}"
        if self._failures:
            return f"Not updating · {age}"
        return f"Updated {age}"

    # --- the star --------------------------------------------------------

    def _on_star(self, launch_id: str, wanted: bool) -> None:
        if wanted == self.store.is_favourite(launch_id):
            return
        got = self.store.toggle(launch_id)
        if got != wanted:
            self.toast(
                f"{MAX_FAVOURITES} starred launches is as many as this app keeps."
            )
        try:
            self.store.save_favourites()
        except OSError as exc:
            self.toast(f"Could not save: {exc.strerror or exc}")
        GLib.idle_add(self._refill)

    # --- detail ----------------------------------------------------------

    def _open_launch(self, launch_id: str) -> None:
        item = self.store.get(launch_id)
        if item is None:
            return
        self._open_id = launch_id
        view = DetailView()
        view.fill(item)
        self._detail_view = view
        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_child(view)
        header = Adw.HeaderBar()
        header.set_title_widget(
            Adw.WindowTitle(title=item.name, subtitle=item.vehicle or item.agency)
        )
        toolbar = Adw.ToolbarView()
        toolbar.add_top_bar(header)
        toolbar.set_content(scroller)
        page = Adw.NavigationPage(title=item.name, tag=f"launch-{item.id}")
        page.set_child(toolbar)
        self._nav.push(page)

    def _on_popped(self, *_args) -> None:
        self._open_id = ""
        self._detail_view = None

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
        if not self._dirty:
            return
        try:
            self.store.save_upcoming()
            self._dirty = False
        except OSError:
            pass

    def _on_tick(self) -> bool:
        self._tick()
        return GLib.SOURCE_CONTINUE

    def _tick(self) -> None:
        self._refill()
        if self._due():
            self._fetch()

    def _due(self) -> bool:
        if self.source is None or self._fetching:
            return False
        if self._retry_at and time.monotonic() < self._retry_at:
            return False
        return self.store.age() >= launches.refresh_after(self.store.launches)

    # --- the network -----------------------------------------------------

    def _fetch(self, *, manual: bool = False) -> None:
        if self.source is None or self._fetching:
            return
        self._fetching = True
        self._generation += 1
        self._retitle()
        threading.Thread(
            target=self._work,
            args=(self._generation, manual),
            daemon=True,
        ).start()

    def _work(self, generation: int, manual: bool) -> None:
        items: list[launches.Launch] = []
        trouble = ""
        retry = 0.0
        try:
            items = list(self.source.upcoming())
        except launches.LaunchError as exc:
            trouble, retry = str(exc), exc.retry_after
        except Exception as exc:  # noqa: BLE001
            trouble = f"Could not read the launches: {exc}"
        GLib.idle_add(self._arrived, items, trouble, retry, generation, manual)

    def _arrived(
        self,
        items: list[launches.Launch],
        trouble: str,
        retry: float,
        generation: int,
        manual: bool,
    ) -> bool:
        if generation != self._generation:
            return GLib.SOURCE_REMOVE
        self._fetching = False
        if trouble:
            self._failures += 1
            wait = retry or BACKOFF_S[min(self._failures - 1, len(BACKOFF_S) - 1)]
            self._retry_at = time.monotonic() + wait
            self._trouble = trouble
            if manual or not self.store.launches:
                self.toast(trouble)
        else:
            self._failures = 0
            self._retry_at = 0.0
            self._trouble = ""
            self.store.replace(items, fetched=time.time())
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
        self.upcoming_page.top()
        self.starred_page.top()

    def _on_search_mode(self, bar: Gtk.SearchBar, *_args) -> None:
        if not bar.get_search_mode():
            self._entry.set_text("")
            self.set_query("")
            return
        GLib.idle_add(self._focus_entry)

    def _focus_entry(self) -> bool:
        self._entry.grab_focus()
        return GLib.SOURCE_REMOVE

    def _requested(self) -> None:
        """Open where an environment variable says, for the harness."""
        page = os.environ.get("MOARCHY_LAUNCHES_PAGE")
        if page == "favourites":
            self._stack.set_visible_child_name("favourites")
        elif page == "upcoming":
            self._stack.set_visible_child_name("upcoming")
        text = os.environ.get("MOARCHY_LAUNCHES_SEARCH")
        if text is not None:
            self._search_button.set_active(True)
            self._entry.set_text(text)
            self.set_query(text)
        open_id = os.environ.get("MOARCHY_LAUNCHES_OPEN", "")
        if page == "detail" or open_id:
            target = open_id or (
                self.store.launches[0].id if self.store.launches else ""
            )
            if target:
                GLib.idle_add(self._open_launch, target)
