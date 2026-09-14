"""The badges, the history row, and the scanner overlay.

Nothing in this file is drawn with cairo. A Nutri-Score is a letter in a
coloured box -- a `Gtk.Label` -- so it scales with the phone's font size and
is read out by a screen reader. That is the repo's standing rule about text,
and it is also why this package does not depend on python-cairo.
"""

from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gtk, Pango  # noqa: E402
from moarchy_ui.icons import icon  # noqa: E402

from . import theme  # noqa: E402
from .facts import DASH, Product  # noqa: E402

APP_ICON = "org.moarchy.Food"


class GradeBadge(Gtk.Box):
    """A letter the size of a thumb, with a caption under it."""

    __gtype_name__ = "FoodGradeBadge"

    def __init__(self, caption: str) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.set_halign(Gtk.Align.CENTER)
        self._letter = Gtk.Label()
        self._letter.add_css_class("letter")
        self._letter.set_valign(Gtk.Align.CENTER)
        self._letter.set_halign(Gtk.Align.CENTER)
        self._caption = Gtk.Label(label=caption)
        self._caption.add_css_class("letter-caption")
        self.append(self._letter)
        self.append(self._caption)
        self._hue = ""

    def set_caption(self, caption: str) -> None:
        self._caption.set_label(caption)

    def fill(self, grade: str, *, fallback: str = DASH) -> None:
        letter = grade.lower()
        if self._hue:
            self._letter.remove_css_class(f"grade-{self._hue}")
        if letter in theme.GRADE_HUES:
            self._letter.add_css_class(f"grade-{letter}")
            self._hue = letter
            self._letter.set_label(letter.upper())
        else:
            self._hue = ""
            self._letter.set_label(fallback)


class ProductRow(Gtk.ListBoxRow):
    """A name, a brand, and the Nutri-Score as a small letter on the right."""

    __gtype_name__ = "FoodProductRow"

    def __init__(self) -> None:
        super().__init__()
        self.product: Product | None = None
        self.set_activatable(True)
        self.add_css_class("food-row")

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)

        names = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        names.set_valign(Gtk.Align.CENTER)
        names.set_hexpand(True)
        self._name = Gtk.Label(xalign=0.0)
        self._name.add_css_class("food-name")
        self._name.set_ellipsize(Pango.EllipsizeMode.END)
        self._note = Gtk.Label(xalign=0.0)
        self._note.add_css_class("food-note")
        self._note.set_ellipsize(Pango.EllipsizeMode.END)
        names.append(self._name)
        names.append(self._note)
        box.append(names)

        self._badge = Gtk.Label()
        self._badge.add_css_class("letter")
        self._badge.set_valign(Gtk.Align.CENTER)
        self._badge.set_size_request(theme.TARGET, theme.TARGET)
        box.append(self._badge)
        self._hue = ""

        self.set_child(box)

    def fill(self, product: Product) -> None:
        self.product = product
        self._name.set_label(product.name)
        self._note.set_label(product.subtitle or product.code)
        letter = product.nutriscore.lower()
        if self._hue:
            self._badge.remove_css_class(f"grade-{self._hue}")
        if letter in theme.GRADE_HUES:
            self._badge.add_css_class(f"grade-{letter}")
            self._hue = letter
            self._badge.set_label(letter.upper())
        else:
            self._hue = ""
            self._badge.set_label(DASH)
        self.set_visible(True)


class ScanView(Gtk.Box):
    """The viewfinder, or a reason there is no camera.

    Two states and only two. A working camera is a `Gtk.Picture` with a
    reticle over it. Anything else -- no device, a pipeline that failed, a
    lookup in flight -- is a StatusPage, never a text field.
    """

    __gtype_name__ = "FoodScanView"

    def __init__(self) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.add_css_class("scan")

        self.picture = Gtk.Picture()
        self.picture.add_css_class("scan-preview")
        self.picture.set_hexpand(True)
        self.picture.set_vexpand(True)
        self.picture.set_content_fit(Gtk.ContentFit.COVER)

        reticle = Gtk.Box()
        reticle.add_css_class("reticle")
        reticle.set_halign(Gtk.Align.CENTER)
        reticle.set_valign(Gtk.Align.CENTER)
        reticle.set_can_target(False)

        hint = Gtk.Label(label="Point at a barcode")
        hint.add_css_class("scan-hint")
        hint.set_halign(Gtk.Align.CENTER)
        hint.set_valign(Gtk.Align.END)
        hint.set_margin_bottom(24)
        hint.set_can_target(False)

        overlay = Gtk.Overlay()
        overlay.set_child(self.picture)
        overlay.add_overlay(reticle)
        overlay.add_overlay(hint)
        overlay.set_hexpand(True)
        overlay.set_vexpand(True)

        self._blank = Adw.StatusPage()
        self._blank.set_icon_name(
            icon("camera-photo-symbolic", "camera-video-symbolic", APP_ICON)
        )
        self._blank.set_vexpand(True)

        self._stack = Gtk.Stack()
        self._stack.add_named(overlay, "live")
        self._stack.add_named(self._blank, "blank")
        self._stack.set_vexpand(True)
        self.append(self._stack)

    def show_live(self) -> None:
        self._stack.set_visible_child_name("live")

    def show_blank(self, title: str, body: str) -> None:
        self._blank.set_title(title)
        self._blank.set_description(body)
        self._stack.set_visible_child_name("blank")


class HistoryView(Gtk.Box):
    """A list of scanned products, or an invitation to scan one."""

    __gtype_name__ = "FoodHistoryView"

    def __init__(self, on_open) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self._on_open = on_open
        self._rows: list[ProductRow] = []

        self._list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        self._list.set_valign(Gtk.Align.START)
        self._list.connect("row-activated", self._activated)

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_hexpand(True)
        scroller.set_vexpand(True)
        scroller.set_child(self._list)

        self._blank = Adw.StatusPage()
        self._blank.set_icon_name(
            icon("view-list-symbolic", "view-list-bullet-symbolic", APP_ICON)
        )
        self._blank.set_title("Nothing scanned yet")
        self._blank.set_description(
            "Point the camera at a barcode. That is the only way a product gets here."
        )
        self._blank.set_vexpand(True)

        self._stack = Gtk.Stack()
        self._stack.add_named(scroller, "list")
        self._stack.add_named(self._blank, "blank")
        self._stack.set_vexpand(True)
        self.append(self._stack)

    def fill(self, products: list[Product]) -> None:
        for index, product in enumerate(products):
            if index == len(self._rows):
                row = ProductRow()
                self._rows.append(row)
                self._list.append(row)
            self._rows[index].fill(product)
        for row in self._rows[len(products) :]:
            row.set_visible(False)
        self._stack.set_visible_child_name("list" if products else "blank")

    def _activated(self, _list, row: Gtk.ListBoxRow) -> None:
        if isinstance(row, ProductRow) and row.product is not None:
            self._on_open(row.product)
