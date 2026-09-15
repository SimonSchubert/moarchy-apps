#!/usr/bin/python3
"""Write an upcoming list to look at, and three stars beside it.

A launch tracker photographs badly against the real thing. The countdowns
move between one shot and the next, so two screenshots taken a minute apart
disagree about what the app says; the list is different every week; and a
container with no route to the internet -- which is where the checks run --
draws the one screen this app is designed to almost never show.

So this writes a pad: ten launches with invented NETs around a frozen now,
a status each, and enough names that a search for `falcon` leaves two rows.
The names are real, because they are facts about the world and inventing
them would make the screenshots useless for judging the app; no time here is.

`scripts/check.sh` runs this before it runs the app, which is also why a
check run never touches the network: the cache it writes is seconds old, the
window only fetches when its launches are older than fifteen minutes, and
the run is over in four seconds.
"""

from __future__ import annotations

import os
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_launches.launches import (  # noqa: E402
    STATUS_GO,
    STATUS_HOLD,
    STATUS_SUCCESS,
    STATUS_TBC,
    STATUS_TBD,
    Launch,
)
from moarchy_launches.store import Store  # noqa: E402

# Frozen for screenshots. shots.sh exports the same value so the countdown
# in the pictures is T-00:12:00, every time.
NOW = datetime(2026, 9, 14, 18, 0, 0, tzinfo=timezone.utc)

# Starred, in the order somebody would have tapped them -- which is
# deliberately not NET order, because that ordering is a decision the
# starred page makes and a screenshot is the only place it can be seen.
STARRED = ["electron-capella", "soyuz-progress", "falcon-ussf"]


def at(*offset: int, **kwargs) -> datetime:
    """NOW plus a timedelta, so the demo is a function of the frozen clock."""
    return NOW + timedelta(*offset, **kwargs)


MARKET = [
    Launch(
        id="falcon-o3b",
        name="O3b mPower 11-13",
        vehicle="Falcon 9 Block 5",
        agency="SpaceX",
        status_id=STATUS_SUCCESS,
        status="Success",
        net=at(hours=-14),
        precision="MIN",
        window_start=at(hours=-14),
        window_end=at(hours=-12, minutes=-44),
        pad="Space Launch Complex 40",
        location="Cape Canaveral SFS, FL, USA",
        orbit="MEO",
        mission_type="Communications",
        probability=None,
        weather="",
        hold="",
        description="Three high-throughput communications satellites.",
    ),
    Launch(
        id="vega-sentinel",
        name="Sentinel-3C & FLEX",
        vehicle="Vega-C",
        agency="Arianespace",
        status_id=STATUS_GO,
        status="Go",
        net=at(minutes=12),
        precision="SEC",
        window_start=at(minutes=12),
        window_end=at(minutes=12),
        pad="Ensemble de Lancement Vega",
        location="Guiana Space Centre, French Guiana",
        orbit="SSO",
        mission_type="Earth Science",
        probability=75,
        weather="Cumulus Cloud Rule",
        hold="",
        description="Copernicus ocean and land satellites, and a fluorescence explorer.",
    ),
    Launch(
        id="zhuque",
        name="Unknown Payload",
        vehicle="Zhuque-2E Block 2",
        agency="LandSpace",
        status_id=STATUS_GO,
        status="Go",
        net=at(hours=2, minutes=25),
        precision="MIN",
        window_start=None,
        window_end=None,
        pad="Launch Area 96",
        location="Jiuquan, China",
        orbit="LEO",
        mission_type="",
        probability=None,
        weather="",
        hold="",
        description="",
    ),
    Launch(
        id="falcon-ussf",
        name="USSF-259",
        vehicle="Falcon 9 Block 5",
        agency="SpaceX",
        status_id=STATUS_HOLD,
        status="Hold",
        net=at(hours=6),
        precision="MIN",
        window_start=at(hours=6),
        window_end=at(hours=8),
        pad="Space Launch Complex 40",
        location="Cape Canaveral SFS, FL, USA",
        orbit="LEO",
        mission_type="National Security",
        probability=40,
        weather="Surface Electric Fields Rule",
        hold="Weather",
        description="A US Space Force mission.",
    ),
    Launch(
        id="gravity",
        name="Unknown Payload",
        vehicle="Gravity-1",
        agency="Orienspace",
        status_id=STATUS_GO,
        status="Go",
        net=at(hours=8),
        precision="MIN",
        window_start=None,
        window_end=None,
        pad="Oriental Spaceport",
        location="Haiyang, China",
        orbit="SSO",
        mission_type="",
        probability=None,
        weather="",
        hold="",
        description="",
    ),
    Launch(
        id="soyuz-progress",
        name="Progress MS-35 (96P)",
        vehicle="Soyuz 2.1b",
        agency="Roscosmos",
        status_id=STATUS_GO,
        status="Go",
        net=at(days=1, hours=19, minutes=33),
        precision="SEC",
        window_start=at(days=1, hours=19, minutes=33),
        window_end=at(days=1, hours=19, minutes=33),
        pad="Launch Complex 31/6",
        location="Baikonur, Kazakhstan",
        orbit="LEO",
        mission_type="ISS Resupply",
        probability=None,
        weather="",
        hold="",
        description="A Progress cargo spacecraft bound for the International Space Station.",
    ),
    Launch(
        id="long-march",
        name="Unknown Payload",
        vehicle="Long March 12",
        agency="CASC",
        status_id=STATUS_GO,
        status="Go",
        net=at(days=2, hours=8),
        precision="HR",
        window_start=None,
        window_end=None,
        pad="Commercial Launch Complex 1",
        location="Wenchang, China",
        orbit="LEO",
        mission_type="",
        probability=None,
        weather="",
        hold="",
        description="",
    ),
    Launch(
        id="electron-capella",
        name="Capella 17",
        vehicle="Electron",
        agency="Rocket Lab",
        status_id=STATUS_TBC,
        status="TBC",
        net=at(days=2),
        precision="MIN",
        window_start=None,
        window_end=None,
        pad="Launch Complex 1A",
        location="Mahia Peninsula, New Zealand",
        orbit="SSO",
        mission_type="Earth Observation",
        probability=None,
        weather="",
        hold="",
        description="A synthetic-aperture radar satellite.",
    ),
    Launch(
        id="kuaizhou",
        name="Unknown Payload",
        vehicle="Kuaizhou 11",
        agency="ExPace",
        status_id=STATUS_GO,
        status="Go",
        net=at(days=3),
        precision="HR",
        window_start=None,
        window_end=None,
        pad="Launch Area 95A",
        location="Jiuquan, China",
        orbit="SSO",
        mission_type="",
        probability=None,
        weather="",
        hold="",
        description="",
    ),
    Launch(
        id="sls-artemis",
        name="Artemis III",
        vehicle="SLS Block 1",
        agency="NASA",
        status_id=STATUS_TBD,
        status="TBD",
        net=datetime(2027, 7, 1, 0, 0, tzinfo=timezone.utc),
        precision="Q3",
        window_start=None,
        window_end=None,
        pad="Launch Complex 39B",
        location="Kennedy Space Center, FL, USA",
        orbit="TLI",
        mission_type="Human Exploration",
        probability=None,
        weather="",
        hold="",
        description="The first crewed landing of the Artemis programme.",
    ),
]


def main() -> int:
    target = os.environ.get("MOARCHY_LAUNCHES_DIR")
    if not target:
        print(
            "set MOARCHY_LAUNCHES_DIR first -- refusing to touch real favourites",
            file=sys.stderr,
        )
        return 2

    store = Store(Path(target))
    store.replace(list(MARKET), fetched=time.time())
    store.favourites = [i for i in STARRED if any(item.id == i for item in MARKET)]
    store.save_upcoming()
    store.save_favourites()
    print(
        f"wrote {len(MARKET)} launches and {len(store.favourites)} stars to {store.dir}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
