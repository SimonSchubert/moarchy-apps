"""What survives the app being killed: the last products scanned.

Two files, and the split is the same one Coins makes.

`history.json` is a list of barcodes in the order they were scanned and is
the only thing in this app a person has made. It is written the instant a
lookup succeeds, through a temporary file and a rename, because on a phone
"the process was killed a moment after the scan" is the ordinary case: the
compositor reclaims backgrounded apps, and nothing asks first.

`products.json` is the last answer Open Food Facts gave for each barcode. It
exists so that opening a row in the history on a train with no signal opens
on facts rather than on an apology, and so that scanning the same packet
twice in a shop does not cost a second request.

The facts are cached; *what you ate* is not. Nothing here holds a diary, a
portion or a calorie goal -- the whole file is public data plus a list of
barcodes, which is what makes leaving it unencrypted in ~/.local/share an
honest decision rather than an oversight.
"""

from __future__ import annotations

import json
import os
import time
from pathlib import Path

from .facts import Product

SCHEMA = 1

HISTORY = "history.json"
PRODUCTS = "products.json"

# A guard on the file rather than on the person. Nobody scans two hundred
# packets in a sitting; a history that says they did has been written by
# something other than this app.
MAX_HISTORY = 100


def data_dir() -> Path:
    """Where this app keeps its two files.

    Overridable, which is what makes the tests and the screenshot harness
    possible without touching anybody's real history.
    """
    override = os.environ.get("MOARCHY_FOOD_DIR")
    if override:
        return Path(override)
    base = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return Path(base) / "moarchy-food"


def _write(path: Path, payload: dict) -> None:
    """Temporary file, fsync, rename. See the header."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    with tmp.open("w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=1)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, path)


def _read(path: Path) -> dict | None:
    """The file as a table, or None for anything else.

    A file that cannot be parsed is moved aside rather than left in place to
    be overwritten by the next save, which is the one operation that would
    destroy whatever the user actually had.
    """
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError:
        return None
    try:
        data = json.loads(raw)
    except ValueError:
        try:
            path.rename(path.with_suffix(f".broken-{int(time.time())}.json"))
        except OSError:
            pass
        return None
    return data if isinstance(data, dict) else None


class Store:
    """The history, the cached products, and the two files they live in."""

    def __init__(self, directory: Path | str | None = None) -> None:
        self.dir = Path(directory) if directory else data_dir()
        # Barcodes, newest first.
        self.history: list[str] = []
        self.products: dict[str, Product] = {}
        # Wall-clock seconds of the last successful lookup, per code.
        self.fetched: dict[str, float] = {}

    @property
    def history_path(self) -> Path:
        return self.dir / HISTORY

    @property
    def products_path(self) -> Path:
        return self.dir / PRODUCTS

    def load(self) -> None:
        self._load_history()
        self._load_products()

    def _load_history(self) -> None:
        data = _read(self.history_path)
        if data is None:
            return
        codes = data.get("codes")
        if not isinstance(codes, list):
            return
        seen: list[str] = []
        for code in codes:
            if isinstance(code, str) and code and code not in seen:
                seen.append(code)
            if len(seen) >= MAX_HISTORY:
                break
        self.history = seen

    def _load_products(self) -> None:
        data = _read(self.products_path)
        if data is None:
            return
        records = data.get("products")
        if not isinstance(records, dict):
            return
        fetched = data.get("fetched")
        if not isinstance(fetched, dict):
            fetched = {}
        for code, record in records.items():
            if not isinstance(record, dict):
                continue
            try:
                product = Product.from_dict(record)
            except (TypeError, ValueError):
                continue
            self.products[str(code)] = product
            stamp = fetched.get(code)
            if isinstance(stamp, (int, float)) and stamp > 0:
                self.fetched[str(code)] = float(stamp)

    def save_history(self) -> None:
        _write(self.history_path, {"schema": SCHEMA, "codes": list(self.history)})

    def save_products(self) -> None:
        _write(
            self.products_path,
            {
                "schema": SCHEMA,
                "products": {
                    code: product.to_dict() for code, product in self.products.items()
                },
                "fetched": dict(self.fetched),
            },
        )

    def remember(self, product: Product, *, when: float | None = None) -> None:
        """Put this product at the front of the history and on disk.

        Called the moment a lookup succeeds, before the page is even pushed:
        the next thing that happens to a phone app is usually being killed.
        A code already in the list is moved to the front rather than
        duplicated, so scanning the same packet twice is a refresh, not a
        second row.
        """
        self.products[product.code] = product
        self.fetched[product.code] = when if when is not None else time.time()
        self.history = [product.code] + [c for c in self.history if c != product.code]
        self.history = self.history[:MAX_HISTORY]
        # Drop cached products that have fallen off the history, so the file
        # cannot grow without bound from a weekend of shopping.
        keep = set(self.history)
        self.products = {c: p for c, p in self.products.items() if c in keep}
        self.fetched = {c: t for c, t in self.fetched.items() if c in keep}
        self.save_history()
        self.save_products()

    def get(self, code: str) -> Product | None:
        return self.products.get(code)

    def recent(self) -> list[Product]:
        """History as products, skipping any barcode whose cache is gone."""
        return [self.products[c] for c in self.history if c in self.products]
