"""The application: styles, one store, one source of facts, and one window.

The stylesheet is rebuilt whenever the active Omarchy theme changes, so
`omarchy-theme-set` recolours the badges in place -- the same behaviour the
bar, the drawer and the keyboard have.

Where the data comes from is decided here rather than in the window, because
it is a property of the process rather than of a window: the directory the
history lives in, and whether there is a network at all. That is what lets
the screenshot harness point the whole app at a directory of files and no
network without a screenshot mode existing anywhere inside the app.
"""

from __future__ import annotations

import os
import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gdk, Gio, GLib, Gtk  # noqa: E402

from . import __version__, theme  # noqa: E402
from .facts import Live  # noqa: E402
from .store import Store  # noqa: E402
from .window import FoodWindow  # noqa: E402

APP_ID = "org.moarchy.Food"

THEME_SETTLE_MS = 200


def _source() -> Live | None:
    """Where facts come from, or None for an app told to stay off the network."""
    if os.environ.get("MOARCHY_FOOD_OFFLINE"):
        return None
    return Live()


class FoodApplication(Adw.Application):
    def __init__(self) -> None:
        super().__init__(application_id=APP_ID)
        self._styles: Gtk.CssProvider | None = None
        self._monitors: list[Gio.FileMonitor] = []
        self._reload_source = 0
        self.store = Store()
        self.store.load()

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
            window = FoodWindow(self.store, _source(), application=self)
        window.present()

        seconds = os.environ.get("MOARCHY_FOOD_QUIT_AFTER")
        if seconds and seconds.isdigit():
            GLib.timeout_add_seconds(int(seconds), self.quit)

    def do_shutdown(self) -> None:
        window = self.props.active_window
        if isinstance(window, FoodWindow):
            window._camera.stop()
        Adw.Application.do_shutdown(self)

    def _apply_styles(self) -> None:
        display = Gdk.Display.get_default()
        if display is None:
            return

        manager = Adw.StyleManager.get_default()
        palette = theme.load()
        if palette is not None:
            manager.set_color_scheme(
                Adw.ColorScheme.FORCE_DARK
                if palette.dark
                else Adw.ColorScheme.FORCE_LIGHT
            )
        else:
            palette = theme.fallback(dark=manager.get_dark())

        if self._styles is None:
            self._styles = Gtk.CssProvider()
            Gtk.StyleContext.add_provider_for_display(
                display, self._styles, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            )
        self._styles.load_from_string(theme.stylesheet(palette))

    def _watch_theme(self) -> None:
        if self._monitors:
            return
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

    def _on_about(self, *_args) -> None:
        about = Adw.AboutDialog(
            application_name="Food",
            application_icon=APP_ID,
            version=__version__,
            developer_name="Simon Schubert",
            license_type=Gtk.License.MIT_X11,
            website="https://github.com/SimonSchubert/moarchy-apps",
            issue_url="https://github.com/SimonSchubert/moarchy-apps/issues",
            comments=(
                "Point the camera at a barcode. Open Food Facts answers with "
                "the name, the Nutri-Score, the nutrients and the allergens. "
                "There is no typed entry and no account — a barcode the camera "
                "cannot see cannot be looked up."
            ),
        )
        about.present(self.props.active_window)


def main() -> int:
    return FoodApplication().run(sys.argv)
