"""The market: what CoinGecko says, and what a phone can do with it.

Nothing here imports GTK, which is what makes the half of this app that can be
wrong -- parsing somebody else's JSON, and turning a number into the string a
person reads -- testable on any machine with a Python. The same split Habits
has between `habits.py` and its window, and for the same reason.

**The endpoint is `/coins/markets`, once, for the whole list.** One request
returns a hundred coins with their price, their rank, their cap and their day,
which is every number this app draws. The alternative -- `/simple/price` per
coin, or the per-coin endpoint for a detail page -- is a hundred requests for
the same screen, on a connection that is metered and a radio that is the second
biggest battery draw on the phone.

**No API key is required and one is used if offered.** The keyless tier is
rate-limited per IP at somewhere around five to fifteen calls a minute, shared
with everybody else behind the same carrier NAT, so a 429 is an ordinary
answer rather than an error -- `MarketError.retry_after` carries what to do
about it and the window backs off. `MOARCHY_COINS_KEY` is sent as
`x-cg-demo-api-key` for anybody who has registered one.

**Every number is optional.** A new listing has no rank, a coin that has not
traded today has no 24-hour change, and a delisted one has no price at all.
Each is dropped or drawn as a dash rather than being allowed to raise: a list
of a hundred coins that refuses to draw because the eighty-third has a null in
it is the failure mode to design against.
"""

from __future__ import annotations

import http.client
import json
import math
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass

API = "https://api.coingecko.com/api/v3/coins/markets"

# Who is asking. CoinGecko asks for a UA that identifies the client, and an app
# that names itself is one whose traffic can be recognised and blocked on its
# own rather than with every other keyless caller.
AGENT = "moarchy-coins/0.1.0 (+https://github.com/SimonSchubert/moarchy-apps)"

# Twelve seconds. A phone on a cell connection is slow rather than absent, and
# the usual ten is short enough to fail a request that would have arrived; the
# fetch is on a thread either way, so nothing is waiting on this but the word
# "Updating" in the header.
TIMEOUT = 12.0

# How many coins the list holds. A hundred is the length of every "top coins"
# list there has ever been, is about 80 kB of JSON, and is as far down the
# rankings as a person scrolls before they search instead. The endpoint's own
# ceiling is 250.
TOP = 100
PER_PAGE_MAX = 250

# The most a response may be before it is refused unread. 250 coins is a couple
# of hundred kilobytes; four megabytes is a body that has gone wrong, and on a
# metered connection an unbounded read is the expensive kind of wrong.
MAX_BYTES = 4 * 1024 * 1024

# The prices are in this unless something says otherwise. There is no picker in
# the app yet -- see the README -- so this and MOARCHY_COINS_CURRENCY are how it
# changes, and everything that formats a number takes the code rather than
# assuming the dollar.
CURRENCY = "usd"

# Currencies that have a sign worth drawing. Anything else is drawn as its code,
# which is how a currency nobody wrote a symbol for still reads correctly rather
# than silently becoming dollars.
SIGNS = {
    "usd": "$",
    "eur": "€",
    "gbp": "£",
    "jpy": "¥",
    "cny": "¥",
    "inr": "₹",
    "krw": "₩",
    "rub": "₽",
    "btc": "₿",
}

# What a 429 costs when the answer did not say how long to wait. CoinGecko's
# keyless limit is a handful of calls a minute per address, so a minute or two
# is the difference between being let back in and being refused again.
RATE_LIMIT_S = 120.0

# A number that is not there. An em dash rather than "0" or "n/a", because a
# missing 24-hour change and a flat one are different facts and a column of
# zeroes would be a lie told in the same typeface as the truth.
DASH = "—"

# Where a price stops being read as a price. Ten thousand is where the cents
# stop meaning anything -- nobody reads Bitcoin's -- and it is also where the
# string stops fitting the column: "$77,243" is seven characters and
# "$9,999.99" is nine, which is what a 360px row has room for beside a name.
# Below a hundredth the significant digits are all past the fourth place, so
# there the number of decimals is computed rather than fixed.
BIG = 10_000.0
SMALL = 0.01
FIGURES = 4
MAX_PLACES = 10

# Market caps, the way every exchange writes them.
UNITS = ((1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K"))


class MarketError(Exception):
    """Something a person can be told, and a hint about when to try again.

    Every failure in this module arrives as one of these carrying a sentence in
    plain words, because all of them end up in the same place: one line under a
    list of prices that are now older than they were. `retry_after` is seconds,
    and is 0 when the answer carried no such advice.
    """

    def __init__(self, message: str, *, retry_after: float = 0.0) -> None:
        super().__init__(message)
        self.retry_after = retry_after


@dataclass(frozen=True)
class Coin:
    """One row: everything drawn about a coin, and nothing else.

    Deliberately not the whole record. The endpoint returns thirty fields per
    coin -- supply, all-time highs, the date of each, a logo URL -- and this app
    draws seven of them. Keeping the other twenty-three would make the cache
    five times the size for a screen that never shows them, and would invite a
    detail page to be built out of whatever happened to be lying around rather
    than out of a request made for it.
    """

    id: str
    symbol: str
    name: str
    rank: int
    price: float
    change: float | None
    cap: float

    def matches(self, query: str) -> bool:
        """Is this the coin somebody is typing the name of?

        The front of the symbol, or the front of any word in the name. Not a
        substring anywhere: "itc" matching Bitcoin means a search box that fills
        with coincidences, and the coin somebody means is almost always one
        whose name or symbol starts that way. Any *word* rather than the first
        one, because "cash" has to find Bitcoin Cash and "inu" has to find Shiba
        Inu -- which is the same rule a launcher uses on app names.
        """
        text = query.strip().lower()
        if not text:
            return True
        if self.symbol.lower().startswith(text):
            return True
        return any(word.startswith(text) for word in self.name.lower().split())

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "symbol": self.symbol,
            "name": self.name,
            "rank": self.rank,
            "price": self.price,
            "change": self.change,
            "cap": self.cap,
        }

    @classmethod
    def from_dict(cls, data: dict) -> Coin:
        """One coin back out of our own cache file.

        Separate from `parse` below on purpose: that reads CoinGecko's shape and
        this reads ours. Folding them together would mean a change to the API's
        field names quietly rewriting what a cache written last week means.
        """
        if not isinstance(data, dict):
            raise TypeError("coin is not a table")
        price = _number(data.get("price"))
        if not data.get("id") or price is None:
            raise ValueError("coin has no id or no price")
        return cls(
            id=str(data["id"]),
            symbol=str(data.get("symbol") or ""),
            name=str(data.get("name") or data["id"]),
            rank=int(_number(data.get("rank")) or 0),
            price=price,
            change=_number(data.get("change")),
            cap=_number(data.get("cap")) or 0.0,
        )


def _number(value: object) -> float | None:
    """A JSON number, or None for anything that is not one.

    `isinstance(True, int)` is True in Python, and a bool where a price should
    be would otherwise become 1.0 and be drawn as a dollar.
    """
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    number = float(value)
    return None if math.isnan(number) or math.isinf(number) else number


def parse(record: object, rank: int) -> Coin | None:
    """One coin out of CoinGecko's shape, or None if it is not usable.

    `rank` is where the coin sat in the answer, and stands in for a null
    `market_cap_rank` -- which a coin can genuinely have while still being the
    fortieth largest thing in a list ordered by market cap.
    """
    if not isinstance(record, dict):
        return None
    identifier = record.get("id")
    price = _number(record.get("current_price"))
    if not isinstance(identifier, str) or not identifier or price is None or price <= 0:
        # No price is not a coin worth a row: every column on the right of the
        # screen is derived from it.
        return None
    reported = _number(record.get("market_cap_rank"))
    return Coin(
        id=identifier,
        symbol=str(record.get("symbol") or "")[:8].upper(),
        name=str(record.get("name") or identifier),
        rank=int(reported) if reported and reported > 0 else rank,
        price=price,
        change=_number(record.get("price_change_percentage_24h")),
        cap=_number(record.get("market_cap")) or 0.0,
    )


def parse_markets(payload: object) -> list[Coin]:
    """The whole answer, with the unusable rows left out rather than fatal."""
    if not isinstance(payload, list):
        raise MarketError("CoinGecko sent something that is not a list of coins.")
    coins = []
    for position, record in enumerate(payload, start=1):
        coin = parse(record, position)
        if coin is not None:
            coins.append(coin)
    if not coins and payload:
        # Every row unusable is not "a quiet market": it is the shape of the
        # answer having changed, and saying so beats drawing an empty list.
        raise MarketError("CoinGecko sent coins in a shape this app cannot read.")
    return coins


# --- the wire ------------------------------------------------------------


def _retry_after(error: urllib.error.HTTPError) -> float:
    header = error.headers.get("Retry-After") if error.headers else None
    if isinstance(header, str) and header.strip().isdigit():
        return float(header.strip())
    return 0.0


def _get(url: str, *, key: str = "", timeout: float = TIMEOUT) -> object:
    """One GET, and a sentence for every way it can fail."""
    # The URL is always one this module built out of `API` and an urlencoded
    # query, so there is no scheme here a caller could have chosen.
    request = urllib.request.Request(
        url, headers={"User-Agent": AGENT, "Accept": "application/json"}
    )
    if key:
        request.add_header("x-cg-demo-api-key", key)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read(MAX_BYTES + 1)
    except urllib.error.HTTPError as exc:
        if exc.code == 429:
            raise MarketError(
                "CoinGecko is rate-limiting this connection.",
                retry_after=_retry_after(exc) or RATE_LIMIT_S,
            ) from exc
        if 500 <= exc.code < 600:
            raise MarketError("CoinGecko is having trouble.") from exc
        raise MarketError(f"CoinGecko refused the request ({exc.code}).") from exc
    except (OSError, http.client.HTTPException) as exc:
        # URLError, a timeout, a reset, a half-sent body: on a phone these are
        # all one thing -- the radio -- and one sentence is the honest report.
        raise MarketError("No answer from CoinGecko.") from exc
    if len(raw) > MAX_BYTES:
        raise MarketError("CoinGecko sent more than this app will read.")
    try:
        return json.loads(raw)
    except ValueError as exc:
        raise MarketError("CoinGecko sent something that is not JSON.") from exc


class Live:
    """CoinGecko over HTTPS, which is the only thing in this app that is.

    An object rather than two functions so that the window can be handed
    something else entirely: the tests pass a stand-in with these two methods,
    and `MOARCHY_COINS_OFFLINE` passes nothing at all. The app has no idea which
    it has, which is why "the screenshots never touch the network" is a property
    of one environment variable rather than of a mode inside the window.
    """

    def __init__(
        self,
        *,
        currency: str = CURRENCY,
        count: int = TOP,
        key: str = "",
        timeout: float = TIMEOUT,
    ) -> None:
        self.currency = currency.lower() or CURRENCY
        self.count = max(1, min(count, PER_PAGE_MAX))
        self.key = key
        self.timeout = timeout

    def _url(self, **extra: str) -> str:
        query = {
            "vs_currency": self.currency,
            "order": "market_cap_desc",
            "per_page": str(self.count),
            "page": "1",
            # No sparkline. It is 168 hourly prices per coin -- seven times the
            # size of the whole rest of the answer -- for a chart this app does
            # not draw. See the README.
            "sparkline": "false",
            "price_change_percentage": "24h",
            "locale": "en",
        }
        query.update(extra)
        return f"{API}?{urllib.parse.urlencode(query)}"

    def markets(self) -> list[Coin]:
        """The top `count` coins by market capitalisation."""
        return parse_markets(_get(self._url(), key=self.key, timeout=self.timeout))

    def by_ids(self, ids: list[str]) -> list[Coin]:
        """Named coins, whatever their rank.

        The second request, and only when a starred coin has fallen out of the
        top hundred -- which is the one case where the list on screen cannot
        answer for a coin somebody asked to watch. An empty list of ids is not a
        request: without `ids` this endpoint answers with the whole market.
        """
        wanted = [i for i in ids if i][:PER_PAGE_MAX]
        if not wanted:
            return []
        url = self._url(ids=",".join(wanted), per_page=str(len(wanted)))
        return parse_markets(_get(url, key=self.key, timeout=self.timeout))


# --- numbers as somebody reads them --------------------------------------


def sign(currency: str) -> str:
    """The currency's mark, or its code and a space."""
    code = (currency or CURRENCY).lower()
    return SIGNS.get(code, f"{code.upper()} ")


def _places(value: float) -> str:
    """A price with as many decimals as it has significant digits, near zero.

    A coin priced at 0.0000132 has four figures worth reading and they all sit
    past the fourth decimal place, so a fixed two -- or a fixed eight -- is
    either a row of zeroes or a row of noise. This counts the leading zeroes and
    keeps four figures after them.
    """
    if value >= BIG:
        return f"{value:,.0f}"
    if value >= 1.0:
        return f"{value:,.2f}"
    if value >= SMALL:
        return f"{value:.4f}"
    leading = math.floor(-math.log10(value))
    return f"{value:.{min(leading + FIGURES, MAX_PLACES)}f}"


def money(value: float | None, currency: str = CURRENCY) -> str:
    if value is None or value <= 0:
        return DASH
    return f"{sign(currency)}{_places(value)}"


def compact(value: float | None, currency: str = CURRENCY) -> str:
    """A market cap: three significant figures and a letter.

    $1.55 T rather than $1,551,224,442,911, which is twenty characters of a
    360-pixel row spent on digits that change every second and mean nothing
    individually.
    """
    if value is None or value <= 0:
        return DASH
    for scale, suffix in UNITS:
        if value >= scale:
            scaled = value / scale
            if scaled < 10:
                return f"{sign(currency)}{scaled:.2f} {suffix}"
            if scaled < 100:
                return f"{sign(currency)}{scaled:.1f} {suffix}"
            return f"{sign(currency)}{scaled:.0f} {suffix}"
    return f"{sign(currency)}{value:,.0f}"


def percent(value: float | None) -> str:
    """The day, as a signed percentage.

    Always signed. The colour says up or down too, and the colour is the half a
    person sees first -- but roughly one man in twelve cannot tell this app's
    green from its red, and for them the sign *is* the answer.
    """
    if value is None:
        return DASH
    return f"{value:+.2f}%"


def direction(value: float | None) -> str:
    """ "up", "down" or "flat", for the class the figure is drawn in."""
    if value is None:
        return "flat"
    # Under half a hundredth rounds to +0.00%, and a plus sign in green over a
    # number that is not moving is a claim the figure beside it does not make.
    if value >= 0.005:
        return "up"
    if value <= -0.005:
        return "down"
    return "flat"


def freshness(seconds: float) -> str:
    """How old the prices are, in the words somebody would use.

    A clock that has gone backwards -- a phone that has just picked up NTP after
    being off for a week, which is the ordinary case rather than a strange one --
    reads as "just now" rather than as a negative number of minutes.
    """
    if seconds < 60:
        return "just now"
    if seconds < 3600:
        return f"{int(seconds // 60)} min ago"
    if seconds < 86400:
        hours = int(seconds // 3600)
        return f"{hours} hour ago" if hours == 1 else f"{hours} hours ago"
    days = int(seconds // 86400)
    return "yesterday" if days == 1 else f"{days} days ago"
