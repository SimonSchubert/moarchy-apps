"""The window, driven by calling it rather than by tapping it.

Needs a display. Skipped where there is none, so `python3 -m unittest` on a
machine without GTK still runs the arithmetic and the file formats.

Two things get particular attention, because they are the two the user
asked for. A barcode cannot be typed: there is no `Gtk.Entry` in the tree.
And a code can only arrive from the camera: the tests hand the window a
stand-in that emits one.
"""

from __future__ import annotations

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
    from moarchy_food.window import FoodWindow

from moarchy_food.facts import FactsError, Nutrient, Product  # noqa: E402
from moarchy_food.store import Store  # noqa: E402

KNOBS = (
    "PAGE",
    "CODE",
    "DIR",
    "OFFLINE",
    "QUIT_AFTER",
    "CAMERA",
    "PREVIEW",
    "SCAN_ONLY",
)

NUTELLA = Product(
    code="3017620422003",
    name="Nutella",
    brand="Ferrero",
    quantity="400 g",
    nutriscore="e",
    nova=4,
    ecoscore="d",
    allergens=("Milk", "Nuts"),
    ingredients="Sugar, palm oil, hazelnuts.",
    nutrients=(Nutrient("energy-kcal_100g", "Energy", 539, "kcal"),),
    image_url="",
)


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


def walk(widget):
    yield widget
    child = widget.get_first_child() if hasattr(widget, "get_first_child") else None
    while child is not None:
        yield from walk(child)
        child = child.get_next_sibling()


class FakeCamera:
    def __init__(self, picture=None) -> None:
        self._on_code = None
        self.running = False
        self.reason = ""
        self.started = 0
        self.stopped = 0

    def on_code(self, callback) -> None:
        self._on_code = callback

    def start(self) -> bool:
        self.started += 1
        self.running = True
        self.reason = ""
        return True

    def stop(self) -> None:
        self.stopped += 1
        self.running = False

    def emit(self, code: str) -> None:
        if self._on_code is not None:
            self._on_code(code)


class Fake:
    def __init__(self, answer=None, *, trouble: FactsError | None = None) -> None:
        self.answer = answer if answer is not None else NUTELLA
        self.trouble = trouble
        self.asked: list[str] = []

    def product(self, code: str) -> Product:
        self.asked.append(code)
        if self.trouble is not None:
            raise self.trouble
        if isinstance(self.answer, Product):
            return self.answer
        raise FactsError("no product", missing=True)

    def image(self, url: str) -> bytes:
        raise FactsError("no image")


@unittest.skipIf(REASON, REASON)
class WindowActions(unittest.TestCase):
    def setUp(self):
        for knob in KNOBS:
            os.environ.pop(f"MOARCHY_FOOD_{knob}", None)
        os.environ["MOARCHY_FOOD_CAMERA"] = "0"
        self.dir = TemporaryDirectory()
        os.environ["MOARCHY_FOOD_DIR"] = self.dir.name
        self.store = Store(self.dir.name)
        self.camera = FakeCamera()
        self.source = Fake()
        self.window = FoodWindow(self.store, self.source, camera=self.camera)
        self.addCleanup(self.window.destroy)
        self.addCleanup(self.dir.cleanup)

    def test_there_is_no_place_to_type_a_barcode(self):
        """The user asked for a camera, and for no manual input. The tree
        is the proof: an Entry anywhere in it would be a typed barcode
        wearing a placeholder's clothes.
        """
        typed = [
            w.__class__.__name__
            for w in walk(self.window)
            if isinstance(w, (Gtk.Editable, Gtk.TextView))
            or w.__class__.__name__ in {"Entry", "SearchEntry", "PasswordEntry"}
        ]
        # Gtk.Label can be selectable (ingredients) and still is not typed.
        typed = [n for n in typed if n != "Label"]
        self.assertEqual(typed, [])

    def test_a_scan_looks_the_code_up_and_opens_the_product(self):
        self.window._on_map()
        self.camera.emit(NUTELLA.code)
        self.assertTrue(
            pump(lambda: self.store.get(NUTELLA.code) is not None),
            "the product never landed in the store",
        )
        self.assertEqual(self.source.asked, [NUTELLA.code])
        self.assertEqual(self.store.history, [NUTELLA.code])
        page = self.window._nav.get_visible_page()
        self.assertIsNotNone(page)
        self.assertNotEqual(page.get_tag(), "home")

    def test_a_missing_product_is_a_page_not_a_text_field(self):
        self.source.trouble = FactsError(
            "Nothing in Open Food Facts for 0000000000000.", missing=True
        )
        self.camera.emit("0000000000000")

        def opened() -> bool:
            page = self.window._nav.get_visible_page()
            return page is not None and page.get_tag() != "home"

        self.assertTrue(pump(opened), "the missing page never opened")
        page = self.window._nav.get_visible_page()
        self.assertTrue(page.get_tag().startswith("missing-"))

    def test_history_lists_what_was_scanned(self):
        self.store.remember(NUTELLA)
        self.window._refill_history()
        self.window._stack.set_visible_child_name("history")
        visible = [row for row in self.window.history_page._rows if row.get_visible()]
        self.assertEqual(len(visible), 1)
        self.assertEqual(visible[0].product.name, "Nutella")

    def test_offline_opens_a_cached_product_and_does_not_fetch(self):
        self.store.remember(NUTELLA)
        self.window.source = None
        self.camera.emit(NUTELLA.code)
        self.assertEqual(self.source.asked, [])
        page = self.window._nav.get_visible_page()
        self.assertTrue(page.get_tag().startswith("product-"))
