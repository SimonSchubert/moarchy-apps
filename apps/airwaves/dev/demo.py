#!/usr/bin/python3
"""Put the recorded answers in front of Airwaves, and a listener's files beside them.

dev/capture.py wrote dev/fixture.json: what radio-browser.info said, by the
path Airwaves asks with. This copies it into MOARCHY_AIRWAVES_DIR, where the
app reads it when it runs with MOARCHY_AIRWAVES_OFFLINE, and writes the
preferences a listener would have -- favourites, a week of Recent, the station
last played, the United Kingdom as the country -- all made of stations in the
fixture, so every tab has something on it and nothing is fetched.

    MOARCHY_AIRWAVES_DIR=/tmp/airwaves python3 apps/airwaves/dev/demo.py

The appearance is the one scripts/app-shot.sh chose (LOOK, or THEME, which it
writes into its own prefs file beside Airwaves'), and "theme" wherever a
colors.toml has been staged. MOARCHY_AIRWAVES_STATION picks the station last
played, by part of its name.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

FAVORITES = ["SomaFM Secret Agent", "Radio Paradise Main Mix (EU)", "Classic FM UK", "Jazz Radio Blues",
             "FM4", "BBC Radio 3", "Bossa Jazz Brasil", "Dance Wave!"]
# (name, minutes ago)
RECENT = [("SomaFM Secret Agent", 4), ("Radio Paradise Main Mix (EU)", 38), ("BBC World Service", 150),
          ("Classic FM UK", 320), ("Jazz Radio Blues", 60 * 22), ("FM4", 60 * 30),
          ("Bossa Jazz Brasil", 60 * 52), ("Deutschlandfunk", 60 * 75), ("Dance Wave!", 60 * 100)]
LAST = "SomaFM Secret Agent"

COUNTRY_NAMES = {
    "The United States Of America": "United States",
    "The United Kingdom Of Great Britain And Northern Ireland": "United Kingdom",
    "The Russian Federation": "Russia",
    "The Netherlands": "Netherlands",
}


def url(v: object) -> str:
    s = str(v or "").strip()
    return s if re.match(r"^https?://[^\s/?#]+", s, re.I) else ""


def saved(o: dict) -> dict:
    """A station as Api.station() shapes it, which is what favourites keep."""
    country = COUNTRY_NAMES.get(o.get("country", ""), re.sub(r"^The ", "", o.get("country", "")))
    tags: list[str] = []
    for t in str(o.get("tags", "")).split(","):
        t = t.strip().lower()[:32]
        if len(t) >= 2 and t not in tags and len(tags) < 10:
            tags.append(t)
    langs = [" ".join(p.capitalize() for p in w.split()) for w in str(o.get("language", "")).split(",") if w.strip()]
    return {
        "id": o["stationuuid"], "name": o["name"].strip(), "stream": url(o.get("url_resolved")) or url(o.get("url")),
        "homepage": url(o.get("homepage")), "favicon": url(o.get("favicon")), "tags": tags,
        "country": country, "cc": str(o.get("countrycode", "")).upper(), "state": o.get("state", ""),
        "language": ", ".join(langs[:3]),
        "codec": str(o.get("codec", "")).upper().replace("UNKNOWN", ""), "bitrate": int(o.get("bitrate") or 0),
        "hls": int(o.get("hls") or 0) == 1, "votes": int(o.get("votes") or 0),
        "clicks": int(o.get("clickcount") or 0), "trend": int(o.get("clicktrend") or 0),
        "ok": int(o.get("lastcheckok", 1)) != 0,
    }


def main() -> int:
    src = HERE / "fixture.json"
    if not src.exists():
        print("no dev/fixture.json -- run dev/capture.py", file=sys.stderr)
        return 1
    home = Path.home()
    state = Path(os.environ.get("XDG_STATE_HOME") or home / ".local/state")
    dest = Path(os.environ.get("MOARCHY_AIRWAVES_DIR") or state / "airwaves")
    dest.mkdir(parents=True, exist_ok=True)
    shutil.copy(src, dest / "fixture.json")
    fx = json.loads(src.read_text())
    now = fx["NOW"]

    by_name: dict[str, dict] = {}
    for answer in fx.values():
        if isinstance(answer, list):
            for s in answer:
                if "stationuuid" in s:
                    by_name.setdefault(s["name"].strip(), s)

    def find(part: str) -> dict:
        for name, s in by_name.items():
            if name.lower().startswith(part.lower()):
                return saved(s)
        raise SystemExit(f"no station named {part!r} in the fixture -- run dev/capture.py again")

    # What app-shot.sh chose, from the file it writes for kit apps.
    look = ""
    shot_prefs = state / "moarchy-airwaves" / "prefs.json"
    if shot_prefs.exists():
        look = json.loads(shot_prefs.read_text()).get("appearance", "")
    staged = (state / "omarchy/current/theme/colors.toml").exists()
    if look not in ("theme", "system", "light", "dark"):
        look = "theme" if staged else "system"

    prefs = {
        "version": 1, "lastTab": "discover",
        "favorites": [find(n) for n in FAVORITES],
        "recent": [{"s": find(n), "t": now - m * 60000} for n, m in RECENT],
        "lastStation": find(os.environ.get("MOARCHY_AIRWAVES_STATION") or LAST),
        "volume": 70, "muted": False, "country": "GB", "browse": "tags", "order": "clickcount",
        "logos": True, "appearance": look, "appearancePicked": True, "launcher": True, "launcherAdded": True,
    }
    out = state / "airwaves"
    out.mkdir(parents=True, exist_ok=True)
    (out / "prefs.json").write_text(json.dumps(prefs, ensure_ascii=False, indent=1) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
