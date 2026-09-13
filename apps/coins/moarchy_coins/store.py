"""What survives the app being killed: the stars, and the last prices seen.

Two files, and the split is the whole design of this module.

`favourites.json` is a list of coin ids and is the only thing in this app a
person has made. It is written the instant a star is tapped, through a
temporary file and a rename, because on a phone "the process was killed a
moment after the tap" is the ordinary case: the compositor reclaims backgrounded
apps, and nothing asks first.

`market.json` is the last answer CoinGecko gave. It exists so that an app opened
on a train with no signal opens on prices rather than on an apology, and it is
disposable by definition -- every byte of it is replaced by the next successful
fetch. It is written when the window leaves the screen rather than on each
refresh, because a refresh is once a minute and this file is eighty kilobytes:
an app left open for an hour would otherwise fsync five megabytes onto the
phone's flash to save a copy of something it already had in memory.

The prices are cached; *what they are worth* is not. Nothing here holds a
portfolio, an amount, or a wallet address, and the app never asks for one -- the
whole file is public data plus a list of names, which is what makes leaving it
unencrypted in ~/.local/share an honest decision rather than an oversight.
"""

from __future__ import annotations

import json
import os
import time
from pathlib import Path

from .market import CURRENCY, Coin

SCHEMA = 1

FAVOURITES = "favourites.json"
MARKET = "market.json"

# A guard on the file rather than on the person. Nobody watches two hundred
# coins; a favourites file that says they do has been written by something
# other than this app, and the list is what every refresh iterates.
MAX_FAVOURITES = 200


def data_dir() -> Path:
    """Where this app keeps its two files.

    Overridable, which is what makes the tests and the screenshot harness
    possible without touching anybody's real stars.
    """
    override = os.environ.get("MOARCHY_COINS_DIR")
    if override:
        return Path(override)
    base = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return Path(base) / "moarchy-coins"


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

    A file that cannot be parsed is moved aside rather than left in place to be
    overwritten by the next save, which is the one operation that would destroy
    whatever the user actually had. The same thing Habits does, for the same
    reason: the broken copy is the only evidence of what went wrong.
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
    """The stars, the cached market, and the two files they live in."""

    def __init__(self, directory: Path | str | None = None) -> None:
        self.dir = Path(directory) if directory else data_dir()
        # Coin ids, in the order they were starred. See `starred()`.
        self.favourites: list[str] = []
        self.coins: list[Coin] = []
        self.currency = CURRENCY
        # Wall-clock seconds, because this one is compared against a clock the
        # user can see. Everything about *when to fetch again* is monotonic and
        # lives in the window.
        self.fetched = 0.0

    # --- files -----------------------------------------------------------

    @property
    def favourites_path(self) -> Path:
        return self.dir / FAVOURITES

    @property
    def market_path(self) -> Path:
        return self.dir / MARKET

    def load(self) -> None:
        self._load_favourites()
        self._load_market()

    def _load_favourites(self) -> None:
        data = _read(self.favourites_path)
        raw = data.get("favourites") if data else None
        if not isinstance(raw, list):
            self.favourites = []
            return
        seen: list[str] = []
        for entry in raw:
            # Duplicates would draw a coin twice on the starred page and toggle
            # half of it at a time.
            if isinstance(entry, str) and entry and entry not in seen:
                seen.append(entry)
        self.favourites = seen[:MAX_FAVOURITES]

    def _load_market(self) -> None:
        data = _read(self.market_path)
        if not data:
            return
        records = data.get("coins")
        if not isinstance(records, list):
            return
        coins = []
        for record in records:
            try:
                coins.append(Coin.from_dict(record))
            except (ValueError, TypeError):
                continue
        self.coins = coins
        currency = data.get("currency")
        self.currency = currency.lower() if isinstance(currency, str) else CURRENCY
        fetched = data.get("fetched")
        self.fetched = float(fetched) if isinstance(fetched, (int, float)) else 0.0

    def save_favourites(self) -> None:
        _write(self.favourites_path, {"schema": SCHEMA, "favourites": self.favourites})

    def save_market(self) -> None:
        if not self.coins:
            # Nothing to cache, and writing an empty list would turn "we have
            # never fetched" into "the market is empty" on the next launch.
            return
        _write(
            self.market_path,
            {
                "schema": SCHEMA,
                "currency": self.currency,
                "fetched": self.fetched,
                "coins": [coin.to_dict() for coin in self.coins],
            },
        )

    # --- the stars -------------------------------------------------------

    def is_favourite(self, coin_id: str) -> bool:
        return coin_id in self.favourites

    def toggle(self, coin_id: str) -> bool:
        """Star or unstar a coin. Returns whether it is now starred.

        Appends rather than inserts, which is what makes the starred page read
        in the order things were added to it.
        """
        if coin_id in self.favourites:
            self.favourites.remove(coin_id)
            return False
        if len(self.favourites) >= MAX_FAVOURITES:
            return False
        self.favourites.append(coin_id)
        return True

    def starred(self) -> list[Coin]:
        """The starred coins, in the order they were starred.

        Not in rank order, which is the obvious alternative and is wrong on a
        phone: a watchlist sorted by market cap reorders itself under a thumb
        that is halfway down it, and the one ordering a person can actually
        control -- without a drag handle this app has no room for -- is when
        they added each one.

        A star with no price behind it is left out rather than drawn as a row of
        dashes. That happens for exactly as long as it takes the next fetch to
        ask for it by name, and a row that says nothing about a coin is worse
        than the coin arriving a second later.
        """
        known = {coin.id: coin for coin in self.coins}
        return [known[i] for i in self.favourites if i in known]

    def missing(self) -> list[str]:
        """Starred coins the last answer did not cover.

        Which is what the second request exists for: a coin can only be starred
        from a list of the top hundred, but it can fall out of that list
        afterwards, and a watchlist that quietly goes on showing last week's
        price for it is worse than one that says it cannot.
        """
        known = {coin.id for coin in self.coins}
        return [i for i in self.favourites if i not in known]

    # --- the market ------------------------------------------------------

    def replace(self, coins: list[Coin], *, fetched: float, currency: str) -> None:
        """Take a fetch, keeping at most one row per coin.

        The two requests can overlap -- the second asks for coins by name and
        the first may already have answered for one of them -- so the later
        record wins and the order of the first request is kept, because that
        order is the ranking the market page is drawn in.

        A coin that came back from the second request keeps its real rank, so a
        starred coin that has fallen to 187th sorts to the end of the market
        page rather than into the middle of the top hundred. That is one extra
        row below the hundredth with 187 on it, which is the truthful way for
        the list to answer "where did it go".
        """
        seen: dict[str, Coin] = {}
        for coin in coins:
            seen[coin.id] = coin
        self.coins = sorted(seen.values(), key=lambda coin: coin.rank)
        self.fetched = fetched
        self.currency = currency

    def age(self, now: float | None = None) -> float:
        """How old the cached prices are, in seconds, never negative."""
        if self.fetched <= 0:
            return float("inf")
        return max(0.0, (now if now is not None else time.time()) - self.fetched)
