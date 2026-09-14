"""The product page: a name, three grades, a table, the allergens.

Built as one scrolling column at 360px. The Nutri-Score is the size of a
thumb because it is the one fact a person in a supermarket aisle actually
came for; the table under it is what they stay for.
"""

from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gtk, Pango  # noqa: E402

from .facts import DASH, Product  # noqa: E402
from .widgets import GradeBadge  # noqa: E402


class ProductView(Gtk.Box):
    """One product, filled in place when a lookup returns."""

    __gtype_name__ = "FoodProductView"

    def __init__(self) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.add_css_class("product")
        self.product: Product | None = None

        self.hero = Gtk.Picture()
        self.hero.add_css_class("hero")
        self.hero.set_content_fit(Gtk.ContentFit.CONTAIN)
        self.hero.set_size_request(-1, 140)
        self.hero.set_hexpand(True)
        self.hero.set_visible(False)
        self.append(self.hero)

        self._name = Gtk.Label(xalign=0.0, wrap=True)
        self._name.add_css_class("product-name")
        self._name.set_wrap_mode(Pango.WrapMode.WORD_CHAR)
        self.append(self._name)

        self._note = Gtk.Label(xalign=0.0, wrap=True)
        self._note.add_css_class("product-note")
        self.append(self._note)

        badges = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16)
        badges.set_halign(Gtk.Align.CENTER)
        badges.set_margin_top(4)
        badges.set_margin_bottom(4)
        self._nutri = GradeBadge("Nutri-Score")
        self._nova = GradeBadge("NOVA")
        self._eco = GradeBadge("Eco-Score")
        badges.append(self._nutri)
        badges.append(self._nova)
        badges.append(self._eco)
        self.append(badges)

        self._table = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self._table.add_css_class("card")
        self._table.set_margin_top(4)
        self.append(self._table)

        self._allergens = Gtk.Label(xalign=0.0, wrap=True)
        self._allergens.add_css_class("allergens")
        self._allergens.set_wrap_mode(Pango.WrapMode.WORD_CHAR)
        self.append(self._allergens)

        self._ingredients = Gtk.Label(xalign=0.0, wrap=True)
        self._ingredients.add_css_class("ingredients")
        self._ingredients.set_wrap_mode(Pango.WrapMode.WORD_CHAR)
        self.append(self._ingredients)

    def fill(self, product: Product) -> None:
        self.product = product
        self.hero.set_visible(False)
        self._name.set_label(product.name)
        self._note.set_label(product.subtitle or product.code)
        self._nutri.fill(product.nutriscore)
        self._nova.fill("", fallback=str(product.nova) if product.nova else DASH)
        # NOVA is a number, not a letter of the Nutri-Score alphabet, so the
        # caption carries the words and the badge carries 1-4.
        self._nova.set_caption(product.nova_label if product.nova else "NOVA")
        self._eco.fill(product.ecoscore)

        while (child := self._table.get_first_child()) is not None:
            self._table.remove(child)
        if product.nutrients:
            heading = Gtk.Label(label="Per 100 g", xalign=0.0)
            heading.add_css_class("product-note")
            heading.set_margin_bottom(4)
            self._table.append(heading)
            for nutrient in product.nutrients:
                row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
                row.add_css_class("nutrient-row")
                label = Gtk.Label(label=nutrient.label, xalign=0.0, hexpand=True)
                label.add_css_class("nutrient-label")
                value = Gtk.Label(label=nutrient.drawn(), xalign=1.0)
                value.add_css_class("nutrient-value")
                row.append(label)
                row.append(value)
                self._table.append(row)
        self._table.set_visible(bool(product.nutrients))

        if product.allergens:
            self._allergens.set_label("Allergens: " + " · ".join(product.allergens))
            self._allergens.set_visible(True)
        else:
            self._allergens.set_visible(False)

        if product.ingredients:
            self._ingredients.set_label(product.ingredients)
            self._ingredients.set_visible(True)
        else:
            self._ingredients.set_visible(False)


class MissingView(Gtk.Box):
    """A barcode that scanned cleanly and is not in the catalogue."""

    __gtype_name__ = "FoodMissingView"

    def __init__(self) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.code = ""
        page = Adw.StatusPage()
        page.set_icon_name("dialog-information-symbolic")
        page.set_title("Not in Open Food Facts")
        self._body = Gtk.Label(wrap=True)
        self._body.add_css_class("product-note")
        self._body.set_justify(Gtk.Justification.CENTER)
        page.set_child(self._body)
        page.set_vexpand(True)
        self.append(page)

    def fill(self, code: str) -> None:
        self.code = code
        self._body.set_label(
            f"{code} is a real barcode, and the catalogue has no product for it. "
            "Scan another."
        )
