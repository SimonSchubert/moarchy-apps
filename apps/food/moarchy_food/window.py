"""The window: a camera, a history, and one product at a time.

Two pages behind a switcher at the *bottom*, where a thumb is -- the same
arrangement Coins and Vitals have, for the same reason. Scan is the job;
history is the list of jobs already done. A product is pushed on top of
both, because on 360px a product is the whole screen.

**There is no typed barcode.** The only way a code enters this window is a
zbar message from the camera pipeline. A missing camera is an empty state
that says so, not a text field that pretends the lens was optional.

**The network is on a thread and nothing waits for it.** A fetch is twelve
seconds at worst on a phone's radio. So it happens the way every other slow
thing in this repo does -- a daemon thread, a generation counter, and one
`GLib.idle_add` back -- and the scanner stays up until the answer arrives.

**The camera stops when the window leaves the screen.** An app that keeps
the sensor running after the phone is in a pocket is a battery bug wearing
a feature's clothes, and on a phone the app is not closed, it is hidden.
"""

from __future__ import annotations

import os
import threading

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gdk, Gio, GLib, Gtk  # noqa: E402
from moarchy_ui.icons import icon  # noqa: E402

from . import camera as camera_mod  # noqa: E402
from .facts import FactsError, Product  # noqa: E402
from .pages import MissingView, ProductView  # noqa: E402
from .widgets import APP_ICON, HistoryView, ScanView  # noqa: E402


class FoodWindow(Adw.ApplicationWindow):
    __gtype_name__ = "FoodWindow"

    def __init__(self, store, source, camera=None, **kwargs) -> None:
        super().__init__(**kwargs)
        self.store = store
        # None is an app that has been told not to use the network at all --
        # `MOARCHY_FOOD_OFFLINE`, which is what the screenshots run under.
        self.source = source
        self._camera = camera
        self._fetching = False
        self._generation = 0
        self._mapped = False

        self.set_title("Food")
        self.set_default_size(360, 720)

        self.scan_page = ScanView()
        self.history_page = HistoryView(self._open_product)
        if self._camera is None:
            self._camera = camera_mod.Camera(self.scan_page.picture)
        self._camera.on_code(self._on_code)

        self._stack = Adw.ViewStack()
        self._stack.add_titled_with_icon(
            self.scan_page,
            "scan",
            "Scan",
            icon("camera-photo-symbolic", "camera-video-symbolic", APP_ICON),
        )
        self._stack.add_titled_with_icon(
            self.history_page,
            "history",
            "History",
            icon(
                "view-list-symbolic",
                "view-list-bullet-symbolic",
                "document-open-symbolic",
            ),
        )
        self._stack.connect(
            "notify::visible-child-name", lambda *_: self._sync_camera()
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

        toolbar = Adw.ToolbarView()
        toolbar.add_top_bar(self._header())
        toolbar.set_content(home)

        self._nav = Adw.NavigationView()
        self._home = Adw.NavigationPage(title="Food", tag="home")
        self._home.set_child(toolbar)
        self._nav.add(self._home)
        self._nav.connect("popped", lambda *_: self._sync_camera())

        self._toasts = Adw.ToastOverlay()
        self._toasts.set_child(self._nav)
        self.set_content(self._toasts)

        self.connect("map", lambda *_: self._on_map())
        self.connect("unmap", lambda *_: self._on_unmap())

        self._refill_history()
        self._requested()
        GLib.idle_add(self._drop_focus)

    def _drop_focus(self) -> bool:
        # No text field on purpose, but a selectable label can still steal
        # focus and look like one. Put it nowhere.
        self.set_focus(None)
        return GLib.SOURCE_REMOVE

    # --- chrome ----------------------------------------------------------

    def _header(self) -> Adw.HeaderBar:
        header = Adw.HeaderBar()
        self._title = Adw.WindowTitle(title="Food", subtitle="Open Food Facts")
        header.set_title_widget(self._title)
        menu_button = Gtk.MenuButton(
            icon_name=icon("open-menu-symbolic", "application-menu-symbolic")
        )
        menu_button.set_menu_model(self._menu())
        header.pack_end(menu_button)
        return header

    def _menu(self) -> Gio.Menu:
        menu = Gio.Menu()
        menu.append("About Food", "app.about")
        menu.append("Quit", "app.quit")
        return menu

    # --- camera ----------------------------------------------------------

    def _on_map(self) -> None:
        self._mapped = True
        # First paint before GStreamer. Gst.init plus PLAYING on a v4l2 node is
        # the better part of a second on this phone, and doing it from map
        # holds the first frame until it finishes. The reticle goes up now;
        # the pipeline is attached from an idle once GTK has had a chance to
        # draw.
        if self._on_scan_tab() and not self._fetching:
            self.scan_page.show_live()
        GLib.idle_add(self._start_camera_later)

    def _start_camera_later(self) -> bool:
        if not self._mapped:
            return GLib.SOURCE_REMOVE
        # Tests hand in a stand-in with no GStreamer behind it; starting that
        # from idle is enough. The real camera inits Gst on a side thread so
        # the main loop can keep painting, then PLAYING is back on this thread
        # because the pipeline is not safe to build anywhere else.
        if not isinstance(self._camera, camera_mod.Camera):
            self._sync_camera()
            return GLib.SOURCE_REMOVE

        def prepare() -> None:
            camera_mod._gst()
            GLib.idle_add(self._sync_camera)

        threading.Thread(target=prepare, daemon=True, name="food-gst-init").start()
        return GLib.SOURCE_REMOVE

    def _on_unmap(self) -> None:
        self._mapped = False
        self._camera.stop()

    def _on_scan_tab(self) -> bool:
        if self._nav.get_visible_page() is not self._home:
            return False
        return self._stack.get_visible_child_name() == "scan"

    def _sync_camera(self) -> None:
        if not self._mapped or not self._on_scan_tab() or self._fetching:
            self._camera.stop()
            if not self._on_scan_tab():
                return
            if self._fetching:
                self.scan_page.show_blank("Looking up", "Open Food Facts is answering.")
            return
        if self._camera.start():
            self.scan_page.show_live()
            return
        reason = self._camera.reason or "No camera found."
        self.scan_page.show_blank(
            "Camera required",
            f"{reason} Point this phone at a barcode to look up nutrition facts. There is no other way in.",
        )

    # --- lookup ----------------------------------------------------------

    def _on_code(self, code: str) -> None:
        if os.environ.get("MOARCHY_FOOD_SCAN_ONLY"):
            self._toast(code)
            return
        if self._fetching:
            return
        cached = self.store.get(code)
        if cached is not None and self.source is None:
            self.store.remember(cached)
            self._refill_history()
            self._open_product(cached)
            return
        if self.source is None:
            self._toast("No network, and this barcode is not in the cache.")
            return
        self._fetching = True
        self._generation += 1
        generation = self._generation
        self._sync_camera()
        thread = threading.Thread(
            target=self._lookup, args=(code, generation), daemon=True
        )
        thread.start()

    def _lookup(self, code: str, generation: int) -> None:
        try:
            product = self.source.product(code)
            error = None
        except FactsError as exc:
            product = None
            error = exc
        GLib.idle_add(self._looked_up, code, generation, product, error)

    def _looked_up(
        self,
        code: str,
        generation: int,
        product: Product | None,
        error: FactsError | None,
    ) -> bool:
        if generation != self._generation:
            return GLib.SOURCE_REMOVE
        self._fetching = False
        if product is not None:
            self.store.remember(product)
            self._refill_history()
            self._open_product(product)
            return GLib.SOURCE_REMOVE
        if error is not None and error.missing:
            self._open_missing(code)
        elif error is not None:
            self._toast(str(error))
            self._sync_camera()
        else:
            self._sync_camera()
        return GLib.SOURCE_REMOVE

    def _open_product(self, product: Product) -> None:
        view = ProductView()
        view.fill(product)
        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_child(view)
        header = Adw.HeaderBar()
        header.set_title_widget(
            Adw.WindowTitle(
                title=product.name, subtitle=product.subtitle or product.code
            )
        )
        toolbar = Adw.ToolbarView()
        toolbar.add_top_bar(header)
        toolbar.set_content(scroller)
        page = Adw.NavigationPage(title=product.name, tag=f"product-{product.code}")
        page.set_child(toolbar)
        self._nav.push(page)
        self._camera.stop()
        self._load_image(view, product)
        GLib.idle_add(self._drop_focus)

    def _open_missing(self, code: str) -> None:
        view = MissingView()
        view.fill(code)
        header = Adw.HeaderBar()
        header.set_title_widget(Adw.WindowTitle(title="Not found", subtitle=code))
        toolbar = Adw.ToolbarView()
        toolbar.add_top_bar(header)
        toolbar.set_content(view)
        page = Adw.NavigationPage(title="Not found", tag=f"missing-{code}")
        page.set_child(toolbar)
        self._nav.push(page)
        self._camera.stop()

    def _load_image(self, view: ProductView, product: Product) -> None:
        if self.source is None or not product.image_url:
            return
        generation = self._generation

        def fetch() -> None:
            try:
                raw = self.source.image(product.image_url)
            except FactsError:
                return
            GLib.idle_add(self._set_image, view, product, raw, generation)

        threading.Thread(target=fetch, daemon=True).start()

    def _set_image(
        self, view: ProductView, product: Product, raw: bytes, generation: int
    ) -> bool:
        if view.product is None or view.product.code != product.code:
            return GLib.SOURCE_REMOVE
        try:
            gi.require_version("GdkPixbuf", "2.0")
            from gi.repository import GdkPixbuf

            loader = GdkPixbuf.PixbufLoader()
            loader.write(raw)
            loader.close()
            pixbuf = loader.get_pixbuf()
        except GLib.Error:
            return GLib.SOURCE_REMOVE
        if pixbuf is None:
            return GLib.SOURCE_REMOVE
        view.hero.set_paintable(Gdk.Texture.new_for_pixbuf(pixbuf))
        view.hero.set_visible(True)
        return GLib.SOURCE_REMOVE

    def _refill_history(self) -> None:
        self.history_page.fill(self.store.recent())

    def _toast(self, message: str) -> None:
        self._toasts.add_toast(Adw.Toast(title=message, timeout=3))

    # --- debug hooks -----------------------------------------------------

    def _requested(self) -> None:
        """Open on a particular screen, so a screenshot needs no tap.

        `MOARCHY_FOOD_PAGE` is `scan`, `history`, `product` or `missing`.
        `MOARCHY_FOOD_CODE` picks which cached product; without it, product
        is the most recently scanned.
        """
        page = os.environ.get("MOARCHY_FOOD_PAGE", "")
        code = os.environ.get("MOARCHY_FOOD_CODE", "")
        if page == "history":
            self._stack.set_visible_child_name("history")
            return
        if page == "missing":
            self._open_missing(code or "0000000000000")
            return
        if page == "product":
            product = self.store.get(code) if code else None
            if product is None:
                recent = self.store.recent()
                product = recent[0] if recent else None
            if product is not None:
                GLib.idle_add(self._open_product, product)
            return
        self._stack.set_visible_child_name("scan")
