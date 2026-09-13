"""The application: styles, one store, one source of prices, and one window.

The stylesheet is rebuilt whenever the active Omarchy theme changes, so
`omarchy-theme-set` recolours the list in place -- the same behaviour the bar,
the drawer and the keyboard have. Unlike Vitals there is no second half to hand
a palette to: nothing in this app is drawn with cairo, so the stylesheet is the
whole of it.

Where the data comes from is decided here rather than in the window, because it
is a property of the process rather than of a window: the directory the stars
live in, the currency, the API key if there is one, and whether there is a
network at all. That is what lets the screenshot harness point the whole app at
a directory of files and no network without a screenshot mode existing anywhere
inside the app.

Three environment variables, and they are the app's whole configuration:

  MOARCHY_COINS_DIR        where the stars and the cached prices live
  MOARCHY_COINS_CURRENCY   what to price them in; usd unless said otherwise
  MOARCHY_COINS_KEY        a CoinGecko demo key, for anybody who has one
  MOARCHY_COINS_OFFLINE    never touch the network; show what is cached
"""

from __future__ import annotations

import os
import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gdk, Gio, GLib, Gtk  # noqa: E402

from . import __version__, theme  # noqa: E402
from .market import CURRENCY, TOP, Live  # noqa: E402
from .store import Store  # noqa: E402
from .window import CoinsWindow  # noqa: E402

APP_ID = "org.moarchy.Coins"

# A theme change rewrites colors.toml as a copy, which arrives as several file
# events in a row. Rebuilding the stylesheet on each one is wasteful and, on a
# partially written file, wrong.
THEME_SETTLE_MS = 200


def _source() -> Live | None:
    """Where prices come from, or None for an app told to stay off the network.

    `MOARCHY_COINS_OFFLINE` is how the screenshots are taken and how anybody who
    wants a look at the app on a metered connection can have one: the window
    hides its refresh button, keeps the cached prices, and says how old they
    are.
    """
    if os.environ.get("MOARCHY_COINS_OFFLINE"):
        return None
    return Live(
        currency=os.environ.get("MOARCHY_COINS_CURRENCY") or CURRENCY,
        count=TOP,
        key=os.environ.get("MOARCHY_COINS_KEY", ""),
    )


class CoinsApplication(Adw.Application):
    def __init__(self) -> None:
        super().__init__(application_id=APP_ID)
        self._styles: Gtk.CssProvider | None = None
        self._monitors: list[Gio.FileMonitor] = []
        self._reload_source = 0
        self.store = Store()
        self.store.load()

    # --- lifecycle -------------------------------------------------------

    def do_startup(self) -> None:
        Adw.Application.do_startup(self)

        about = Gio.SimpleAction.new("about", None)
        about.connect("activate", self._on_about)
        self.add_action(about)

        quit_action = Gio.SimpleAction.new("quit", None)
        quit_action.connect("activate", lambda *_: self.quit())
        self.add_action(quit_action)
        self.set_accels_for_action("app.quit", ["<Primary>q"])

    def do_activate(self) -> None:
        self._apply_styles()
        self._watch_theme()
        window = self.props.active_window
        if window is None:
            window = CoinsWindow(self.store, _source(), application=self)
        window.present()

        # Debug hook: quit after N seconds. The headless checks need the app to
        # end by itself -- a log cut off by a kill cannot be told apart from one
        # that stopped because something went wrong.
        seconds = os.environ.get("MOARCHY_COINS_QUIT_AFTER")
        if seconds and seconds.isdigit():
            GLib.timeout_add_seconds(int(seconds), self.quit)

    def do_shutdown(self) -> None:
        # The window writes its cache when it leaves the screen; this is for the
        # ways out that do not unmap it first.
        window = self.props.active_window
        if isinstance(window, CoinsWindow):
            window.save()
        Adw.Application.do_shutdown(self)

    # --- styles ----------------------------------------------------------

    def _apply_styles(self) -> None:
        display = Gdk.Display.get_default()
        if display is None:
            return

        manager = Adw.StyleManager.get_default()
        palette = theme.load()
        if palette is not None:
            # Follow the theme's own light/dark, not the desktop portal's --
            # there may not be one on this session, and libadwaita's default
            # without it is light, which on tokyo-night would mean white
            # popovers and dialogs over a near-black window.
            manager.set_color_scheme(
                Adw.ColorScheme.FORCE_DARK
                if palette.dark
                else Adw.ColorScheme.FORCE_LIGHT
            )
        else:
            # No Omarchy to read. Follow whatever the desktop asked for, so the
            # app is still dark on a dark desktop.
            palette = theme.fallback(dark=manager.get_dark())

        if self._styles is None:
            self._styles = Gtk.CssProvider()
            # APPLICATION, not USER: USER outranks a user's own gtk.css, and
            # someone who has written one means it.
            Gtk.StyleContext.add_provider_for_display(
                display, self._styles, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            )
        self._styles.load_from_string(theme.stylesheet(palette))

    def _watch_theme(self) -> None:
        if self._monitors:
            return
        # Watch the file and the directory holding it: omarchy-theme-set
        # replaces the staged copy, and a replaced file stops delivering events
        # to a monitor on the old inode.
        for path in (theme.COLORS, theme.CURRENT_THEME):
            try:
                monitor = Gio.File.new_for_path(str(path)).monitor(
                    Gio.FileMonitorFlags.NONE, None
                )
            except GLib.Error:
                continue
            monitor.connect("changed", self._on_theme_changed)
            self._monitors.append(monitor)

    def _on_theme_changed(self, *_args) -> None:
        if self._reload_source:
            GLib.source_remove(self._reload_source)
        self._reload_source = GLib.timeout_add(THEME_SETTLE_MS, self._reload_styles)

    def _reload_styles(self) -> bool:
        self._reload_source = 0
        self._apply_styles()
        return GLib.SOURCE_REMOVE

    # --- about -----------------------------------------------------------

    def _on_about(self, *_args) -> None:
        about = Adw.AboutDialog(
            application_name="Coins",
            application_icon=APP_ID,
            version=__version__,
            developer_name="Simon Schubert",
            license_type=Gtk.License.MIT_X11,
            website="https://github.com/SimonSchubert/moarchy-apps",
            issue_url="https://github.com/SimonSchubert/moarchy-apps/issues",
            comments=(
                "The top hundred coins by market capitalisation, and the few "
                "you starred, drawn for a phone. Prices come from CoinGecko's "
                "public API; the stars stay on the device. There is no account, "
                "no wallet and no portfolio — the app knows which coins you "
                "watch and nothing about what you hold."
            ),
        )
        about.present(self.props.active_window)


def main() -> int:
    return CoinsApplication().run(sys.argv)
