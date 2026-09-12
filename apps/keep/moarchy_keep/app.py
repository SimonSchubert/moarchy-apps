"""The application: styles, the store, and one window.

The stylesheet is rebuilt whenever the active Omarchy theme changes, so
`omarchy-theme-set` recolours the notes in place -- the same behaviour the bar,
the drawer and the keyboard have. Note colours are CSS classes, so a reload is
the whole mechanism: every card already on screen repaints and the grid never
learns that a theme exists.
"""

from __future__ import annotations

import os
import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gdk, Gio, GLib, Gtk  # noqa: E402

from . import theme  # noqa: E402
from .notes import Store  # noqa: E402
from .window import KeepWindow  # noqa: E402

APP_ID = "org.moarchy.Keep"

# A theme change rewrites colors.toml as a copy, which arrives as several file
# events in a row. Rebuilding the stylesheet on each one is wasteful and, on a
# partially written file, wrong.
THEME_SETTLE_MS = 200


class KeepApplication(Adw.Application):
    def __init__(self) -> None:
        super().__init__(application_id=APP_ID)
        self._styles: Gtk.CssProvider | None = None
        self._monitors: list[Gio.FileMonitor] = []
        self._reload_source = 0
        self.store = Store()

    # --- lifecycle -------------------------------------------------------

    def do_startup(self) -> None:
        Adw.Application.do_startup(self)
        self.store.load()

    def do_activate(self) -> None:
        self._apply_styles()
        self._watch_theme()
        window = self.props.active_window
        if window is None:
            window = KeepWindow(self.store, application=self)
            window.connect("close-request", self._on_close)
        window.present()

        # Debug hook: quit after N seconds. The headless checks need the app to
        # end by itself -- a log that was cut off by a kill cannot be told apart
        # from one that stopped because something went wrong.
        seconds = os.environ.get("MOARCHY_KEEP_QUIT_AFTER")
        if seconds and seconds.isdigit():
            GLib.timeout_add_seconds(int(seconds), self.quit)

    def do_shutdown(self) -> None:
        # Belt and braces: the window flushes on close-request, but a session
        # ending under us never sends one.
        try:
            self.store.save()
        except OSError as exc:
            print(f"moarchy-keep: could not save notes: {exc}", file=sys.stderr)
        Adw.Application.do_shutdown(self)

    def _on_close(self, window: KeepWindow) -> bool:
        window.shutdown()
        return False  # let it close

    # --- styling ---------------------------------------------------------

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
            # entries and popovers over a near-black window.
            manager.set_color_scheme(
                Adw.ColorScheme.FORCE_DARK
                if palette.dark
                else Adw.ColorScheme.FORCE_LIGHT
            )

        css, _ = theme.stylesheet(dark_hint=manager.get_dark())

        if self._styles is None:
            self._styles = Gtk.CssProvider()
            # APPLICATION, not USER: USER outranks a user's own gtk.css, and
            # someone who has written one means it.
            Gtk.StyleContext.add_provider_for_display(
                display, self._styles, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            )
        self._styles.load_from_string(css)

    def _watch_theme(self) -> None:
        if self._monitors:
            return
        # Both the file and the directory holding it: omarchy-theme-set stages
        # a *copy* of the theme, so colors.toml is replaced rather than edited,
        # and a monitor on the old inode alone would go quiet after the first
        # switch.
        for path in (theme.COLORS, theme.CURRENT_THEME):
            target = Gio.File.new_for_path(str(path))
            try:
                monitor = target.monitor(Gio.FileMonitorFlags.NONE, None)
            except GLib.Error:
                continue
            monitor.connect("changed", lambda *_: self._theme_changed())
            self._monitors.append(monitor)

    def _theme_changed(self) -> None:
        if self._reload_source:
            GLib.source_remove(self._reload_source)
        self._reload_source = GLib.timeout_add(THEME_SETTLE_MS, self._reload_styles)

    def _reload_styles(self) -> bool:
        self._reload_source = 0
        self._apply_styles()
        return False  # one-shot


def main() -> int:
    return KeepApplication().run(sys.argv)
