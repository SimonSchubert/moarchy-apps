#!/usr/bin/python3
"""Put the recorded answers in front of Crypto Market, and a portfolio beside them.

dev/capture.py wrote dev/fixture.json: what CoinGecko said, by the URL Crypto
Market asks with. This copies it into MOARCHY_CRYPTO_MARKET_DIR, where the app
reads it when it runs with MOARCHY_CRYPTO_MARKET_OFFLINE, and writes the app's
own prefs.json: a watchlist and a portfolio of the coins capture.py recorded,
bought at prices a few months and a year before the recording, so every tab
has something on it and no socket is opened. Never an API key.

    MOARCHY_CRYPTO_MARKET_DIR=/tmp/cm HOME=/tmp/cm-home python3 apps/crypto-market/dev/demo.py

It writes over the preferences in $XDG_STATE_HOME (or ~/.local/state), so it
refuses to run without MOARCHY_CRYPTO_MARKET_DIR: scripts/app-shot.sh sets it,
with HOME a scratch home of its own.
"""

from __future__ import annotations

import json
import os
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
DAY = 86400 * 1000

# What was bought, when (days before the recording) and at what fraction of
# the recorded price. Two buys of Bitcoin and a sale of some Solana, so the
# coin page lists trades and the profit is not the same figure everywhere.
TRADES = {
    "bitcoin": [("buy", 0.25, 410, 0.52), ("buy", 0.17, 96, 0.93)],
    "ethereum": [("buy", 3.2, 240, 0.71)],
    "solana": [("buy", 60, 300, 0.64), ("sell", 12, 45, 1.08)],
    "chainlink": [("buy", 180, 150, 1.21)],
    "dogecoin": [("buy", 15000, 200, 0.83)],
    "cardano": [("buy", 2400, 120, 1.12)],
}
WATCHLIST = ["bitcoin", "ethereum", "solana", "ripple", "cardano", "dogecoin", "chainlink"]


def main() -> int:
    data = os.environ.get("MOARCHY_CRYPTO_MARKET_DIR")
    if not data:
        print("MOARCHY_CRYPTO_MARKET_DIR is not set -- this writes over the app's preferences", file=sys.stderr)
        return 1
    src = HERE / "fixture.json"
    if not src.exists():
        print("no dev/fixture.json -- run dev/capture.py", file=sys.stderr)
        return 1
    dest = Path(data)
    dest.mkdir(parents=True, exist_ok=True)
    shutil.copy(src, dest / "fixture.json")
    fx = json.loads(src.read_text())
    now = fx["NOW"] * 1000

    top = next(v for k, v in fx.items() if "per_page=250&page=1" in k and "&ids=" not in k)
    by = {r["id"]: r for r in top}
    holdings = {}
    for cid, trades in TRADES.items():
        r = by[cid]
        holdings[cid] = {
            "name": r["name"], "symbol": r["symbol"].upper(), "image": r["image"].replace("/large/", "/small/"),
            "txs": [{"side": side, "amount": amount, "price": float(f"{r['current_price'] * frac:.4g}"),
                     "cur": "usd", "ts": now - days * DAY}
                    for side, amount, days, frac in trades],
        }

    state = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "crypto-market"
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    prefs = {
        "version": 1, "currency": "usd", "apiKey": "", "topN": 100, "refreshSec": 120,
        "watchlist": WATCHLIST, "holdings": holdings, "lastTab": "markets",
        "launcher": True, "launcherAdded": True,
    }
    (state / "prefs.json").write_text(json.dumps(prefs, indent=1) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
