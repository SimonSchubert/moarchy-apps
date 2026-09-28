#!/usr/bin/python3
"""Record what radio-browser.info answers, under the paths Airwaves asks with, for the shots.

A radio directory photographs badly against the real thing: what is trending
changes by the hour, and a logo is whatever a station's own site serves today.
So this asks the questions Airwaves asks once, trims every answer to the fields
Api.mjs reads, and writes

  dev/fixture.json   the answers, by request path (RadioBrowser.qml offline)
  dev/.images/       the logos, by md5 of their URL (MOARCHY_AIRWAVES_IMAGES)

dev/demo.py puts the fixture in front of each shot, and dev/shots pins the
clock to NOW in the fixture, so "5 min ago" is five minutes ago every time.

    python3 apps/airwaves/dev/capture.py

A station is kept in a list only when its logo downloads as a picture Qt draws
and is big enough for Art.qml to show it; the rest would be initials, which
is not what the store should show. Nor are the lists anybody's politics or
faith: stations tagged so are left out of the shots, not out of the app.
"""

from __future__ import annotations

import hashlib
import json
import struct
import subprocess
import sys
import time
import urllib.parse
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
SERVER = "https://all.api.radio-browser.info"
AGENT = "Airwaves/1.0 (+https://github.com/SimonSchubert/moarchy-apps)"
PAGE = 40
# Popular in ... on Discover: the shots set this country in the preferences.
COUNTRY = "GB"
# The lists a shot opens, besides Discover's.
TAGS = ["jazz", "classical", "electronic"]
SEARCH = "radio paradise"
AVOID = {"christian", "christian music", "gospel", "gospel music", "religious", "religion",
         "islam", "quran", "church", "catholic", "worship", "politics", "persian", "iran"}
AVOID_NAMES = ("iran", "quran", "القرآن", "bible", "church")


def get(path: str) -> object:
    out = subprocess.run(["curl", "-sS", "--compressed", "--max-time", "40", "-H", f"User-Agent: {AGENT}",
                          "-H", "Accept: application/json", SERVER + path], check=True, capture_output=True).stdout
    return json.loads(out)


# The paths, exactly as Api.mjs builds them.
def q(v: str) -> str:
    return urllib.parse.quote(v, safe="~()*!.'-_")


ORDERS = {"clickcount": True, "clicktrend": True, "votes": True, "bitrate": True, "name": False}


def stations_path(f: dict, order: str, page: int = 0) -> str:
    p = (f"/json/stations/search?hidebroken=true&order={order}&reverse={'true' if ORDERS[order] else 'false'}"
         f"&limit={PAGE}&offset={page * PAGE}")
    if f.get("tag"):
        p += f"&tag={q(f['tag'])}&tagExact=true"
    if f.get("country"):
        p += f"&countrycode={q(f['country'])}"
    if f.get("name"):
        p += f"&name={q(f['name'])}"
    return p


TAGS_PATH = "/json/tags?order=stationcount&reverse=true&hidebroken=true&limit=400"
COUNTRIES_PATH = "/json/countries?order=stationcount&reverse=true&hidebroken=true"
LANGUAGES_PATH = "/json/languages?order=stationcount&reverse=true&hidebroken=true&limit=250"
STATS_PATH = "/json/stats"

STATION_FIELDS = ("stationuuid", "name", "url", "url_resolved", "homepage", "favicon", "tags", "country",
                  "countrycode", "state", "language", "codec", "bitrate", "hls", "votes", "clickcount",
                  "clicktrend", "lastcheckok")


def picture(data: bytes) -> tuple[int, int] | None:
    """Width and height of a PNG, JPEG or GIF; None for anything else."""
    if data[:8] == b"\x89PNG\r\n\x1a\n" and len(data) >= 24:
        return struct.unpack(">II", data[16:24])
    if data[:6] in (b"GIF87a", b"GIF89a"):
        return struct.unpack("<HH", data[6:10])
    if data[:3] == b"\xff\xd8\xff":
        i = 2
        while i + 9 < len(data):
            if data[i] != 0xFF:
                i += 1
                continue
            marker = data[i + 1]
            size = struct.unpack(">H", data[i + 2:i + 4])[0]
            if marker in (0xC0, 0xC1, 0xC2):
                h, w = struct.unpack(">HH", data[i + 5:i + 9])
                return w, h
            i += 2 + size
    return None


def fetch_logo(url: str, images: Path) -> bool:
    out = images / hashlib.md5(url.encode()).hexdigest()
    if not out.exists():
        subprocess.run(["curl", "-sS", "-f", "-L", "--max-time", "20", "--max-filesize", "1000000",
                        "-H", f"User-Agent: {AGENT}", "-o", str(out), url], check=False, capture_output=True)
    if not out.exists():
        return False
    size = picture(out.read_bytes())
    # Art.qml draws a logo of 40 px or more; a favicon is initials.
    if not size or max(size) < 64:
        out.unlink()
        return False
    return True


def main() -> int:
    fixture: dict[str, object] = {"NOW": int(time.time()) * 1000}
    lists = {
        "loved": stations_path({}, "votes"),
        "trending": stations_path({}, "clicktrend"),
        "local": stations_path({"country": COUNTRY}, "clickcount"),
        "search": stations_path({"name": SEARCH}, "clickcount"),
    }
    for tag in TAGS:
        lists[tag] = stations_path({"tag": tag}, "clickcount")

    answers = {path: get(path) for path in lists.values()}
    for path in (TAGS_PATH, COUNTRIES_PATH, LANGUAGES_PATH):
        fixture[path] = [{k: f.get(k) for k in ("name", "stationcount", "iso_3166_1") if k in f}
                         for f in get(path)]
    fixture[STATS_PATH] = {k: v for k, v in get(STATS_PATH).items()
                           if k in ("stations", "countries", "tags", "languages")}

    images = HERE / ".images"
    images.mkdir(exist_ok=True)
    urls = sorted({s["favicon"] for a in answers.values() for s in a if s.get("favicon", "").startswith("http")})
    with ThreadPoolExecutor(8) as pool:
        good = {u for u, ok in zip(urls, pool.map(lambda u: fetch_logo(u, images), urls)) if ok}

    def keep(s: dict) -> bool:
        tags = {t.strip().lower() for t in str(s.get("tags", "")).split(",")}
        name = str(s.get("name", "")).lower()
        return s.get("favicon") in good and not tags & AVOID and not any(w in name for w in AVOID_NAMES)

    for name, path in lists.items():
        kept = [{k: s[k] for k in STATION_FIELDS if k in s} for s in answers[path] if keep(s)]
        fixture[path] = kept
        print(f"{name:12} {len(kept):3} of {len(answers[path])}", file=sys.stderr)

    (HERE / "fixture.json").write_text(json.dumps(fixture, ensure_ascii=False, indent=None) + "\n")

    used = {hashlib.md5(s["favicon"].encode()).hexdigest() for path in lists.values() for s in fixture[path]}
    for f in images.iterdir():
        if f.name not in used:
            f.unlink()
    print(f"{len(used)} logos of {len(urls)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
