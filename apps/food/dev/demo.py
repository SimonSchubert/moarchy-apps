#!/usr/bin/python3
"""Write a history to look at, and a barcode the scanner can see.

A food-facts app photographs badly against the real thing: Open Food Facts
moves, a container has no camera and no route to the internet, and the one
screen this app is designed to almost never show -- an empty history -- is
the one a check run would otherwise open on.

So this writes, into MOARCHY_FOOD_DIR, in 0.1.0's shapes:

    history.json    three barcodes, newest first
    products.json   the product for each, with invented nutrients (the names
                    and barcodes are real, because they are facts about the
                    world)
    barcode.png     Nutella's EAN-13, bars and quiet zone, which zbar reads --
                    the still MOARCHY_FOOD_PREVIEW points the scanner at
    scan.txt        a code for the fake scanner to "see" (MOARCHY_FOOD_SCAN_FAKE)
    idle.txt        nothing for it to see, for a picture of the viewfinder

The scanner resolves those two names against MOARCHY_FOOD_DIR, so dev/shots
can name them without knowing where the harness put the directory.

    MOARCHY_FOOD_DIR=/tmp/food python3 apps/food/dev/demo.py
"""

from __future__ import annotations

import json
import os
import struct
import sys
import zlib
from pathlib import Path

NUTELLA = "3017620422003"


def nutrients(*rows):
    return [{"key": k, "label": label, "value": v, "unit": unit} for k, label, v, unit in rows]


PRODUCTS = [
    {
        "code": NUTELLA,
        "name": "Nutella",
        "brand": "Ferrero",
        "quantity": "400 g",
        "nutriscore": "e",
        "nova": 4,
        "ecoscore": "d",
        "allergens": ["Milk", "Nuts", "Soybeans"],
        "ingredients": (
            "Sugar, palm oil, hazelnuts 13%, fat-reduced cocoa 7.4%, skimmed milk "
            "powder 6.6%, whey powder, emulsifiers: lecithins (soya), vanillin."
        ),
        "nutrients": nutrients(
            ("energy-kcal_100g", "Energy", 539, "kcal"),
            ("fat_100g", "Fat", 30.9, "g"),
            ("saturated-fat_100g", "Saturates", 10.6, "g"),
            ("carbohydrates_100g", "Carbohydrates", 57.5, "g"),
            ("sugars_100g", "Sugars", 56.3, "g"),
            ("fiber_100g", "Fibre", 0, "g"),
            ("proteins_100g", "Protein", 6.3, "g"),
            ("salt_100g", "Salt", 0.107, "g"),
        ),
        "image_url": "",
        "additives": 2,
    },
    {
        "code": "5449000000996",
        "name": "Coca-Cola",
        "brand": "Coca-Cola",
        "quantity": "330 ml",
        "nutriscore": "e",
        "nova": 4,
        "ecoscore": "c",
        "allergens": [],
        "ingredients": "Carbonated water, sugar, colour (caramel E150d), phosphoric acid, natural flavourings including caffeine.",
        "nutrients": nutrients(
            ("energy-kcal_100g", "Energy", 42, "kcal"),
            ("fat_100g", "Fat", 0, "g"),
            ("carbohydrates_100g", "Carbohydrates", 10.6, "g"),
            ("sugars_100g", "Sugars", 10.6, "g"),
            ("proteins_100g", "Protein", 0, "g"),
            ("salt_100g", "Salt", 0, "g"),
        ),
        "image_url": "",
        "additives": None,
    },
    {
        "code": "8000500037560",
        "name": "Plain yoghurt",
        "brand": "Example Dairy",
        "quantity": "125 g",
        "nutriscore": "a",
        "nova": 1,
        "ecoscore": "b",
        "allergens": ["Milk"],
        "ingredients": "Milk, live cultures.",
        "nutrients": nutrients(
            ("energy-kcal_100g", "Energy", 61, "kcal"),
            ("fat_100g", "Fat", 3.2, "g"),
            ("saturated-fat_100g", "Saturates", 2.1, "g"),
            ("carbohydrates_100g", "Carbohydrates", 4.7, "g"),
            ("sugars_100g", "Sugars", 4.7, "g"),
            ("proteins_100g", "Protein", 3.5, "g"),
            ("salt_100g", "Salt", 0.1, "g"),
        ),
        "image_url": "",
        "additives": None,
    },
]

# EAN-13 as bars: left-hand A (odd) and B (even) encodings, right-hand C.
_A = {
    "0": "0001101", "1": "0011001", "2": "0010011", "3": "0111101", "4": "0100011",
    "5": "0110001", "6": "0101111", "7": "0111011", "8": "0110111", "9": "0001011",
}
_B = {d: b[::-1].translate(str.maketrans("01", "10")) for d, b in _A.items()}
_C = {d: b.translate(str.maketrans("01", "10")) for d, b in _A.items()}
_P = {
    "0": "AAAAAA", "1": "AABABB", "2": "AABBAB", "3": "AABBBA", "4": "ABAABB",
    "5": "ABBAAB", "6": "ABBBAA", "7": "ABABAB", "8": "ABABBA", "9": "ABBABA",
}


def write_ean13_png(path: Path, code: str, scale: int = 4, quiet: int = 40, height: int = 520) -> None:
    """A scannable EAN-13 as a PNG, on a wide white card so it fills a
    viewfinder the way a packet does."""
    left = "".join(_A[d] if p == "A" else _B[d] for d, p in zip(code[1:7], _P[code[0]], strict=True))
    bits = "101" + left + "01010" + "".join(_C[d] for d in code[7:]) + "101"
    width = (quiet * 2 + len(bits)) * scale
    white, black = b"\xff\xff\xff", b"\x00\x00\x00"
    row = (
        b"\x00"
        + white * quiet * scale
        + b"".join((black if b == "1" else white) * scale for b in bits)
        + white * quiet * scale
    )

    def chunk(tag: bytes, data: bytes) -> bytes:
        crc = struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        return struct.pack(">I", len(data)) + tag + data + crc

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(row * height, 9))
        + chunk(b"IEND", b"")
    )


def main() -> int:
    target = os.environ.get("MOARCHY_FOOD_DIR")
    if not target:
        print("set MOARCHY_FOOD_DIR first -- refusing to touch real history", file=sys.stderr)
        return 2
    out = Path(target)
    out.mkdir(parents=True, exist_ok=True)
    codes = [p["code"] for p in PRODUCTS]
    (out / "history.json").write_text(json.dumps({"schema": 1, "codes": codes}, indent=1) + "\n")
    (out / "products.json").write_text(json.dumps({
        "schema": 1,
        "products": {p["code"]: p for p in PRODUCTS},
        "fetched": {c: 1.0 for c in codes},
    }, ensure_ascii=False, indent=1) + "\n")
    write_ean13_png(out / "barcode.png", NUTELLA)
    (out / "scan.txt").write_text(f"EAN-13 {NUTELLA}\n")
    (out / "idle.txt").write_text("# nothing in front of the lens\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
