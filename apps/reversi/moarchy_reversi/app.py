"""The application: styles, the saved game, and one window.

The stylesheet is rebuilt whenever the active Omarchy theme changes, so
`omarchy-theme-set` recolours the board in place -- the same behaviour the bar,
the drawer and the keyboard have.

Unlike the other apps here, a reload is not the whole mechanism: most of this
app is drawn rather than styled, and cairo cannot read a CSS class. So the
palette is handed to the window as well, which hands it to the board, which
repaints. Everything that *is* a widget -- the chips, the buttons, the record --
still comes from the stylesheet and needs nothing but the reload.
"""

from __future__ import annotations

import os
import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gdk, Gio, GLib, Gtk  # noqa: E402

from . import __version__, theme  # noqa: E402
from .store import Store  # noqa: E402
from .window import ReversiWindow  # noqa: E402

APP_ID = "org.moarchy.Reversi"

# A theme change rewrites colors.toml as a copy, which arrives as several file
# events in a row. Rebuilding the stylesheet on each one is wasteful and, on a
# partially written file, wrong.
THEME_SETTLE_MS = 200


class ReversiApplication(Adw.Application):
    def __init__(self) -> None:
        super().__init__(application_id=APP_ID)
        self._styles: Gtk.CssProvider | None = None
        self._monitors: list[Gio.FileMonitor] = []
        self._reload_source = 0
        self.palette: theme.Palette | None = None
        self.store = Store()

    # --- lifecycle -------------------------------------------------------

    def do_startup(self) -> None:
        Adw.Application.do_startup(self)
        self.store.load()

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
            window = ReversiWindow(self.store, application=self)
            if self.palette is not None:
                window.set_palette(self.palette)
        window.present()

        # Debug hook: quit after N seconds. The headless checks need the app to
        # end by itself -- a log cut off by a kill cannot be told apart from one
        # that stopped because something went wrong.
        seconds = os.environ.get("MOARCHY_REVERSI_QUIT_AFTER")
        if seconds and seconds.isdigit():
            GLib.timeout_add_seconds(int(seconds), self.quit)

    def do_shutdown(self) -> None:
        # Belt and braces: the window saves after every move and again on
        # close-request, but a session ending under us never sends one.
        try:
            self.store.save()
        except OSError as exc:
            print(f"moarchy-reversi: could not save the game: {exc}", file=sys.stderr)
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

        self.palette = palette
        if self._styles is None:
            self._styles = Gtk.CssProvider()
            # APPLICATION, not USER: USER outranks a user's own gtk.css, and
            # someone who has written one means it.
            Gtk.StyleContext.add_provider_for_display(
                display, self._styles, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            )
        self._styles.load_from_string(theme.stylesheet(palette))

        window = self.props.active_window
        if window is not None:
            window.set_palette(palette)

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
            application_name="Reversi",
            application_icon=APP_ID,
            version=__version__,
            developer_name="Simon Schubert",
            license_type=Gtk.License.MIT_X11,
            website="https://github.com/SimonSchubert/moarchy-apps",
            issue_url="https://github.com/SimonSchubert/moarchy-apps/issues",
            comments=(
                "Reversi for a Linux phone. The board is your theme's green, "
                "the opponent thinks on a clock, and the game is kept on the "
                "device."
            ),
        )
        about.present(self.props.active_window)


def main() -> int:
    return ReversiApplication().run(sys.argv)
