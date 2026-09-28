#!/usr/bin/python3
"""Record what CoinGecko answers, under the URLs Crypto Market asks with, for the shots.

A market app photographs badly against the real thing: every price is
different a minute later, and a public API that allows a handful of calls a
minute answers a screenshot run with 429s. So this asks the questions Crypto
Market asks once, trims each answer to the fields Api.mjs reads, and writes

  dev/fixture.json   the answers, by request URL (Gecko.qml, sealed)
  dev/.images/       the coin logos, by LogoCache.fixedName (MOARCHY_CRYPTO_MARKET_LOGOS)

dev/demo.py puts the fixture in front of each shot, with a portfolio and a
watchlist made of the same coins, and dev/shots pins the clock to NOW in the
fixture, so the prices are as fresh as when they were recorded.

    python3 apps/crypto-market/dev/capture.py

CoinGecko's public API needs no key and allows somewhere between five and
fifteen calls a minute, so the calls are spaced out; the run takes a minute
or two. The lists the watchlist and the portfolio ask for are cut from the
top 250 rather than asked again: the same moment, one call fewer each.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
import time
import urllib.parse
from pathlib import Path

HERE = Path(__file__).resolve().parent
BASE = "https://api.coingecko.com/api/v3"
AGENT = "crypto-market/1.1 (+https://github.com/SimonSchubert/moarchy-apps)"
CUR = "usd"
GAP = 12  # seconds between API calls: the public tier 429s at 8
COINS = ["bitcoin", "ethereum"]                 # coin pages the shots open
CHARTS = {"bitcoin": ["7", "30", "365"], "ethereum": ["7"]}
# demo.py's watchlist and portfolio, in its order; every one is in the top 250.
WATCHLIST = ["bitcoin", "ethereum", "solana", "ripple", "cardano", "dogecoin", "chainlink"]
HOLDINGS = ["bitcoin", "ethereum", "solana", "chainlink", "dogecoin", "cardano"]

# The URLs, built exactly as Api.mjs builds them: the fixture is keyed by them.
RANGES = "&sparkline=true&price_change_percentage=1h%2C24h%2C7d"


def q(v: str) -> str:
    return urllib.parse.quote(str(v), safe="-_.!~*'()")  # encodeURIComponent


def markets_url(page: int, per_page: int) -> str:
    return (f"{BASE}/coins/markets?vs_currency={q(CUR)}&order=market_cap_desc&per_page={per_page}"
            f"&page={page}{RANGES}")


def ids_url(ids: list[str]) -> str:
    return (f"{BASE}/coins/markets?vs_currency={q(CUR)}&ids={q(','.join(sorted(ids)))}"
            f"&per_page=250&page=1{RANGES}")


def coin_url(cid: str) -> str:
    return (f"{BASE}/coins/{cid}?localization=false&tickers=false&market_data=true"
            "&community_data=false&developer_data=false&sparkline=false")


def chart_url(cid: str, days: str) -> str:
    return f"{BASE}/coins/{cid}/market_chart?vs_currency={q(CUR)}&days={q(days)}"


def curl(url: str) -> object:
    for attempt in range(4):
        out = subprocess.run(["curl", "-sS", "--compressed", "--max-time", "40", "-w", "\n%{http_code}",
                              "-H", f"User-Agent: {AGENT}", "-H", "Accept: application/json", url],
                             check=True, capture_output=True, text=True).stdout
        body, _, status = out.rpartition("\n")
        if status == "200":
            time.sleep(GAP)
            return json.loads(body)
        print(f"  {status} for {url}, waiting", file=sys.stderr)
        time.sleep(60 * (attempt + 1))
    raise SystemExit(f"CoinGecko kept refusing {url}")


def only(d: dict | None, keys: tuple[str, ...]) -> dict:
    return {k: d[k] for k in keys if d and k in d}


# Six figures of a price are more than a line 120 px tall can show.
def fig(v: object) -> object:
    return float(f"{v:.6g}") if isinstance(v, float) else v


# Api.thin(points, 42), done here: the app thins what it is given to the same
# points, and the fixture is a quarter of the size.
def thin(points: list, target: int = 42) -> list:
    if not points:
        return []
    step = max(1, len(points) // target)
    out = points[::step]
    if out[-1] != points[-1]:
        out.append(points[-1])
    return [fig(v) for v in out]


ROW = ("id", "symbol", "name", "image", "market_cap_rank", "current_price", "market_cap",
       "fully_diluted_valuation", "total_volume", "high_24h", "low_24h",
       "price_change_percentage_1h_in_currency", "price_change_percentage_24h_in_currency",
       "price_change_percentage_24h", "price_change_percentage_7d_in_currency",
       "circulating_supply", "total_supply", "max_supply", "ath", "ath_change_percentage",
       "ath_date", "atl", "atl_change_percentage", "atl_date")


def trim_row(c: dict) -> dict:
    out = only(c, ROW)
    out["sparkline_in_7d"] = {"price": thin((c.get("sparkline_in_7d") or {}).get("price") or [])}
    return out


def trim_global(g: dict) -> dict:
    d = g.get("data") or {}
    return {"data": {
        "total_market_cap": only(d.get("total_market_cap"), (CUR,)),
        "total_volume": only(d.get("total_volume"), (CUR,)),
        "market_cap_percentage": only(d.get("market_cap_percentage"), ("btc", "eth")),
        **only(d, ("market_cap_change_percentage_24h_usd", "active_cryptocurrencies", "markets")),
    }}


def trim_trending(t: dict) -> dict:
    keep = ("id", "name", "symbol", "market_cap_rank", "small", "thumb", "score")
    return {"coins": [{"item": only(c.get("item"), keep)} for c in t.get("coins", [])]}


MARKET = ("current_price", "market_cap", "fully_diluted_valuation", "total_volume", "high_24h",
          "low_24h", "price_change_percentage_1h_in_currency", "price_change_percentage_24h_in_currency",
          "price_change_percentage_7d_in_currency", "price_change_percentage_30d_in_currency",
          "price_change_percentage_1y_in_currency", "ath", "ath_change_percentage", "ath_date",
          "atl", "atl_change_percentage", "atl_date")


def trim_coin(c: dict) -> dict:
    m = c.get("market_data") or {}
    market = {k: only(m[k], (CUR,)) for k in MARKET if isinstance(m.get(k), dict)}
    market |= only(m, ("circulating_supply", "total_supply", "max_supply"))
    links = c.get("links") or {}
    return {
        **only(c, ("id", "name", "symbol", "market_cap_rank", "categories", "genesis_date",
                   "hashing_algorithm", "sentiment_votes_up_percentage", "watchlist_portfolio_users")),
        "image": only(c.get("image"), ("small", "large")),
        "market_data": market,
        "links": {
            "homepage": (links.get("homepage") or [])[:1],
            "blockchain_site": [s for s in links.get("blockchain_site") or [] if s][:2],
            "repos_url": {"github": ((links.get("repos_url") or {}).get("github") or [])[:1]},
            "subreddit_url": links.get("subreddit_url") or "",
        },
        "description": {"en": ((c.get("description") or {}).get("en") or "")[:6000]},
    }


# The logo each answer makes the app load, as Api.mjs picks it.
def small(u: str) -> str:
    return u.replace("/large/", "/small/")


def fixed_name(url: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]", "_", re.sub(r"\?.*$", "", re.sub(r"^https://[^/]+/", "", url)))


def logos(fixture: dict) -> set[str]:
    want: set[str] = set()
    for url, ans in fixture.items():
        if not url.startswith(BASE):
            continue
        if isinstance(ans, list) and "/coins/markets" in url:
            want |= {small(r["image"]) for r in ans if r.get("image")}
        elif url.endswith("/search/trending"):
            want |= {c["item"].get("small") or c["item"].get("thumb") for c in ans["coins"]}
        elif isinstance(ans, dict) and "market_data" in ans:
            want.add(ans["image"].get("small") or ans["image"].get("large"))
    return {u for u in want if u and re.match(r"^https://(coin-images|assets)\.coingecko\.com/", u)}


def main() -> int:
    fixture: dict[str, object] = {"NOW": int(time.time())}

    top = [trim_row(c) for c in curl(markets_url(1, 250))]
    fixture[markets_url(1, 250)] = top
    fixture[markets_url(1, 100)] = top[:100]
    by = {r["id"]: r for r in top}
    for ids in (WATCHLIST, HOLDINGS):
        missing = [i for i in ids if i not in by]
        if missing:
            raise SystemExit(f"not in the top 250 today: {missing} -- pick others in capture.py")
        fixture[ids_url(ids)] = [r for r in top if r["id"] in ids]
    print("markets", len(top), file=sys.stderr)

    fixture[f"{BASE}/global"] = trim_global(curl(f"{BASE}/global"))
    trending = trim_trending(curl(f"{BASE}/search/trending"))
    fixture[f"{BASE}/search/trending"] = trending
    tids = [c["item"]["id"] for c in trending["coins"]][:30]
    fixture[ids_url(tids)] = [trim_row(c) for c in curl(ids_url(tids))]
    print("trending", len(tids), file=sys.stderr)

    for cid in COINS:
        fixture[coin_url(cid)] = trim_coin(curl(coin_url(cid)))
        for days in CHARTS.get(cid, []):
            prices = curl(chart_url(cid, days)).get("prices", [])
            fixture[chart_url(cid, days)] = {"prices": [[t, fig(v)] for t, v in prices]}
        print("coin", cid, file=sys.stderr)

    # The logos, once each. A logo that will not download is dropped from
    # the answer, which is what the app shows for it anyway: initials.
    images = HERE / ".images"
    images.mkdir(exist_ok=True)
    gone: set[str] = set()
    for url in sorted(logos(fixture)):
        out = images / fixed_name(url)
        if not out.exists():
            subprocess.run(["curl", "-sS", "-f", "--max-time", "30", "-H", f"User-Agent: {AGENT}",
                            "-o", str(out), url], check=False)
            time.sleep(0.2)
        head = out.read_bytes()[:12] if out.exists() else b""
        if not (head.startswith(b"\x89PNG") or head.startswith(b"\xff\xd8\xff")
                or head[8:12] == b"WEBP" or head.startswith(b"GIF8")):
            out.unlink(missing_ok=True)
            gone.add(url)

    def blank(row: dict) -> None:
        for k in ("image", "small", "thumb"):
            if isinstance(row.get(k), str) and (row[k] in gone or small(row[k]) in gone):
                row[k] = ""

    for url, ans in fixture.items():
        if isinstance(ans, list):
            for r in ans:
                blank(r)
        elif isinstance(ans, dict) and "coins" in ans:
            for c in ans["coins"]:
                blank(c["item"])
        elif isinstance(ans, dict) and "image" in ans:
            for k in ("small", "large"):
                if ans["image"].get(k) in gone:
                    ans["image"][k] = ""

    (HERE / "fixture.json").write_text(json.dumps(fixture, ensure_ascii=False, indent=None) + "\n")
    print(f"{len(fixture) - 1} answers, {len(logos(fixture))} logos, {len(gone)} gone", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
