#!/usr/bin/python3
"""Write an upcoming list to look at, and three stars beside it.

A launch tracker photographs badly against the real thing: the countdowns move
between one shot and the next, the list is different every week, and a
container with no route to the internet draws the one screen this app is
designed to almost never show.

So this writes a pad in the two files the app reads (upcoming.json and
favourites.json, the GTK version's shapes): ten launches with invented NETs
around a frozen now, a status each, and enough names that a search for
`falcon` leaves two rows. The names are real, because they are facts about the
world; no time here is. dev/shots pins the app's clock to the same NOW with
MOARCHY_LAUNCHES_NOW, and runs it with MOARCHY_LAUNCHES_OFFLINE, so the
countdown in the pictures is T-00:12:00 every time and no socket is opened.

    MOARCHY_LAUNCHES_DIR=/tmp/launches python3 apps/launches/dev/demo.py
"""

from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

NOW = datetime(2026, 9, 14, 18, 0, 0, tzinfo=timezone.utc)

# Starred in the order somebody would have tapped them -- deliberately not NET
# order, which is a decision the starred page makes.
STARRED = ["electron-capella", "soyuz-progress", "falcon-ussf"]


def at(**offset: int) -> str:
    return iso(NOW + timedelta(**offset))


def iso(moment: datetime) -> str:
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def launch(identifier, name, vehicle, agency, status_id, status, net, precision,
           pad, location, orbit, mission_type="", window=None, probability=None,
           weather="", hold="", description=""):
    return {
        "id": identifier, "name": name, "vehicle": vehicle, "agency": agency,
        "status_id": status_id, "status": status, "net": net, "precision": precision,
        "window_start": window[0] if window else None,
        "window_end": window[1] if window else None,
        "pad": pad, "location": location, "orbit": orbit, "mission_type": mission_type,
        "probability": probability, "weather": weather, "hold": hold,
        "description": description,
    }


GO, TBD, SUCCESS, HOLD, TBC = 1, 2, 3, 5, 8
SLC40 = ("Space Launch Complex 40", "Cape Canaveral SFS, FL, USA")

PAD = [
    launch("falcon-o3b", "O3b mPower 11-13", "Falcon 9 Block 5", "SpaceX", SUCCESS, "Success",
           at(hours=-14), "MIN", *SLC40, "MEO", "Communications",
           window=(at(hours=-14), at(hours=-12, minutes=-44)),
           description="Three high-throughput communications satellites."),
    launch("vega-sentinel", "Sentinel-3C & FLEX", "Vega-C", "Arianespace", GO, "Go",
           at(minutes=12), "SEC", "Ensemble de Lancement Vega", "Guiana Space Centre, French Guiana",
           "SSO", "Earth Science", window=(at(minutes=12), at(minutes=12)), probability=75,
           weather="Cumulus Cloud Rule",
           description="Copernicus ocean and land satellites, and a fluorescence explorer."),
    launch("zhuque", "Unknown Payload", "Zhuque-2E Block 2", "LandSpace", GO, "Go",
           at(hours=2, minutes=25), "MIN", "Launch Area 96", "Jiuquan, China", "LEO"),
    launch("falcon-ussf", "USSF-259", "Falcon 9 Block 5", "SpaceX", HOLD, "Hold",
           at(hours=6), "MIN", *SLC40, "LEO", "National Security",
           window=(at(hours=6), at(hours=8)), probability=40,
           weather="Surface Electric Fields Rule", hold="Weather",
           description="A US Space Force mission."),
    launch("gravity", "Unknown Payload", "Gravity-1", "Orienspace", GO, "Go",
           at(hours=8), "MIN", "Oriental Spaceport", "Haiyang, China", "SSO"),
    launch("soyuz-progress", "Progress MS-35 (96P)", "Soyuz 2.1b", "Roscosmos", GO, "Go",
           at(days=1, hours=19, minutes=33), "SEC", "Launch Complex 31/6", "Baikonur, Kazakhstan",
           "LEO", "ISS Resupply",
           window=(at(days=1, hours=19, minutes=33), at(days=1, hours=19, minutes=33)),
           description="A Progress cargo spacecraft bound for the International Space Station."),
    launch("long-march", "Unknown Payload", "Long March 12", "CASC", GO, "Go",
           at(days=2, hours=8), "HR", "Commercial Launch Complex 1", "Wenchang, China", "LEO"),
    launch("electron-capella", "Capella 17", "Electron", "Rocket Lab", TBC, "TBC",
           at(days=2), "MIN", "Launch Complex 1A", "Mahia Peninsula, New Zealand",
           "SSO", "Earth Observation", description="A synthetic-aperture radar satellite."),
    launch("kuaizhou", "Unknown Payload", "Kuaizhou 11", "ExPace", GO, "Go",
           at(days=3), "HR", "Launch Area 95A", "Jiuquan, China", "SSO"),
    launch("sls-artemis", "Artemis III", "SLS Block 1", "NASA", TBD, "TBD",
           iso(datetime(2027, 7, 1, tzinfo=timezone.utc)), "Q3", "Launch Complex 39B",
           "Kennedy Space Center, FL, USA", "TLI", "Human Exploration",
           description="The first crewed landing of the Artemis programme."),
]


def main() -> int:
    target = os.environ.get("MOARCHY_LAUNCHES_DIR")
    if not target:
        print("set MOARCHY_LAUNCHES_DIR first -- refusing to touch real favourites", file=sys.stderr)
        return 2
    out = Path(target)
    out.mkdir(parents=True, exist_ok=True)
    fetched = NOW.timestamp()
    (out / "upcoming.json").write_text(
        json.dumps({"schema": 1, "fetched": fetched, "launches": PAD}, indent=1) + "\n", encoding="utf-8")
    (out / "favourites.json").write_text(
        json.dumps({"schema": 1, "favourites": STARRED}, indent=1) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
