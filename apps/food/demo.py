#!/usr/bin/python3
"""Write a history to look at, and a barcode the scanner can still see.

A food-facts app photographs badly against the real thing. Open Food Facts
moves, a container has no camera and no route to the internet, and the one
screen this app is designed to almost never show -- an empty history -- is
the one a check run would otherwise open on.

So this writes three products with invented nutrients (the names and
barcodes are real, because they are facts about the world), a history in
the order they were scanned, and an EAN-13 PNG the camera pipeline can
decode when `MOARCHY_FOOD_PREVIEW` points at it.

`scripts/check.sh` runs this before it runs the app, which is also why a
check run never touches the network: the cache it writes is already there,
the window only fetches when the camera hands it a code, and the run is
over in four seconds with the camera never started.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_food.facts import Nutrient, Product, write_ean13_png  # noqa: E402
from moarchy_food.store import Store  # noqa: E402

# Nutella's EAN-13, which is the barcode every food-facts screenshot in the
# world is of. The nutrients are the real per-100g figures as of 2026-09;
# they are here so the product page has numbers, not so they can be cited.
NUTELLA = "3017620422003"

PRODUCTS = [
    Product(
        code=NUTELLA,
        name="Nutella",
        brand="Ferrero",
        quantity="400 g",
        nutriscore="e",
        nova=4,
        ecoscore="d",
        allergens=("Milk", "Nuts", "Soybeans"),
        ingredients=(
            "Sugar, palm oil, hazelnuts 13%, fat-reduced cocoa 7.4%, "
            "skimmed milk powder 6.6%, whey powder, emulsifiers: lecithins "
            "(soya), vanillin."
        ),
        nutrients=(
            Nutrient("energy-kcal_100g", "Energy", 539, "kcal"),
            Nutrient("fat_100g", "Fat", 30.9, "g"),
            Nutrient("saturated-fat_100g", "Saturates", 10.6, "g"),
            Nutrient("carbohydrates_100g", "Carbohydrates", 57.5, "g"),
            Nutrient("sugars_100g", "Sugars", 56.3, "g"),
            Nutrient("fiber_100g", "Fibre", 0, "g"),
            Nutrient("proteins_100g", "Protein", 6.3, "g"),
            Nutrient("salt_100g", "Salt", 0.107, "g"),
        ),
        image_url="",
        additives=2,
    ),
    Product(
        code="5449000000996",
        name="Coca-Cola",
        brand="Coca-Cola",
        quantity="330 ml",
        nutriscore="e",
        nova=4,
        ecoscore="c",
        allergens=(),
        ingredients="Carbonated water, sugar, colour (caramel E150d), phosphoric acid, natural flavourings including caffeine.",
        nutrients=(
            Nutrient("energy-kcal_100g", "Energy", 42, "kcal"),
            Nutrient("fat_100g", "Fat", 0, "g"),
            Nutrient("carbohydrates_100g", "Carbohydrates", 10.6, "g"),
            Nutrient("sugars_100g", "Sugars", 10.6, "g"),
            Nutrient("proteins_100g", "Protein", 0, "g"),
            Nutrient("salt_100g", "Salt", 0, "g"),
        ),
        image_url="",
    ),
    Product(
        code="8000500037560",
        name="Plain yoghurt",
        brand="Example Dairy",
        quantity="125 g",
        nutriscore="a",
        nova=1,
        ecoscore="b",
        allergens=("Milk",),
        ingredients="Milk, live cultures.",
        nutrients=(
            Nutrient("energy-kcal_100g", "Energy", 61, "kcal"),
            Nutrient("fat_100g", "Fat", 3.2, "g"),
            Nutrient("saturated-fat_100g", "Saturates", 2.1, "g"),
            Nutrient("carbohydrates_100g", "Carbohydrates", 4.7, "g"),
            Nutrient("sugars_100g", "Sugars", 4.7, "g"),
            Nutrient("proteins_100g", "Protein", 3.5, "g"),
            Nutrient("salt_100g", "Salt", 0.1, "g"),
        ),
        image_url="",
    ),
]


def main() -> int:
    target = os.environ.get("MOARCHY_FOOD_DIR")
    if not target:
        print(
            "set MOARCHY_FOOD_DIR first -- refusing to touch real history",
            file=sys.stderr,
        )
        return 2

    store = Store(Path(target))
    # Remembered oldest-first so the last call is the front of the history
    # -- Nutella, which is the product page the screenshots open on.
    for product in reversed(PRODUCTS):
        store.remember(product, when=1.0)
    barcode = Path(target) / "barcode.png"
    write_ean13_png(barcode, NUTELLA)
    print(f"wrote {len(PRODUCTS)} products and {barcode.name} to {store.dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
