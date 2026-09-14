"""Open Food Facts: one barcode in, one product out.

Nothing here imports GTK, which is what makes the half of this app that can be
wrong -- parsing somebody else's JSON, and turning a grade into the letter a
person reads -- testable on any machine with a Python. The same split Coins
has between `market.py` and its window, and for the same reason.

**The endpoint is `/api/v2/product/{code}`, once, for the barcode just
scanned.** One request returns the name, the scores, the nutrients and the
allergens, which is every fact this app draws. A search-by-name endpoint
exists and is not used: this app has no keyboard for a reason, and a typed
query is a different job.

**No API key.** Open Food Facts asks only that the User-Agent name the app,
so a flood can be recognised as one client rather than as the carrier NAT
behind a hundred phones. A 429 is an ordinary answer rather than an error --
`FactsError.retry_after` carries what to do about it and the window backs off.

**Every field is optional.** A product with no Nutri-Score, no photo and no
ingredients is still a product: the barcode was on a shelf. Each missing
field is dropped or drawn as a dash rather than being allowed to raise.
"""

from __future__ import annotations

import http.client
import json
import math
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass

API = "https://world.openfoodfacts.org/api/v2/product/"

# Who is asking. Open Food Facts refuses a generic Python UA and asks that
# the client name itself, with a way to reach the person who ships it.
AGENT = "moarchy-food/0.1.0 (+https://github.com/SimonSchubert/moarchy-apps)"

# Twelve seconds. A phone on a cell connection is slow rather than absent, and
# the fetch is on a thread either way, so nothing is waiting on this but the
# word "Looking up" on the scan page.
TIMEOUT = 12.0

# The most a response may be before it is refused unread. A product record is
# tens of kilobytes with the fields this app asks for; four megabytes is a
# body that has gone wrong, and on a metered connection an unbounded read is
# the expensive kind of wrong.
MAX_BYTES = 4 * 1024 * 1024

# A front-of-pack JPEG is a few tens of kilobytes. Half a megabyte is a URL
# that did not point at a thumbnail.
MAX_IMAGE_BYTES = 512 * 1024

# What a 429 costs when the answer did not say how long to wait.
RATE_LIMIT_S = 60.0

# The fields the product page actually draws. Asking for the whole record is
# a 200 kB habit for a screen that shows twelve numbers.
FIELDS = (
    "code",
    "product_name",
    "product_name_en",
    "brands",
    "quantity",
    "nutriscore_grade",
    "nova_group",
    "ecoscore_grade",
    "allergens_tags",
    "traces_tags",
    "ingredients_text",
    "ingredients_text_en",
    "nutriments",
    "image_front_small_url",
    "additives_n",
)

# Nutri-Score and Eco-Score share the same five letters. "unknown" and
# "not-applicable" are how the API says the grade is not a grade.
GRADES = ("a", "b", "c", "d", "e")

NOVA_LABELS = {
    1: "Unprocessed",
    2: "Ingredients",
    3: "Processed",
    4: "Ultra-processed",
}

# Per 100 g, in the order a nutrition table is read. The keys are Open Food
# Facts' own; the labels are what a person expects to see next to them.
NUTRIENTS = (
    ("energy-kcal_100g", "Energy", "kcal"),
    ("fat_100g", "Fat", "g"),
    ("saturated-fat_100g", "Saturates", "g"),
    ("carbohydrates_100g", "Carbohydrates", "g"),
    ("sugars_100g", "Sugars", "g"),
    ("fiber_100g", "Fibre", "g"),
    ("proteins_100g", "Protein", "g"),
    ("salt_100g", "Salt", "g"),
)

# zbar's names for the codes a packet of food actually carries. QR is a URL
# more often than a barcode, and this app has nowhere to put a URL.
PRODUCT_KINDS = {
    "EAN-13",
    "EAN-8",
    "EAN13",
    "EAN8",
    "UPC-A",
    "UPC-E",
    "UPCA",
    "UPCE",
    "ISBN-13",
    "ISBN-10",
}

DASH = "—"


class FactsError(Exception):
    """Something a person can be told, and a hint about when to try again.

    Every failure in this module arrives as one of these carrying a sentence
    in plain words, because all of them end up in the same place: a toast over
    the scanner, or a page that says the barcode is not in the catalogue.
    `missing` is a 404 of the product, not of the network: the camera worked
    and Open Food Facts has never heard of this packet. `retry_after` is
    seconds, and is 0 when the answer carried no such advice.
    """

    def __init__(
        self,
        message: str,
        *,
        retry_after: float = 0.0,
        missing: bool = False,
    ) -> None:
        super().__init__(message)
        self.retry_after = retry_after
        self.missing = missing


@dataclass(frozen=True)
class Nutrient:
    key: str
    label: str
    value: float
    unit: str

    def drawn(self) -> str:
        if self.unit == "kcal":
            return f"{self.value:.0f} kcal"
        if abs(self.value - round(self.value)) < 0.05:
            return f"{round(self.value):.0f} g"
        if self.value >= 1:
            return f"{self.value:.1f} g"
        return f"{self.value:.2f} g"


@dataclass(frozen=True)
class Product:
    """Everything drawn about a food, and nothing else.

    Deliberately not the whole record. The endpoint can return hundreds of
    fields -- traces of traces, a full ingredient tree, images in four sizes
    -- and this app draws a name, three grades, a table and a sentence of
    allergens. Keeping the rest would invite a page to be built out of
    whatever happened to be lying around rather than out of a request made
    for it.
    """

    code: str
    name: str
    brand: str
    quantity: str
    nutriscore: str
    nova: int | None
    ecoscore: str
    allergens: tuple[str, ...]
    ingredients: str
    nutrients: tuple[Nutrient, ...]
    image_url: str
    additives: int | None = None

    @property
    def subtitle(self) -> str:
        parts = [p for p in (self.brand, self.quantity) if p]
        return " · ".join(parts)

    @property
    def nova_label(self) -> str:
        if self.nova is None:
            return DASH
        return NOVA_LABELS.get(self.nova, f"NOVA {self.nova}")

    def to_dict(self) -> dict:
        return {
            "code": self.code,
            "name": self.name,
            "brand": self.brand,
            "quantity": self.quantity,
            "nutriscore": self.nutriscore,
            "nova": self.nova,
            "ecoscore": self.ecoscore,
            "allergens": list(self.allergens),
            "ingredients": self.ingredients,
            "nutrients": [
                {
                    "key": n.key,
                    "label": n.label,
                    "value": n.value,
                    "unit": n.unit,
                }
                for n in self.nutrients
            ],
            "image_url": self.image_url,
            "additives": self.additives,
        }

    @classmethod
    def from_dict(cls, data: dict) -> Product:
        """One product back out of our own cache file.

        Separate from `parse` below on purpose: that reads Open Food Facts'
        shape and this reads ours. Folding them together would mean a change
        to the API's field names quietly rewriting what a cache written last
        week means.
        """
        if not isinstance(data, dict):
            raise TypeError("product is not a table")
        code = str(data.get("code") or "")
        name = str(data.get("name") or "")
        if not code or not name:
            raise ValueError("product has no code or no name")
        nutrients = []
        raw = data.get("nutrients")
        if isinstance(raw, list):
            for row in raw:
                if not isinstance(row, dict):
                    continue
                value = _number(row.get("value"))
                if value is None:
                    continue
                nutrients.append(
                    Nutrient(
                        key=str(row.get("key") or ""),
                        label=str(row.get("label") or ""),
                        value=value,
                        unit=str(row.get("unit") or "g"),
                    )
                )
        allergens = data.get("allergens") or ()
        if not isinstance(allergens, (list, tuple)):
            allergens = ()
        nova = data.get("nova")
        nova_n = int(nova) if isinstance(nova, int) and 1 <= nova <= 4 else None
        additives = data.get("additives")
        additives_n = (
            int(additives) if isinstance(additives, int) and additives >= 0 else None
        )
        return cls(
            code=code,
            name=name,
            brand=str(data.get("brand") or ""),
            quantity=str(data.get("quantity") or ""),
            nutriscore=_grade(data.get("nutriscore")),
            nova=nova_n,
            ecoscore=_grade(data.get("ecoscore")),
            allergens=tuple(str(a) for a in allergens if a),
            ingredients=str(data.get("ingredients") or ""),
            nutrients=tuple(nutrients),
            image_url=str(data.get("image_url") or ""),
            additives=additives_n,
        )


def _number(value: object) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    number = float(value)
    return None if math.isnan(number) or math.isinf(number) else number


def _grade(value: object) -> str:
    if not isinstance(value, str):
        return ""
    letter = value.strip().lower()
    return letter if letter in GRADES else ""


def _tag_label(tag: object) -> str:
    """`en:milk` becomes `Milk`. Anything else is left alone."""
    if not isinstance(tag, str) or not tag:
        return ""
    name = tag.split(":", 1)[-1].replace("-", " ").strip()
    return name[:1].upper() + name[1:] if name else ""


def _first_brand(value: object) -> str:
    if not isinstance(value, str):
        return ""
    return value.split(",")[0].strip()


def _text(*candidates: object) -> str:
    for value in candidates:
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def parse(payload: object, *, scanned: str = "") -> Product:
    """One product out of Open Food Facts' shape.

    `status` 0 is a missing product, not a malformed one: the barcode was
    read correctly and the catalogue has no row for it. That is a page of
    its own rather than a toast, because it is the ordinary end of pointing
    the camera at a local brand the project has not photographed yet.
    """
    if not isinstance(payload, dict):
        raise FactsError("Open Food Facts sent something that is not a product.")
    status = payload.get("status")
    if status == 0:
        code = str(payload.get("code") or scanned or "")
        raise FactsError(
            f"Nothing in Open Food Facts for {code}."
            if code
            else "Nothing in Open Food Facts for this barcode.",
            missing=True,
        )
    record = payload.get("product")
    if not isinstance(record, dict):
        raise FactsError(
            "Open Food Facts sent a product in a shape this app cannot read."
        )
    code = str(record.get("code") or payload.get("code") or scanned or "")
    name = _text(record.get("product_name_en"), record.get("product_name"))
    if not code or not name:
        raise FactsError("Open Food Facts sent a product with no name.")
    nutriments = record.get("nutriments")
    nutrients: list[Nutrient] = []
    if isinstance(nutriments, dict):
        for key, label, unit in NUTRIENTS:
            value = _number(nutriments.get(key))
            if value is None:
                continue
            nutrients.append(Nutrient(key=key, label=label, value=value, unit=unit))
    allergens = []
    tags = record.get("allergens_tags")
    if isinstance(tags, list):
        for tag in tags:
            label = _tag_label(tag)
            if label and label not in allergens:
                allergens.append(label)
    nova = record.get("nova_group")
    nova_n = int(nova) if isinstance(nova, int) and 1 <= nova <= 4 else None
    additives = _number(record.get("additives_n"))
    image = record.get("image_front_small_url") or record.get("image_url") or ""
    return Product(
        code=code,
        name=name,
        brand=_first_brand(record.get("brands")),
        quantity=_text(record.get("quantity")),
        nutriscore=_grade(record.get("nutriscore_grade")),
        nova=nova_n,
        ecoscore=_grade(record.get("ecoscore_grade")),
        allergens=tuple(allergens),
        ingredients=_text(
            record.get("ingredients_text_en"), record.get("ingredients_text")
        ),
        nutrients=tuple(nutrients),
        image_url=str(image) if isinstance(image, str) else "",
        additives=int(additives) if additives is not None and additives >= 0 else None,
    )


# --- barcodes ------------------------------------------------------------


def ean_checksum(digits: str) -> int:
    """The check digit for an EAN/UPC body, from the right.

    Positions from the right (the check digit not among them) alternate
    ×3 and ×1, starting with ×3. The check digit is what makes the sum
    a multiple of ten. This is the whole of why a scan of a crumpled
    packet can be rejected before it becomes a request.
    """
    total = 0
    for index, char in enumerate(reversed(digits)):
        total += int(char) * (3 if index % 2 == 0 else 1)
    return (10 - (total % 10)) % 10


def _all_digits(text: str) -> str:
    return "".join(c for c in text if c.isdigit())


def expand_upce(code: str) -> str | None:
    """UPC-E (7 or 8 digits) to a 12-digit UPC-A, or None if it is not one."""
    digits = _all_digits(code)
    if len(digits) == 8:
        ns, body, check = digits[0], digits[1:7], digits[7]
    elif len(digits) == 7:
        ns, body, check = "0", digits[:6], digits[6]
    else:
        return None
    if ns not in "01":
        return None
    last = body[5]
    if last in "012":
        middle = body[0:2] + last + "0000" + body[2:5]
    elif last == "3":
        middle = body[0:3] + "00000" + body[3:5]
    elif last == "4":
        middle = body[0:4] + "00000" + body[4]
    else:
        middle = body[0:5] + "0000" + last
    upca = ns + middle
    if ean_checksum(upca) != int(check):
        return None
    return upca + check


def normalize_barcode(text: str) -> str | None:
    """A barcode Open Food Facts will accept, or None.

    UPC-A is padded to EAN-13 with a leading zero, which is the same
    number and the form the catalogue is keyed on. A code whose check
    digit is wrong is not sent: the camera misread it, and a 404 for a
    number that never existed is a worse sentence than scanning again.
    """
    digits = _all_digits(text)
    if not digits:
        return None
    if len(digits) == 8:
        # Could be EAN-8 or UPC-E. EAN-8 first: its checksum is on 7 digits.
        if ean_checksum(digits[:7]) == int(digits[7]):
            return digits
        expanded = expand_upce(digits)
        return ("0" + expanded) if expanded else None
    if len(digits) == 12:
        if ean_checksum(digits[:11]) != int(digits[11]):
            return None
        return "0" + digits
    if len(digits) == 13:
        if ean_checksum(digits[:12]) != int(digits[12]):
            return None
        return digits
    if len(digits) == 7:
        expanded = expand_upce(digits)
        return ("0" + expanded) if expanded else None
    return None


def from_scan(kind: str, symbol: str) -> str | None:
    """A product barcode out of a zbar message, or None.

    QR codes are dropped even when they contain digits: a QR on a packet is
    almost always a URL, and this app has no browser in it. The kinds a
    packet of food actually prints are the EAN and UPC family.
    """
    family = (kind or "").upper().replace("_", "-")
    aliases = PRODUCT_KINDS | {k.replace("-", "") for k in PRODUCT_KINDS}
    # An empty kind with a plausible digit string is allowed: some pipelines
    # emit the digits and nothing else. A kind we do not know is not a
    # product code — a QR on a packet is a URL, not a lookup.
    if family and family not in aliases and family.replace("-", "") not in aliases:
        return None
    return normalize_barcode(symbol)


# --- EAN-13 as bars, for a still the scanner can read --------------------

# Left-hand A (odd) encodings, then B (even); right-hand is A inverted.
_EAN_A = {
    "0": "0001101",
    "1": "0011001",
    "2": "0010011",
    "3": "0111101",
    "4": "0100011",
    "5": "0110001",
    "6": "0101111",
    "7": "0111011",
    "8": "0110111",
    "9": "0001011",
}
_EAN_B = {
    d: bits[::-1].translate(str.maketrans("01", "10")) for d, bits in _EAN_A.items()
}
_EAN_C = {d: bits.translate(str.maketrans("01", "10")) for d, bits in _EAN_A.items()}
_EAN_PARITY = {
    "0": "AAAAAA",
    "1": "AABABB",
    "2": "AABBAB",
    "3": "AABBBA",
    "4": "ABAABB",
    "5": "ABBAAB",
    "6": "ABBBAA",
    "7": "ABABAB",
    "8": "ABABBA",
    "9": "ABBABA",
}


def ean13_modules(code: str) -> str:
    """95 bits of an EAN-13, including the start/middle/end guards.

    Used to draw a still the camera pipeline can decode, so a screenshot of
    the scanner is a picture of a barcode rather than of a black rectangle.
    """
    digits = normalize_barcode(code)
    if digits is None or len(digits) != 13:
        raise ValueError("not an EAN-13")
    first, left, right = digits[0], digits[1:7], digits[7:13]
    parity = _EAN_PARITY[first]
    bits = ["101"]
    for digit, side in zip(left, parity, strict=True):
        bits.append(_EAN_A[digit] if side == "A" else _EAN_B[digit])
    bits.append("01010")
    for digit in right:
        bits.append(_EAN_C[digit])
    bits.append("101")
    return "".join(bits)


def write_ean13_png(
    path, code: str, *, scale: int = 3, quiet: int = 12, height: int = 80
) -> None:
    """A scannable EAN-13 as a PNG, no library required.

    The scanner's demo still is this file: a real barcode, quiet zone and
    all, so zbar has something to read when there is no camera.
    """
    import struct
    import zlib
    from pathlib import Path

    modules = ean13_modules(code)
    width = (quiet * 2 + len(modules)) * scale
    rows = []
    for _ in range(height):
        row = bytearray()
        row.append(0)  # PNG filter: none
        for _ in range(quiet * scale):
            row.extend(b"\xff\xff\xff")
        for bit in modules:
            pixel = b"\x00\x00\x00" if bit == "1" else b"\xff\xff\xff"
            for _ in range(scale):
                row.extend(pixel)
        for _ in range(quiet * scale):
            row.extend(b"\xff\xff\xff")
        rows.append(bytes(row))
    raw = b"".join(rows)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    Path(path).write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


# --- the wire ------------------------------------------------------------


def _retry_after(error: urllib.error.HTTPError) -> float:
    header = error.headers.get("Retry-After") if error.headers else None
    if isinstance(header, str) and header.strip().isdigit():
        return float(header.strip())
    return 0.0


def _get(url: str, *, timeout: float = TIMEOUT, limit: int = MAX_BYTES) -> bytes:
    request = urllib.request.Request(
        url, headers={"User-Agent": AGENT, "Accept": "application/json"}
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read(limit + 1)
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            raise FactsError(
                "Nothing in Open Food Facts for this barcode.", missing=True
            ) from exc
        if exc.code == 429:
            raise FactsError(
                "Open Food Facts is rate-limiting this connection.",
                retry_after=_retry_after(exc) or RATE_LIMIT_S,
            ) from exc
        if 500 <= exc.code < 600:
            raise FactsError("Open Food Facts is having trouble.") from exc
        raise FactsError(f"Open Food Facts refused the request ({exc.code}).") from exc
    except (OSError, http.client.HTTPException) as exc:
        raise FactsError("No answer from Open Food Facts.") from exc
    if len(raw) > limit:
        raise FactsError("Open Food Facts sent more than this app will read.")
    return raw


class Live:
    """Open Food Facts over HTTPS, which is the only thing in this app that is.

    An object rather than a function so the window can be handed something
    else entirely: the tests pass a stand-in with this one method, and
    `MOARCHY_FOOD_OFFLINE` passes nothing at all.
    """

    def __init__(self, *, timeout: float = TIMEOUT) -> None:
        self.timeout = timeout

    def product(self, code: str) -> Product:
        barcode = normalize_barcode(code)
        if barcode is None:
            raise FactsError("That barcode is not a product code.")
        query = urllib.parse.urlencode({"fields": ",".join(FIELDS)})
        url = f"{API}{urllib.parse.quote(barcode)}?{query}"
        raw = _get(url, timeout=self.timeout)
        try:
            payload = json.loads(raw)
        except ValueError as exc:
            raise FactsError(
                "Open Food Facts sent something that is not JSON."
            ) from exc
        return parse(payload, scanned=barcode)

    def image(self, url: str) -> bytes:
        """The front-of-pack thumbnail, or raise. Never called with a page URL."""
        if not url.startswith(("https://", "http://")):
            raise FactsError("Product image is not an HTTP URL.")
        return _get(url, timeout=self.timeout, limit=MAX_IMAGE_BYTES)


def freshness(seconds: float) -> str:
    if seconds < 60:
        return "just now"
    if seconds < 3600:
        return f"{int(seconds // 60)} min ago"
    if seconds < 86400:
        hours = int(seconds // 3600)
        return f"{hours} hour ago" if hours == 1 else f"{hours} hours ago"
    days = int(seconds // 86400)
    return "yesterday" if days == 1 else f"{days} days ago"
