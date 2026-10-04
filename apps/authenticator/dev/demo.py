#!/usr/bin/env python3
"""Accounts to photograph, where the app reads them.

An authenticator with nothing in it is an empty state and a plus. Every part
worth looking at -- the issuer tiles in the theme's hues, a code in two
halves, the ring running down, an eight-digit code, a sixty-second one -- is
only itself with accounts in the list.

    MOARCHY_AUTHENTICATOR_DIR=/tmp/a apps/authenticator/dev/demo.py

**Every key here is invented**: base32 of a SHA-1 over a phrase in this file,
belonging to no account anywhere. The issuers are real names because that is
what an authenticator's list is; none of them issued these keys. The shape
and the one-space indent are Store.js's `serialize()`, so the app reads this
without a special case.
"""

from __future__ import annotations

import base64
import hashlib
import json
import os
from pathlib import Path

SCHEMA = 1

# issuer, account, algorithm, digits, period
ACCOUNTS = [
    ("GitHub", "simon", "SHA1", 6, 30),
    ("Codeberg", "simon", "SHA1", 6, 30),
    ("Hetzner", "simon@example.org", "SHA1", 6, 30),
    ("Fastmail", "simon@example.org", "SHA1", 6, 30),
    ("Mastodon", "@simon@fosstodon.example", "SHA1", 6, 30),
    ("Proton", "simon@proton.example", "SHA1", 6, 30),
    ("AUR", "simon", "SHA1", 6, 30),
    ("Tailscale", "simon@example.org", "SHA1", 6, 30),
    ("Bank", "Current account", "SHA256", 8, 60),
    ("Work VPN", "s.schubert", "SHA1", 6, 30),
]


def key(issuer: str, name: str) -> str:
    seed = hashlib.sha1(f"moarchy demo {issuer} {name}".encode()).digest()
    return base64.b32encode(seed).decode().rstrip("=")


def main() -> None:
    directory = Path(
        os.environ.get("MOARCHY_AUTHENTICATOR_DIR")
        or Path.home() / ".local/share/moarchy-authenticator"
    )
    directory.mkdir(parents=True, exist_ok=True)
    rows = []
    for index, (issuer, name, algorithm, digits, period) in enumerate(ACCOUNTS, start=1):
        rows.append({
            "id": "a-demo-%02d" % index,
            "issuer": issuer,
            "name": name,
            "secret": key(issuer, name),
            "algorithm": algorithm,
            "digits": digits,
            "period": period,
        })
    path = directory / "accounts.json"
    path.write_text(json.dumps({"schema": SCHEMA, "accounts": rows}, indent=1) + "\n")
    print(path)


if __name__ == "__main__":
    main()
