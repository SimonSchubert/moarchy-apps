#!/usr/bin/python3
"""Write a market to look at, and four stars beside it.

A coin tracker photographs badly against the real thing. The prices move
between one shot and the next, so two screenshots taken a minute apart disagree
about what the app says; the list is different every week; and a container with
no route to the internet -- which is where the checks run -- draws the one
screen this app is designed to almost never show.

So this writes a market: forty coins with invented prices, a day's movement
each, and a market capitalisation that is the price multiplied by a supply
rather than a number picked to look large. Ranking falls out of that
arithmetic, the same way it does at CoinGecko, which is what stops the list
disagreeing with itself.

The prices are invented and this file is the only place they exist. Every name
and symbol is real, because they are facts about the world and inventing them
would make the screenshots useless for judging the app; no number here is.

`scripts/check.sh` runs this before it runs the app, which is also why a check
run never touches the network: the cache it writes is seconds old, the window
only fetches when its prices are older than a minute, and the run is over in
four seconds.
"""

from __future__ import annotations

import os
import random
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_coins.market import Coin  # noqa: E402
from moarchy_coins.store import Store  # noqa: E402

# (id, name, symbol, price, circulating supply). Shiba Inu and Pepe are in here
# on purpose: they are the rows that prove the price column, because a fixed two
# decimals draws both of them as $0.00 and a fixed eight draws Bitcoin as
# $77,000.00000000.
MARKET = [
    ("bitcoin", "Bitcoin", "BTC", 77_000.0, 19_900_000),
    ("ethereum", "Ethereum", "ETH", 2_500.0, 120_500_000),
    ("tether", "Tether", "USDT", 1.0, 141_000_000_000),
    ("ripple", "XRP", "XRP", 2.05, 59_000_000_000),
    ("binancecoin", "BNB", "BNB", 640.0, 140_000_000),
    ("solana", "Solana", "SOL", 148.0, 540_000_000),
    ("usd-coin", "USDC", "USDC", 1.0, 62_000_000_000),
    ("dogecoin", "Dogecoin", "DOGE", 0.176, 149_000_000_000),
    ("cardano", "Cardano", "ADA", 0.61, 36_000_000_000),
    ("tron", "TRON", "TRX", 0.24, 86_000_000_000),
    ("staked-ether", "Lido Staked Ether", "STETH", 2_500.0, 9_000_000),
    ("wrapped-bitcoin", "Wrapped Bitcoin", "WBTC", 77_000.0, 130_000),
    ("chainlink", "Chainlink", "LINK", 14.8, 660_000_000),
    ("avalanche-2", "Avalanche", "AVAX", 21.5, 420_000_000),
    ("hedera-hashgraph", "Hedera", "HBAR", 0.185, 42_000_000_000),
    ("sui", "Sui", "SUI", 2.05, 3_600_000_000),
    ("stellar", "Stellar", "XLM", 0.27, 31_000_000_000),
    ("shiba-inu", "Shiba Inu", "SHIB", 0.0000119, 589_000_000_000_000),
    ("bitcoin-cash", "Bitcoin Cash", "BCH", 350.0, 19_900_000),
    ("litecoin", "Litecoin", "LTC", 78.0, 76_000_000),
    ("polkadot", "Polkadot", "DOT", 3.35, 1_600_000_000),
    ("uniswap", "Uniswap", "UNI", 7.4, 630_000_000),
    ("monero", "Monero", "XMR", 235.0, 18_400_000),
    ("aptos", "Aptos", "APT", 4.1, 700_000_000),
    ("near", "NEAR Protocol", "NEAR", 2.3, 1_250_000_000),
    ("pepe", "Pepe", "PEPE", 0.0000068, 420_000_000_000_000),
    ("aave", "Aave", "AAVE", 178.0, 15_100_000),
    ("internet-computer", "Internet Computer", "ICP", 5.1, 530_000_000),
    ("ethereum-classic", "Ethereum Classic", "ETC", 16.2, 152_000_000),
    ("cosmos", "Cosmos Hub", "ATOM", 3.9, 460_000_000),
    ("polygon-ecosystem-token", "POL", "POL", 0.185, 10_400_000_000),
    ("filecoin", "Filecoin", "FIL", 2.35, 680_000_000),
    ("render-token", "Render", "RENDER", 3.15, 518_000_000),
    ("arbitrum", "Arbitrum", "ARB", 0.31, 5_000_000_000),
    ("algorand", "Algorand", "ALGO", 0.17, 8_700_000_000),
    ("vechain", "VeChain", "VET", 0.018, 80_900_000_000),
    ("maker", "Maker", "MKR", 1_350.0, 900_000),
    ("optimism", "Optimism", "OP", 0.62, 1_700_000_000),
    ("stacks", "Stacks", "STX", 0.52, 1_500_000_000),
    ("injective-protocol", "Injective", "INJ", 9.1, 98_000_000),
]

# Starred, in the order somebody would have tapped them -- which is deliberately
# not rank order, because that ordering is a decision the starred page makes and
# a screenshot is the only place it can be seen.
STARRED = ["monero", "chainlink", "dogecoin", "ethereum"]

# A day that has some weather in it. Most coins move a percent or two, a couple
# move ten, and the stablecoins do not move at all -- a list where every row is
# green says as little as one where every row is grey.
QUIET = ("tether", "usd-coin")
SWING = 9.0


def main() -> int:
    target = os.environ.get("MOARCHY_COINS_DIR")
    if not target:
        print(
            "set MOARCHY_COINS_DIR first -- refusing to touch real favourites",
            file=sys.stderr,
        )
        return 2

    rng = random.Random(20260913)
    priced = []
    for identifier, name, symbol, price, supply in MARKET:
        if identifier in QUIET:
            change = rng.uniform(-0.04, 0.04)
        else:
            # Skewed a little towards nothing much happening, with the tail out
            # at SWING: a market where every coin has moved eight per cent is a
            # market nobody has ever photographed.
            change = rng.triangular(-SWING, SWING, rng.uniform(-1.5, 1.5))
        priced.append((price * supply, identifier, name, symbol, price, change))

    priced.sort(key=lambda row: -row[0])
    coins = [
        Coin(
            id=identifier,
            symbol=symbol,
            name=name,
            rank=rank,
            price=price,
            change=round(change, 3),
            cap=cap,
        )
        for rank, (cap, identifier, name, symbol, price, change) in enumerate(
            priced, start=1
        )
    ]

    store = Store(Path(target))
    store.replace(coins, fetched=time.time(), currency="usd")
    store.favourites = [i for i in STARRED if any(c.id == i for c in coins)]
    store.save_market()
    store.save_favourites()
    print(f"wrote {len(coins)} coins and {len(store.favourites)} stars to {store.dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
